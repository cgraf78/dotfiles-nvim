# shellcheck shell=bash

nvim_test_doctor() {
  local tmp fake_bin output nvim_log api_home public_api_log
  tmp=$(mktemp -d)
  fake_bin=$tmp/bin
  nvim_log=$tmp/nvim.log
  mkdir -p "$fake_bin"
  cat >"$fake_bin/nvim" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$NVIM_DOCTOR_TEST_LOG"
case " $* " in
  *' --version '*) printf 'NVIM v0.11.0\n' ;;
  *'checkhealth vim.health'*)
    for arg in "$@"; do
      case $arg in
        '+w! '*) : >"${arg#+w! }" ;;
      esac
    done
    ;;
esac
exit 0
EOF
  cat >"$fake_bin/timeout" <<'EOF'
#!/bin/sh
shift
exec "$@"
EOF
  chmod +x "$fake_bin/nvim"
  chmod +x "$fake_bin/timeout"

  api_home=$tmp/api-home
  public_api_log=$tmp/public-doctor-api.log
  mkdir -p "$api_home/.local/lib/dotfiles/doctor.d/lib"
  cp "$HOME/.local/lib/dotfiles/doctor.d/70-nvim.sh" \
    "$api_home/.local/lib/dotfiles/doctor.d/70-nvim.sh"
  cp "$HOME/.local/lib/dotfiles/doctor.d/lib/nvim.sh" \
    "$api_home/.local/lib/dotfiles/doctor.d/lib/nvim.sh"
  cp "$HOME/.local/lib/dotfiles/doctor.d/lib/compat.sh" \
    "$api_home/.local/lib/dotfiles/doctor.d/lib/compat.sh"
  if [[ -f $HOME/.local/lib/dotfiles/doctor.d/lib/shdeps-assets.sh ]]; then
    cp "$HOME/.local/lib/dotfiles/doctor.d/lib/shdeps-assets.sh" \
      "$api_home/.local/lib/dotfiles/doctor.d/lib/shdeps-assets.sh"
  fi

  DOT_DOCTOR_RESULT_FILE=$tmp/doctor-results.tsv
  export DOT_DOCTOR_RESULT_FILE
  _test_load_dot_doctor_api "$api_home" || {
    nvim_test_fail 'Neovim doctor tests load the pinned Dot public doctor API'
    return
  }
  eval "$(declare -f dot_doctor_source | sed '1s/^dot_doctor_source /_nvim_public_dot_doctor_source /')"
  eval "$(declare -f dot_doctor_section | sed '1s/^dot_doctor_section /_nvim_public_dot_doctor_section /')"
  eval "$(declare -f dot_doctor_ok | sed '1s/^dot_doctor_ok /_nvim_public_dot_doctor_ok /')"
  eval "$(declare -f dot_doctor_warn | sed '1s/^dot_doctor_warn /_nvim_public_dot_doctor_warn /')"
  eval "$(declare -f dot_doctor_fail | sed '1s/^dot_doctor_fail /_nvim_public_dot_doctor_fail /')"
  eval "$(declare -f dot_doctor_skip | sed '1s/^dot_doctor_skip /_nvim_public_dot_doctor_skip /')"
  # shellcheck disable=SC2329 # Called by the sourced doctor extension.
  dot_doctor_source() {
    printf 'source\t%s\n' "$1" >>"$public_api_log"
    _nvim_public_dot_doctor_source "$@"
  }
  # shellcheck disable=SC2329 # Called through the inherited editor compat shim.
  dot_doctor_section() {
    printf 'section\t%s\n' "$1" >>"$public_api_log"
    _nvim_public_dot_doctor_section "$@"
  }
  # shellcheck disable=SC2329 # Called through the inherited editor compat shim.
  dot_doctor_ok() {
    printf 'ok\t%s\n' "$1" >>"$public_api_log"
    _nvim_public_dot_doctor_ok "$@"
  }
  # shellcheck disable=SC2329 # Called through the inherited editor compat shim.
  dot_doctor_warn() {
    printf 'warn\t%s\n' "$1" >>"$public_api_log"
    _nvim_public_dot_doctor_warn "$@"
  }
  # shellcheck disable=SC2329 # Called through the inherited editor compat shim.
  dot_doctor_fail() {
    printf 'fail\t%s\n' "$1" >>"$public_api_log"
    _nvim_public_dot_doctor_fail "$@"
  }
  # shellcheck disable=SC2329 # Called through the inherited editor compat shim.
  dot_doctor_skip() {
    printf 'skip\t%s\n' "$1" >>"$public_api_log"
    _nvim_public_dot_doctor_skip "$@"
  }
  dot_doctor_source doctor.d/70-nvim.sh || {
    nvim_test_fail 'Neovim doctor entry point loads through the public doctor API'
    return
  }
  NVIM_DOCTOR_TEST_LOG=$nvim_log PATH="$fake_bin:$PATH" doctor
  output=$(cat "$DOT_DOCTOR_RESULT_FILE")
  case $output in
    *$'ok\tnvim installed'*$'ok\tnvim config syntax is valid'*$'ok\tcheckhealth passed'*) nvim_test_ok ;;
    *) nvim_test_fail 'Neovim doctor checks editor syntax and general health' ;;
  esac
  if printf '%s\n' "$output" | grep -F 'LSP' >/dev/null; then
    nvim_test_fail 'editor doctor emitted a development LSP check'
  else
    nvim_test_ok
  fi
  if awk '
    /--version/ { next }
    $0 !~ /--clean/ || $0 !~ /-u NONE/ || $0 !~ /-i NONE/ { exit 1 }
    /init\.lua|Lazy|mason|lspconfig/ { exit 1 }
  ' "$nvim_log"; then
    nvim_test_ok
  else
    nvim_test_fail 'Neovim doctor uses only network-free clean-profile checks'
  fi
  _assert_contains "nvim doctor: loads support through public doctor API" \
    $'source\tdoctor.d/lib/nvim.sh' "$(cat "$public_api_log")"
  _assert_contains "nvim doctor: reports through public doctor API" \
    $'ok\tcheckhealth passed' "$(cat "$public_api_log")"
}
