#!/usr/bin/env bash
# helpers.sh — shared test framework for dotfiles tests.
#
# Source this file from test scripts to get assertion helpers,
# temp directory management, and a summary reporter.
#
# Usage:
#   . "$HOME/.local/lib/dotfiles/tests/helpers.sh"
#   _assert_eq "description" "expected" "actual"
#   ...
#   _test_summary  # prints results, exits 0 or 1

PASS=0
FAIL=0
CLEANUP_DIRS=()

# Mark every suite, including suites run directly, so code that can reach
# outside the mock HOME can avoid touching the real host during WSL tests.
export DOT_TEST=1

# Tests import Python helpers directly from dot-managed config directories.
# Bytecode caches there look like stale user config after test runs, so keep
# tests from writing __pycache__ beside source fixtures.
export PYTHONDONTWRITEBYTECODE=1

# `dot test` sets DOT_TEST_STYLE=1 for child suites when styled output is
# appropriate. Individual suites keep exporting NO_COLOR for deterministic tool
# output, so this opt-in is separate from NO_COLOR and only affects our harness
# status lines.
_DOT_TEST_PRETTY=false
[[ "${DOT_TEST_STYLE:-0}" = 1 ]] && _DOT_TEST_PRETTY=true

_test_style() {
  local color="$1"
  shift
  if $_DOT_TEST_PRETTY; then
    local sgr
    case "$color" in
      green) sgr='38;2;63;185;80' ;;
      red) sgr='38;2;248;81;73' ;;
      yellow) sgr='38;2;210;153;34' ;;
      dim) sgr='38;2;139;148;158' ;;
      bold) sgr='1' ;;
      *) sgr='0' ;;
    esac
    printf '\033[%sm%s\033[0m\n' "$sgr" "$*"
  else
    echo "$*"
  fi
}

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------

_pass() {
  PASS=$((PASS + 1))
  if $_DOT_TEST_PRETTY; then
    _test_style green "  ✓ $1"
  else
    echo "  PASS: $1"
  fi
}
_fail() {
  FAIL=$((FAIL + 1))
  if $_DOT_TEST_PRETTY; then
    _test_style red "  ✗ $1" >&2
  else
    echo "  FAIL: $1" >&2
  fi
}

_assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    _pass "$desc"
  else
    _fail "$desc (expected '$expected', got '$actual')"
  fi
}

# Small aliases used by the extracted component-specific wrapper suites.
nvim_test_ok() { _pass "component assertion"; }
nvim_test_fail() { _fail "$1"; }
nvim_test_assert() {
  local description=$1
  shift
  if "$@"; then _pass "$description"; else _fail "$description"; fi
}
nvim_test_contains() {
  local description=$1 needle=$2 file=$3
  if grep -F -- "$needle" "$file" >/dev/null; then
    _pass "$description"
  else
    _fail "$description"
  fi
}
nvim_test_not_contains() {
  local description=$1 pattern=$2
  shift 2
  if rg -n -i "$pattern" "$@" >/dev/null 2>&1; then
    _fail "$description"
  else
    _pass "$description"
  fi
}
nvim_test_finish() { _test_summary; }

# Canonicalize a path for tests that care about filesystem identity rather than
# the exact spelling returned by macOS or libuv. In particular, temporary paths
# under /var may be reported as /private/var by some tools.
_test_realpath() {
  local path="$1" target directory basename canonical_directory

  if [[ -L $path ]]; then
    target=$(readlink "$path") || return 1
    case $target in
      /*) path=$target ;;
      *) path=${path%/*}/$target ;;
    esac
  fi

  if command -v realpath >/dev/null 2>&1; then
    realpath "$path" 2>/dev/null && return
  fi
  if [[ -d $path ]]; then
    (cd -P -- "$path" 2>/dev/null && pwd -P) && return
  fi

  directory=${path%/*}
  basename=${path##*/}
  [[ $directory != "$path" ]] || directory=.
  canonical_directory=$(cd -P -- "$directory" 2>/dev/null && pwd -P) || {
    printf '%s\n' "$path"
    return
  }
  if [[ $canonical_directory == / ]]; then
    printf '/%s\n' "$basename"
  else
    printf '%s/%s\n' "$canonical_directory" "$basename"
  fi
}

