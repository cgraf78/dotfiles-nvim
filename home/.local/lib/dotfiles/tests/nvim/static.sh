# shellcheck shell=bash

nvim_test_static() {
  local owner_root config

  owner_root=$(_nvim_repo_root)
  config=$owner_root/home/.config/nvim

  nvim_test_assert 'Neovim init exists' test -f "$config/init.lua"
  nvim_test_assert 'editor plugin spec exists' test -f "$config/lua/plugins/editor.lua"
  nvim_test_assert 'workspace plugin spec exists' test -f "$config/lua/plugins/workspace.lua"
  nvim_test_assert 'LazyVim extras extension exists' \
    test -f "$config/lua/dotfiles/lazyvim_extras/init.lua"
  nvim_test_assert 'plugin override extension exists' \
    test -f "$config/lua/dotfiles/plugin_overrides/init.lua"
  nvim_test_assert 'final policy extension exists' \
    test -f "$config/lua/dotfiles/final_policy/init.lua"
  nvim_test_assert 'Lazy imports have an explicit capability order' awk '
    /import = "lazyvim.plugins"/ { core = NR }
    /import = "dotfiles.lazyvim_extras"/ { extras = NR }
    /import = "plugins"/ { plugins = NR }
    /import = "dotfiles.plugin_overrides"/ { overrides = NR }
    /import = "dotfiles.final_policy"/ { policy = NR }
    END { exit !(core && extras && plugins && overrides && policy &&
      core < extras && extras < plugins && plugins < overrides &&
      overrides < policy) }
  ' "$config/lua/config/lazy.lua"
  nvim_test_assert 'development coding spec is absent' test ! -e "$config/lua/plugins/coding.lua"
  nvim_test_assert 'development formatting spec is absent' test ! -e "$config/lua/plugins/formatting.lua"
  nvim_test_assert 'development linting spec is absent' test ! -e "$config/lua/plugins/linting.lua"
  nvim_test_assert 'Mason policy is absent' test ! -e "$config/lua/config/mason-policy.lua"
  nvim_test_assert 'Copilot config is absent' test ! -e "$config/lua/plugins/copilot.lua"
  nvim_test_not_contains 'editor profile selects no dev-only LazyVim extra' \
    'mason-org|mason-nvim|nvim-dap|copilot|clangd|rust_analyzer|tsserver|none-ls|nvim-lint|conform.nvim' \
    "$config/lazyvim.json"

  nvim_test_env_defaults "$owner_root/home/.config/shell/env.d"
  nvim_test_env_real_loader "$owner_root/home/.config/shell/env.d"
  nvim_test_contains 'editor profile defines vi alias' "alias vi='nvim'" \
    "$owner_root/home/.config/shell/interactive.d/60-editor-aliases.sh"
  nvim_test_contains 'ripgrep editor config owns link host routing' '--hostname-bin=ripgrep-link-host' \
    "$owner_root/home/.config/ripgrep/config.editor"
  nvim_test_assert 'ripgrep editor adapter is executable' \
    test -x "$owner_root/home/.local/bin/ripgrep-link-host"
  nvim_test_portability "$owner_root"
}

# Termux portability for the suites themselves, as base's static suite checks
# its own: a bare `env -i` drops the libtermux-exec LD_PRELOAD that Termux's
# Google Play build needs for every nested exec, and a literal /usr/bin:/bin
# fixture PATH has no userland under Termux. CI's Termux build reproduces
# neither. helpers.sh owns DOT_TEST_ENV_CLEAN and DOT_TEST_SYSTEM_PATH; a
# deliberate literal PATH carries the marker on the line above.
nvim_test_portability() {
  local owner_root=$1 rel findings=''

  while IFS= read -r rel; do
    case $rel in *.md | *.py | *.lua) continue ;; esac
    [[ -f $owner_root/$rel && ! -L $owner_root/$rel ]] || continue
    # The patterns are split so this check never matches its own source.
    findings+=$(awk -v rel="$rel" -v env_i='env'' -i' \
      -v sys_path='/usr/bin'':/bin' -v marker='dot-test-portability:'' literal system PATH' '
      {
        code = $0
        sub(/^[ \t]+/, "", code)
        if (code !~ /^#/ && code !~ /^DOT_TEST_(ENV_CLEAN|SYSTEM_PATH)=/) {
          if (index($0, env_i)) print rel ":" NR ": clears the environment without DOT_TEST_ENV_CLEAN"
          if (index($0, sys_path) && index(previous, marker) == 0)
            print rel ":" NR ": literal system PATH; use DOT_TEST_SYSTEM_PATH"
        }
        previous = $0
      }' "$owner_root/$rel")
  done < <(git -C "$owner_root" ls-files -- home/.local/lib/dotfiles/tests)
  _assert_eq 'Termux portability: suites use the shared clean env and system PATH' \
    '' "$findings"
}

