#!/usr/bin/env bash
# Validate an overlay's declared Dot test-suite inventory.
#
# Shared by cgraf78/actions capability-harness. Consumers vendor this file
# through consumer-ci/sync.sh; edit the provider copy, never a vendored one.

# Print each declared suite name, one per line, after proving the inventory
# and the executable suites under ROOT describe the same set. A suite that
# exists but is not declared would otherwise silently drop out of CI.
validate_suite_inventory() {
  local root=$1 inventory=$2 source_root=$3 entry suite relative_suite suite_name
  while IFS= read -r entry || [[ -n $entry ]]; do
    case $entry in '' | \#*) continue ;; esac
    [[ $entry =~ ^home/\.local/lib/dotfiles/tests/[a-z0-9][a-z0-9-]*-test$ ]] || {
      echo "invalid suite inventory entry: $entry" >&2
      return 1
    }
    [[ -f $source_root/$entry && -x $source_root/$entry ]] || {
      echo "missing executable suite: $entry" >&2
      return 1
    }
    suite_name=${entry##*/}
    printf '%s\n' "${suite_name%-test}"
  done <"$inventory"
  [[ ! -d $root ]] || while IFS= read -r suite; do
    relative_suite=${suite#"$source_root"/}
    grep -Fx "$relative_suite" "$inventory" >/dev/null || {
      echo "unlisted executable suite: $relative_suite" >&2
      return 1
    }
  done < <(find "$root" -type f -name '*-test' -perm -u+x -print | LC_ALL=C sort)
}

suite_inventory_self_test() {
  local tmp root inventory output
  tmp=$(mktemp -d)
  # Consumers call this from their own self-test function. Clear the trap as
  # it fires so the caller's later returns cannot rerun it with `tmp` unset.
  trap 'rm -rf -- "$tmp"; trap - RETURN' RETURN
  root=$tmp/repo/home/.local/lib/dotfiles/tests
  inventory=$tmp/repo/inventory
  mkdir -p "$root"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$root/declared-test"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$root/unlisted-test"
  chmod +x "$root/declared-test" "$root/unlisted-test"
  printf 'home/.local/lib/dotfiles/tests/declared-test\n' >"$inventory"
  if validate_suite_inventory "$root" "$inventory" "$tmp/repo" >/dev/null 2>&1; then
    echo 'suite inventory accepted an unlisted executable' >&2
    return 1
  fi
  rm "$root/unlisted-test"
  output=$(validate_suite_inventory "$root" "$inventory" "$tmp/repo")
  [[ $output == declared ]]
}

# Sourcing callers own their shell options; only a direct run opts into strict
# mode for its self-test or command entry point.
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  set -euo pipefail
  case ${1:-} in
    --self-test) suite_inventory_self_test ;;
    *)
      echo 'usage: suite-inventory.sh --self-test' >&2
      exit 2
      ;;
  esac
fi
