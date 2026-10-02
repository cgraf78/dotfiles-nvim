# Neovim configuration

This directory owns the editor-profile Neovim configuration. The editor
profile covers navigation, sessions, buffers, file search, syntax, colors, and
basic Git indicators.

`init.lua` waits for any scheduled Lazy plugin update and then requires
`config.lazy`. `lua/config/lazy.lua` loads plugin policy in five explicit
phases: LazyVim core, `lua/dotfiles/lazyvim_extras/`, ordinary `lua/plugins/`,
capability overrides under `lua/dotfiles/plugin_overrides/`, and final
constraints under `lua/dotfiles/final_policy/`. The empty editor-owned
extension modules make that ordering stable even when higher overlays are
absent. The `dotfiles-dev` overlay contributes language services, debugging,
AI assistance, formatting, linting, and advanced Git workflows through those
extension points without replacing this editor configuration.

`dot doctor` loads this configuration headless to report startup errors. It
sets `vim.g.plugin_install_disabled` first, so `config.lazy` neither clones
lazy.nvim nor installs missing plugins during the probe.

The editor-owned `nvim-workspace` options use only generic repository markers
and the tracked dotfiles HOME. Sley discovery and Lazygit routing are additive
dev-overlay policy.

`lua/config/keymaps.lua` loads optional higher-profile keymap domains only when
they are present. Editor-only machines therefore do not require development
modules.

Termnav owns Ctrl-h/j/k/l pane selection, Ctrl-backslash previous-pane
selection, Ctrl-Tab switching, Alt-Shift-bracket tab movement, and
Alt-Shift-H/J/K/L pane movement across Neovim and tmux boundaries.

The focused suites under `~/.local/lib/dotfiles/tests/` check editor startup,
plugin specs, shell/tmux integration, the launcher, update hook, and doctor.
