# dotfiles-nvim

[![Tests](https://github.com/cgraf78/dotfiles-nvim/actions/workflows/test.yml/badge.svg)](https://github.com/cgraf78/dotfiles-nvim/actions/workflows/test.yml)

Public Neovim capability overlay for the top-level
[`cgraf78/dotfiles`](https://github.com/cgraf78/dotfiles) environment.

Only files below `home/` are linked into a user's home directory. The
top-level dotfiles profile selects this repository; this overlay never defines
or changes profile selection. Installation declarations, configuration,
runtime hooks, focused tests, doctor checks, and component documentation move
together under the capability that owns them.

Configuration here may use only tools owned by this overlay or inherited from
a lower profile. Private, employer-specific, host-specific, and user-specific
material is forbidden.
