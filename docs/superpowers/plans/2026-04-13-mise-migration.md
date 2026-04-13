# Mise Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current mixed-language runtime installation flow with a single global `mise` configuration, while preserving the existing user-visible toolset.

**Architecture:** Add one repo-managed `configs/.config/mise/config.toml`, simplify shell startup so it only activates `mise`, and replace the legacy `Rust` / `Node.js` / `Go` / `uv` / `Bun` / `Zig` installer section in `setup.sh` with `mise` install helpers. Keep existing non-language package management intact, and preserve `--skip LANG` by mapping language groups to `mise` tool targets.

**Tech Stack:** `bash`, `zsh`, `mise`, TOML, existing `setup.sh` helper functions (`safe_exec`, `run_remote_install_script`, `_deploy_config_item`)

**Git Note:** `git status --short --branch` currently fails with `fatal: not a git repository`, so commit steps are intentionally replaced with verification checkpoints.

---

### Task 1: Add Global Mise Config And Shell Activation

**Files:**
- Create: `configs/.config/mise/config.toml`
- Modify: `configs/.config/shell/env:1-67`
- Modify: `configs/.zshrc:129-133`

- [ ] **Step 1: Write the failing checks**

```bash
test -f configs/.config/mise/config.toml
rg -n 'NVM_DIR|BUN_INSTALL|cargo/env|/usr/local/go/bin' \
  configs/.config/shell/env \
  configs/.zshrc
```

- [ ] **Step 2: Run the checks to verify current state fails the new design**

Run:

```bash
test -f configs/.config/mise/config.toml
```

Expected: exit status `1`

Run:

```bash
rg -n 'NVM_DIR|BUN_INSTALL|cargo/env|/usr/local/go/bin' \
  configs/.config/shell/env \
  configs/.zshrc
```

Expected: existing matches for `NVM_DIR`, `BUN_INSTALL`, `cargo/env`, and `/usr/local/go/bin`

- [ ] **Step 3: Create `configs/.config/mise/config.toml`**

Write this file exactly:

```toml
[settings]
all_compile = false
not_found_auto_install = false

[settings.python]
precompiled_flavor = "install_only_stripped"

[tools]
node = "24"
python = "3.14"
go = "1.26"
rust = { version = "stable", components = "rust-analyzer" }
bun = "1.3"
zig = "0.15"

zls = "latest"
uv = "latest"
pnpm = "latest"
biome = "latest"
shfmt = "latest"
golangci-lint = "latest"
staticcheck = "latest"

"npm:typescript" = "6.0.2"
"npm:typescript-language-server" = "5.1.3"
"npm:pyright" = "1.1.408"

"go:golang.org/x/tools/gopls" = "latest"
"go:golang.org/x/tools/cmd/goimports" = "latest"
"go:github.com/go-delve/delve/cmd/dlv" = "latest"
"go:mvdan.cc/garble" = "latest"

"cargo:cargo-nextest" = "latest"
"cargo:eza" = "latest"
"cargo:sd" = "latest"
"cargo:tokei" = "latest"
"cargo:hyperfine" = "latest"
"cargo:git-absorb" = "latest"
"cargo:just" = "latest"

"pipx:black" = "latest"
"pipx:ruff" = "latest"
"pipx:pipx" = "latest"
"pipx:pytest" = "latest"
```

- [ ] **Step 4: Rewrite `configs/.config/shell/env` to remove legacy runtime wiring and activate `mise`**

Replace the file body with:

```sh
#!/bin/sh
# shellcheck shell=sh
# 共享环境变量配置
# 由 .bashrc 和 .zshrc 共同引用

############################################
# 用户 PATH 配置
############################################
add_to_path() {
    case ":$PATH:" in
        *":$1:"*) ;;
        *) PATH="$1:$PATH" ;;
    esac
}

add_to_path "$HOME/.local/bin"
add_to_path "$HOME/bin"

############################################
# Homebrew
############################################
if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

############################################
# Mise
############################################
if command -v mise >/dev/null 2>&1; then
    if [ -n "${ZSH_VERSION:-}" ]; then
        eval "$(mise activate zsh)"
    else
        eval "$(mise activate bash)"
    fi
fi

############################################
# .NET
############################################
export DOTNET_ROOT="$HOME/.dotnet"
[ -d "$HOME/.dotnet" ] && add_to_path "$HOME/.dotnet"

############################################
# 其他环境文件
############################################
# shellcheck disable=SC1091
[ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"

export PATH
```

