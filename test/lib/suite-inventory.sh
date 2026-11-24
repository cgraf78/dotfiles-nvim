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
  local declared='' discovered entries
  entries=$(cat -- "$inventory") || {
    echo "could not read suite inventory: $inventory" >&2
    return 1
  }
  while IFS= read -r entry; do
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
    declared+="${suite_name%-test}"$'\n'
  done <<<"$entries"
  if [[ -d $root ]]; then
    # Process substitution hides a traversal error from the consuming loop.
    # Buffer names until both sides of discovery have been checked.
    discovered=$(
      set -o pipefail
      find "$root" -type f -name '*-test' -perm -u+x -print | LC_ALL=C sort
    ) || {
      echo "could not discover executable suites under $root" >&2
      return 1
    }
    while IFS= read -r suite; do
      [[ -n $suite ]] || continue
      relative_suite=${suite#"$source_root"/}
      grep -Fx -- "$relative_suite" <<<"$entries" >/dev/null || {
        echo "unlisted executable suite: $relative_suite" >&2
        return 1
      }
    done <<<"$discovered"
  fi
  printf '%s' "$declared"
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
  [[ $output == declared ]] || return 1

  # An absent suite directory can describe an empty inventory only after
  # the inventory file itself has been read successfully.
  if validate_suite_inventory "$tmp/absent-suites" "$tmp/absent-inventory" "$tmp/repo" \
    >/dev/null 2>&1; then
    echo 'suite inventory accepted a missing declaration file' >&2
    return 1
  fi

  # Traversal can fail after emitting the expected paths. A partial inventory
  # must not be accepted or handed to the runner as a complete suite list.
  if output=$(
    find() {
      command find "$@" || return
      return 73
    }
    validate_suite_inventory "$root" "$inventory" "$tmp/repo" 2>"$tmp/discovery-error"
  ); then
    echo 'suite inventory accepted failed discovery' >&2
    return 1
  fi
  if [[ -n $output ]]; then
    echo 'suite inventory printed suites after failed discovery' >&2
    return 1
  fi
  grep -Fq 'could not discover executable suites' "$tmp/discovery-error"
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
