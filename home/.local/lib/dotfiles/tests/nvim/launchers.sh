# shellcheck shell=bash

nvim_test_launchers() {
  local launcher=$HOME/.local/bin/nvim result expected
  local nvim_launcher_home nvim_launcher_cwd nvim_launcher_provider
  local nvim_reuse_home nvim_missing_rc nvim_missing_output
  local nvim_launcher_path=$PATH nvim_reuse_path=$PATH

  _nvim_launcher_test_shdeps() {
    local home=$1
    mkdir -p "$home/.local/bin"
    cat >"$home/.local/bin/shdeps" <<'SHDEPS'
#!/usr/bin/env bash
[[ ${DOT_SHDEPS_TEST_MISSING:-0} != 1 ]] || exit 1
[[ ${1:-} == dep-file && ${2:-} == cgraf78/termnav &&
  ${3:-} == lib/termnav/nvim-open/launcher.sh ]] || exit 1
[[ -r ${NVIM_LAUNCHER_PROVIDER:-} ]] || exit 1
printf '%s\n' "$NVIM_LAUNCHER_PROVIDER"
SHDEPS
    chmod +x "$home/.local/bin/shdeps"
  }

  nvim_test_assert 'Neovim launcher is executable' test -x "$launcher"
  nvim_test_not_contains 'Neovim launcher does not search for alternate editors' \
    '_dot_launcher_find_real' "$launcher"

  nvim_launcher_home=$(_tmpdir)
  nvim_launcher_cwd="$nvim_launcher_home/project"
  nvim_launcher_provider="$nvim_launcher_home/termnav-nvim-launcher.sh"
  mkdir -p "$nvim_launcher_home/.local/share/neovim/neovim/bin" "$nvim_launcher_cwd"
  _nvim_launcher_test_shdeps "$nvim_launcher_home"
  nvim_launcher_path=$nvim_launcher_home/.local/bin:$PATH

  cat >"$nvim_launcher_home/.local/share/neovim/neovim/bin/nvim" <<'MOCK'
#!/usr/bin/env bash
printf 'real:%s:%s\n' "$PWD" "$*"
MOCK
  chmod +x "$nvim_launcher_home/.local/share/neovim/neovim/bin/nvim"

  cat >"$nvim_launcher_provider" <<'MOCK'
termnav_nvim_try_reuse() {
  printf 'provider:%s:%s\n' "$PWD" "$*"
  [[ "${NVIM_TEST_REUSE:-0}" == 1 ]]
}
MOCK

  result=$(
    cd "$nvim_launcher_cwd" || exit
    HOME="$nvim_launcher_home" PATH="$nvim_launcher_path" \
      NVIM_LAUNCHER_PROVIDER="$nvim_launcher_provider" \
      NVIM_TEST_REUSE=1 "$launcher" src/app.lua
  )
  _assert_eq "nvim launcher: delegates pane reuse to Termnav in the caller cwd" \
    "provider:$nvim_launcher_cwd:src/app.lua" "$result"

  nvim_reuse_home=$(_tmpdir)
  _nvim_launcher_test_shdeps "$nvim_reuse_home"
  nvim_reuse_path=$nvim_reuse_home/.local/bin:$PATH
  result=$(
    cd "$nvim_launcher_cwd" || exit
    HOME="$nvim_reuse_home" PATH="$nvim_reuse_path" \
      NVIM_LAUNCHER_PROVIDER="$nvim_launcher_provider" \
      NVIM_TEST_REUSE=1 "$launcher" src/app.lua
  )
  _assert_eq "nvim launcher: provider success does not require a fallback binary" \
    "provider:$nvim_launcher_cwd:src/app.lua" "$result"

  result=$(
    cd "$nvim_launcher_cwd" || exit
    HOME="$nvim_launcher_home" PATH="$nvim_launcher_path" \
      NVIM_LAUNCHER_PROVIDER="$nvim_launcher_provider" \
      "$launcher" src/app.lua
  )
  expected=$(printf 'provider:%s:src/app.lua\nreal:%s:src/app.lua' \
    "$nvim_launcher_cwd" "$nvim_launcher_cwd")
  _assert_eq "nvim launcher: provider refusal falls back to real nvim in the caller cwd" \
    "$expected" "$result"

  result=$(
    cd "$nvim_launcher_cwd" || exit
    HOME="$nvim_launcher_home" PATH="$nvim_launcher_path" \
      NVIM_LAUNCHER_PROVIDER="$nvim_launcher_provider" \
      "$launcher" --headless 'src/file with spaces.lua'
  )
  expected=$(printf 'provider:%s:--headless src/file with spaces.lua\nreal:%s:--headless src/file with spaces.lua' \
    "$nvim_launcher_cwd" "$nvim_launcher_cwd")
  _assert_eq "nvim launcher: forwards the complete argv to Termnav and real nvim" \
    "$expected" "$result"

  nvim_missing_rc=0
  nvim_missing_output=$(
    cd "$nvim_launcher_cwd" || exit
    HOME="$nvim_launcher_home" PATH="$nvim_launcher_path" \
      DOT_SHDEPS_TEST_MISSING=1 \
      NVIM_LAUNCHER_PROVIDER="$nvim_launcher_provider" \
      "$launcher" src/app.lua 2>&1
  ) || nvim_missing_rc=$?
  _assert_eq "nvim launcher: missing Termnav is a broken installation" \
    "127" "$nvim_missing_rc"
  _assert_contains "nvim launcher: missing Termnav suggests repair" \
    "run dot update" "$nvim_missing_output"
  unset -f _nvim_launcher_test_shdeps
}