- [ ] **Step 5: Remove the legacy Bun completion dependency from `configs/.zshrc`**

Delete this block:

```zsh
############################################
# Bun 补全
############################################
# shellcheck disable=SC1091
[ -s "$BUN_INSTALL/_bun" ] && source "$BUN_INSTALL/_bun"
```

- [ ] **Step 6: Run targeted validation**

Run:

```bash
bash -n configs/.config/shell/env
zsh -n configs/.zshrc
shellcheck -x configs/.config/shell/env configs/.bashrc configs/.zshrc
python3 - <<'PY'
from pathlib import Path
import tomllib
tomllib.load(Path("configs/.config/mise/config.toml").open("rb"))
print("MISE_TOML_OK")
PY
! rg -n 'NVM_DIR|BUN_INSTALL|cargo/env|/usr/local/go/bin' \
  configs/.config/shell/env \
  configs/.zshrc
```

Expected:

- syntax checks exit `0`
- `shellcheck` exits `0`
- Python prints `MISE_TOML_OK`
- the final `rg` command exits `1`

---

### Task 2: Replace Legacy Runtime Installers In `setup.sh`

**Files:**
- Modify: `setup.sh:1449-1937`
- Modify: `setup.sh:2325-2370`
- Verify: `setup.sh --help` output

- [ ] **Step 1: Write the failing checks for the old runtime section**

```bash
rg -n 'install_rust\(|install_nodejs\(|install_go\(|install_uv\(|install_bun\(|install_zig\(|install_cargo_tools\(' setup.sh
rg -n 'install_mise\(|activate_mise_for_current_session\(|install_mise_toolchain\(' setup.sh
```

- [ ] **Step 2: Run the checks to confirm the old implementation is still present**

Run:

```bash
rg -n 'install_rust\(|install_nodejs\(|install_go\(|install_uv\(|install_bun\(|install_zig\(|install_cargo_tools\(' setup.sh
```

Expected: multiple matches

Run:

```bash
rg -n 'install_mise\(|activate_mise_for_current_session\(|install_mise_toolchain\(' setup.sh
```

Expected: no output, exit status `1`

- [ ] **Step 3: Replace the legacy language section with `mise` helpers**

Keep `should_skip_lang()` and replace the runtime installer section with this block:

```bash
should_skip_lang() {
  local lang="$1"
  for skip in "${SKIP_LANGS[@]}"; do
    [[ "$skip" == "$lang" ]] && return 0
  done
  return 1
}

install_mise() {
  if have_cmd mise; then
    info "mise 已安装，跳过"
    return 0
  fi

  log "安装 mise..."
  if ! run_remote_install_script "安装 mise" sh "https://mise.run"; then
    warn "mise 安装失败"
    return 1
  fi

  export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
  if ! have_cmd mise; then
    warn "mise 安装后未找到命令"
    return 1
  fi
}

_mise_all_targets() {
  cat <<'EOF'
rust
cargo:cargo-nextest
cargo:eza
cargo:sd
cargo:tokei
cargo:hyperfine
cargo:git-absorb
cargo:just
node
pnpm
npm:typescript
npm:typescript-language-server
npm:pyright
go
go:golang.org/x/tools/gopls
go:golang.org/x/tools/cmd/goimports
go:github.com/go-delve/delve/cmd/dlv
go:mvdan.cc/garble
golangci-lint
staticcheck
python
uv
pipx:black
pipx:ruff
pipx:pipx
pipx:pytest
bun
zig
zls
biome
shfmt
EOF
}

should_skip_mise_target() {
  local target="$1"
  local skip

  for skip in "${SKIP_LANGS[@]}"; do
    case "$skip:$target" in
      rust:rust|rust:cargo:cargo-nextest|rust:cargo:eza|rust:cargo:sd|rust:cargo:tokei|rust:cargo:hyperfine|rust:cargo:git-absorb|rust:cargo:just)
        return 0
        ;;
      node:node|node:pnpm|node:npm:typescript|node:npm:typescript-language-server|node:npm:pyright)
        return 0
        ;;
      go:go|go:go:golang.org/x/tools/gopls|go:go:golang.org/x/tools/cmd/goimports|go:go:github.com/go-delve/delve/cmd/dlv|go:go:mvdan.cc/garble|go:golangci-lint|go:staticcheck)
        return 0
        ;;
      python:python|python:uv|python:pipx:black|python:pipx:ruff|python:pipx:pipx|python:pipx:pytest)
        return 0
        ;;
      bun:bun)
        return 0
        ;;
      zig:zig|zig:zls)
        return 0
        ;;
    esac
  done

  return 1
}

build_mise_install_targets() {
  local target
  while IFS= read -r target; do
    [ -z "$target" ] && continue
    if ! should_skip_mise_target "$target"; then
      printf '%s\n' "$target"
    fi
  done < <(_mise_all_targets)
}

activate_mise_for_current_session() {
  if ! have_cmd mise; then
    return 0
  fi

  eval "$(mise activate bash)"
}

install_mise_toolchain() {
  local config_file="$HOME/.config/mise/config.toml"
  local targets=()

  if [ ! -f "$config_file" ]; then
    warn "mise 配置不存在: $config_file"
    return 1
  fi

  if ! have_cmd mise; then
    warn "mise 未安装，无法安装工具链"
    return 1
  fi

  mapfile -t targets < <(build_mise_install_targets)

  if [ ${#targets[@]} -eq 0 ]; then
    info "没有需要安装的 mise 工具"
    return 0
  fi

  if [ "$DRY_RUN" = true ]; then
    info "[DRY-RUN] mise install ${targets[*]}"
    return 0
  fi

  if ! mise install "${targets[@]}"; then
    warn "mise 工具链安装失败"
    return 1
  fi
}
```

