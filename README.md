# dotfiles-nvim

[![Tests](https://github.com/cgraf78/dotfiles-nvim/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/cgraf78/dotfiles-nvim/actions/workflows/test.yml?query=branch%3Amain)
[![License](https://img.shields.io/badge/license-MIT-67ac09)](LICENSE)

My Neovim configuration, built on [LazyVim](https://www.lazyvim.org/):

- VS Code-style editing keys: Shift-arrow selection, Ctrl-C/X/V clipboard,
  Ctrl-F find, and F2/F12 LSP aliases.
- Workspace-aware file search, grep, and explorer via
  [nvim-workspace](https://github.com/cgraf78/nvim-workspace).
- Ctrl-h/j/k/l navigation across Neovim and tmux panes, including tmux on a
  remote host reached through `termnav ssh`, via
  [termnav](https://github.com/cgraf78/termnav) and the tmux bindings in my
  base dotfiles.
- A copy-only OSC 52 clipboard for remote sessions outside tmux.

The config lives in [`home/.config/nvim/`](home/.config/nvim/); its
[README](home/.config/nvim/README.md) explains the plugin load order and
integrations.

This is the editor layer of my [dotfiles](https://github.com/cgraf78/dotfiles):
an [overlay](https://github.com/cgraf78/dot/blob/main/docs/overlays.md) whose
`home/` tree is linked into `$HOME` on top of the base repo. It is installed by
default there (the `editor` profile), and
[dotfiles-dev](https://github.com/cgraf78/dotfiles-dev) adds language
servers, debugging, formatting, and Git workflows on top.

It is not a drop-in config. Startup loads termnav through
[shdeps](https://github.com/cgraf78/shdeps), so copying `home/.config/nvim/`
alone fails without the dotfiles runtime. Borrow individual files instead.

Maintainer and agent notes (ownership rules, tests, CI) are in
[AGENTS.md](AGENTS.md).
