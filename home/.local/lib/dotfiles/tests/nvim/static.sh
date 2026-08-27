# shellcheck shell=bash

nvim_test_static() {
  local owner_root config

  owner_root=$(_nvim_repo_root)
  config=$owner_root/home/.config/nvim

  nvim_test_assert 'Neovim init exists' test -f "$config/init.lua"
  nvim_test_assert 'editor plugin spec exists' test -f "$config/lua/plugins/editor.lua"
  nvim_test_assert 'workspace plugin spec exists' test -f "$config/lua/plugins/workspace.lua"
  nvim_test_assert 'development coding spec is absent' test ! -e "$config/lua/plugins/coding.lua"
  nvim_test_assert 'development formatting spec is absent' test ! -e "$config/lua/plugins/formatting.lua"
  nvim_test_assert 'development linting spec is absent' test ! -e "$config/lua/plugins/linting.lua"
  nvim_test_assert 'Mason policy is absent' test ! -e "$config/lua/config/mason-policy.lua"
  nvim_test_assert 'Copilot config is absent' test ! -e "$config/lua/plugins/copilot.lua"
  nvim_test_not_contains 'editor profile selects no dev-only LazyVim extra' \
    'mason-org|mason-nvim|nvim-dap|copilot|clangd|rust_analyzer|tsserver|none-ls|nvim-lint|conform.nvim' \
    "$config/lazyvim.json"

  nvim_test_contains 'editor profile sets EDITOR' 'export EDITOR=nvim' \
    "$owner_root/home/.config/shell/env.d/80-editor-defaults.sh"
  nvim_test_contains 'editor profile sets its colorscheme' 'export NVIM_COLORSCHEME=night-owl' \
    "$owner_root/home/.config/shell/env.d/80-editor-defaults.sh"
  nvim_test_contains 'editor profile defines vi alias' "alias vi='nvim'" \
    "$owner_root/home/.config/shell/interactive.d/60-editor-aliases.sh"
  nvim_test_contains 'ripgrep editor config owns link host routing' '--hostname-bin=nvim-link-host' \
    "$owner_root/home/.config/ripgrep/config.editor"
}