- [ ] **Step 4: Replace the stage-3 runtime calls so `mise` runs before cargo-backed packages**

Update `_stage3_software_installation()` to this shape:

```bash
_stage3_software_installation() {
  step "阶段 3/4: 软件安装"
  
  install_base_packages
  install_ffmpeg
  install_docker

  install_mise || return 1
  install_mise_toolchain || return 1
  activate_mise_for_current_session

  # 终端与工具
  install_lazygit
  install_zellij
  install_yazi
  install_ghostty

  # Linux 专用工具
  [ "$OS" = "linux" ] && install_vicinae

  # GUI 应用
  install_vscode
  install_telegram

  # Shell 配置
  configure_shell
}
```

- [ ] **Step 5: Remove the old runtime helper functions and old stage-3 calls**

Delete these functions entirely:

```text
install_rust
install_cargo_tools
install_nodejs
_download_and_install_go
install_go
install_uv
install_bun
_get_zig_version_info
_download_and_install_zig
install_zig
```

After deletion, verify only these runtime entry points remain:

```bash
rg -n 'install_mise\(|activate_mise_for_current_session\(|install_mise_toolchain\(' setup.sh
! rg -n 'install_rust\(|install_nodejs\(|install_go\(|install_uv\(|install_bun\(|install_zig\(|install_cargo_tools\(' setup.sh
```

- [ ] **Step 6: Update the CLI help text for `--skip LANG`**

Change the `usage()` block to this text:

```text
  -s, --skip LANG         跳过指定语言组（rust|node|go|python|bun|zig）
                          会同时跳过该语言组对应的 mise tools
```

- [ ] **Step 7: Validate the new helper behavior**

Run:

```bash
bash -n setup.sh
bash setup.sh --help | sed -n '1,20p'
bash <<'EOF'
set -euo pipefail
cd /home/z/Documents/xtpz/jb
source <(awk '/^# 执行主流程/{exit} {print}' setup.sh)
SKIP_LANGS=(rust)
build_mise_install_targets > /tmp/mise-targets.txt
! rg -n '^(rust|cargo:cargo-nextest|cargo:eza|cargo:sd|cargo:tokei|cargo:hyperfine|cargo:git-absorb|cargo:just)$' /tmp/mise-targets.txt
EOF
```

Expected:

- `bash -n` exits `0`
- `--help` shows the updated `--skip LANG` description
- the skip-target validation exits `0`

---

### Task 3: Deploy `mise` Config And Rewire Verification

**Files:**
- Modify: `setup.sh:2100-2235`
- Verify: deployment helpers with temporary `HOME`

- [ ] **Step 1: Write the failing checks for deployment and verification**

```bash
rg -n '\.config/mise/config.toml|check_cmd mise --version|check_cmd pnpm --version|check_cmd pyright --version|check_cmd black --version' setup.sh
```

- [ ] **Step 2: Run the failing check**

Run:

```bash
rg -n '\.config/mise/config.toml|check_cmd mise --version|check_cmd pnpm --version|check_cmd pyright --version|check_cmd black --version' setup.sh
```