# Suites that start real editor/tool processes from a worktree HOME can reuse
# the host's installed tool data while still reading config from the source
# tree. Writable cache/state roots remain suite-local when dot test supplies
# them; this prevents editor smoke tests from modifying either checkout.
_test_use_host_runtime_dirs() {
  local dependency_home="${DOT_TEST_HOST_HOME:-$HOME}"

  XDG_CONFIG_HOME="$HOME/.config"
  export XDG_CONFIG_HOME

  if [[ -n ${NVIM_TEST_DATA_HOME:-} ]]; then
    XDG_DATA_HOME=$NVIM_TEST_DATA_HOME
    export XDG_DATA_HOME
  elif [[ -n "$dependency_home" && "$dependency_home" != "$HOME" ]]; then
    XDG_DATA_HOME="$dependency_home/.local/share"
    export XDG_DATA_HOME
  fi

  if [[ -n ${NVIM_TEST_STATE_HOME:-} ]]; then
    XDG_STATE_HOME=$NVIM_TEST_STATE_HOME
    export XDG_STATE_HOME
  fi
  if [[ -n ${NVIM_TEST_CACHE_HOME:-} ]]; then
    XDG_CACHE_HOME=$NVIM_TEST_CACHE_HOME
    export XDG_CACHE_HOME
  fi
}

# Suites that execute host-installed binaries from a worktree HOME sometimes
# need the matching host shdeps tree too. Keep this opt-in instead of exporting
# shdeps from dot test globally: several low-level tests intentionally provide
# fixture SHDEPS_DIR/SHDEPS_GIT_DEV_DIR values and must not be overridden.
_test_use_host_shdeps() {
  local dependency_home="${DOT_TEST_HOST_HOME:-$HOME}"

  [[ -n "$dependency_home" ]] || return 0
  SHDEPS_CONF_DIR="$dependency_home/.config/shdeps"
  SHDEPS_HOOKS_DIR="$dependency_home/.config/shdeps/hooks.d"
  SHDEPS_STATE_DIR="$dependency_home/.local/state/shdeps"
  SHDEPS_INSTALL_DIR="$dependency_home/.local/share"
  SHDEPS_BIN_DIR="$dependency_home/.local/bin"
  SHDEPS_GIT_DEV_DIR="$dependency_home/git"
  export SHDEPS_CONF_DIR SHDEPS_HOOKS_DIR SHDEPS_STATE_DIR
  export SHDEPS_INSTALL_DIR SHDEPS_BIN_DIR SHDEPS_GIT_DEV_DIR
  unset SHDEPS_TEST_PLATFORM SHDEPS_TEST_HOST

  unset SHDEPS_LIB SHDEPS_DIR SHDEPS_LUA_DIR
  if [[ -f "$dependency_home/git/shdeps/shdeps.sh" ]]; then
    export SHDEPS_LIB="$dependency_home/git/shdeps/shdeps.sh"
    export SHDEPS_LUA_DIR="$dependency_home/git/shdeps/lua"
  elif [[ -f "$dependency_home/.local/share/shdeps/shdeps.sh" ]]; then
    export SHDEPS_DIR="$dependency_home/.local/share/shdeps"
    export SHDEPS_LUA_DIR="$dependency_home/.local/share/shdeps/lua"
  fi
}

_test_dot_root() {
  local host_home=${DOT_TEST_HOST_HOME:-$HOME} candidate

  for candidate in \
    "${DOT_TEST_DOT_ROOT:-}" \
    "$host_home/git/dot" \
    "$host_home/.local/share/cgraf78/dot"; do
    [[ -n $candidate && -r $candidate/lib/dot/extension-worker.sh ]] || continue
    (cd -P -- "$candidate" && pwd -P)
    return
  done
  return 1
}

_nvim_repo_root() {
  local tests_dir=${DOT_TEST_TESTS_DIR:-} helper_source candidate helper_dir

  helper_source=$(_test_realpath "${BASH_SOURCE[0]}")
  case $helper_source in
    */home/.local/lib/dotfiles/tests/nvim/helpers.sh)
      candidate=${helper_source%/home/.local/lib/dotfiles/tests/nvim/helpers.sh}
      if [[ -f $candidate/.github/dot-test-suites.txt &&
        -d $candidate/home ]]; then
        printf '%s\n' "$candidate"
        return 0
      fi
      ;;
  esac

  case $tests_dir in
    */home/.local/lib/dotfiles/tests)
      printf '%s\n' "${tests_dir%/home/.local/lib/dotfiles/tests}"
      return 0
      ;;
  esac

  helper_dir=$(cd "${BASH_SOURCE[0]%/*}" && pwd -P)
  (cd "$helper_dir/../../../../../.." && pwd -P)
}

