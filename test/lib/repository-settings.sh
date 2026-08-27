#!/usr/bin/env bash
# Manifest-driven GitHub repository policy export, comparison, and application.
set -euo pipefail

repo_root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd -P)
manifest=$repo_root/.github/repository-settings-endpoints.txt

die() {
  printf 'repository-settings: %s\n' "$*" >&2
  exit 1
}

repo_allowed() {
  case $1 in
    cgraf78/dotfiles | cgraf78/dotfiles-nvim | cgraf78/dotfiles-dev) return 0 ;;
    *) return 1 ;;
  esac
}

target_allowed() {
  case $1 in
    cgraf78/dotfiles-nvim | cgraf78/dotfiles-dev) return 0 ;;
    *) return 1 ;;
  esac
}

validate_manifest() {
  local file=${1:-$manifest} line family get_method get_path apply_method
  local apply_path normalizer absence extra index=0
  local -a expected=(repository actions_permissions actions_workflow actions_selected rulesets main_protection topics vulnerability_alerts automated_security_fixes private_vulnerability_reporting code_security_configuration interaction_limits pages environments)
  local -A seen=()

  [[ $(sed -n '1p' "$file") == '# version=1' ]] || die 'manifest must begin with # version=1'
  while IFS= read -r line || [[ -n $line ]]; do
    case $line in '' | \#*) continue ;; esac
    IFS=$'\t' read -r family get_method get_path apply_method apply_path normalizer absence extra <<<"$line"
    [[ -n $family && -z ${extra:-} ]] || die "invalid manifest record: $line"
    ((index < ${#expected[@]})) || die "unexpected manifest family: $family"
    [[ $family == "${expected[index]}" ]] || die "manifest family out of order: $family"
    [[ -z ${seen[$family]+x} ]] || die "duplicate manifest family: $family"
    seen[$family]=1
    case $get_method in GET | GET_PAGINATE) ;; *) die "unknown get method: $get_method" ;; esac
    case $apply_method in PATCH | PUT | PUT_OR_DELETE | SYNC | DELETE_IF_ATTACHED | DELETE_IF_PRESENT | DELETE_UNEXPECTED) ;; *) die "unknown apply method: $apply_method" ;; esac
    case $normalizer in repository | exact | rulesets | protection | topics | http_boolean | http_none | http_absent | environments) ;; *) die "unknown normalizer: $normalizer" ;; esac
    case $absence in forbidden | conflict_when_all | empty | no_content | empty_object | not_found) ;; *) die "unknown absence rule: $absence" ;; esac
    for path in "$get_path" "$apply_path"; do
      case $path in repos/'{repo}' | repos/'{repo}'/*) ;; *) die "unsafe manifest repository path: $path" ;; esac
      case $path in /* | */ | *//* | */./* | */../* | */. | */.. | *' '*) die "non-normalized manifest path: $path" ;; esac
      path=${path//\{repo\}/}
      path=${path//\{environment_name\}/}
      [[ $path != *'{'* && $path != *'}'* ]] || die "unknown path placeholder: $path"
    done
    index=$((index + 1))
  done <"$file"
  [[ $index -eq ${#expected[@]} ]] || die 'manifest is missing required families'
}

render_path() {
  local template=$1 repo=$2 environment_name=${3:-}
  REPLY=${template//\{repo\}/$repo}
  if [[ $REPLY == *'{environment_name}'* ]]; then
    [[ $environment_name =~ ^[A-Za-z0-9._-]+$ ]] || die 'unsafe environment name'
    REPLY=${REPLY//\{environment_name\}/$environment_name}
  fi
}

status_allowed() {
  local status=$1 absence=$2
  case $absence:$status in
    forbidden:200 | forbidden:204 | conflict_when_all:409 | empty:200 | no_content:204 | empty_object:200 | not_found:404) return 0 ;;
    *) return 1 ;;
  esac
}

source_state_allowed() {
  local family=$1 status=$2 absence=$3 body=$4
  status_allowed "$status" "$absence" || return 1
  case $family in
    repository)
      [[ $status == 200 ]] && jq -e 'type == "object" and (.visibility | type == "string") and (.default_branch | type == "string") and (.security_and_analysis | type == "object")' "$body" >/dev/null
      ;;
    actions_permissions)
      [[ $status == 200 ]] && jq -e '.enabled == true and .allowed_actions == "all" and (.sha_pinning_required | type == "boolean")' "$body" >/dev/null
      ;;
    actions_workflow)
      [[ $status == 200 ]] && jq -e '.default_workflow_permissions == "read" and (.can_approve_pull_request_reviews | type == "boolean")' "$body" >/dev/null
      ;;
    actions_selected) [[ $status == 409 ]] ;;
    rulesets) [[ $status == 200 && $(jq 'flatten | length' "$body") == 0 ]] ;;
    main_protection) [[ $status == 200 ]] && jq -e 'type == "object" and (.required_status_checks | type == "object") and (.enforce_admins.enabled | type == "boolean")' "$body" >/dev/null ;;
    topics) [[ $status == 200 ]] && jq -e '.names | type == "array"' "$body" >/dev/null ;;
    vulnerability_alerts) [[ $status == 204 && ! -s $body ]] ;;
    automated_security_fixes) [[ $status == 200 ]] && jq -e '(.enabled | type == "boolean") and (.paused | type == "boolean")' "$body" >/dev/null ;;
    private_vulnerability_reporting) [[ $status == 200 ]] && jq -e '.enabled | type == "boolean"' "$body" >/dev/null ;;
    code_security_configuration) [[ $status == 204 && ! -s $body ]] ;;
    interaction_limits) [[ $status == 200 && $(jq -c . "$body") == '{}' ]] ;;
    pages) [[ $status == 404 ]] ;;
    environments) [[ $status == 200 && $(jq '.environments | length' "$body") == 0 ]] ;;
    *) return 1 ;;
  esac
}