# The editor env.d fragments export through base's _shell_env_set. They must
# work on a base checkout without it (plain exports, the pre-helper behavior)
# and must route every value through it, so a fill-only load keeps a caller's
# EDITOR. The stub mirrors base's fill-only contract: keep any set value.
nvim_test_env_defaults() {
  local env_d=$1 sh probe fill got
  # shellcheck disable=SC2016 # Expansion belongs to the isolated child shell.
  probe='. "$1"; . "$2"; printf "%s|%s|%s" "$EDITOR" "$NVIM_COLORSCHEME" "$RIPGREP_CONFIG_PATH"'
  # shellcheck disable=SC2016 # Expansion belongs to the isolated child shell.
  fill='_shell_env_set() { eval "[ -n \"\${$1+x}\" ]" || export "$1=$2"; }; '
  for sh in bash zsh; do
    command -v "$sh" >/dev/null 2>&1 || continue
    got=$("${DOT_TEST_ENV_CLEAN[@]}" HOME=/fixture PATH="$PATH" EDITOR=vim \
      "$sh" -c "$probe" _ "$env_d/60-editor.sh" "$env_d/80-editor-defaults.sh")
    _assert_eq "editor env ($sh): plain exports without the base helper" \
      "nvim|night-owl|/fixture/.config/ripgrep/config.editor" "$got"
    got=$("${DOT_TEST_ENV_CLEAN[@]}" HOME=/fixture PATH="$PATH" EDITOR=vim \
      "$sh" -c "$fill$probe" _ "$env_d/60-editor.sh" "$env_d/80-editor-defaults.sh")
    _assert_eq "editor env ($sh): fill-only load keeps a caller EDITOR" \
      "vim|night-owl|/fixture/.config/ripgrep/config.editor" "$got"
    got=$("${DOT_TEST_ENV_CLEAN[@]}" HOME=/fixture PATH="$PATH" RIPGREP_CONFIG_PATH=/caller/rg \
      "$sh" -c "$fill$probe" _ "$env_d/60-editor.sh" "$env_d/80-editor-defaults.sh")
    _assert_eq "editor env ($sh): fill-only load keeps a caller ripgrep config" \
      "nvim|night-owl|/caller/rg" "$got"
  done
}

# With a base checkout that ships _shell_env_set, run a real fill-only load of
# base's 50-core.sh plus these fragments: the overlay must still replace
# base's RIPGREP_CONFIG_PATH within one load (the helper tracks names it
# exported), while values the caller passed down survive.
nvim_test_env_real_loader() {
  local env_d=$1 base=${DOT_TEST_SOURCE_HOME:-$HOME} fx sh got
  if ! grep -q '^_shell_env_set()' "$base/.local/lib/dotfiles/shell-loader.sh" 2>/dev/null; then
    printf 'SKIP: editor env real-loader checks (base predates _shell_env_set)\n'
    return 0
  fi
  fx=$(_tmpdir)
  mkdir -p "$fx/.config/shell/env.d" "$fx/.local/lib/dotfiles"
  cp "$base/.local/lib/dotfiles/shell-loader.sh" "$fx/.local/lib/dotfiles/"
  cp "$base/.config/shell/env-noninteractive.sh" "$fx/.config/shell/"
  cp "$base/.zshenv" "$fx/"
  cp "$base/.config/shell/env.d/50-core.sh" "$env_d/60-editor.sh" \
    "$env_d/80-editor-defaults.sh" "$fx/.config/shell/env.d/"
  for sh in bash zsh; do
    command -v "$sh" >/dev/null 2>&1 || continue
    # shellcheck disable=SC2016 # Expansion belongs to the isolated child shell.
    got=$("${DOT_TEST_ENV_CLEAN[@]}" HOME="$fx" ZDOTDIR="$fx" PATH="$PATH" \
      BASH_ENV="$fx/.config/shell/env-noninteractive.sh" \
      "$sh" -c 'printf "%s|%s" "$EDITOR" "$RIPGREP_CONFIG_PATH"' </dev/null)
    _assert_eq "editor env ($sh): real fill-only load layers over base" \
      "nvim|$fx/.config/ripgrep/config.editor" "$got"
    # shellcheck disable=SC2016 # Expansion belongs to the isolated child shell.
    got=$("${DOT_TEST_ENV_CLEAN[@]}" HOME="$fx" ZDOTDIR="$fx" PATH="$PATH" EDITOR=vim \
      RIPGREP_CONFIG_PATH=/caller/rg \
      BASH_ENV="$fx/.config/shell/env-noninteractive.sh" \
      "$sh" -c 'printf "%s|%s" "$EDITOR" "$RIPGREP_CONFIG_PATH"' </dev/null)
    _assert_eq "editor env ($sh): real fill-only load keeps caller values" \
      "vim|/caller/rg" "$got"
  done
}