# Load the public merge-extension API for tests that exercise client policy
# functions directly. Production still executes hooks in isolated workers;
# these unit tests intentionally keep the functions in-process so they can
# probe narrow adapters and failure paths without duplicating engine code.
_test_load_dot_merge_api() {
  local source_home=${1:-${DOT_TEST_SOURCE_HOME:-$HOME}} dot_root

  dot_root=$(_test_dot_root) || return 1
  DOT_SOURCE_ROOT=$dot_root
  DOT_EXTENSIONS_DIR=$source_home/.local/lib/dotfiles
  DOT_EXTENSION_API=1
  export DOT_SOURCE_ROOT DOT_EXTENSIONS_DIR DOT_EXTENSION_API

  # shellcheck source=/dev/null
  . "$dot_root/lib/dot/public/xdg.sh"
  # shellcheck source=/dev/null
  . "$dot_root/lib/dot/log.sh"
  # shellcheck source=/dev/null
  . "$dot_root/lib/dot/temp.sh"
  # shellcheck source=/dev/null
  . "$dot_root/lib/dot/merge-block.sh"
  # shellcheck source=/dev/null
  . "$dot_root/lib/dot/families.sh"
  # shellcheck source=/dev/null
  . "$dot_root/lib/dot/merge-hooks.sh"
  # shellcheck source=/dev/null
  . "$dot_root/lib/dot/extension-trust.sh"
  # shellcheck source=/dev/null
  . "$dot_root/lib/dot/repos/overlays.sh"
  # shellcheck source=/dev/null
  . "$dot_root/lib/dot/hook-api.sh"
}

# Load the standalone doctor extension API plus the dotfiles-owned application
# checks for focused in-process tests. Production still runs each extension in
# a fresh worker; these tests exercise the client policy helpers without
# importing private coordinator state.
_test_load_dot_doctor_api() {
  local extension_home=${1:-${DOT_TEST_SOURCE_HOME:-$HOME}} dot_root

  dot_root=$(_test_dot_root) || return 1
  DOT_SOURCE_ROOT=$dot_root
  DOT_EXTENSIONS_DIR=$extension_home/.local/lib/dotfiles
  DOT_EXTENSION_API=1
  DOT_DOCTOR_RESULT_FILE=${DOT_DOCTOR_RESULT_FILE:-$extension_home/.doctor-results.tsv}
  export DOT_SOURCE_ROOT DOT_EXTENSIONS_DIR DOT_EXTENSION_API
  export DOT_DOCTOR_RESULT_FILE
  : >"$DOT_DOCTOR_RESULT_FILE"

  # shellcheck source=/dev/null
  . "$dot_root/lib/dot/public/xdg.sh"
  # shellcheck source=/dev/null
  . "$dot_root/lib/dot/extension-trust.sh"
  # shellcheck source=/dev/null
  . "$dot_root/lib/dot/repos/overlays.sh"
  # shellcheck source=/dev/null
  . "$dot_root/lib/dot/doctor-api.sh"
  dot_doctor_source doctor.d/lib/compat.sh || return 1
}

# Editor-policy suites should exercise the managed Neovim payload directly;
# core-launchers-test owns the public wrapper. Resolve the host payload when a
# worktree HOME is active so this accommodation stays in test code.
_test_managed_nvim_bin() {
  local dependency_home="${DOT_TEST_HOST_HOME:-$HOME}"

  if [[ -n ${NVIM_TEST_BIN:-} && -x $NVIM_TEST_BIN && ! -d $NVIM_TEST_BIN ]]; then
    REPLY=$NVIM_TEST_BIN
    return 0
  fi
  REPLY="$dependency_home/.local/share/neovim/neovim/bin/nvim"
  if [[ ! -x "$REPLY" || -d "$REPLY" ]]; then
    printf 'test harness: managed Neovim not found at %s\n' "$REPLY" >&2
    return 1
  fi
}

