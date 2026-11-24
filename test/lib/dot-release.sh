# shellcheck shell=bash
# Install one checksum-verified Dot release for an overlay's capability tests.
#
# Shared by cgraf78/actions capability-harness. Consumers vendor this file
# through consumer-ci/sync.sh; edit the provider copy, never a vendored one.
#
# Post-cutover the engine ships only as a native binary, and the CI matrix
# images carry no Rust toolchain: capability CI consumes the latest Dot
# release (checksum-verified, resolved once and frozen per run) instead of
# a source checkout it cannot build, matching what the fleet installs. An
# explicit DOT_TEST_DOT_RELEASE_TAG still selects that exact release.
#
# This file is a sourced library: it defines functions only and leaves the
# caller's shell options alone.

# Reject repository spellings that could escape the github.com/OWNER/NAME
# URL shape the download paths below are built from.
_capability_dot_release_valid_repo() {
  case ${1:-} in
    '' | *[!A-Za-z0-9._/-]* | */*/* | /* | */ | *..*)
      ;;
    */*) return 0 ;;
  esac
  echo "invalid Dot test release repository: ${1:-}" >&2
  return 1
}

# Map this machine to the Dot release platform suffix. Mirrors the base
# resolver: Termux reports Android through uname -o with the PREFIX
# spelling as the established fallback for minimal uname builds.
_capability_dot_release_platform() {
  local kernel machine system arch
  kernel=$(uname -s)
  machine=$(uname -m)
  system=$(uname -o 2>/dev/null || true)
  if [[ $system == Android || ${PREFIX:-} == *com.termux*/usr ]]; then
    case $machine in
      x86_64) arch=x86_64 ;;
      aarch64 | arm64) arch=aarch64 ;;
      *)
        echo "unsupported Android architecture: $machine" >&2
        return 1
        ;;
    esac
    printf 'android-%s\n' "$arch"
    return 0
  fi
  case $kernel in
    Linux | Darwin) ;;
    *)
      echo "unsupported kernel: $kernel" >&2
      return 1
      ;;
  esac
  case $machine in
    x86_64) arch=x86_64 ;;
    aarch64 | arm64) arch=aarch64 ;;
    *)
      echo "unsupported $kernel architecture: $machine" >&2
      return 1
      ;;
  esac
  if [[ $kernel == Linux ]]; then
    printf 'linux-%s-musl\n' "$arch"
  elif [[ $arch == x86_64 ]]; then
    printf 'macos-x86_64\n'
  else
    printf 'macos-aarch64\n'
  fi
}

_capability_dot_release_destination() {
  local dest=$1 operation=$2 entries
  [[ -n $dest ]] || {
    echo "Dot release $operation is missing the destination" >&2
    return 1
  }
  mkdir -p -- "$dest" || return
  entries=$(ls -A -- "$dest") || return
  [[ -z $entries ]] || {
    echo "refusing to $operation into a nonempty directory: $dest" >&2
    return 1
  }
}

# Bind the digest to the archive selected by the caller. A sidecar cannot
# make us hash any other file, even when that file's own digest is valid.
capability_dot_release_verify_checksum() {
  local archive=$1 sidecar=$2 name expected actual
  name=${archive##*/}
  expected=$(awk -v name="$name" '
    substr($0, 65, 2) ~ /^ [ *]$/ && substr($0, 67) == name {
      matches++
      digest = substr($0, 1, 64)
    }
    END {
      if (matches != 1 || digest !~ /^[[:xdigit:]]+$/) exit 1
      print tolower(digest)
    }
  ' "$sidecar") || {
    echo "checksum mismatch for $name (expected one record for this archive)" >&2
    return 1
  }
  if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum <"$archive") || return
  elif command -v shasum >/dev/null 2>&1; then
    actual=$(shasum -a 256 <"$archive") || return
  else
    echo 'sha256sum or shasum is required' >&2
    return 1
  fi
  [[ ${actual%% *} == "$expected" ]] || {
    echo "checksum mismatch for $name" >&2
    return 1
  }
}

# Extract an already verified archive into an empty destination. A caller
# crossing a privilege boundary must keep the staged archive read-only.
capability_dot_release_extract() {
  local archive=${1:-} dest=${2:-}
  [[ -f $archive && ! -L $archive ]] || {
    echo "invalid staged Dot release archive: $archive" >&2
    return 1
  }
  _capability_dot_release_destination "$dest" extract || return
  tar -xzf "$archive" -C "$dest" || {
    echo "could not extract ${archive##*/}" >&2
    return 1
  }
  if [[ -e $dest/.shdeps-release-layout || -L $dest/.shdeps-release-layout ]]; then
    echo 'archive ships reserved shdeps marker' >&2
    return 1
  fi
}