api_read() {
  local method=$1 path=$2 output=$3 rc=0
  local response=$output.response error=$output.error
  if [[ $method == GET_PAGINATE ]]; then
    gh api --paginate --slurp "$path" >"$output.body" 2>"$error" || rc=$?
    [[ $rc -eq 0 ]] || {
      cat "$error" >&2
      return "$rc"
    }
    printf '200\n' >"$output.status"
    rm -f "$error"
    return 0
  fi
  gh api --include "$path" >"$response" 2>"$error" || rc=$?
  awk '/^HTTP\// { status=$2 } END { if (status) print status }' "$response" >"$output.status"
  [[ -s $output.status ]] || {
    cat "$error" >&2
    return 1
  }
  awk 'body { sub(/\r$/, ""); print } /^\r?$/ { body=1 }' "$response" >"$output.body"
  rm -f "$response" "$error"
}

export_policy() {
  local repo=$1 output_dir=$2 line family get_method get_path apply_method
  local apply_path normalizer absence status
  repo_allowed "$repo" || die "repository is not allowlisted: $repo"
  validate_manifest
  [[ ! -e $output_dir ]] || die "export directory already exists: $output_dir"
  mkdir -p "$output_dir"
  while IFS= read -r line || [[ -n $line ]]; do
    case $line in '' | \#*) continue ;; esac
    IFS=$'\t' read -r family get_method get_path apply_method apply_path normalizer absence <<<"$line"
    render_path "$get_path" "$repo"
    api_read "$get_method" "$REPLY" "$output_dir/$family" || true
    [[ -s $output_dir/$family.status ]] || die "no HTTP status for $family"
    status=$(<"$output_dir/$family.status")
    if [[ $repo == cgraf78/dotfiles ]]; then
      source_state_allowed "$family" "$status" "$absence" "$output_dir/$family.body" || die "unexpected source state for $family: $status"
    else
      [[ $status =~ ^(200|204|404|409)$ ]] || die "unexpected target status for $family: $status"
    fi
  done <"$manifest"
  printf '%s\n' "$repo" >"$output_dir/repository-name"
}

normalize() {
  local family=$1 normalizer=$2 status=$3 body=$4
  case $normalizer in
    repository)
      [[ $status == 200 ]] || {
        printf 'status=%s\n' "$status"
        return
      }
      jq -S '{visibility,default_branch,has_issues,has_projects,has_wiki,has_pages,has_discussions,is_template,allow_forking,web_commit_signoff_required,allow_merge_commit,allow_squash_merge,allow_rebase_merge,allow_auto_merge,delete_branch_on_merge,allow_update_branch,use_squash_pr_title_as_default,squash_merge_commit_title,squash_merge_commit_message,archived,disabled,security_and_analysis}' "$body"
      ;;
    protection)
      [[ $status == 200 ]] || {
        printf 'status=%s\n' "$status"
        return
      }
      jq -S 'walk(if type == "object" then del(.url,.contexts_url) else . end) | if .required_status_checks then .required_status_checks.checks |= sort_by(.context,.app_id) | .required_status_checks.contexts |= sort else . end' "$body"
      ;;
    topics) jq -S '.names |= sort' "$body" ;;
    rulesets) jq -S 'flatten | sort_by(.name)' "$body" ;;
    environments) jq -S '.environments // [] | map(walk(if type == "object" then del(.id,.node_id,.url,.html_url,.deployment_branch_policy.url) else . end)) | sort_by(.name)' "$body" ;;
    http_boolean | http_none | http_absent) printf 'status=%s\n' "$status" ;;
    exact)
      if [[ -s $body ]]; then jq -S . "$body"; else printf 'status=%s\n' "$status"; fi
      ;;
  esac
}

