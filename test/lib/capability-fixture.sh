#!/usr/bin/env bash
# Build the smallest supported no-base Dot client for one overlay.
#
# Shared by cgraf78/actions capability-harness. Consumers vendor this file
# through consumer-ci/sync.sh; edit the provider copy, never a vendored one.

capability_fixture_create() {
  local fixture_root=${1:-} overlay_root=${2:-} descriptor=${3:-}
  local config_dir=$fixture_root/.config/dot

  [[ $fixture_root == /* && $overlay_root == /* ]] || {
    echo 'capability fixture paths must be absolute' >&2
    return 2
  }
  # The descriptor name orders this overlay among real clients' overlays, so
  # each consumer keeps its established priority instead of inheriting one.
  [[ $descriptor =~ ^[0-9][0-9]-[a-z0-9][a-z0-9-]*\.conf$ ]] || {
    echo "capability fixture descriptor must look like NN-name.conf: $descriptor" >&2
    return 2
  }
  [[ ! -e $fixture_root/.git && ! -e $fixture_root/.dotfiles ]] || {
    echo 'capability fixture must not contain a base repository' >&2
    return 2
  }
  # Dot treats the extension root as a trust boundary. Create it empty and
  # owner-only here so permissive CI umasks cannot leave it group- or
  # world-writable, and so every caller gets the same locked-down root.
  mkdir -p "$config_dir/overlays.d" "$config_dir/extensions"
  chmod 700 "$config_dir/extensions"
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
  } >"$config_dir/overlays.d/$descriptor"
}

capability_fixture_self_test() {
  local tmp overlay mode
  tmp=$(mktemp -d)
  overlay=$tmp/overlay
  # Clear the trap as it fires so it cannot run again, with `tmp` out of
  # scope, when a caller's own function later returns.
  trap 'rm -rf -- "$tmp"; trap - RETURN' RETURN
  mkdir "$overlay"
  capability_fixture_create "$tmp/home" "$overlay" 50-example.conf
  [[ ! -e $tmp/home/.git && ! -e $tmp/home/.dotfiles ]]
  [[ $(<"$tmp/home/.config/dot/overlays.d/50-example.conf") == $'sync=none\npath='"$overlay" ]]
  [[ $(<"$tmp/home/.config/dot/config") == *'dependency_provider=none'* ]]
  # shellcheck disable=SC2016  # verify the literal deferred HOME expansion
  [[ $(<"$tmp/home/.config/dot/config") == *'extensions_dir=$HOME/.config/dot/extensions'* ]]
  [[ -d $tmp/home/.config/dot/extensions ]]
  [[ -z $(ls -A "$tmp/home/.config/dot/extensions") ]]
  # Read the mode portably: GNU and BSD stat disagree on format flags.
  mode=$(ls -ld "$tmp/home/.config/dot/extensions")
  [[ ${mode:0:10} == drwx------ ]]
}

# Sourcing callers own their shell options; only a direct run opts into strict
# mode for its self-test or command entry point.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  set -euo pipefail
  case ${1:-} in
    --self-test) capability_fixture_self_test ;;
    *)
      echo 'usage: capability-fixture.sh --self-test' >&2
      exit 2
      ;;
  esac
fi
