# dotfiles-nvim

[![Tests](https://github.com/cgraf78/dotfiles-nvim/actions/workflows/test.yml/badge.svg)](https://github.com/cgraf78/dotfiles-nvim/actions/workflows/test.yml)

Public Neovim capability overlay for the top-level
[`cgraf78/dotfiles`](https://github.com/cgraf78/dotfiles) environment.

This repository is the payload selected by the `editor` profile. It owns the
Neovim binary declaration, editor configuration, navigation and UI plugins,
editor shell/tmux/ripgrep fragments, update hook, focused tests, doctor checks,
and documentation. Development-only language tooling and Git workflows are
added by `dotfiles-dev`.

Only files below `home/` are linked into a user's home directory. The
top-level dotfiles profile selects this repository; this overlay never defines
or changes profile selection. Installation declarations, configuration,
runtime hooks, focused tests, doctor checks, and component documentation move
together under the capability that owns them.

Configuration here may use only tools owned by this overlay or inherited from
a lower profile. Private, employer-specific, host-specific, and user-specific
material is forbidden.

## Local verification

Run `test/run`. The harness creates a temporary no-base Dot client, selects
this checkout as a `sync=none` overlay, converges it into an isolated HOME, and
runs only the suites listed in `.github/dot-test-suites.txt`. Because Dot does
not authorize executable extensions from `sync=none` sources, update-time
extension discovery points at an empty inherited fixture root; the owner suites
then exercise this overlay's hooks and doctor code explicitly. The top-level
profile integration tests cover automatic extension discovery from the real
Git-backed overlay.

The harness reports two deliberately separate footprint scopes. The
`source-harness` figures cover the linked editor configuration, the selected
Neovim executable, and isolated state/cache artifacts; they are not presented
as a package-install estimate. The `installed-editor` figures add the real
Lazy plugin graph resolved by the full configuration smoke test and enforce
the editor profile's 500 MiB measured incremental budget. This measures the
selected executable rather than every file in a distribution-specific Neovim
package, which is not portable across the CI matrix.

For a network-free local run, set `CAPABILITY_TEST_NVIM_DATA_HOME` to an
existing Neovim data directory. The suite still resolves this checkout's
editor-only graph and measures only the plugin directories in that resolved
graph; unrelated installed development plugins are excluded.
