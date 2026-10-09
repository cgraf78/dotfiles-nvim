# shellcheck shell=bash
# Repository-contract checks shared by Dot overlay `test/workflow-test` scripts.
#
# Shared by cgraf78/actions capability-harness. Consumers vendor this file
# through consumer-ci/sync.sh; edit the provider copy, never a vendored one.
#
# Each overlay keeps its own workflow-shape assertions (schedule, profiles,
# jobs) and Dot release pin checks. This library owns only the policy every
# overlay states identically: repository identity, the public MIT license and
# remote settings, the `.gitignore` contract, and the bounded remote poll.
# Version-lock and ShellCheck-inventory checks are deliberately absent: the
# `cgraf78/actions sync` job and shell CI's `shellcheck-inventory` own them.
#
# This file is a sourced library: it defines functions only and leaves the
# caller's shell options alone. Call its checks from the repository root.

# Canonical bytes of the MIT LICENSE every public overlay ships.
_workflow_contract_license_sha256=bfaed6d8fb29d7208c1266afa313681591d6ca05ec2f7e005cebe3d7a7b43579
_workflow_contract_license_bytes=1067

# Report a contract violation and stop the contract script. This is an
# assertion helper, so unlike the other functions it exits rather than
# returning: every caller treats a violation as fatal.
fail() {
  printf 'workflow-test: %s\n' "$*" >&2
  exit 1
}

# Print the repository name for ROOT, preferring GitHub's identity, then the
# origin remote, then the checkout basename. Worktree and CI checkout
# directories are often named after a branch or job, so the basename is only
# a last resort.
workflow_contract_repo_name() {
  local root=${1:-} github_repository=${2:-} remote=${3:-}
  if [[ -n $github_repository ]]; then
    printf '%s\n' "${github_repository##*/}"
  elif [[ -n $remote ]]; then
    remote=${remote##*/}
    printf '%s\n' "${remote%.git}"
  else
    printf '%s\n' "${root##*/}"
  fi
}

# Resolve this checkout's repository name into WORKFLOW_CONTRACT_REPO and
# require it to be EXPECTED. The remote checks query the resolved name, so a
# fork or rename is rejected here instead of silently checking another repo.
workflow_contract_init() {
  local expected=${1:-} remote
  [[ -n $expected ]] || fail 'workflow_contract_init needs the expected repository name'
  remote=$(git config --get remote.origin.url 2>/dev/null) || remote=
  WORKFLOW_CONTRACT_REPO=$(workflow_contract_repo_name \
    "$PWD" "${GITHUB_REPOSITORY:-}" "$remote")
  [[ $WORKFLOW_CONTRACT_REPO == "$expected" ]] ||
    fail "unexpected repository name: $WORKFLOW_CONTRACT_REPO"
}

# test/run proves it executes workflow-test exactly once by pointing
# WORKFLOW_TEST_COUNT_FILE at a counter; standalone runs leave it unset.
workflow_contract_count_run() {
  local count=0
  [[ -n ${WORKFLOW_TEST_COUNT_FILE:-} ]] || return 0
  [[ ! -f $WORKFLOW_TEST_COUNT_FILE ]] || count=$(<"$WORKFLOW_TEST_COUNT_FILE")
  printf '%s\n' "$((count + 1))" >"$WORKFLOW_TEST_COUNT_FILE"
}

# Require the canonical MIT LICENSE bytes and the worktree-only .gitignore.
workflow_contract_check_files() {
  local license_hash
  if command -v sha256sum >/dev/null 2>&1; then
    license_hash=$(sha256sum LICENSE | awk '{print $1}')
  else
    license_hash=$(shasum -a 256 LICENSE | awk '{print $1}')
  fi
  [[ $license_hash == "$_workflow_contract_license_sha256" ]] ||
    fail 'LICENSE bytes differ from the canonical MIT license'
  [[ $(wc -c <LICENSE | tr -d '[:space:]') == "$_workflow_contract_license_bytes" ]] ||
    fail 'LICENSE size differs from the canonical MIT license'
  [[ $(<.gitignore) == '.worktrees/' ]] || fail '.gitignore must contain only .worktrees/'
}

# Overlays lint every inventoried shell file. shellcheck-inventory accepts
# `fixture` rows that it discovers but does not lint, so require that every
# row of the typed inventory at PATH is a `program`.
workflow_contract_check_inventory_programs() {
  local inventory=${1:-} type path
  [[ -f $inventory ]] || fail "missing ShellCheck inventory: $inventory"
  while IFS=$'\t' read -r type path || [[ -n $type ]]; do
    case $type in '' | \#*) continue ;; esac
    [[ $type == program ]] ||
      fail "ShellCheck inventory row is not a linted program: $type $path"
  done <"$inventory"
}

# One attempt at the GitHub-side contract: public, default branch main, MIT
# license detected, and the published LICENSE identical to this checkout's.
workflow_contract_remote_predicate() {
  local repo=${WORKFLOW_CONTRACT_REPO:?workflow_contract_init must run first}
  local remote_tmp
  command -v gh >/dev/null || fail 'gh is required for remote validation'
  [[ $(gh api "repos/cgraf78/$repo" --jq .visibility) == public ]] || fail 'remote repository is not public'
  [[ $(gh api "repos/cgraf78/$repo" --jq .default_branch) == main ]] || fail 'remote default branch is not main'
  [[ $(gh api "repos/cgraf78/$repo/license" --jq .license.spdx_id) == MIT ]] || fail 'remote license is not MIT'
  remote_tmp=$(mktemp -d)
  # Clear the trap as it fires so it cannot rerun, with `remote_tmp` out of
  # scope, when a caller's function later returns under `set -u`.
  trap 'rm -rf -- "$remote_tmp"; trap - RETURN' RETURN
  # `fail` exits, which skips the RETURN trap, so remove the download first
  # on each failure path; a bounded poll may run this dozens of times.
  if ! gh api --method GET "repos/cgraf78/$repo/contents/LICENSE" --jq .content |
    base64 --decode >"$remote_tmp/target-LICENSE"; then
    rm -rf -- "$remote_tmp"
    fail 'could not download the remote LICENSE'
  fi
  cmp -s "$remote_tmp/target-LICENSE" LICENSE || {
    rm -rf -- "$remote_tmp"
    fail 'remote license differs from the tested checkout'
  }
}

# Handle the contract script's `--remote-predicate` mode: run one remote
# attempt and exit before any local check. Other arguments return untouched.
workflow_contract_dispatch_predicate() {
  [[ ${1:-} == --remote-predicate ]] || return 0
  workflow_contract_remote_predicate
  exit 0
}

# Poll the remote contract by re-running SCRIPT in `--remote-predicate` mode.
# A predicate failure exits that child, so each attempt starts clean, and the
# bounded deadline absorbs GitHub's eventually consistent settings and
# license detection right after a push.
workflow_contract_poll_remote() {
  local script=${1:-}
  [[ -n $script ]] || fail 'workflow_contract_poll_remote needs the contract script path'
  # The poller is vendored beside this file in every consumer, and lives
  # beside it in the provider, so resolve it from this file, not the cwd.
  # shellcheck source=/dev/null
  . "$(dirname "${BASH_SOURCE[0]}")/wait-github-state.sh"
  wait_github_state 120 3 "$script" --remote-predicate
}
