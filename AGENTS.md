# AGENTS.md

## About

The public `editor` profile overlay for
[cgraf78/dotfiles](https://github.com/cgraf78/dotfiles). Only files under
`home/` are linked into `$HOME`. The base repo selects this overlay; nothing
here defines or changes profile selection.

- Configuration may use only tools this overlay owns or inherits from base.
  Development-only language tooling and Git workflows belong in
  `dotfiles-dev`.
- No private, employer-specific, host-specific, or user-specific material.
- A capability's install declaration, config, runtime hooks, focused tests,
  doctor checks, and docs live and move together.
- The tmux fragment (`home/.config/tmux/conf.d/20-editor.conf`) holds only
  keys that need Neovim on the other end. Base owns mouse mode and pane, tab,
  and link routing.

## Layout

- `home/.config/nvim/`: the config. `lua/config/lazy.lua` loads plugins in
  five phases: LazyVim core, `lua/dotfiles/lazyvim_extras/`, `lua/plugins/`,
  `lua/dotfiles/plugin_overrides/`, then `lua/dotfiles/final_policy/`. The
  empty modules are deliberate extension points for higher overlays.
- `home/.config/{tmux,shell,ripgrep,shdeps}`: fragments, including the
  Neovim and tree-sitter CLI declarations.
- `home/.local/lib/dotfiles/tests/`: focused suites; `docs/`: component docs.
- `test/run`: the suite runner. `test/workflow-test`: the repo contract.
- `test/lib/`: vendored from cgraf78/actions `capability-harness/`.

## Invariants

- The `installed-editor` incremental footprint (Neovim, config, state,
  cache, and the resolved plugin graph) must stay at or under 500 MiB.
  Adding plugins can fail CI. It is measured on macOS and glibc Linux;
  other libcs (musl, Android) and Neovim older than 0.11.2 skip it.

## Testing

- `test/run`: what CI runs. It needs network (it installs the latest Dot
  release unless `DOT_TEST_DOT_RELEASE_TAG` names one; `test/workflow-test`
  rejects a tag committed in `test/run` or a workflow) and `nvim` in a system
  root or an absolute `CAPABILITY_TEST_NVIM`. An absolute
  `CAPABILITY_TEST_NVIM_DATA_HOME` (an XDG data root that runs write to, so
  use a scratch copy) reuses installed plugins. No gate runs selene.
- `test/workflow-test` (`--remote` also checks GitHub and needs `gh`).

## Test isolation

Suites run on a restricted PATH: only the `required_commands` in `test/run`,
resolved from `$PREFIX/bin` (Termux), `/opt/homebrew/bin`, `/usr/local/bin`,
`/usr/bin`, and `/bin`; `~/.local/bin` and mise shims are not visible. A new
tool needs three paired edits:
`required_commands`, the `profiles:` line in `.github/workflows/test.yml`, and
the matching `grep -Fx` line in `test/workflow-test`.

## CI and generated files

- CI's ShellCheck job fails on any shell program missing from
  `.github/shellcheck-files.txt` (untracked files included) and on stale rows;
  `test/run` runs no ShellCheck. Rows must be `program`. Before pushing, run
  `SHELLCHECK_EXCLUDE_CODES=SC1091 bash <actions@lock>/.github/actions/shellcheck-inventory/run.sh "$PWD" .github/shellcheck-files.txt`.
- Every executable suite must be listed in `.github/dot-test-suites.txt`;
  `test/run` rejects unlisted ones.
- `.github/cgraf78-actions.lock` and every `uses: cgraf78/actions/...@sha`
  move together, only via `consumer-ci/sync.sh <this checkout>` run from
  cgraf78/actions at the locked SHA. The same command refreshes `test/lib/*`;
  change those files in actions, never here.
- `test/workflow-test` pins exact lines of `test.yml` (name, cron
  `23 9 * * *`, the `profiles:` list, the `installed-profiles` inputs), the
  `20-nvim.conf` fixture call and footprint labels in `test/run`, and the
  LICENSE and `.gitignore` bytes. Edit it together with any of those.
- `retry-infrastructure.yml` keys on the workflow name `Tests`; keep it.
- The `installed-profiles` job calls base `installed-profiles.yml@main` with
  profiles `editor dev`, so a base change can turn this repo red. `nvim-test`
  defers its editor-only checks to the editor home when dev is installed.

## Release

None; installs track `main`.