Expected: no output, exit status `1`

- [ ] **Step 3: Add `mise` config deployment to `deploy_config_files()`**

Extend `CONFIG_FILES_COPY` to include:

```bash
declare -A CONFIG_FILES_COPY=(
  ["$CONFIG_DIR/.zshrc"]="$HOME/.zshrc"
  ["$CONFIG_DIR/.bashrc"]="$HOME/.bashrc"
  ["$CONFIG_DIR/.config/starship.toml"]="$HOME/.config/starship.toml"
  ["$CONFIG_DIR/.config/shell/env"]="$HOME/.config/shell/env"
  ["$CONFIG_DIR/.config/mise/config.toml"]="$HOME/.config/mise/config.toml"
)
```

- [ ] **Step 4: Rewire `verify_installations()` to use shared env and add `mise` checks**

Replace the old hardcoded runtime-path prelude with:

```bash
verify_installations() {
  log "验证已安装工具版本..."

  export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
  # shellcheck disable=SC1091
  [ -f "$HOME/.config/shell/env" ] && . "$HOME/.config/shell/env"

  check_cmd() {
    local cmd="$1"
    shift
    if have_cmd "$cmd"; then
      printf "  %-15s " "$cmd:"
      "$cmd" "$@" 2>/dev/null | head -n1
    else
      printf "  %-15s %s\n" "$cmd:" "❌ 未找到"
    fi
  }

  echo ""
  check_cmd mise --version
  check_cmd git --version
  check_cmd gcc --version
  check_cmd cmake --version
  check_cmd meson --version
  check_cmd nvim --version
  check_cmd curl --version
  check_cmd zsh --version
  check_cmd tmux -V
  check_cmd zellij --version
  check_cmd rg --version
  check_cmd fzf --version
  check_cmd zoxide --version
  check_cmd fd --version
  check_cmd bat --version
  check_cmd eza --version
  check_cmd btop --version
  check_cmd gh --version
  check_cmd just --version
  check_cmd lazygit --version
  check_cmd yazi --version
  check_cmd ffmpeg -version
  check_cmd ghostty --version
  check_cmd code --version
  check_cmd telegram-desktop --version
  check_cmd vicinae --version
  check_cmd fastfetch --version
  check_cmd git-absorb --version
  check_cmd delta --version
  check_cmd 7z
  check_cmd sd --version
  check_cmd tokei --version
  check_cmd hyperfine --version
  check_cmd node --version
  check_cmd pnpm --version
  check_cmd go version
  check_cmd gopls version
  check_cmd dlv version
  check_cmd uv --version
  check_cmd bun --version
  check_cmd zig version
  check_cmd zls --version
  check_cmd rustc --version
  check_cmd cargo --version
  check_cmd cargo-nextest --version
  check_cmd biome --version
  check_cmd pyright --version
  check_cmd black --version
  check_cmd ruff --version
  check_cmd pytest --version
  check_cmd shfmt --version
  check_cmd starship --version
}
```

- [ ] **Step 5: Verify deployment and config parsing with a temporary home**

Run:

```bash
bash <<'EOF'
set -euo pipefail
cd /home/z/Documents/xtpz/jb
tmp_home=$(mktemp -d)
source <(awk '/^# 执行主流程/{exit} {print}' setup.sh)
CONFIG_DIR="$PWD/configs"
BACKUP_TS=test
HOME="$tmp_home"
_deploy_config_item "$CONFIG_DIR/.config/mise/config.toml" "$HOME/.config/mise/config.toml" false
test -f "$HOME/.config/mise/config.toml"
HOME="$tmp_home" XDG_CONFIG_HOME="$tmp_home/.config" MISE_GLOBAL_CONFIG_FILE="$tmp_home/.config/mise/config.toml" mise ls | tee /tmp/mise-ls.txt
rg -n 'node|python|go|rust|bun|zig' /tmp/mise-ls.txt
rm -rf "$tmp_home"
EOF
```

Expected:

- deploy helper exits `0`
- `mise ls` succeeds
- `rg` finds the six runtime names

- [ ] **Step 6: Re-run repository-level static checks**

Run:

```bash
bash -n setup.sh
bash -n configs/.config/shell/env
bash -n configs/.bashrc
zsh -n configs/.zshrc
shellcheck -x setup.sh configs/.config/shell/env configs/.bashrc configs/.zshrc
```

