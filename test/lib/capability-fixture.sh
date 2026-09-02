#!/usr/bin/env bash
# Build the smallest supported no-base Dot client for this overlay.
set -euo pipefail

capability_fixture_create() {
  local fixture_root=$1 overlay_root=$2
  local config_dir=$fixture_root/.config/dot

  [[ $fixture_root == /* && $overlay_root == /* ]] || {
    echo 'capability fixture paths must be absolute' >&2
    return 2
  }
  [[ ! -e $fixture_root/.git && ! -e $fixture_root/.dotfiles ]] || {
    echo 'capability fixture must not contain a base repository' >&2
    return 2
  }
  mkdir -p "$config_dir/overlays.d"
  cat >"$config_dir/config" <<'EOF'
version=1
extension_api=1
# sync=none sources are intentionally not trusted as executable extension
# providers. Keep update-time discovery on an empty inherited root; test/run
# invokes this checkout's suites explicitly through DOT_TEST_TESTS_DIR.
extensions_dir=$HOME/.config/dot/extensions
dependency_provider=none
EOF
  {
    printf 'sync=none\n'
    printf 'path=%s\n' "$overlay_root"
  } >"$config_dir/overlays.d/20-nvim.conf"
}

capability_fixture_self_test() {
  local tmp overlay
  tmp=$(mktemp -d)
  overlay=$tmp/overlay
  trap 'rm -rf -- "$tmp"' RETURN
  mkdir "$overlay"
  capability_fixture_create "$tmp/home" "$overlay"
  [[ ! -e $tmp/home/.git && ! -e $tmp/home/.dotfiles ]]
  [[ $(<"$tmp/home/.config/dot/overlays.d/20-nvim.conf") == $'sync=none\npath='"$overlay" ]]
  [[ $(<"$tmp/home/.config/dot/config") == *'dependency_provider=none'* ]]
  [[ $(<"$tmp/home/.config/dot/config") == *"extensions_dir=\$HOME/.config/dot/extensions"* ]]
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  case ${1:-} in
    --self-test) capability_fixture_self_test ;;
    *)
      echo 'usage: capability-fixture.sh --self-test' >&2
      exit 2
      ;;
  esac
fi