# Suites that exercise higher-level editor or dependency policy should not
# accidentally use a site-specific Git wrapper. By default the selected Git is
# first on PATH. The after-dotfiles mode keeps the tracked launcher first while
# making the selected Git its immediate backend, preserving integration
# coverage without invoking later site wrappers.
_test_prefer_system_git() {
  local mode="${1:-first}" candidate git_bin source_bin path_entry
  local -a candidates=()

  [[ "$mode" = first || "$mode" = after-dotfiles ]] || {
    echo "test harness: invalid system Git mode: $mode" >&2
    return 2
  }

  [[ -z "${DOT_TEST_SYSTEM_GIT:-}" ]] || candidates+=("$DOT_TEST_SYSTEM_GIT")
  candidates+=(/usr/bin/git /bin/git /opt/homebrew/bin/git)
  [[ -z "${PREFIX:-}" ]] || candidates+=("$PREFIX/bin/git")
  while IFS= read -r path_entry; do
    candidates+=("$path_entry")
  done < <(type -P -a git 2>/dev/null)

  source_bin="${DOT_TEST_SOURCE_HOME:-$HOME}/.local/bin"
  for candidate in "${candidates[@]}"; do
    [[ -x "$candidate" && ! -d "$candidate" ]] || continue
    [[ "$candidate" != "$source_bin/git" ]] || continue
    git_bin=$(_mock_bin)
    ln -s "$candidate" "$git_bin/git" || return 1
    if [[ "$mode" = after-dotfiles ]]; then
      case "$PATH" in
        "$source_bin") PATH="$source_bin:$git_bin" ;;
        "$source_bin:"*) PATH="$source_bin:$git_bin:${PATH#"$source_bin:"}" ;;
        *) PATH="$source_bin:$git_bin:$PATH" ;;
      esac
    else
      PATH="$git_bin:$PATH"
    fi
    export PATH
    return 0
  done

  echo "test harness: could not find a system Git executable" >&2
  return 1
}

# Core/bootstrap suites need the current shdeps implementation, but sourcing a
# development checkout lets its bootstrap pull and rebuild that shared checkout.
# Copy only the sourceable surface and resolved binary into this suite's temp
# root so parallel tests cannot mutate or race user-owned shdeps state.
_test_prepare_shdeps_snapshot() {
  local home source_dir="" binary="" candidate snapshot optional
  local head="" version="" git_root="" source_root=""

  for home in "$@"; do
    [[ -n "$home" ]] || continue
    for candidate in "$home/git/shdeps" "$home/.local/share/shdeps"; do
      if [[ -f "$candidate/install.sh" && -f "$candidate/shdeps.sh" ]]; then
        source_dir="$candidate"
        break 2
      fi
    done
  done
  if [[ -z "$source_dir" ]]; then
    echo "dot test: no shdeps implementation available for an isolated snapshot" >&2
    return 1
  fi

  source_root=$(cd -P -- "$source_dir" 2>/dev/null && pwd) || return 1
  git_root=$(git -C "$source_dir" rev-parse --show-toplevel 2>/dev/null || true)
  if [[ -n "$git_root" ]]; then
    git_root=$(cd -P -- "$git_root" 2>/dev/null && pwd) || return 1
  fi
  if [[ "$git_root" == "$source_root" ]]; then
    # A development checkout is authoritative. Never silently combine its
    # current shell API with an older installed binary or fallback release.
    head=$(git -C "$source_dir" rev-parse --short=8 HEAD 2>/dev/null) || {
      echo "dot test: could not resolve shdeps checkout HEAD: $source_dir" >&2
      return 1
    }
    for candidate in \
      "$source_dir/shdeps" \
      "$source_dir/target/release/shdeps" \
      "$source_dir/target/debug/shdeps"; do
      [[ -x "$candidate" ]] || continue
      version=$("$candidate" version 2>/dev/null || true)
      if [[ "$version" == *"$head"* ]]; then
        binary="$candidate"
        break
      fi
    done
  else
    for candidate in \
      "$source_dir/shdeps" \
      "$source_dir/target/release/shdeps" \
      "$source_dir/target/debug/shdeps"; do
      if [[ -x "$candidate" ]]; then
        binary="$candidate"
        break
      fi
    done
  fi
  if [[ -z "$binary" ]]; then
    if [[ -n "$head" ]]; then
      echo "dot test: shdeps checkout has no binary for HEAD $head; run cargo build --release --locked in $source_dir" >&2
    else
      echo "dot test: shdeps implementation has no runnable binary: $source_dir" >&2
    fi
    return 1
  fi

  snapshot=$(_tmpdir)
  cp "$source_dir/install.sh" "$source_dir/shdeps.sh" "$snapshot/" || return 1
  cp -L "$binary" "$snapshot/shdeps" || return 1
  chmod +x "$snapshot/shdeps" || return 1
  # Keep the isolated payload coherent with the public installer surface. In
  # particular, current install.sh publishes the Lua tree during activation;
  # omitting it would make snapshot-backed tests exercise an impossible release.
  for optional in completions lua man; do
    [[ -e "$source_dir/$optional" ]] || continue
    cp -R "$source_dir/$optional" "$snapshot/" || return 1
  done

  DOT_TEST_SHDEPS_SNAPSHOT="$snapshot"
  SHDEPS_LIB="$snapshot/shdeps.sh"
  SHDEPS_RUST_CLI="$snapshot/shdeps"
  export DOT_TEST_SHDEPS_SNAPSHOT SHDEPS_LIB SHDEPS_RUST_CLI
}

