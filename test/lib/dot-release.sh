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
      echo "invalid Dot test release repository: ${1:-}" >&2
      return 1
      ;;
  esac
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

# Download the resolved Dot release asset plus its .sha256 sidecar, verify
# the checksum, and extract into $4 (which must already exist and be empty).
_capability_dot_release_fetch() {
  local repo=${1:-} tag=${2:-} platform=${3:-} dest=${4:-}
  local scratch tarball sidecar sum_bin
  [[ -n $repo && -n $tag && -n $platform && -n $dest ]] || {
    echo 'Dot release fetch is missing arguments' >&2
    return 1
  }
  [[ -d $dest ]] || {
    echo "Dot release destination is missing: $dest" >&2
    return 1
  }
  [[ -z $(ls -A "$dest") ]] || {
    echo "refusing to extract into a nonempty directory: $dest" >&2
    return 1
  }
  if command -v sha256sum >/dev/null 2>&1; then
    sum_bin=sha256sum
  elif command -v shasum >/dev/null 2>&1; then
    sum_bin='shasum -a 256'
  else
    echo 'sha256sum or shasum is required' >&2
    return 1
  fi
  tarball=dot-$tag-$platform.tar.gz
  sidecar=$tarball.sha256
  scratch=$(mktemp -d) || return 1
  # A RETURN trap set inside a function stays installed after it fires. Clear
  # it as it runs so a failure here cannot rerun the cleanup, with `scratch`
  # out of scope, when the caller's function returns under `set -u`.
  trap 'rm -rf -- "$scratch"; trap - RETURN' RETURN
  curl --fail --silent --show-error --location \
    --connect-timeout 10 --max-time 120 \
    --retry 2 --retry-delay 2 --retry-max-time 65 --retry-all-errors \
    "https://github.com/$repo/releases/download/$tag/$tarball" \
    -o "$scratch/$tarball" || {
    echo "could not download $tarball" >&2
    return 1
  }
  curl --fail --silent --show-error --location \
    --connect-timeout 10 --max-time 60 \
    --retry 2 --retry-delay 2 --retry-max-time 65 --retry-all-errors \
    "https://github.com/$repo/releases/download/$tag/$sidecar" \
    -o "$scratch/$sidecar" || {
    echo "could not download $sidecar" >&2
    return 1
  }
  # shellcheck disable=SC2086 # The checksum command is selected above.
  (cd "$scratch" && $sum_bin -c "$sidecar") >/dev/null || {
    echo "checksum mismatch for $tarball" >&2
    return 1
  }
  tar -xzf "$scratch/$tarball" -C "$dest" || {
    echo "could not extract $tarball" >&2
    return 1
  }
  if [[ -e $dest/.shdeps-release-layout || -L $dest/.shdeps-release-layout ]]; then
    echo 'archive ships reserved shdeps marker' >&2
    return 1
  fi
}

# Resolve the newest published Dot release tag through the anonymous web
# redirect (/releases/latest -> /releases/tag/<tag>), without touching
# api.github.com. Mirrors the base resolver, including repository and
# release-grammar validation; the caller re-validates to cover explicit
# tags as well.
_capability_dot_release_latest_tag() {
  local repo=${1:-} effective tag
  [[ -n $repo ]] || {
    echo 'Dot latest-tag lookup is missing the repository' >&2
    return 1
  }
  _capability_dot_release_valid_repo "$repo" || return 1
  effective=$(curl -fsSIL -o /dev/null -w '%{url_effective}' \
    --retry 2 --retry-delay 2 --retry-max-time 65 --retry-all-errors \
    "https://github.com/$repo/releases/latest") || {
    echo "could not resolve the latest Dot release for $repo" >&2
    return 1
  }
  tag=${effective##*/}
  [[ $effective != */releases || $tag != releases ]] || {
    echo "Dot repository has no releases yet: $repo" >&2
    return 1
  }
  [[ $tag =~ ^[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$ ]] || {
    echo "unexpected latest-release redirect: $effective" >&2
    return 1
  }
  printf '%s\n' "$tag"
}

# Resolve, download, verify, and extract the requested Dot release into DEST,
# which is created when absent and must otherwise be empty. The request comes
# from DOT_TEST_DOT_RELEASE_TAG (default: latest) and DOT_TEST_DOT_RELEASE_REPO
# (default: cgraf78/dot) so every consumer exposes the same override contract.
capability_dot_release_install() {
  local dest=${1:-} request repo tag platform
  [[ -n $dest ]] || {
    echo 'Dot release install is missing the destination' >&2
    return 1
  }
  request=${DOT_TEST_DOT_RELEASE_TAG:-latest}
  repo=${DOT_TEST_DOT_RELEASE_REPO:-cgraf78/dot}
  _capability_dot_release_valid_repo "$repo" || return 1
  if [[ $request == latest ]]; then
    tag=$(_capability_dot_release_latest_tag "$repo") || return 1
  else
    tag=$request
  fi
  [[ $tag =~ ^[0-9]{8}-[0-9]{6}-[0-9a-f]{8}$ ]] || {
    echo "invalid Dot test release tag: $tag" >&2
    return 1
  }
  platform=$(_capability_dot_release_platform) || return 1
  mkdir -p "$dest" || return 1
  _capability_dot_release_fetch "$repo" "$tag" "$platform" "$dest"
}
