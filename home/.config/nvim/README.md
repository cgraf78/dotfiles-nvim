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

`lua/config/keymaps.lua` loads the editor-owned VSCode-style domain
(`lua/config/keymaps/vscode/`): Shift-arrow selection, Ctrl-C/X/V clipboard,
Ctrl-F find, and F2/F12 LSP aliases. Higher overlays add their own mappings
through the extension points above; the dev overlay's Lazygit mapping is one.

Termnav owns Ctrl-h/j/k/l pane selection, Ctrl-backslash previous-pane
selection, Ctrl-Tab switching, Alt-Shift-bracket tab movement, and
Alt-Shift-H/J/K/L pane movement across Neovim and tmux boundaries.

In remote sessions (by Termnav's `link-host` notion, which also covers
transports without `SSH_CONNECTION`), `lua/config/remote-open.lua` forwards
`vim.ui.open` URLs to the local desktop through `termnav open-url`. Local
sessions, VS Code terminals, file paths, an explicit `opt.cmd`, a missing,
broken, or older Termnav, an outer terminal Termnav cannot confirm is
WezTerm, and failed delivery all fall back to Neovim's own opener. Inside
tmux, Termnav itself skips VS Code clients per request.
Overlays that wrap other openers can call its `forward(url)` and run their own
fallback through `fallback(fn, ...)` so it does not forward again, and an
overlay that knows its whole host is remote can set
`vim.g.remote_open_assume_remote = true` to skip the per-session check.

`lua/config/clipboard.lua` gives remote sessions outside tmux a copy-only
OSC 52 clipboard. A session is remote when `SSH_CONNECTION` or `SSH_TTY` is
set or an overlay sets `vim.g.remote_open_assume_remote`. 'clipboard' stays
`unnamedplus`, which keeps Neovim from picking its own OSC 52 provider; that
provider would also paste with OSC 52 and wait on terminals such as WezTerm
that never answer the read. Yanks and deletes go to the local clipboard
through OSC 52, and `p` puts what this editor session last copied, or before
then, Neovim's unnamed register, which ShaDa restores across restarts. Local
sessions, tmux (whose provider already forwards copies), VS Code terminals,
UIs without a terminal such as vscode-neovim, headless runs, an explicit
`g:clipboard`, and any clipboard tool Neovim finds keep Neovim's own
provider choice. Neovim 0.11 also counts a running tmux server as such a
tool even outside tmux; 0.12 does not.

The provider is named `OSC 52`, like Neovim's own, because plugins key on
that name to mean that `+` and `*` do not reflect the real clipboard:

- Yanky keeps its default register and every save and restore on `"`, so
  its put wrappers and picker never send this editor's older text to the
  local clipboard. Its picker's set-default-register action writes only
  `"`. If Yanky ever drops that name check, its save and restore would send
  the temporary text and then the old text over OSC 52.
- The which-key and Snacks register lists show `+` and `*` as not checked.

The focused suites under `~/.local/lib/dotfiles/tests/` check editor startup,
plugin specs, shell/tmux integration, the launcher, update hook, and doctor.
