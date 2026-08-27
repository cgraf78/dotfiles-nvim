#!/usr/bin/env bash
# Poll a GitHub-state predicate with a bounded monotonic deadline.
set -euo pipefail

wait_github_state() {
  local timeout_seconds=$1 interval_seconds=$2
  shift 2
  [[ $timeout_seconds =~ ^[1-9][0-9]*$ ]] || {
    echo 'wait-github-state: timeout must be a positive integer' >&2
    return 2
  }
  [[ $interval_seconds =~ ^([0-9]+)(\.[0-9]+)?$ ]] || {
    echo 'wait-github-state: interval must be non-negative' >&2
    return 2
  }
  (($# > 0)) || {
    echo 'wait-github-state: missing predicate command' >&2
    return 2
  }

  local started=$SECONDS output rc
  while :; do
    if output=$("$@" 2>&1); then
      [[ -z $output ]] || printf '%s\n' "$output"
      return 0
    else
      rc=$?
    fi
    if ((SECONDS - started >= timeout_seconds)); then
      printf 'wait-github-state: timed out after %ss (last exit %s)\n' \
        "$timeout_seconds" "$rc" >&2
      [[ -z $output ]] || printf '%s\n' "$output" >&2
      return 1
    fi
    sleep "$interval_seconds"
  done
}

wait_github_state_self_test() {
  local tmp predicate output started
  tmp=$(mktemp -d)
  trap 'rm -rf -- "$tmp"' RETURN
  predicate=$tmp/predicate
  cat >"$predicate" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
state_file=$1
count=0
[[ ! -f $state_file ]] || count=$(<"$state_file")
count=$((count + 1))
printf '%s\n' "$count" >"$state_file"
if ((count == 1)); then
  printf 'HTTP 404 attempt %s\n' "$count"
  exit 1
fi
if ((count == 2)); then
  printf 'stale normalized settings diff on attempt %s\n' "$count"
  exit 1
fi
printf 'ready on attempt %s\n' "$count"
EOF
  chmod +x "$predicate"
  output=$(wait_github_state 2 0.01 "$predicate" "$tmp/state")
  [[ $output == 'ready on attempt 3' ]]

  started=$SECONDS
  wait_github_state 5 1 true
  ((SECONDS - started < 1))

  if output=$(wait_github_state 1 0.05 sh -c 'echo "last normalized diff"; exit 7' 2>&1); then
    echo 'wait-github-state: never-ready predicate unexpectedly passed' >&2
    return 1
  fi
  [[ $output == *'last exit 7'* && $output == *'last normalized diff'* ]]
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
  if [[ ${1:-} == --self-test ]]; then
    wait_github_state_self_test
  elif (($# >= 3)); then
    wait_github_state "$@"
  else
    echo 'usage: wait-github-state.sh TIMEOUT INTERVAL COMMAND [ARG ...]' >&2
    exit 2
  fi
fi