compare_policy() {
  local source_dir=$1 target_dir=$2 target_repo=$3 line family get_method get_path
  local apply_method apply_path normalizer absence source_status target_status tmp expected_description
  target_allowed "$target_repo" || die "target is not allowlisted: $target_repo"
  [[ $(<"$source_dir/repository-name") == cgraf78/dotfiles ]] || die 'comparison source must be cgraf78/dotfiles'
  [[ $(<"$target_dir/repository-name") == "$target_repo" ]] || die 'target export identity mismatch'
  expected_description="Public ${target_repo#cgraf78/dotfiles-} capability overlay for cgraf78/dotfiles."
  jq -e --arg name "${target_repo#cgraf78/}" --arg description "$expected_description" '.owner.login == "cgraf78" and .name == $name and .description == $description and .visibility == "public" and .default_branch == "main"' "$target_dir/repository.body" >/dev/null || die 'target identity/description/public-main assertion failed'
  tmp=$(mktemp -d)
  trap 'rm -rf -- "$tmp"' RETURN
  while IFS= read -r line || [[ -n $line ]]; do
    case $line in '' | \#*) continue ;; esac
    IFS=$'\t' read -r family get_method get_path apply_method apply_path normalizer absence <<<"$line"
    source_status=$(<"$source_dir/$family.status")
    target_status=$(<"$target_dir/$family.status")
    normalize "$family" "$normalizer" "$source_status" "$source_dir/$family.body" >"$tmp/source"
    normalize "$family" "$normalizer" "$target_status" "$target_dir/$family.body" >"$tmp/target"
    diff -u "$tmp/source" "$tmp/target" || die "repository policy differs for $family"
  done <"$manifest"
}

api_input() {
  local method=$1 path=$2 payload=$3
  printf '%s\n' "$payload" | gh api --method "$method" "$path" --input - >/dev/null
}

apply_one() {
  local family=$1 target=$2 source_dir=$3 apply_method=$4 apply_path=$5
  local path status body payload id name
  status=$(<"$source_dir/$family.status")
  body=$source_dir/$family.body
  render_path "$apply_path" "$target"
  path=$REPLY
  case $family in
    repository)
      payload=$(jq -c --arg description "Public ${target#cgraf78/dotfiles-} capability overlay for cgraf78/dotfiles." '{description:$description,visibility,default_branch,has_issues,has_projects,has_wiki,has_discussions,is_template,allow_forking,web_commit_signoff_required,allow_merge_commit,allow_squash_merge,allow_rebase_merge,allow_auto_merge,delete_branch_on_merge,allow_update_branch,use_squash_pr_title_as_default,squash_merge_commit_title,squash_merge_commit_message,archived,security_and_analysis:(.security_and_analysis | with_entries(select(.key == "secret_scanning" or .key == "secret_scanning_push_protection" or .key == "secret_scanning_non_provider_patterns" or .key == "secret_scanning_validity_checks")))}' "$body")
      api_input "$apply_method" "$path" "$payload"
      ;;
    actions_permissions | actions_workflow) api_input "$apply_method" "$path" "$(jq -c . "$body")" ;;
    actions_selected)
      [[ $status == 409 ]] || die 'selected-actions source must conflict when allowed_actions=all'
      ;;
    rulesets)
      [[ $(jq 'flatten | length' "$body") == 0 ]] || die 'non-empty source rulesets require reviewed synchronization support'
      while IFS= read -r id; do gh api --method DELETE "repos/$target/rulesets/$id" >/dev/null; done < <(gh api --paginate --slurp "repos/$target/rulesets" --jq 'flatten[]?.id')
      ;;
    main_protection)
      payload=$(jq -c '{required_status_checks:(.required_status_checks | if . == null then null else {strict,checks} end),enforce_admins:.enforce_admins.enabled,required_pull_request_reviews:(.required_pull_request_reviews | if . == null then null else {dismissal_restrictions:{},dismiss_stale_reviews,require_code_owner_reviews,required_approving_review_count,require_last_push_approval} end),restrictions:null,required_linear_history:.required_linear_history.enabled,allow_force_pushes:.allow_force_pushes.enabled,allow_deletions:.allow_deletions.enabled,block_creations:.block_creations.enabled,required_conversation_resolution:.required_conversation_resolution.enabled,lock_branch:.lock_branch.enabled,allow_fork_syncing:.allow_fork_syncing.enabled}' "$body")
      api_input "$apply_method" "$path" "$payload"
      ;;
    topics) api_input "$apply_method" "$path" "$(jq -c '{names}' "$body")" ;;
    vulnerability_alerts)
      if [[ $status == 204 ]]; then gh api --method PUT "$path" >/dev/null; else gh api --method DELETE "$path" >/dev/null || true; fi
      ;;
    automated_security_fixes | private_vulnerability_reporting)
      [[ $status == 200 ]] || die "unexpected source status for $family: $status"
      if [[ $(jq -r '.enabled' "$body") == true ]]; then
        gh api --method PUT "$path" >/dev/null
      else
        gh api --method DELETE "$path" >/dev/null || true
      fi
      ;;
    code_security_configuration)
      [[ $status == 204 ]] || die 'source unexpectedly has an attached code-security configuration'
      gh api --method DELETE "$path" >/dev/null 2>&1 || true
      ;;
    interaction_limits)
      [[ $status == 200 && $(jq -c . "$body") == '{}' ]] || die 'source interaction limit is not empty'
      gh api --method DELETE "$path" >/dev/null 2>&1 || true
      ;;
    pages)
      [[ $status == 404 ]] || die 'source unexpectedly has Pages enabled'
      gh api --method DELETE "$path" >/dev/null 2>&1 || true
      ;;
    environments)
      [[ $(jq '.environments | length' "$body") == 0 ]] || die 'source environments are not empty'
      while IFS= read -r name; do
        [[ $name =~ ^[A-Za-z0-9._-]+$ ]] || die 'unsafe target environment name'
        render_path "$apply_path" "$target" "$name"
        gh api --method DELETE "$REPLY" >/dev/null
      done < <(gh api --paginate "repos/$target/environments" --jq '.environments[]?.name')
      ;;
  esac
}

