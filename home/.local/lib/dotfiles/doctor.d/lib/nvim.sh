# shellcheck shell=bash
# Editor-profile Neovim checks. Development LSP/toolchain policy belongs to the
# additive dotfiles-dev doctor extension.

_dr_check_nvim_config_syntax() {
  local config_root=${XDG_CONFIG_HOME:-$HOME/.config}/nvim query_file output status

  [[ -d $config_root ]] || {
    _dr_skip "nvim config syntax" "configuration directory is absent"
    return 0
  }
  query_file=$(mktemp "${TMPDIR:-/tmp}/dot-nvim-syntax.XXXXXX") || {
    _dr_warn "nvim config syntax check failed" "could not create temp file"
    return 0
  }
  cat >"$query_file" <<'LUA'
local root = assert(vim.env.DOT_NVIM_CONFIG_ROOT)
for name, entry_type in vim.fs.dir(root, { depth = 100 }) do
  if entry_type == "file" and name:sub(-4) == ".lua" then
    local path = root .. "/" .. name
    local chunk, err = loadfile(path)
    if not chunk then
      error(path .. ": " .. err)
    end
  end
end
LUA
  output=$(DOT_NVIM_CONFIG_ROOT=$config_root \
    nvim --clean --headless -u NONE -i NONE -l "$query_file" 2>&1)
  status=$?
  rm -f "$query_file"
  if [[ $status -eq 0 ]]; then
    _dr_ok "nvim config syntax is valid"
  else
    _dr_fail "nvim config syntax check failed" "${output:-run nvim --clean against the config to inspect}"
  fi
}

_dr_check_nvim_health() {
  local health_file timeout_bin health_errors

  health_file=$(mktemp "${TMPDIR:-/tmp}/dot-nvim-health.XXXXXX") || {
    _dr_skip "checkhealth" "could not create temp file"
    return 0
  }
  if command -v timeout >/dev/null 2>&1; then
    timeout_bin=timeout
  elif command -v gtimeout >/dev/null 2>&1; then
    timeout_bin=gtimeout
  else
    rm -f "$health_file"
    _dr_skip "checkhealth" "timeout command not available"
    return 0
  fi

  if "$timeout_bin" 15 nvim --clean --headless -u NONE -i NONE \
    +"checkhealth vim.health" +"w! $health_file" +"qa!" >/dev/null 2>&1; then
    health_errors=$(grep -ci 'ERROR' "$health_file" || true)
    if [[ $health_errors -gt 0 ]]; then
      _dr_warn "checkhealth: $health_errors error(s)" \
        "run 'nvim --clean -u NONE -i NONE' and ':checkhealth vim.health' to inspect"
    else
      _dr_ok "checkhealth passed"
    fi
  else
    _dr_skip "checkhealth" "timed out or failed under the clean profile"
  fi
  rm -f "$health_file"
}

_dr_check_nvim() {
  _dr_section "Neovim"

  if ! command -v nvim >/dev/null 2>&1; then
    _dr_skip "nvim not installed"
    return 0
  fi
  if ! nvim --version >/dev/null 2>&1; then
    _dr_warn "nvim found but cannot run" "binary may be incompatible with this platform"
    return 0
  fi

  local nvim_ver
  nvim_ver=$(nvim --version 2>/dev/null | head -1 | awk '{print $2}')
  _dr_ok "nvim installed" "$nvim_ver"

  # Both probes use Neovim's clean profile. Doctor must remain diagnostic on a
  # freshly activated editor profile and must never bootstrap plugins or tools.
  _dr_check_nvim_config_syntax
  _dr_check_nvim_health
}