# Print the repository's latest published Dot tag using the anonymous web
# redirect. The GitHub credential remains available for the exact assets.
capability_dot_release_latest_tag() {
  local repo=${1:-} releases response effective tag status=0
  [[ -n $repo ]] || {
    echo 'Dot latest-tag lookup is missing the repository' >&2
    return 1
  }
  _capability_dot_release_valid_repo "$repo" || return 1
  releases=https://github.com/$repo/releases
  response=$(curl -q -fsSIL -o /dev/null -w '%{http_code} %{url_effective}' \
    --proto '=https' --proto-redir '=https' --connect-timeout 10 --max-time 30 \
    --retry 2 --retry-delay 2 --retry-max-time 65 --retry-all-errors \
    "$releases/latest") || status=$?
  # Curl can report success when Retry-After exceeds the retry window even
  # though the final response was an HTTP error.
  case "$status:$response" in
    0:2[0-9][0-9]\ *) effective=${response#* } ;;
    *)
      printf 'could not resolve the latest Dot release for %s (curl exit %s, HTTP %s)\n' \
        "$repo" "$status" "${response%% *}" >&2
      return 1
      ;;
  esac
  [[ $effective != "$releases" ]] || {
    echo "Dot repository has no releases yet: $repo" >&2
    return 1
  }
  tag=${effective#"$releases/tag/"}
  [[ $effective == "$releases/tag/"* && $tag =~ ^[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$ ]] || {
    echo "unexpected latest-release redirect: $effective" >&2
    return 1
  }
  printf '%s\n' "$tag"
}

# Download and verify a requested release into an empty DEST. Print its
# absolute archive path so a separate, credential-free worker can extract it.
capability_dot_release_stage() (
  local dest=${1:-} request repo tag platform scratch tarball sidecar
  request=${DOT_TEST_DOT_RELEASE_TAG:-latest}
  repo=${DOT_TEST_DOT_RELEASE_REPO:-cgraf78/dot}
  _capability_dot_release_valid_repo "$repo" || return 1
  if [[ $request == latest ]]; then
    tag=$(capability_dot_release_latest_tag "$repo") || return 1
  else
    tag=$request
  fi
  [[ $tag =~ ^[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$ ]] || {
    echo "invalid Dot test release tag: $tag" >&2
    return 1
  }
  platform=$(_capability_dot_release_platform) || return 1
  _capability_dot_release_destination "$dest" stage || return
  # Keep relative destinations anchored here, including a literal "-".
  [[ $dest == /* ]] || dest="./$dest"
  dest=$(cd -P -- "$dest" && pwd -P) || return
  scratch=$(mktemp -d "$dest/.dot-release.XXXXXX") || return
  trap 'rm -rf -- "$scratch"' EXIT
  # shellcheck source=./github-release.sh
  . "$(dirname -- "${BASH_SOURCE[0]}")/github-release.sh" || return
  tarball=dot-$tag-$platform.tar.gz
  sidecar=$tarball.sha256
  github_release_download "$repo" "$tag" "$tarball" "$scratch/$tarball" \
    --connect-timeout 10 --max-time 120 \
    --retry 2 --retry-delay 2 --retry-max-time 65 --retry-all-errors || {
    echo "could not download $tarball" >&2
    return 1
  }
  github_release_download "$repo" "$tag" "$sidecar" "$scratch/$sidecar" \
    --connect-timeout 10 --max-time 60 \
    --retry 2 --retry-delay 2 --retry-max-time 65 --retry-all-errors || {
    echo "could not download $sidecar" >&2
    return 1
  }
  capability_dot_release_verify_checksum "$scratch/$tarball" "$scratch/$sidecar" || return
  mv -f -- "$scratch/$tarball" "$dest/$tarball" || return
  printf '%s\n' "$dest/$tarball"
)

# Keep the ordinary install entry point for callers that do not need to
# separate the authenticated download and extraction processes.
capability_dot_release_install() (
  local dest=${1:-} scratch archive
  _capability_dot_release_destination "$dest" extract || return
  scratch=$(mktemp -d) || return
  trap 'rm -rf -- "$scratch"' EXIT
  archive=$(capability_dot_release_stage "$scratch") || return
  capability_dot_release_extract "$archive" "$dest"
)