apply_policy() {
  local target=$1 source_dir=$2 family line get_method get_path apply_method apply_path normalizer absence status
  local -a order=(repository actions_permissions actions_workflow actions_selected topics vulnerability_alerts automated_security_fixes private_vulnerability_reporting code_security_configuration interaction_limits pages environments rulesets main_protection)
  local -A methods=() paths=()
  target_allowed "$target" || die "target is not allowlisted: $target"
  [[ $(<"$source_dir/repository-name") == cgraf78/dotfiles ]] || die 'apply source must be cgraf78/dotfiles'
  validate_manifest
  while IFS= read -r line || [[ -n $line ]]; do
    case $line in '' | \#*) continue ;; esac
    IFS=$'\t' read -r family get_method get_path apply_method apply_path normalizer absence <<<"$line"
    [[ -s $source_dir/$family.status && -f $source_dir/$family.body ]] || die "missing required source read: $family"
    status=$(<"$source_dir/$family.status")
    source_state_allowed "$family" "$status" "$absence" "$source_dir/$family.body" || die "unusable source state for $family: $status"
    methods[$family]=$apply_method
    paths[$family]=$apply_path
  done <"$manifest"
  for family in "${order[@]}"; do apply_one "$family" "$target" "$source_dir" "${methods[$family]}" "${paths[$family]}"; done
}

self_test() {
  local tmp body
  validate_manifest
  repo_allowed cgraf78/dotfiles
  target_allowed cgraf78/dotfiles-nvim
  if target_allowed cgraf78/dotfiles; then die 'source repository accepted as a mutation target'; fi
  if repo_allowed example/other; then die 'unknown repository accepted'; fi
  tmp=$(mktemp)
  trap 'rm -f -- "$tmp"' RETURN
  sed 's/^topics\t/topics2\t/' "$manifest" >"$tmp"
  if (validate_manifest "$tmp") >/dev/null 2>&1; then
    die 'manifest validator accepted an unknown family'
  fi
  awk 'BEGIN { FS=OFS="\t" } /^repository\t/ { $3="repos/{repo}-other" } { print }' "$manifest" >"$tmp"
  if (validate_manifest "$tmp") >/dev/null 2>&1; then
    die 'manifest validator accepted a repository-prefix escape'
  fi
  body=$(mktemp)
  trap 'rm -f -- "$tmp" "$body"' RETURN
  if source_state_allowed actions_permissions 204 forbidden "$body"; then
    die 'preflight accepted an empty actions-permissions source'
  fi
  printf '{"enabled":"invalid","paused":false}\n' >"$body"
  if source_state_allowed automated_security_fixes 200 forbidden "$body"; then
    die 'preflight accepted a malformed enabled value'
  fi
}

case ${1:-} in
  validate) validate_manifest ;;
  export)
    (($# == 3)) || die 'usage: repository-settings.sh export REPO OUTPUT_DIR'
    export_policy "$2" "$3"
    ;;
  compare)
    (($# == 4)) || die 'usage: repository-settings.sh compare SOURCE_DIR TARGET_DIR TARGET_REPO'
    compare_policy "$2" "$3" "$4"
    ;;
  apply)
    (($# == 3)) || die 'usage: repository-settings.sh apply TARGET_REPO SOURCE_DIR'
    apply_policy "$2" "$3"
    ;;
  --self-test) self_test ;;
  *) die 'usage: repository-settings.sh validate|export|compare|apply|--self-test' ;;
esac
