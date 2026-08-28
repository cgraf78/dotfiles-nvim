# Neovim configuration

This directory owns the editor-profile Neovim configuration. The editor
profile covers navigation, sessions, buffers, file search, syntax, colors, and
basic Git indicators.

`init.lua` loads LazyVim and imports every plugin spec under `lua/plugins/`.
That directory is the stable additive extension point used by higher overlays.
The `dotfiles-dev` overlay contributes language services, debugging, AI
assistance, formatting, linting, and advanced Git workflows without replacing
this editor configuration. `lua/plugins/editor.lua` explicitly disables the
development services imported by LazyVim core; the dev overlay re-enables them
alongside its language extras.

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
