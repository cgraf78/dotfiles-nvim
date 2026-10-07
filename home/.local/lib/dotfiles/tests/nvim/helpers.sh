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

# Drop the startup-file hooks a live shell exports: BASH_ENV makes every
# nested non-interactive bash load the user's env.d, and ENV does the same for
# interactive sh. Fixture children run with a stub PATH or HOME, so inheriting
# them loads the live environment into code under test, and a stub for a
# command env.d itself runs (a `#!/usr/bin/env bash` uname) recurses without
# end. Tests of startup files pass BASH_ENV or ENV to the child under test.
# The suite shell itself has already loaded env.d at startup, and zsh children
# still read $HOME/.zshenv, so use a fixture HOME or `zsh -f` where it matters.
unset BASH_ENV ENV

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

# Suites that start real editor/tool processes read config from the source
# tree while every writable Neovim root stays invocation-owned. Explicit
# NVIM_TEST_{DATA,STATE,CACHE}_HOME roots (owner CI) are used as given, and
# a cold Lazy install may populate them. Otherwise data starts as a private
# copy of the host's installed plugin cache: the host tree is only read, so
# plugin self-builds, parser installs, logs, and Lazy state stay suite-local.
# Lazy writes its lockfile beside the source config after any install, so a
# private copy sets NVIM_TEST_PLUGIN_INSTALL_DISABLED=1 for full-config runs
# to load only what the copy holds.
# shellcheck disable=SC2034 # NVIM_TEST_PLUGIN_INSTALL_DISABLED is read by callers.
_test_use_host_runtime_dirs() {
  local dependency_home="${DOT_TEST_HOST_HOME:-$HOME}" host_data entry link target

  host_data="${XDG_DATA_HOME:-$dependency_home/.local/share}/nvim"
  XDG_CONFIG_HOME="$HOME/.config"
  export XDG_CONFIG_HOME

  if [[ -n ${NVIM_TEST_DATA_HOME:-} ]]; then
    NVIM_TEST_PLUGIN_INSTALL_DISABLED=0
    XDG_DATA_HOME=$NVIM_TEST_DATA_HOME
    export XDG_DATA_HOME
  else
    # Publish the private root and the install guard before seeding, so a
    # failed copy can never leave Neovim installing into the caller's data.
    NVIM_TEST_PLUGIN_INSTALL_DISABLED=1
    XDG_DATA_HOME=$(_tmpdir)
    export XDG_DATA_HOME
    mkdir -p "$XDG_DATA_HOME/nvim" || return 1
    # `lazy` holds the plugins and `site` the compiled Tree-sitter parsers;
    # without the parsers a full-config start would try to build them.
    for entry in lazy site; do
      [[ -d $host_data/$entry ]] || continue
      _test_copy_tree "$host_data/$entry" "$XDG_DATA_HOME/nvim/$entry" || return 1
    done
    # Tree-sitter links its queries into `site` by absolute path; point the
    # copies at the private plugin tree so nothing resolves into the host's.
    while IFS= read -r link; do
      target=$(readlink "$link") || return 1
      [[ $target == "$host_data"/* ]] || continue
      ln -sfn "$XDG_DATA_HOME/nvim/${target#"$host_data"/}" "$link" || return 1
    done < <(find "$XDG_DATA_HOME/nvim" -type l)
    # A copy taken mid-update would make every full-config start wait for an
    # updater that will never finish here.
    rm -rf "$XDG_DATA_HOME/nvim/lazy/lazy.nvim.update.lock"
  fi

  if [[ -n ${NVIM_TEST_STATE_HOME:-} ]]; then
    XDG_STATE_HOME=$NVIM_TEST_STATE_HOME
  else
    XDG_STATE_HOME=$(_tmpdir)
  fi
  if [[ -n ${NVIM_TEST_CACHE_HOME:-} ]]; then
    XDG_CACHE_HOME=$NVIM_TEST_CACHE_HOME
  else
    XDG_CACHE_HOME=$(_tmpdir)
  fi
  export XDG_STATE_HOME XDG_CACHE_HOME
}

# Copy a directory tree, sharing extents where the filesystem can: GNU cp
# reflinks on btrfs and XFS, and macOS cp clones on APFS, which keeps seeding
# a plugin cache of a few hundred MB near-instant. Anything else falls back
# to a plain recursive copy. Symlinks are copied as links.
_test_copy_tree() {
  local src=$1 dest=$2

  if [[ $(uname -s) == Darwin ]]; then
    cp -cR "$src" "$dest" 2>/dev/null && return 0
  else
    cp -R --reflink=auto "$src" "$dest" 2>/dev/null && return 0
  fi
  rm -rf "$dest"
  cp -R "$src" "$dest"
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
    [[ -n $candidate && -r $candidate/lib/dot/public/api-version.sh ]] || continue
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
  export DOT_SOURCE_ROOT DOT_EXTENSIONS_DIR

  # shellcheck source=/dev/null
  . "$dot_root/lib/dot/public/xdg.sh"
  # Post-cutover the engine-internal shell libraries live only in the
  # versioned public hook runtime; extension tests load that runtime.
  # shellcheck source=/dev/null
  . "$dot_root/lib/dot/public/hook-runtime-v1/log.sh"
  # shellcheck source=/dev/null
  . "$dot_root/lib/dot/public/hook-runtime-v1/temp.sh"
  # shellcheck source=/dev/null
  . "$dot_root/lib/dot/public/hook-runtime-v1/merge-block.sh"
  # shellcheck source=/dev/null
  . "$dot_root/lib/dot/public/hook-runtime-v1/families.sh"
  # shellcheck source=/dev/null
  . "$dot_root/lib/dot/public/hook-runtime-v1/merge-hooks.sh"
  # shellcheck source=/dev/null
  . "$dot_root/lib/dot/public/hook-runtime-v1/extension-trust.sh"
  # shellcheck source=/dev/null
  . "$dot_root/lib/dot/public/hook-runtime-v1/repos/overlays.sh"
  # shellcheck source=/dev/null
  . "$dot_root/lib/dot/public/hook-runtime-v1/hook-api.sh"
}

# Load the standalone doctor extension API plus the dotfiles-owned application
# checks for focused in-process tests. Production still runs each extension in
# a fresh worker; these tests exercise the client policy helpers without
# importing private coordinator state.
#
# Args: $1 = extension home (required). There is deliberately no HOME
# fallback: the default result file lives under this root and the loader
# truncates it, so an implicit live or source HOME would be written to.
_test_load_dot_doctor_api() {
  local extension_home=${1:-} dot_root

  if [[ -z $extension_home ]]; then
    echo "test harness: _test_load_dot_doctor_api requires an extension home" >&2
    return 2
  fi

  dot_root=$(_test_dot_root) || return 1
  DOT_SOURCE_ROOT=$dot_root
  DOT_EXTENSIONS_DIR=$extension_home/.local/lib/dotfiles
  DOT_DOCTOR_RESULT_FILE=${DOT_DOCTOR_RESULT_FILE:-$extension_home/.doctor-results.tsv}
  export DOT_SOURCE_ROOT DOT_EXTENSIONS_DIR
  export DOT_DOCTOR_RESULT_FILE
  : >"$DOT_DOCTOR_RESULT_FILE"

  # shellcheck source=/dev/null
  . "$dot_root/lib/dot/public/xdg.sh"
  # shellcheck source=/dev/null
  . "$dot_root/lib/dot/public/hook-runtime-v1/extension-trust.sh"
  # shellcheck source=/dev/null
  . "$dot_root/lib/dot/public/hook-runtime-v1/repos/overlays.sh"
  # shellcheck source=/dev/null
  . "$dot_root/lib/dot/public/hook-runtime-v1/doctor-api.sh"
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

_assert_exit() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" -eq "$actual" ]]; then
    _pass "$desc"
  else
    _fail "$desc (expected exit $expected, got $actual)"
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