Expected: all commands exit `0`

---

### Task 4: Full Integration Validation And Legacy Regression Sweep

**Files:**
- Verify: `setup.sh`
- Verify: `configs/.config/mise/config.toml`
- Verify: `configs/.config/shell/env`
- Verify: `configs/.zshrc`

- [ ] **Step 1: Confirm all legacy runtime references are gone**

Run:

```bash
! rg -n 'NVM_DIR|BUN_INSTALL|cargo/env|/usr/local/go/bin|install_rust\(|install_nodejs\(|install_go\(|install_uv\(|install_bun\(|install_zig\(|install_cargo_tools\(' \
  setup.sh \
  configs/.config/shell/env \
  configs/.zshrc
```

Expected: exit status `0`

- [ ] **Step 2: Run the full static verification suite**

Run:

```bash
bash -n setup.sh && \
bash -n configs/.config/shell/env && \
bash -n configs/.bashrc && \
zsh -n configs/.zshrc

shellcheck -x setup.sh configs/.config/shell/env configs/.bashrc configs/.zshrc

python3 - <<'PY'
from pathlib import Path
import tomllib
for path in [
    Path("configs/.config/mise/config.toml"),
    Path("configs/.config/starship.toml"),
    Path("configs/.config/yazi/yazi.toml"),
    Path("configs/.config/yazi/keymap.toml"),
    Path("configs/.config/yazi/theme.toml"),
]:
    tomllib.load(path.open("rb"))
print("ALL_TOML_OK")
PY
```

Expected:

- shell syntax commands exit `0`
- `shellcheck` exits `0`
- Python prints `ALL_TOML_OK`

- [ ] **Step 3: Run top-level CLI validation**

Run:

```bash
bash setup.sh --help >/tmp/setup-help.txt
bash setup.sh --version
bash setup.sh --dry-run >/tmp/setup-dry-run.txt
rg -n 'mise|DRY-RUN' /tmp/setup-dry-run.txt
```

Expected:

- `--help` exits `0`
- `--version` prints `v5.0.0` unless script version changed in implementation
- dry-run output includes `mise` and `DRY-RUN` lines

- [ ] **Step 4: Run a real `mise` config validation in an isolated home**

Run:

```bash
bash <<'EOF'
set -euo pipefail
cd /home/z/Documents/xtpz/jb
tmp_home=$(mktemp -d)
mkdir -p "$tmp_home/.config/mise"
cp configs/.config/mise/config.toml "$tmp_home/.config/mise/config.toml"
HOME="$tmp_home" \
XDG_CONFIG_HOME="$tmp_home/.config" \
MISE_GLOBAL_CONFIG_FILE="$tmp_home/.config/mise/config.toml" \
mise ls | tee /tmp/mise-final-ls.txt
rg -n 'node|python|go|rust|bun|zig|pnpm|pyright|black|ruff|pytest|gopls|goimports|dlv|garble|cargo-nextest|biome|shfmt|zls' /tmp/mise-final-ls.txt
rm -rf "$tmp_home"
EOF
```

Expected:

- `mise ls` exits `0`
- `rg` finds runtime and tool names from the config

- [ ] **Step 5: Run one end-to-end install in an isolated home**

Run:

```bash
bash <<'EOF'
set -euo pipefail
cd /home/z/Documents/xtpz/jb
tmp_home=$(mktemp -d)
mkdir -p "$tmp_home/.config/mise"
cp configs/.config/mise/config.toml "$tmp_home/.config/mise/config.toml"
HOME="$tmp_home" \
XDG_CONFIG_HOME="$tmp_home/.config" \
MISE_GLOBAL_CONFIG_FILE="$tmp_home/.config/mise/config.toml" \
mise install
HOME="$tmp_home" \
XDG_CONFIG_HOME="$tmp_home/.config" \
MISE_GLOBAL_CONFIG_FILE="$tmp_home/.config/mise/config.toml" \
mise ls | tee /tmp/mise-installed-ls.txt
rg -n 'node|python|go|rust|bun|zig' /tmp/mise-installed-ls.txt
rm -rf "$tmp_home"
EOF
```

Expected:

- `mise install` exits `0`
- `mise ls` succeeds after install
- runtime names still appear in the final listing

- [ ] **Step 6: Record the verification checkpoint**

Run:

```bash
printf '%s\n' 'Verification complete. No git commit step: workspace is not a git repository.'
```

Expected:

- the message prints exactly once

