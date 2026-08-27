# Neovim dependency declaration

`20-nvim.conf` declares only the Neovim editor itself. The adjacent custom hook
keeps `~/.local/bin/nvim` available for the tmux-aware launcher and installs the
real binary below the Shdeps-managed installation root.

Language servers, debuggers, formatters, linters, Git workflow tools, and other
development dependencies belong to the `dotfiles-dev` overlay.
