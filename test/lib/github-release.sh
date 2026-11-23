#!/bin/sh

# Validate names before putting them into either GitHub URL. Dots and pluses
# occur in release tags and filenames (notably Termux APKs).
_github_release_component() {
  case "$1" in
    '' | . | .. | *[!a-zA-Z0-9_.+-]*) return 1 ;;
  esac
}

_github_release_encode() {
  printf '%s' "$1" | sed 's/+/%2B/g'
}

_github_release_curl() {
  _github_release_curl_status=0
  _github_release_curl_http=$(curl -q --fail --silent --show-error --location \
    --proto '=https' --proto-redir '=https' --write-out '%{http_code}' "$@") ||
    _github_release_curl_status=$?
  printf '%s' "$_github_release_curl_http"
  # Curl can exit zero when Retry-After exceeds its retry window despite an
  # HTTP error response. Preserve the terminal failure for the caller.
  if [ "$_github_release_curl_status" -eq 0 ]; then
    case "$_github_release_curl_http" in [45][0-9][0-9]) return 22 ;; esac
  fi
  return "$_github_release_curl_status"
}

_github_release_api() {
  _github_release_mime=$1
  shift
  # Authorization goes to curl through stdin, never argv or a file. Curl's
  # normal redirect policy drops the header when GitHub redirects to the
  # asset host. Do not load a curlrc that could enable trusted redirects.
  printf 'header = "Authorization: Bearer %s"\n' "$_github_release_token" |
    _github_release_curl --config - --header "Accept: $_github_release_mime" "$@"
}

_github_release_api_denied() {
  case "$1:$2" in
    22:401 | 22:403 | 22:404) return 0 ;;
  esac
  return 1
}

# Download an asset to the selected pathname. Callers supply their own curl
# time and retry limits and validate the resulting checksum before use.
# Public callers without credentials or a JSON parser retain the web URL.
github_release_download() (
  set +x
  [ "$#" -ge 4 ] || return 2
  _github_release_repo=$1 _github_release_tag=$2 _github_release_name=$3
  _github_release_dest=$4
  shift 4
  case "$_github_release_repo" in
    */*) ;;
    *) return 2 ;;
  esac
  if ! _github_release_component "${_github_release_repo%%/*}" ||
    ! _github_release_component "${_github_release_repo#*/}" ||
    ! _github_release_component "$_github_release_tag" ||
    ! _github_release_component "$_github_release_name"; then
    printf 'invalid GitHub release asset coordinates\n' >&2
    return 2
  fi
  [ ! -d "$_github_release_dest" ] || return 2

  _github_release_tag=$(_github_release_encode "$_github_release_tag") || return
  _github_release_token=${GH_TOKEN:-${GITHUB_TOKEN:-}}
  # Reject config syntax and control bytes without imposing one token prefix.
  case "$_github_release_token" in
    *[!a-zA-Z0-9_.-]*) _github_release_token='' ;;
  esac
  # Stage beside the destination so a failed or interrupted transfer never
  # replaces a previously downloaded archive with an incomplete one.
  _github_release_stage=$(mktemp -d "$(dirname -- "$_github_release_dest")/.github-release.XXXXXX") || return
  trap 'rm -rf -- "$_github_release_stage"' 0
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  _github_release_temp=$_github_release_stage/asset

  if [ -n "$_github_release_token" ] && command -v jq >/dev/null 2>&1; then
    _github_release_base=https://api.github.com/repos/$_github_release_repo/releases
    if _github_release_http=$(_github_release_api application/vnd.github+json \
      --connect-timeout 10 --max-time 15 --retry 1 --retry-all-errors \
      --retry-delay 1 --retry-max-time 16 \
      --output "$_github_release_stage/release" "$_github_release_base/tags/$_github_release_tag"); then
      _github_release_id=$(jq -er --arg name "$_github_release_name" \
        '[.assets[] | select(.name == $name)] | if length == 1 then .[0].id else empty end' \
        "$_github_release_stage/release") || {
        printf 'GitHub release %s %s has no unique asset named %s\n' \
          "$_github_release_repo" "$_github_release_tag" "$_github_release_name" >&2
        return 1
      }
      case "$_github_release_id" in
        '' | *[!0-9]*)
          printf 'invalid GitHub release asset ID\n' >&2
          return 1
          ;;
      esac
      if _github_release_http=$(_github_release_api application/octet-stream \
        "$@" --output "$_github_release_temp" "$_github_release_base/assets/$_github_release_id"); then
        mv -f -- "$_github_release_temp" "$_github_release_dest" || return
        printf 'Downloaded %s through the authenticated GitHub release API\n' "$_github_release_name" >&2
        return 0
      else
        _github_release_status=$?
      fi
    else
      _github_release_status=$?
    fi
    # A repository-scoped workflow token can be denied access to another
    # repository. Public assets have a credential-free fallback. Timeouts and
    # transport/server failures must retain their original failure status.
    if ! _github_release_api_denied "$_github_release_status" "$_github_release_http"; then
      printf 'GitHub release API request failed for %s (curl exit %s, HTTP %s)\n' \
        "$_github_release_name" "$_github_release_status" "$_github_release_http" >&2
      return "$_github_release_status"
    fi
    printf 'GitHub release API access unavailable for %s (HTTP %s); trying public download\n' \
      "$_github_release_name" "$_github_release_http" >&2
  fi

  _github_release_asset=$(_github_release_encode "$_github_release_name") || return
  _github_release_curl "$@" --output "$_github_release_temp" \
    "https://github.com/$_github_release_repo/releases/download/$_github_release_tag/$_github_release_asset" >/dev/null ||
    return
  mv -f -- "$_github_release_temp" "$_github_release_dest"
)