_test_realpath_lines() {
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -e "$line" || -L "$line" ]]; then
      _test_realpath "$line"
    else
      printf '%s\n' "$line"
    fi
  done
}

# Use this only when path spelling is not part of the behavior under test. Tests
# that intentionally distinguish visible HOME aliases from canonical paths should
# keep using _assert_eq with explicit _test_realpath calls at the relevant lines.
_assert_eq_realpath_lines() {
  local desc="$1" expected="$2" actual="$3"
  _assert_eq "$desc" \
    "$(_test_realpath_lines <<<"$expected")" \
    "$(_test_realpath_lines <<<"$actual")"
}

_assert_contains() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == *"$expected"* ]]; then
    _pass "$desc"
  else
    _fail "$desc (expected to contain '$expected', got '$actual')"
  fi
}

_assert_not_contains() {
  local desc="$1" unexpected="$2" actual="$3"
  if [[ "$actual" != *"$unexpected"* ]]; then
    _pass "$desc"
  else
    _fail "$desc (should not contain '$unexpected')"
  fi
}

_assert_colon_list_values_aligned() {
  local desc="$1" content="$2" marker="$3"
  local in_list=0 expected_col="" row_count=0
  local line label after_colon spaces col

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "$marker" ]]; then
      in_list=1
      continue
    fi

    [[ "$in_list" -eq 1 ]] || continue
    [[ -n "$line" ]] || break

    if [[ "$line" != "  "*:* ]]; then
      _fail "$desc (unexpected list row '$line')"
      return
    fi

    label=${line%%:*}
    after_colon=${line#*:}
    spaces=${after_colon%%[! ]*}

    if [[ -z "$spaces" || "$spaces" == "$after_colon" ]]; then
      _fail "$desc (missing list spacing after '$label:')"
      return
    fi

    col=$((${#label} + 1 + ${#spaces}))
    if [[ -z "$expected_col" ]]; then
      expected_col=$col
    elif [[ "$col" -ne "$expected_col" ]]; then
      _fail "$desc (list starts at column $col, expected $expected_col: '$line')"
      return
    fi

    row_count=$((row_count + 1))
  done <<<"$content"

  if [[ "$row_count" -eq 0 ]]; then
    _fail "$desc (no rows found after '$marker')"
  else
    _pass "$desc"
  fi
}

_assert_exit() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" -eq "$actual" ]]; then
    _pass "$desc"
  else
    _fail "$desc (expected exit $expected, got $actual)"
  fi
}

_assert_file_exists() {
  local desc="$1" path="$2"
  if [[ -f "$path" ]]; then
    _pass "$desc"
  else
    _fail "$desc (file not found: $path)"
  fi
}

_assert_file_missing() {
  local desc="$1" path="$2"
  if [[ ! -f "$path" ]]; then
    _pass "$desc"
  else
    _fail "$desc (file should not exist: $path)"
  fi
}

_assert_file_content() {
  local desc="$1" expected="$2" path="$3"
  if [[ -f "$path" ]]; then
    local actual
    actual=$(cat "$path")
    if [[ "$actual" == "$expected" ]]; then
      _pass "$desc"
    else
      _fail "$desc (expected content '$expected', got '$actual')"
    fi
  else
    _fail "$desc (file not found: $path)"
  fi
}

# ---------------------------------------------------------------------------
# Temp directory management
# ---------------------------------------------------------------------------

_DOT_TEST_TMP_ROOT=$(mktemp -d) || {
  echo "failed to create test temp root" >&2
  exit 1
}
if [[ -z "$_DOT_TEST_TMP_ROOT" || ! -d "$_DOT_TEST_TMP_ROOT" ]]; then
  echo "mktemp returned invalid test temp root: $_DOT_TEST_TMP_ROOT" >&2
  exit 1
fi
CLEANUP_DIRS+=("$_DOT_TEST_TMP_ROOT")

_tmpdir() {
  local d
  d=$(mktemp -d "$_DOT_TEST_TMP_ROOT/tmp.XXXXXX") || {
    echo "failed to create test temp directory" >&2
    exit 1
  }
  if [[ -z "$d" || "$d" != "$_DOT_TEST_TMP_ROOT"/* || ! -d "$d" ]]; then
    echo "mktemp returned invalid test temp directory: $d" >&2
    exit 1
  fi
  echo "$d"
}

_tmpfile() {
  local f
  f=$(mktemp "$_DOT_TEST_TMP_ROOT/file.XXXXXX") || {
    echo "failed to create test temp file" >&2
    exit 1
  }
  if [[ -z "$f" || "$f" != "$_DOT_TEST_TMP_ROOT"/* || ! -f "$f" ]]; then
    echo "mktemp returned invalid test temp file: $f" >&2
    exit 1
  fi
  echo "$f"
}

_cleanup_dir() {
  local d="$1" retries=2

  # Git can leave a short-lived asynchronous helper writing under the fixture
  # HOME after the command returns. Give that writer a bounded chance to exit;
  # a persistent leak still fails loudly on the final attempt.
  while ((retries > 0)); do
    rm -rf "$d" 2>/dev/null
    [[ ! -e "$d" && ! -L "$d" ]] && return 0
    retries=$((retries - 1))
    sleep 0.05
  done

  rm -rf "$d"
  if [[ -e "$d" || -L "$d" ]]; then
    echo "test cleanup did not remove: $d" >&2
    return 1
  fi
}

_cleanup() {
  local d status=0
  for d in "${CLEANUP_DIRS[@]+"${CLEANUP_DIRS[@]}"}"; do
    _cleanup_dir "$d" || status=$?
  done
  return "$status"
}

_cleanup_on_exit() {
  local status="$1" cleanup_status=0

  trap - EXIT
  _cleanup || cleanup_status=$?
  if ((status == 0 && cleanup_status != 0)); then
    status=$cleanup_status
  fi
  exit "$status"
}
trap '_cleanup_on_exit "$?"' EXIT

# ---------------------------------------------------------------------------
# Common test setup
# ---------------------------------------------------------------------------

# Create a mock HOME, saving the original. Sets TEST_HOME, REAL_HOME, HOME.
_mock_home() {
  # shellcheck disable=SC2034  # REAL_HOME is used by callers
  REAL_HOME="$HOME"
  TEST_HOME=$(_tmpdir)
  export HOME="$TEST_HOME"
  # Clear caller-owned absolute roots so every tool uses its standard HOME
  # default. This also keeps nested fresh-HOME subprocesses isolated to their
  # own HOME instead of pinning them to the outer fixture's directories.
  unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME
  unset MISE_DATA_DIR MISE_STATE_DIR MISE_CACHE_DIR
  unset SHDEPS_CONF_DIR SHDEPS_HOOKS_DIR SHDEPS_STATE_DIR
  unset SHDEPS_INSTALL_DIR SHDEPS_BIN_DIR SHDEPS_GIT_DEV_DIR
  unset SHDEPS_DIR SHDEPS_BIN SHDEPS_LUA_DIR
  # Isolate tests from real user and system Git config (e.g. core.fsmonitor or
  # commit signing can spawn external processes). Use an empty writable global
  # file so fixture `git config --global` calls still succeed.
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL="$TEST_HOME/.gitconfig-test"
  touch "$GIT_CONFIG_GLOBAL"
}

# Canonical git identity for test repos. Tests never assert on these values;
# they exist only so commits in fixtures have a valid author.
DOT_TEST_GIT_EMAIL="test@test.com"
DOT_TEST_GIT_NAME="Test"

# Set the test git identity on a repo. Pass the git invocation as arguments so
# any form works, e.g.:
#   _git_set_test_identity git -C "$dir"
#   _git_set_test_identity $GIT
#   _git_set_test_identity "${SOME_GIT_ARRAY[@]}"
_git_set_test_identity() {
  "$@" config user.email "$DOT_TEST_GIT_EMAIL"
  "$@" config user.name "$DOT_TEST_GIT_NAME"
}

# Create a temp bin directory for mock commands. Returns the path.
# IMPORTANT: callers must also run `export PATH="$dir:$PATH"` since
# $() runs in a subshell and the export here won't affect the caller.
_mock_bin() {
  local d
  d=$(_tmpdir)
  echo "$d"
}

# ---------------------------------------------------------------------------
# Portable timeout wrapper backed by the repository-required Python 3 runtime.
# One supervisor keeps timeout, signal, and process-group behavior identical on
# Linux and macOS.
# ---------------------------------------------------------------------------

_DOT_TEST_TIMEOUT=${DOT_TEST_TIMEOUT:-}
if [[ -z $_DOT_TEST_TIMEOUT ]]; then
  _DOT_TEST_PROVIDER_ROOT=$(_test_dot_root 2>/dev/null || true)
  _DOT_TEST_TIMEOUT=${_DOT_TEST_PROVIDER_ROOT:+$_DOT_TEST_PROVIDER_ROOT/lib/dot/public/test-timeout-v1}
fi

_with_provider_timeout() {
  local secs="$1"
  shift
  "$_DOT_TEST_TIMEOUT" "$secs" "$@"
}

_with_timeout() {
  local secs="$1"
  shift
  if [[ -x $_DOT_TEST_TIMEOUT ]]; then
    _with_provider_timeout "$secs" "$@"
  else
    echo "test timeout requires the standalone Dot timeout helper" >&2
    return 127
  fi
}

# ---------------------------------------------------------------------------
# Platform checks
# ---------------------------------------------------------------------------

# Check if prebuilt tool binaries will work on this platform. macOS
# ships native binaries; the concern is musl-based Linux (Alpine)
# where glibc-linked binaries fail.
_has_compatible_libc() {
  [[ "$(uname -s)" != "Linux" ]] && return 0
  # Do not use `grep -q` here: with pipefail enabled, grep can exit early
  # after a match and make verbose `ldd` implementations fail with SIGPIPE.
  ldd --version 2>&1 | grep -iE 'glibc|gnu libc' >/dev/null 2>&1
}
# Skip the entire test suite only on Linux libc variants that cannot run the
# prebuilt tools used by these fixtures. macOS remains in coverage.
_require_compatible_libc() {
  if ! _has_compatible_libc; then
    _test_skip_suite "$1 (requires glibc-compatible Linux libc)"
  fi
}

_nvim_version_at_least() {
  local bin=$1 minimum_major=$2 minimum_minor=$3 minimum_patch=$4
  local output version major minor patch

  output=$("$bin" --version 2>/dev/null) || return 1
  version=${output%%$'\n'*}
  version=${version#NVIM v}
  version=${version%%-*}
  IFS=. read -r major minor patch <<<"$version"
  [[ $major =~ ^[0-9]+$ && $minor =~ ^[0-9]+$ && $patch =~ ^[0-9]+$ ]] ||
    return 1
  ((major > minimum_major)) ||
    ((major == minimum_major && minor > minimum_minor)) ||
    ((major == minimum_major && minor == minimum_minor && patch >= minimum_patch))
}

_require_nvim_version() {
  local suite=$1 bin=$2
  if ! _nvim_version_at_least "$bin" 0 11 2; then
    _test_skip_suite "$suite (requires Neovim 0.11.2 or newer)"
  fi
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

_test_skip_suite() {
  local reason=$1
  echo "SKIP: $reason"
  if [[ -n ${DOT_TEST_REPORTER:-} ]]; then
    "$DOT_TEST_REPORTER" skip "$reason" || exit 1
  fi
  exit 0
}

_test_summary() {
  echo ""
  if $_DOT_TEST_PRETTY; then
    local summary_color=green
    [[ $FAIL -ne 0 ]] && summary_color=red
    _test_style "$summary_color" "────────────────────────────────"
    if [[ $FAIL -eq 0 ]]; then
      _test_style green "✓ Results: $PASS passed, $FAIL failed"
    else
      _test_style red "✗ Results: $PASS passed, $FAIL failed"
    fi
    _test_style "$summary_color" "────────────────────────────────"
  else
    echo "================================"
    echo "Results: $PASS passed, $FAIL failed"
    echo "================================"
  fi
  if [[ -n ${DOT_TEST_REPORTER:-} ]]; then
    "$DOT_TEST_REPORTER" complete "$PASS" "$FAIL" || exit 1
  fi
  [[ $FAIL -eq 0 ]] && exit 0 || exit 1
}
