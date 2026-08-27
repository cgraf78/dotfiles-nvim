# Neovim Shdeps hook

The Neovim hook reserves the public `~/.local/bin/nvim` path for the
editor-aware launcher. It installs or links the actual editor at
`$(shdeps_install_dir)/neovim/neovim/bin/nvim`, including the native Termux
package path on Android.
