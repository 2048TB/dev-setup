#!/usr/bin/env bash
set -euo pipefail

# ========================================
# 跨平台开发环境一键安装配置脚本
# 支持 Linux (Fedora/Debian/Ubuntu) 和 macOS
# 集成版：安装软件 + 配置系统 + 部署配置文件
# ========================================

# ================= 全局变量 =================
SCRIPT_VERSION="5.0.0"

# ================= Bash 版本检查 =================
# macOS 默认 Bash 3.2 不支持关联数组（Bash 4.0+ 特性）
if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  echo -e "\033[1;31m[✗]\033[0m 错误: 需要 Bash 4.0 或更高版本（当前版本: ${BASH_VERSION}）"
  echo -e "\033[1;34m[i]\033[0m macOS 用户请执行: brew install bash"
  echo -e "\033[1;34m[i]\033[0m 或使用新版 bash 运行: /usr/local/bin/bash $0"
  exit 1
fi

OS=""
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/configs"
BASHRC="${BASHRC:-$HOME/.bashrc}"
ZSHRC="${ZSHRC:-$HOME/.zshrc}"
BACKUP_TS="$(date +%Y%m%d_%H%M%S)"
DRY_RUN=false
MINIMAL_MODE=false
SKIP_LANGS=()
SKIP_CONFIG=false

# ================= 颜色与日志 =================
COLOR_GREEN='\033[1;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[1;31m'
COLOR_BLUE='\033[1;34m'
COLOR_RESET='\033[0m'

log()  { printf "\n${COLOR_GREEN}[+]${COLOR_RESET} %s\n" "$*"; }
warn() { printf "\n${COLOR_YELLOW}[!]${COLOR_RESET} %s\n" "$*" >&2; }
err()  { printf "\n${COLOR_RED}[✗]${COLOR_RESET} %s\n" "$*" >&2; }
info() { printf "\n${COLOR_BLUE}[i]${COLOR_RESET} %s\n" "$*"; }
step() { printf "\n${COLOR_BLUE}==>${COLOR_RESET} %s\n" "$*"; }

# ================= 操作系统检测 =================

# OS 检测（优先于发行版检测）
detect_os() {
  case "$(uname -s)" in
    Linux)
      OS="linux"
      detect_distro
      ;;
    Darwin)
      OS="macos"
      PKG_MGR="brew"
      DISTRO="macos"
      ;;
    *)
      err "不支持的操作系统: $(uname -s)"
      err "目前仅支持 Linux 和 macOS"
      exit 1
      ;;
  esac
}

# 权限提升设置（在 detect_os 之后调用）
setup_sudo() {
  if [ "$OS" = "macos" ]; then
    SUDO=""  # Homebrew 从不使用 sudo
    info "macOS: 使用 Homebrew（无需 sudo）"
  elif [ "$(id -u)" -eq 0 ]; then
    SUDO=""
    info "以 root 用户运行"
  elif have_cmd sudo; then
    SUDO="sudo"
    info "使用 sudo 提升权限"
  else
    err "需要 root 权限或 sudo 命令"
    exit 1
  fi
}

# ================= 发行版检测与包管理器抽象 =================

# 全局变量（发行版相关）
DISTRO=""
PKG_MGR=""

# Linux 发行版检测
detect_distro() {
  if [ ! -f /etc/os-release ]; then
    err "无法检测发行版：/etc/os-release 不存在"
    exit 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release

  case "$ID" in
    fedora)
      DISTRO="fedora"
      PKG_MGR="dnf"
      ;;
    ubuntu|debian|linuxmint|pop)
      DISTRO="debian"
      PKG_MGR="apt"
      ;;
    *)
      err "不支持的发行版: $ID"
      err "目前仅支持 Fedora 和 Debian/Ubuntu 系列"
      exit 1
      ;;
  esac
}

# 包管理器抽象层
pkg_install() {
  # 处理特殊前缀（SKIP:, CASK:）
  local packages=()
  local cask_packages=()

  for pkg in "$@"; do
    if [[ "$pkg" == SKIP:* ]]; then
      info "跳过: ${pkg#SKIP:}"
    elif [[ "$pkg" == CASK:* ]]; then
      cask_packages+=("${pkg#CASK:}")
    else
      packages+=("$pkg")
    fi
  done

  # 安装 cask 包
  if [ ${#cask_packages[@]} -gt 0 ]; then
    pkg_install_cask "${cask_packages[@]}" || warn "部分 CASK 包安装失败"
  fi

  # 安装普通包
  [ ${#packages[@]} -eq 0 ] && return 0

  case "$PKG_MGR" in
    dnf)
      safe_exec ${SUDO} dnf install -y "${packages[@]}" --setopt=max_parallel_downloads=$DNF_PARALLEL_DOWNLOADS
      ;;
    apt)
      safe_exec ${SUDO} apt-get install -y "${packages[@]}"
      ;;
    brew)
      safe_exec brew install "${packages[@]}"
      ;;
  esac
}

pkg_update() {
  case "$PKG_MGR" in
    dnf)
      safe_exec ${SUDO} dnf upgrade -y --refresh --setopt=max_parallel_downloads=$DNF_PARALLEL_DOWNLOADS
      ;;
    apt)
      safe_exec ${SUDO} apt-get update
      safe_exec ${SUDO} apt-get upgrade -y
      ;;
    brew)
      safe_exec brew update
      safe_exec brew upgrade
      ;;
  esac
}

# Homebrew Cask 安装（GUI 应用）
pkg_install_cask() {
  if [ "$PKG_MGR" != "brew" ]; then
    warn "CASK 安装仅支持 Homebrew，跳过: $*"
    return 0
  fi
  safe_exec brew install --cask "$@"
}

# 添加第三方仓库
pkg_add_repo() {
  local repo_type="$1"
  local repo_id="$2"

  case "$PKG_MGR" in
    dnf)
      case "$repo_type" in
        copr)
          safe_exec ${SUDO} dnf copr enable -y "$repo_id"
          ;;
        rpm)
          safe_exec ${SUDO} dnf install -y "$repo_id"
          ;;
        repo-url)
          # 添加 .repo 配置文件
          if have_cmd dnf-config-manager; then
            safe_exec ${SUDO} dnf config-manager --add-repo "$repo_id"
          else
            # 备选方案：直接下载到 /etc/yum.repos.d/
            local repo_file
            repo_file="/etc/yum.repos.d/$(basename "$repo_id")"
            retry_curl "$repo_id" - | ${SUDO} tee "$repo_file" > /dev/null
          fi
          ;;
      esac
      ;;
    apt)
      case "$repo_type" in
        ppa)
          if ! have_cmd add-apt-repository; then
            pkg_install software-properties-common
          fi
          safe_exec ${SUDO} add-apt-repository -y "ppa:$repo_id"
          safe_exec ${SUDO} apt-get update
          ;;
        deb)
          # 直接安装 .deb 包
          local tmp_deb
          tmp_deb=$(mktemp --suffix=.deb)
          if retry_curl "$repo_id" "$tmp_deb"; then
            safe_exec ${SUDO} dpkg -i "$tmp_deb" || safe_exec ${SUDO} apt-get install -f -y
            rm -f "$tmp_deb"
          fi
          ;;
      esac
      ;;
    brew)
      case "$repo_type" in
        tap)
          safe_exec brew tap "$repo_id"
          ;;
      esac
      ;;
  esac
}

# 包名映射（处理 Fedora/Debian/Homebrew 包名差异）
# 包名映射辅助函数 - DNF
_map_package_dnf() {
  local pkg="$1"
  case "$pkg" in
    build-essential) echo "@development-tools" ;;
    g++) echo "gcc-c++" ;;
    libssl-dev) echo "openssl-devel" ;;
    libsqlite3-dev|libsqlite-dev) echo "sqlite-devel" ;;
    libncurses-dev) echo "ncurses-devel" ;;
    libreadline-dev) echo "readline-devel" ;;
    libffi-dev) echo "libffi-devel" ;;
    libbz2-dev) echo "bzip2-devel" ;;
    liblzma-dev) echo "xz-devel" ;;
    libgdbm-dev) echo "gdbm-devel" ;;
    zlib1g-dev) echo "zlib-devel" ;;
    libtk-dev) echo "tk-devel" ;;
    fonts-jetbrains-mono) echo "jetbrains-mono-fonts" ;;
    fonts-noto-cjk) echo "google-noto-sans-cjk-fonts" ;;
    fonts-noto-color-emoji) echo "google-noto-emoji-fonts" ;;
    pkg-config) echo "pkgconf" ;;
    xz-utils) echo "xz" ;;
    p7zip-full) echo "p7zip" ;;
    p7zip-rar) echo "p7zip-plugins" ;;
    fd-find) echo "fd-find" ;;
    *) echo "$pkg" ;;
  esac
}

# 包名映射辅助函数 - APT
_map_package_apt() {
  local pkg="$1"
  case "$pkg" in
    "@development-tools") echo "build-essential" ;;
    openssl-devel) echo "libssl-dev" ;;
    sqlite-devel) echo "libsqlite3-dev" ;;
    ncurses-devel) echo "libncurses-dev" ;;
    readline-devel) echo "libreadline-dev" ;;
    libffi-devel) echo "libffi-dev" ;;
    bzip2-devel) echo "libbz2-dev" ;;
    xz-devel) echo "liblzma-dev" ;;
    gdbm-devel) echo "libgdbm-dev" ;;
    zlib-devel) echo "zlib1g-dev" ;;
    tk-devel) echo "tk-dev" ;;
    jetbrains-mono-fonts) echo "fonts-jetbrains-mono" ;;
    google-noto-sans-cjk-fonts) echo "fonts-noto-cjk" ;;
    google-noto-emoji-fonts) echo "fonts-noto-color-emoji" ;;
    papirus-icon-theme) echo "papirus-icon-theme" ;;
    gcc-c++) echo "g++" ;;
    pkgconf) echo "pkg-config" ;;
    xz) echo "xz-utils" ;;
    p7zip) echo "p7zip-full" ;;
    p7zip-plugins) echo "p7zip-rar" ;;
    ImageMagick) echo "imagemagick" ;;
    file-roller) echo "file-roller" ;;
    *) echo "$pkg" ;;
  esac
}

# 包名映射辅助函数 - Homebrew
_map_package_brew() {
  local pkg="$1"
  case "$pkg" in
    # 编译工具（macOS 通过 Xcode CLT 提供）
    build-essential|"@development-tools") echo "SKIP:gcc/clang (Xcode CLT)" ;;
    gcc|g++|gcc-c++) echo "gcc" ;;

    # 开发库
    libssl-dev|openssl-devel) echo "openssl@3" ;;
    libsqlite3-dev|sqlite-devel) echo "sqlite" ;;
    libncurses-dev|ncurses-devel) echo "ncurses" ;;
    libreadline-dev|readline-devel) echo "readline" ;;
    libffi-dev|libffi-devel) echo "libffi" ;;
    libbz2-dev|bzip2-devel) echo "bzip2" ;;
    liblzma-dev|xz-devel) echo "xz" ;;
    libgdbm-dev|gdbm-devel) echo "gdbm" ;;
    zlib1g-dev|zlib-devel) echo "zlib" ;;
    libtk-dev|tk-devel) echo "tcl-tk" ;;
    pkg-config|pkgconf) echo "pkg-config" ;;

    # 字体（Homebrew 使用 Cask）
    fonts-jetbrains-mono|jetbrains-mono-fonts) echo "CASK:font-jetbrains-mono" ;;
    fonts-noto-cjk|google-noto-sans-cjk-fonts) echo "SKIP:macOS 自带 CJK 字体" ;;
    fonts-noto-color-emoji|google-noto-emoji-fonts) echo "SKIP:macOS 自带 Emoji" ;;

    # Linux 专用软件（macOS 不需要或有替代）
    papirus-icon-theme) echo "SKIP:图标主题（macOS 不适用）" ;;
    file-roller) echo "SKIP:归档管理器（macOS 内置）" ;;
    pinentry-gnome3) echo "pinentry-mac" ;;
    gnome-extensions-app) echo "SKIP:GNOME 专用" ;;

    # CLI 工具
    python3-pip) echo "python" ;;
    fd-find) echo "fd" ;;
    poppler-utils) echo "poppler" ;;
    xz-utils|xz) echo "xz" ;;
    p7zip-full|p7zip) echo "p7zip" ;;
    p7zip-rar|p7zip-plugins) echo "SKIP:非自由编解码器" ;;
    ImageMagick|imagemagick) echo "imagemagick" ;;

    # 多媒体工具
    imv) echo "SKIP:图片浏览器（用 Preview）" ;;
    zathura) echo "SKIP:PDF 浏览器（用 Skim）" ;;

    # 默认：直接使用包名
    *) echo "$pkg" ;;
  esac
}

# 包名映射（处理 Fedora/Debian/Homebrew 包名差异）
map_package_name() {
  local generic_name="$1"

  case "$PKG_MGR" in
    dnf) _map_package_dnf "$generic_name" ;;
    apt) _map_package_apt "$generic_name" ;;
    brew) _map_package_brew "$generic_name" ;;
  esac
}

# ================= Helper Functions =================
have_cmd() { command -v "$1" >/dev/null 2>&1; }

# 检测权限提升方式
# macOS: Homebrew 不使用 sudo
# Linux: 如果已是 root 用户，不需要 sudo；否则检查并使用 sudo
# 注意：此时 OS 变量尚未设置，将在 main() 中重新处理

# ================= 常量定义 =================
readonly MAX_DOWNLOAD_RETRIES=3        # 网络下载失败时的最大重试次数
readonly INITIAL_RETRY_DELAY=2         # 首次重试前的等待秒数（后续指数增长）
readonly DNF_PARALLEL_DOWNLOADS=20     # DNF 包管理器的并行下载数

# Docker 相关常量
readonly DOCKER_FEDORA_REPO_URL="https://download.docker.com/linux/fedora/docker-ce.repo"
readonly DOCKER_GPG_KEY_PATH="/etc/apt/keyrings/docker.gpg"
readonly DOCKER_APT_LIST_PATH="/etc/apt/sources.list.d/docker.list"
readonly DOCKER_DEFAULT_CHOICE="1"

# 网络下载重试辅助函数
# retry_curl URL [OUTPUT_FILE]
retry_curl() {
  local url="$1"
  local output="${2:--}"  # 默认输出到stdout
  local retry_delay=$INITIAL_RETRY_DELAY
  local attempt=1

  while [ $attempt -le $MAX_DOWNLOAD_RETRIES ]; do
    if [ "$output" = "-" ]; then
      if curl -fsSL "$url"; then
        return 0
      fi
    else
      if curl -fsSL "$url" -o "$output"; then
        return 0
      fi
    fi

    if [ $attempt -lt $MAX_DOWNLOAD_RETRIES ]; then
      warn "下载失败 (尝试 $attempt/$MAX_DOWNLOAD_RETRIES)，${retry_delay}秒后重试..."
      sleep $retry_delay
      retry_delay=$((retry_delay * 2))  # 指数退避
    fi
    attempt=$((attempt + 1))
  done

  err "下载失败，已重试 $MAX_DOWNLOAD_RETRIES 次: $url"
  return 1
}

# 通用的工具安装函数（支持多平台）
# install_tool_package PACKAGE_NAME FEDORA_SOURCE DEBIAN_SOURCE MACOS_SOURCE [DESCRIPTION]
# SOURCE 类型：
#   - "copr:repo" (Fedora COPR)
#   - "ppa:repo" (Ubuntu PPA)
#   - "dnf"/"apt"/"brew" (包管理器)
#   - "cargo" (Rust cargo)
#   - "cask" (Homebrew Cask)
install_tool_package() {
  local pkg_name="$1"
  local fedora_src="$2"
  local debian_src="$3"
  local macos_src="$4"
  local description="${5:-$pkg_name}"

  if [ "$MINIMAL_MODE" = true ]; then
    info "最小模式，跳过 $pkg_name"
    return
  fi

  if have_cmd "$pkg_name"; then
    info "$pkg_name 已安装，跳过"
    return
  fi

  log "安装 $description..."

  local src=""
  case "$OS" in
    linux)
      case "$DISTRO" in
        fedora) src="$fedora_src" ;;
        debian) src="$debian_src" ;;
      esac
      ;;
    macos)
      src="$macos_src"
      ;;
  esac

  # 根据 source 类型安装
  case "$src" in
    copr:*)
      local copr_repo="${src#copr:}"
      pkg_add_repo copr "$copr_repo" || { warn "启用 COPR 仓库失败"; return; }
      pkg_install "$pkg_name" || warn "$pkg_name 安装失败"
      ;;
    ppa:*)
      local ppa_repo="${src#ppa:}"
      pkg_add_repo ppa "$ppa_repo" || { warn "启用 PPA 仓库失败"; return; }
      pkg_install "$pkg_name" || warn "$pkg_name 安装失败"
      ;;
    dnf|apt|brew)
      pkg_install "$pkg_name" || warn "$pkg_name 安装失败"
      ;;
    cask)
      pkg_install_cask "$pkg_name" || warn "$pkg_name 安装失败"
      ;;
    cargo)
      if ! have_cmd cargo; then
        warn "cargo 未安装，跳过 $pkg_name"
        return
      fi
      install_cargo_tool "$pkg_name" "$description"
      ;;
    *)
      warn "未知的安装源类型: $src"
      ;;
  esac
}

# 通用的 Cargo 工具安装函数
# install_cargo_tool TOOL_NAME [DESCRIPTION]
install_cargo_tool() {
  local tool_name="$1"
  local description="${2:-$tool_name}"

  if ! have_cmd "$tool_name"; then
    log "通过 cargo 安装 $description..."
    cargo install "$tool_name" || warn "$tool_name 安装失败，可稍后手动执行: cargo install $tool_name"
  fi
}

# append_block_if_missing_pattern "MARKER" "PATTERN" "BLOCK" "RCFILE"
# 向配置文件添加标记的配置块（如果不存在）
# append_block_if_missing_pattern "MARKER" "PATTERN" "BLOCK" "RCFILE"
# 参数：
#   MARKER: 标记名称，用于标识配置块
#   PATTERN: 用于检测是否已存在的正则表达式模式
#   BLOCK: 要添加的配置内容
#   RCFILE: 目标配置文件路径
append_block_if_missing_pattern() {
  local marker="$1" pat="$2" block="$3" rc="$4"
  if [ "$DRY_RUN" = true ]; then
    info "[DRY-RUN] 将向 $rc 添加配置块: $marker"
    return 0
  fi
  [ -f "$rc" ] || touch "$rc"
  if ! grep -Eq "$pat" "$rc" 2>/dev/null; then
    {
      printf "\n# >>> %s >>>\n" "$marker"
      printf "%s\n" "$block"
      printf "# <<< %s <<<\n" "$marker"
    } >> "$rc"
  fi
}

# 同时添加配置块到 bash 和 zsh
# append_to_shells "MARKER" "PATTERN" "BLOCK"
append_to_shells() {
  local marker="$1" pat="$2" block="$3"
  append_block_if_missing_pattern "$marker" "$pat" "$block" "$BASHRC"
  append_block_if_missing_pattern "$marker" "$pat" "$block" "$ZSHRC"
}

# 安全执行远程安装脚本（支持 dry-run）
# run_remote_install_script DESCRIPTION SHELL_BIN URL [SHELL_ARGS...]
run_remote_install_script() {
  local description="$1"
  local shell_bin="$2"
  local url="$3"
  shift 3

  if [ "$DRY_RUN" = true ]; then
    info "[DRY-RUN] $description"
    return 0
  fi

  local script
  if ! script="$(retry_curl "$url" -)"; then
    warn "$description 失败"
    return 1
  fi

  if ! "$shell_bin" -s -- "$@" <<<"$script"; then
    warn "$description 失败"
    return 1
  fi
}

# 安全执行命令（支持 dry-run）
safe_exec() {
  if [ "$DRY_RUN" = true ]; then
    info "[DRY-RUN] $*"
  else
    "$@"
  fi
}

# 检查架构
check_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64|aarch64|arm64)
      info "架构: $arch"
      ;;
    *)
      warn "未经充分测试的架构: $arch"
      warn "脚本主要针对 x86_64/aarch64 优化，继续执行可能遇到问题"
      ;;
  esac
}

# ================= macOS 专用前置 =================

# 确保 Xcode Command Line Tools 已安装（macOS 必需）
ensure_xcode_clt() {
  [ "$OS" != "macos" ] && return 0

  if xcode-select -p &>/dev/null; then
    return 0
  fi

  if [ "$DRY_RUN" = true ]; then
    info "[DRY-RUN] 跳过 Xcode Command Line Tools 安装"
    return 0
  fi

  log "安装 Xcode Command Line Tools..."
  info "将弹出安装窗口，请按照提示操作"
  xcode-select --install

  # 等待用户完成安装
  info "等待 Xcode Command Line Tools 安装完成..."
  info "（这可能需要几分钟时间，请耐心等待）"
  until xcode-select -p &>/dev/null; do
    sleep 5
  done
}

# 确保 Homebrew 已安装（macOS 包管理器）
ensure_homebrew() {
  [ "$OS" != "macos" ] && return 0

  if have_cmd brew; then
    return 0
  fi

  log "安装 Homebrew..."
  info "使用官方安装脚本（需要网络连接）"

  if ! NONINTERACTIVE=1 run_remote_install_script "安装 Homebrew" /bin/bash "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"; then
    err "Homebrew 安装失败"
    err "请手动访问 https://brew.sh 安装 Homebrew"
    return 1
  fi

  [ "$DRY_RUN" = true ] && return 0
  if ! have_cmd brew; then
    err "Homebrew 安装后未找到 brew 命令"
    return 1
  fi

  # 配置 PATH（区分 Intel 和 Apple Silicon）
  log "配置 Homebrew 环境变量..."
  if [ "$(uname -m)" = "arm64" ]; then
    # Apple Silicon (M1/M2/M3)
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    # Intel Mac
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

# 添加必需的 Homebrew Taps（macOS）
ensure_homebrew_taps() {
  [ "$OS" != "macos" ] && return 0
  [ "$DRY_RUN" = true ] && return 0

  log "确保必需的 Homebrew Taps 已添加..."

  # 字体 tap（用于 Nerd Fonts）
  if ! brew tap | grep -q "^homebrew/cask-fonts$"; then
    safe_exec brew tap homebrew/cask-fonts
  fi
}

# ================= 阶段 1: 系统配置 =================

configure_package_manager() {
  step "配置包管理器..."

  case "$PKG_MGR" in
    dnf)
      DNF_CONF="/etc/dnf/dnf.conf"
      # 检查是否已配置
      if grep -q "max_parallel_downloads" "$DNF_CONF" 2>/dev/null; then
        info "DNF 已配置并行下载，跳过"
      else
        info "备份并优化 DNF 配置..."
        ${SUDO} cp "$DNF_CONF" "${DNF_CONF}.backup.$BACKUP_TS"

        ${SUDO} tee -a "$DNF_CONF" > /dev/null <<EOF

# ===== 性能优化（自动添加）=====
max_parallel_downloads=$DNF_PARALLEL_DOWNLOADS
fastestmirror=True
deltarpm=True
installonly_limit=3
skip_broken=True
clean_requirements_on_remove=True
color=always
EOF
      fi
      ;;
    apt)
      APT_CONF="/etc/apt/apt.conf.d/99-custom"
      if [ ! -f "$APT_CONF" ] || ! grep -q "Acquire::Queue-Mode" "$APT_CONF" 2>/dev/null; then
        info "配置 APT 并行下载..."
        ${SUDO} tee "$APT_CONF" > /dev/null <<EOF
# ===== 性能优化（自动添加）=====
Acquire::Queue-Mode "host";
Acquire::Retries "3";
APT::Install-Recommends "false";
APT::Install-Suggests "false";
EOF
      else
        info "APT 已配置，跳过"
      fi
      ;;
  esac
}

configure_flatpak() {
  step "配置 Flatpak..."

  if ! have_cmd flatpak; then
    info "安装 Flatpak..."
    pkg_install flatpak
  fi

  # 添加 Flathub 仓库（等待 flatpak 初始化完成）
  sleep 1
  if ! flatpak remotes 2>/dev/null | grep -q flathub; then
    safe_exec ${SUDO} flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
  fi
}

cleanup_stale_apt_sources() {
  local apt_sources_dir="${APT_SOURCES_DIR:-/etc/apt/sources.list.d}"
  local stale_repo_pattern='ppa\.launchpadcontent\.net/lazygit-team/release|lazygit-team/release/ubuntu'
  local stale_repo_files=()
  local source_file

  [ "$PKG_MGR" = "apt" ] || return 0
  [ -d "$apt_sources_dir" ] || return 0

  while IFS= read -r -d '' source_file; do
    stale_repo_files+=("$source_file")
  done < <(
    find "$apt_sources_dir" -maxdepth 1 -type f \( -name '*.list' -o -name '*.sources' -o -name '*.save' \) -print0 2>/dev/null |
      while IFS= read -r -d '' source_file; do
        if grep -Eq "$stale_repo_pattern" "$source_file" 2>/dev/null; then
          printf '%s\0' "$source_file"
        fi
      done
  )

  [ ${#stale_repo_files[@]} -eq 0 ] && return 0

  for source_file in "${stale_repo_files[@]}"; do
    info "移除过期 APT 源: $source_file"
    if ! safe_exec ${SUDO} rm -f "$source_file"; then
      warn "移除过期 APT 源失败: $source_file"
      return 1
    fi
  done
}

install_fonts_and_dependencies() {
  step "安装必需字体和依赖..."

  local generic_packages=(
    # 字体
    fonts-jetbrains-mono
    fonts-noto-color-emoji
    fonts-noto-cjk
    # 图标主题
    papirus-icon-theme
    # Yazi 依赖（预览器）
    imv
    mpv
    zathura
    file-roller
  )

  # 发行版特定包
  local distro_specific=()
  case "$DISTRO" in
    fedora)
      distro_specific+=(git-delta pinentry-gnome3)
      ;;
    debian)
      distro_specific+=(git-delta pinentry-gnome3)
      ;;
    macos)
      distro_specific+=(git-delta pinentry-gnome3)  # 将被映射为 pinentry-mac
      ;;
  esac

  # 映射包名并安装
  local mapped_packages=()
  for pkg in "${generic_packages[@]}" "${distro_specific[@]}"; do
    mapped_packages+=("$(map_package_name "$pkg")")
  done

  pkg_install "${mapped_packages[@]}" || warn "部分包安装失败"
}

# 检查是否应该安装 Nerd Fonts
_should_install_nerd_fonts() {
  if [ -t 0 ]; then
    local font_choice
    echo
    info "Nerd Fonts 安装选项："
    info "  1. 安装"
    info "  2. 跳过（默认）"

    while true; do
      read -p "请选择 [1/2，默认 2]: " -n 1 -r font_choice
      echo
      font_choice="${font_choice:-2}"

      case "$font_choice" in
        1) return 0 ;;
        2)
          info "跳过 Nerd Fonts 安装"
          return 1
          ;;
        *) warn "无效选择，请输入 1 或 2" ;;
      esac
    done
  fi

  if [ "${INSTALL_NERD_FONTS:-no}" != "yes" ]; then
    info "跳过 Nerd Fonts 安装（非交互模式）"
    info "设置 INSTALL_NERD_FONTS=yes 可自动安装"
    return 1
  fi
  
  return 0
}

# Nerd Fonts 安装 - Fedora
_install_nerd_fonts_fedora() {
  if ! dnf copr list 2>/dev/null | grep -q atim/nerd-fonts; then
    pkg_add_repo copr atim/nerd-fonts || warn "COPR 启用失败"
  fi
  pkg_install nerd-fonts-symbols-only || warn "Nerd Fonts 安装失败"
}

# Nerd Fonts 安装 - Debian
_install_nerd_fonts_debian() {
  local font_dir="${HOME}/.local/share/fonts"
  local tmp_zip
  tmp_zip="$(mktemp --suffix=.zip)"

  if ! have_cmd unzip; then
    pkg_install unzip || {
      warn "unzip 安装失败，无法自动安装 Nerd Fonts"
      rm -f "$tmp_zip"
      return 1
    }
  fi

  log "下载 Nerd Fonts Symbols Only..."
  if ! retry_curl "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.zip" "$tmp_zip"; then
    warn "Nerd Fonts 下载失败"
    rm -f "$tmp_zip"
    return 1
  fi

  mkdir -p "$font_dir"
  if ! safe_exec unzip -o "$tmp_zip" -d "$font_dir"; then
    warn "Nerd Fonts 解压失败"
    rm -f "$tmp_zip"
    return 1
  fi

  rm -f "$tmp_zip"
  info "Nerd Fonts 已安装到: $font_dir"
  return 0
}

# Nerd Fonts 安装 - macOS
_install_nerd_fonts_macos() {
  log "通过 Homebrew Cask 安装 Nerd Fonts..."
  pkg_install_cask font-jetbrains-mono-nerd-font || warn "Nerd Fonts 安装失败"
}

install_nerd_fonts() {
  step "安装 Nerd Fonts（终端图标字体）..."

  if ! _should_install_nerd_fonts; then
    return 0
  fi

  case "$OS" in
    linux)
      case "$DISTRO" in
        fedora) _install_nerd_fonts_fedora ;;
        debian) _install_nerd_fonts_debian ;;
      esac
      # Linux 需要更新字体缓存
      if have_cmd fc-cache; then
        fc-cache -fq 2>/dev/null || warn "字体缓存更新失败"
      else
        warn "fc-cache 未找到，跳过字体缓存更新"
      fi
      ;;
    macos) _install_nerd_fonts_macos ;;
  esac
}

# ================= 阶段 2: 软件安装 =================

ensure_extra_repos() {
  case "$DISTRO" in
    fedora)
      log "确保 COPR 插件已安装..."
      if ! rpm -q dnf-plugins-core >/dev/null 2>&1; then
        pkg_install dnf-plugins-core || {
          err "dnf-plugins-core 安装失败"
          return 1
        }
      fi
      ;;
    debian)
      cleanup_stale_apt_sources || warn "过期 APT 源清理失败"
      log "确保 PPA 支持已安装..."
      if ! have_cmd add-apt-repository; then
        pkg_install software-properties-common
      fi
      ;;
  esac
  return 0
}

enable_multimedia_repos() {
  case "$DISTRO" in
    fedora)
      if ! rpm -q rpmfusion-free-release >/dev/null 2>&1; then
        log "启用 RPM Fusion 仓库（用于 ffmpeg 等）..."
        pkg_add_repo rpm "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm"
        pkg_add_repo rpm "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm"
      fi
      ;;
    debian)
      # Debian/Ubuntu 官方源通常包含 ffmpeg
      info "Debian 系列使用官方源或 backports 获取多媒体包"
      ;;
  esac
}

update_system() {
  step "更新系统包..."
  pkg_update || warn "系统更新失败"
}

# 获取基础包列表
_get_base_generic_packages() {
  cat <<'EOF'
build-essential
gcc
g++
cmake
meson
ccache
make
git
neovim
wget
curl
zsh
python3-pip
unzip
tmux
pkg-config
libncurses-dev
xz-utils
libssl-dev
libsqlite3-dev
libtk-dev
liblzma-dev
libgdbm-dev
libbz2-dev
libffi-dev
zlib1g-dev
libreadline-dev
jq
poppler-utils
ripgrep
fzf
zoxide
imagemagick
fastfetch
fd-find
bat
btop
p7zip-full
EOF
}

# 获取发行版特定包列表
_get_distro_specific_packages() {
  case "$DISTRO" in
    fedora)
      cat <<'EOF'
git-absorb
gh
just
gnome-extensions-app
p7zip-plugins
EOF
      ;;
    debian)
      cat <<'EOF'
p7zip-rar
EOF
      ;;
    macos)
      cat <<'EOF'
gh
just
EOF
      ;;
  esac
}

# Debian 后处理
_post_install_debian() {
  # 创建 fd 符号链接（Debian包安装后命令是fdfind）
  if have_cmd fdfind && ! have_cmd fd; then
    safe_exec mkdir -p "$HOME/.local/bin"
    safe_exec ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
    info "已创建 fd -> fdfind 符号链接"
  fi

  # 创建 bat 符号链接（Debian/Ubuntu 包安装后命令通常是 batcat）
  if have_cmd batcat && ! have_cmd bat; then
    safe_exec mkdir -p "$HOME/.local/bin"
    safe_exec ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
    info "已创建 bat -> batcat 符号链接"
  fi

  # 安装 gh（GitHub CLI）
  install_github_cli
}

_fastfetch_release_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "aarch64" ;;
    armv6l) echo "armv6l" ;;
    armv7l) echo "armv7l" ;;
    i686|i386) echo "i686" ;;
    ppc64le) echo "ppc64le" ;;
    *)
      return 1
      ;;
  esac
}

_install_fastfetch_debian() {
  local arch package_url

  arch="$(_fastfetch_release_arch)" || {
    warn "当前架构暂未适配 fastfetch 官方 Debian 包: $(uname -m)"
    return 1
  }

  package_url="https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-${arch}.deb"
  pkg_add_repo deb "$package_url"
}

install_packages_with_fallback() {
  local packages=("$@")
  local failed_packages=()
  local pkg

  [ ${#packages[@]} -eq 0 ] && return 0

  if pkg_install "${packages[@]}"; then
    return 0
  fi

  warn "批量安装失败，回退到逐包安装"
  for pkg in "${packages[@]}"; do
    case "$pkg" in
      fastfetch)
        if [ "$DISTRO" = "debian" ] && _install_fastfetch_debian; then
          continue
        fi
        ;;
    esac

    if ! pkg_install "$pkg"; then
      failed_packages+=("$pkg")
    fi
  done

  if [ ${#failed_packages[@]} -gt 0 ]; then
    warn "以下包未安装: ${failed_packages[*]}"
    return 1
  fi

  return 0
}

install_base_packages() {
  log "安装基础开发工具与系统库..."

  # 获取包列表
  local generic_packages=()
  local distro_specific=()
  mapfile -t generic_packages < <(_get_base_generic_packages)
  mapfile -t distro_specific < <(_get_distro_specific_packages)

  # 映射包名
  local mapped_packages=()
  for pkg in "${generic_packages[@]}" "${distro_specific[@]}"; do
    mapped_packages+=("$(map_package_name "$pkg")")
  done

  install_packages_with_fallback "${mapped_packages[@]}" || warn "部分基础包安装失败"

  # Debian 后处理
  [ "$DISTRO" = "debian" ] && _post_install_debian
}

install_github_cli() {
  if have_cmd gh; then
    return
  fi

  if [ "$DRY_RUN" = true ]; then
    info "[DRY-RUN] 将安装 GitHub CLI（gh）"
    return 0
  fi

  case "$DISTRO" in
    fedora)
      pkg_install gh
      ;;
    debian)
      log "安装 GitHub CLI（gh）..."
      # 使用官方安装方式
      local gh_keyring="/usr/share/keyrings/githubcli-archive-keyring.gpg"
      if [ ! -f "$gh_keyring" ]; then
        local tmp_key
        tmp_key=$(mktemp)
        if retry_curl "https://cli.github.com/packages/githubcli-archive-keyring.gpg" "$tmp_key"; then
          ${SUDO} install -m 644 "$tmp_key" "$gh_keyring" || {
            warn "安装 GPG 密钥失败"
            rm -f "$tmp_key"
            return 1
          }
          rm -f "$tmp_key"
          echo "deb [arch=$(dpkg --print-architecture) signed-by=$gh_keyring] https://cli.github.com/packages stable main" | \
            ${SUDO} tee /etc/apt/sources.list.d/github-cli.list > /dev/null
          safe_exec ${SUDO} apt-get update
        else
          warn "下载 GPG 密钥失败"
          rm -f "$tmp_key"
          return 1
        fi
      fi
      pkg_install gh || warn "gh 安装失败"
      ;;
  esac
}

install_ffmpeg() {
  [ "$MINIMAL_MODE" = true ] && return

  log "安装 ffmpeg..."
  case "$DISTRO" in
    fedora)
      enable_multimedia_repos
      pkg_install ffmpeg ffmpeg-devel || warn "ffmpeg 安装失败"
      ;;
    debian)
      pkg_install ffmpeg || warn "ffmpeg 安装失败"
      ;;
    macos)
      pkg_install ffmpeg || warn "ffmpeg 安装失败"
      ;;
  esac
}

# Docker 安装辅助函数 - macOS
_install_docker_macos() {
  log "安装 Docker Desktop（macOS）..."
  pkg_install_cask docker || warn "Docker Desktop 安装失败"
  info "Docker Desktop 已安装，请手动启动应用"
}

# Docker 安装辅助函数 - Fedora
_install_docker_fedora() {
  log "安装 Docker（Fedora 推荐使用 podman-docker 兼容层）..."

  local docker_choice
  if [ -t 0 ]; then
    echo ""
    info "Fedora 系统安装 Docker 有两种方式："
    info "  1. podman-docker（推荐）：使用 Podman 作为后端，兼容 Docker CLI"
    info "  2. Docker CE：官方 Docker 引擎"
    while true; do
      read -p "选择安装方式 [1/2，默认 1]: " -n 1 -r docker_choice
      echo
      docker_choice="${docker_choice:-$DOCKER_DEFAULT_CHOICE}"
      if [[ "$docker_choice" =~ ^[12]$ ]]; then
        break
      fi
      warn "无效选择，请输入 1 或 2"
    done
  else
    docker_choice="${DOCKER_CHOICE:-$DOCKER_DEFAULT_CHOICE}"
    if [[ ! "$docker_choice" =~ ^[12]$ ]]; then
      warn "DOCKER_CHOICE 环境变量无效，使用默认值 1"
      docker_choice="$DOCKER_DEFAULT_CHOICE"
    fi
  fi

  if [ "$docker_choice" = "2" ]; then
    _install_docker_ce_fedora
  else
    _install_podman_docker_fedora
  fi
}

# 安装 Docker CE - Fedora
_install_docker_ce_fedora() {
  log "安装 Docker CE..."
  pkg_add_repo repo-url "$DOCKER_FEDORA_REPO_URL"
  pkg_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  safe_exec ${SUDO} systemctl enable --now docker

  if [ "$USER" != "root" ]; then
    safe_exec ${SUDO} usermod -aG docker "$USER"
    info "Docker 已安装（重新登录后生效）"
  fi
}

# 安装 Podman Docker - Fedora
_install_podman_docker_fedora() {
  pkg_install podman podman-docker podman-compose
  if ! safe_exec systemctl --user enable --now podman.socket; then
    warn "podman.socket 启动失败，可能当前会话不支持 systemd user"
  fi
  info "podman-docker 已安装（无需 root 权限）"
}

# Docker 安装辅助函数 - Debian/Ubuntu
_install_docker_debian() {
  log "安装 Docker CE（官方）..."

  # 移除旧版本
  safe_exec ${SUDO} apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

  # 安装依赖
  pkg_install ca-certificates curl gnupg

  # 添加 Docker GPG 密钥
  _setup_docker_gpg_key || return 1

  # 添加 Docker 仓库
  _add_docker_repository || return 1

  safe_exec ${SUDO} apt-get update

  # 安装 Docker
  pkg_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # 启动 Docker 服务
  safe_exec ${SUDO} systemctl enable --now docker

  # 将当前用户添加到 docker 组
  if [ "$USER" != "root" ]; then
    safe_exec ${SUDO} usermod -aG docker "$USER"
    info "Docker 已安装（重新登录后生效）"
  fi
}

# 设置 Docker GPG 密钥 - Debian
_docker_apt_repo_distro() {
  if [ -z "${ID:-}" ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
  fi

  case "${ID:-}" in
    pop|linuxmint)
      printf 'ubuntu\n'
      ;;
    *)
      printf '%s\n' "${ID:-}"
      ;;
  esac
}

_docker_apt_repo_codename() {
  if [ -z "${ID:-}" ] || { [ -z "${VERSION_CODENAME:-}" ] && [ -z "${UBUNTU_CODENAME:-}" ]; }; then
    # shellcheck disable=SC1091
    . /etc/os-release
  fi

  case "${ID:-}" in
    pop|linuxmint)
      printf '%s\n' "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
      ;;
    *)
      printf '%s\n' "${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
      ;;
  esac
}

_setup_docker_gpg_key() {
  local docker_repo_distro tmp_gpg

  ${SUDO} install -m 0755 -d /etc/apt/keyrings || {
    warn "创建 keyrings 目录失败"
    return 1
  }

  if [ -f "$DOCKER_GPG_KEY_PATH" ]; then
    return 0
  fi

  docker_repo_distro="$(_docker_apt_repo_distro)"
  if [ -z "$docker_repo_distro" ]; then
    warn "无法确定 Docker APT 仓库发行版"
    return 1
  fi

  tmp_gpg=$(mktemp)
  
  if ! retry_curl "https://download.docker.com/linux/${docker_repo_distro}/gpg" "$tmp_gpg"; then
    warn "下载 Docker GPG 密钥失败"
    rm -f "$tmp_gpg"
    return 1
  fi

  if ! ${SUDO} gpg --dearmor -o "$DOCKER_GPG_KEY_PATH" < "$tmp_gpg"; then
    warn "处理 GPG 密钥失败"
    rm -f "$tmp_gpg"
    return 1
  fi

  ${SUDO} chmod a+r "$DOCKER_GPG_KEY_PATH"
  rm -f "$tmp_gpg"
  return 0
}

# 添加 Docker 仓库 - Debian
_add_docker_repository() {
  local docker_repo_distro docker_repo_codename

  docker_repo_distro="$(_docker_apt_repo_distro)"
  docker_repo_codename="$(_docker_apt_repo_codename)"
  if [ -z "$docker_repo_distro" ] || [ -z "$docker_repo_codename" ]; then
    warn "无法确定 Docker APT 仓库信息"
    return 1
  fi

  echo "deb [arch=$(dpkg --print-architecture) signed-by=$DOCKER_GPG_KEY_PATH] https://download.docker.com/linux/${docker_repo_distro} ${docker_repo_codename} stable" | \
    ${SUDO} tee "$DOCKER_APT_LIST_PATH" > /dev/null
}

install_docker() {
  [ "$MINIMAL_MODE" = true ] && return

  if [ "$DRY_RUN" = true ]; then
    info "[DRY-RUN] 将安装 Docker 及其依赖"
    return 0
  fi

  case "$OS" in
    macos)
      _install_docker_macos
      return
      ;;
  esac

  # Linux 安装流程
  case "$DISTRO" in
    fedora) _install_docker_fedora ;;
    debian) _install_docker_debian ;;
  esac

  # 验证安装
  if ! have_cmd docker; then
    warn "Docker 安装失败"
  fi
}

_lazygit_release_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "x86_64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv6l) echo "armv6" ;;
    *)
      return 1
      ;;
  esac
}

_install_lazygit_debian() {
  local arch version tmp_dir tarball_path binary_path api_url download_url

  arch="$(_lazygit_release_arch)" || {
    warn "当前架构暂未适配 lazygit 官方二进制包: $(uname -m)"
    return 1
  }

  api_url="https://api.github.com/repos/jesseduffield/lazygit/releases/latest"
  if have_cmd jq; then
    if ! version="$(retry_curl "$api_url" - | jq -r '.tag_name | sub("^v"; "")')"; then
      warn "获取 lazygit 最新版本失败"
      return 1
    fi
  else
    if ! version="$(retry_curl "$api_url" - | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\{0,1\}\([^"]*\)".*/\1/p' | head -n 1)"; then
      warn "获取 lazygit 最新版本失败"
      return 1
    fi
  fi

  if [ -z "$version" ] || [ "$version" = "null" ]; then
    warn "无法解析 lazygit 最新版本号"
    return 1
  fi

  tmp_dir="$(mktemp -d)"
  tarball_path="${tmp_dir}/lazygit.tar.gz"
  binary_path="${tmp_dir}/lazygit"
  download_url="https://github.com/jesseduffield/lazygit/releases/download/v${version}/lazygit_${version}_linux_${arch}.tar.gz"

  if ! retry_curl "$download_url" "$tarball_path"; then
    warn "下载 lazygit 官方二进制包失败"
    rm -rf "$tmp_dir"
    return 1
  fi

  if ! safe_exec tar -C "$tmp_dir" -xf "$tarball_path" lazygit; then
    warn "解压 lazygit 失败"
    rm -rf "$tmp_dir"
    return 1
  fi

  if ! safe_exec ${SUDO} install "$binary_path" -D -t /usr/local/bin/; then
    warn "安装 lazygit 到 /usr/local/bin 失败"
    rm -rf "$tmp_dir"
    return 1
  fi

  rm -rf "$tmp_dir"
  return 0
}

install_lazygit() {
  if [ "$MINIMAL_MODE" = true ]; then
    info "最小模式，跳过 lazygit"
    return
  fi

  if have_cmd lazygit; then
    info "lazygit 已安装，跳过"
    return
  fi

  log "安装 lazygit..."
  case "$OS" in
    macos)
      pkg_install lazygit || warn "lazygit 安装失败"
      ;;
    linux)
      case "$DISTRO" in
        fedora)
          install_tool_package "lazygit" "copr:dejan/lazygit" "dnf" "brew" "lazygit"
          ;;
        debian)
          _install_lazygit_debian || warn "lazygit 安装失败"
          ;;
      esac
      ;;
  esac
}

_yazi_release_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "x86_64" ;;
    aarch64|arm64) echo "aarch64" ;;
    *)
      return 1
      ;;
  esac
}

_install_yazi_debian() {
  local arch package_url

  arch="$(_yazi_release_arch)" || {
    warn "当前架构暂未适配 Yazi 官方 Debian 包: $(uname -m)"
    return 1
  }

  package_url="https://github.com/sxyazi/yazi/releases/latest/download/yazi-${arch}-unknown-linux-gnu.deb"
  pkg_add_repo deb "$package_url"
}

install_zellij() {
  install_tool_package "zellij" "copr:varlad/zellij" "cargo" "brew" "zellij 终端多路复用器"
}

install_yazi() {
  if [ "$MINIMAL_MODE" = true ]; then
    info "最小模式，跳过 yazi"
    return
  fi

  if have_cmd yazi; then
    info "yazi 已安装，跳过"
    return
  fi

  log "安装 yazi 文件管理器..."
  case "$OS" in
    macos)
      pkg_install yazi || warn "yazi 安装失败"
      ;;
    linux)
      case "$DISTRO" in
        fedora)
          install_tool_package "yazi" "copr:lihaohong/yazi" "dnf" "brew" "yazi 文件管理器"
          ;;
        debian)
          _install_yazi_debian || warn "yazi 安装失败"
          ;;
      esac
      ;;
  esac
}

# Ghostty 安装 - Debian
_install_ghostty_debian() {
  info "使用非官方社区脚本安装 ghostty（mkasberg/ghostty-ubuntu）..."
  info "注意：这不是官方 Ghostty 发行版，而是社区维护的 .deb 包"

  if run_remote_install_script "安装 ghostty" /bin/bash "https://raw.githubusercontent.com/mkasberg/ghostty-ubuntu/HEAD/install.sh"; then
    info "ghostty 已安装（更新方法：重新运行安装命令）"
    return 0
  fi

  warn "ghostty 安装失败"
  info "备选方案："
  info "  1. 访问 https://github.com/mkasberg/ghostty-ubuntu/releases 手动下载 .deb"
  info "  2. 或通过 cargo 编译安装：cargo install --git https://github.com/ghostty-org/ghostty"
  return 1
}

install_ghostty() {
  [ "$MINIMAL_MODE" = true ] && return
  have_cmd ghostty && return

  log "安装 ghostty 终端模拟器..."

  case "$OS" in
    macos)
      pkg_install_cask ghostty || warn "ghostty 安装失败"
      ;;
    linux)
      case "$DISTRO" in
        fedora)
          install_tool_package "ghostty" "copr:scottames/ghostty" "cargo" "cask" "ghostty 终端模拟器"
          ;;
        debian)
          _install_ghostty_debian
          ;;
      esac
      ;;
  esac
}

install_vicinae() {
  # macOS 不需要 vicinae（使用 Raycast/Alfred）
  [ "$OS" = "macos" ] && return
  [ "$MINIMAL_MODE" = true ] && return
  have_cmd vicinae && return

  log "安装 vicinae 启动器（使用官方统一安装脚本）..."

  # 使用官方安装脚本（适用于所有 Linux 发行版）
  if run_remote_install_script "安装 vicinae" bash "https://vicinae.com/install.sh"; then
    info "vicinae 已安装（文档: https://docs.vicinae.com）"
  else
    warn "vicinae 安装失败"
    info "请访问 https://docs.vicinae.com/install 查看手动安装方法"
  fi
}

# VS Code 安装 - macOS
_install_vscode_macos() {
  pkg_install_cask visual-studio-code || warn "VS Code 安装失败"
}

# VS Code 安装 - Fedora
_install_vscode_fedora() {
  local rpm_key="/tmp/microsoft.asc"
  local repo_file="/etc/yum.repos.d/vscode.repo"

  if [ -f "$repo_file" ]; then
    pkg_install code || warn "VS Code 安装失败"
    return
  fi

  info "添加 Microsoft GPG 密钥和仓库..."
  
  if retry_curl "https://packages.microsoft.com/keys/microsoft.asc" "$rpm_key"; then
    ${SUDO} rpm --import "$rpm_key" || warn "导入 GPG 密钥失败"
    rm -f "$rpm_key"
  fi

  ${SUDO} tee "$repo_file" > /dev/null <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

  pkg_install code || warn "VS Code 安装失败"
}

# VS Code 安装 - Debian/Ubuntu
_install_vscode_debian() {
  local apt_keyring="/usr/share/keyrings/packages.microsoft.gpg"
  local apt_list="/etc/apt/sources.list.d/vscode.list"

  if [ -f "$apt_keyring" ]; then
    pkg_install code || warn "VS Code 安装失败"
    return
  fi

  info "添加 Microsoft GPG 密钥和仓库..."
  pkg_install apt-transport-https

  local tmp_key
  tmp_key=$(mktemp)
  
  if ! retry_curl "https://packages.microsoft.com/keys/microsoft.asc" "$tmp_key"; then
    warn "下载 GPG 密钥失败"
    rm -f "$tmp_key"
    return 1
  fi

  if ! ${SUDO} gpg --dearmor -o "$apt_keyring" < "$tmp_key"; then
    warn "处理 GPG 密钥失败"
    rm -f "$tmp_key"
    return 1
  fi

  ${SUDO} chmod a+r "$apt_keyring"
  rm -f "$tmp_key"

  echo "deb [arch=amd64,arm64,armhf signed-by=$apt_keyring] https://packages.microsoft.com/repos/code stable main" | \
    ${SUDO} tee "$apt_list" > /dev/null

  safe_exec ${SUDO} apt-get update
  pkg_install code || warn "VS Code 安装失败"
}

install_vscode() {
  if [ "$DRY_RUN" = true ] && ! have_cmd code && ! have_cmd code-insiders; then
    info "[DRY-RUN] 将安装 Visual Studio Code"
    return 0
  fi

  # 检查是否已安装
  if have_cmd code || have_cmd code-insiders; then
    info "VS Code 已安装，跳过"
    return
  fi

  log "安装 Visual Studio Code..."

  case "$OS" in
    macos) _install_vscode_macos ;;
    linux)
      case "$DISTRO" in
        fedora) _install_vscode_fedora ;;
        debian) _install_vscode_debian ;;
      esac
      ;;
  esac

  # 验证安装
  if have_cmd code; then
    info "VS Code 已成功安装"
    info "启动命令: code"
  fi
}

# Telegram 安装 - Debian (备选方案)
_install_telegram_debian_fallback() {
  info "尝试通过 Flatpak 安装 Telegram..."
  
  if ! have_cmd flatpak; then
    warn "Flatpak 未安装，无法自动安装 Telegram"
    info "请手动安装："
    info "  1. 官网下载: https://desktop.telegram.org/"
    info "  2. 或安装 Snap: sudo snap install telegram-desktop"
    return 1
  fi

  if safe_exec flatpak install -y flathub org.telegram.desktop; then
    return 0
  fi

  warn "Flatpak 安装失败"
  info "备选方案："
  info "  1. 从官网下载: https://desktop.telegram.org/"
  info "  2. 或使用 Snap: sudo snap install telegram-desktop"
  return 1
}

# Telegram 安装 - Debian
_install_telegram_debian() {
  if pkg_install telegram-desktop 2>/dev/null; then
    info "Telegram 已从官方仓库安装"
    return 0
  fi

  _install_telegram_debian_fallback
}

install_telegram() {
  # 检查是否已安装
  if have_cmd telegram-desktop; then
    info "Telegram 已安装，跳过"
    return
  fi

  log "安装 Telegram Desktop..."

  case "$OS" in
    macos)
      pkg_install_cask telegram || warn "Telegram 安装失败"
      ;;
    linux)
      case "$DISTRO" in
        fedora)
          pkg_install telegram-desktop || warn "Telegram 安装失败"
          ;;
        debian)
          _install_telegram_debian
          ;;
      esac
      ;;
  esac

  # 验证安装
  if have_cmd telegram-desktop; then
    info "Telegram Desktop 已成功安装"
  elif [ "$OS" = "linux" ] && have_cmd flatpak && flatpak list 2>/dev/null | grep -q "org.telegram.desktop"; then
    info "Telegram Desktop 已通过 Flatpak 安装"
    info "启动命令: flatpak run org.telegram.desktop"
  fi
}

# ================= 语言运行时安装 =================
should_skip_lang() {
  local lang="$1"
  for skip in "${SKIP_LANGS[@]}"; do
    [[ "$skip" == "$lang" ]] && return 0
  done
  return 1
}

install_mise() {
  local mise_bin_dir="$HOME/.local/bin"

  export PATH="$mise_bin_dir:$PATH"
  if have_cmd mise; then
    info "mise 已安装，跳过"
    return 0
  fi

  log "安装 mise..."
  if ! run_remote_install_script "安装 mise" sh "https://mise.run"; then
    warn "mise 安装失败"
    return 1
  fi

  export PATH="$mise_bin_dir:$PATH"
  if [ "$DRY_RUN" != true ] && ! have_cmd mise; then
    warn "mise 安装后未找到命令"
    return 1
  fi
}

_mise_all_targets() {
  cat <<'EOF'
node
python
go
rust
bun
zig
zls
uv
pnpm
biome
shfmt
golangci-lint
staticcheck
npm:typescript
npm:typescript-language-server
npm:pyright
go:golang.org/x/tools/gopls
go:golang.org/x/tools/cmd/goimports
go:github.com/go-delve/delve/cmd/dlv
go:mvdan.cc/garble
cargo:cargo-nextest
cargo:eza
cargo:sd
cargo:tokei
cargo:hyperfine
cargo:git-absorb
cargo:just
pipx:black
pipx:ruff
pipx:pipx
pipx:pytest
EOF
}

should_skip_mise_target() {
  local target="$1"

  case "$target" in
    rust|cargo:*)
      should_skip_lang rust && return 0
      ;;
    node|pnpm|biome|npm:*)
      should_skip_lang node && return 0
      ;;
    go|golangci-lint|staticcheck|shfmt|go:*)
      should_skip_lang go && return 0
      ;;
    python|uv|pipx:*)
      should_skip_lang python && return 0
      ;;
    bun)
      should_skip_lang bun && return 0
      ;;
    zig|zls)
      should_skip_lang zig && return 0
      ;;
  esac

  return 1
}

build_mise_install_targets() {
  local target

  while IFS= read -r target; do
    [ -n "$target" ] || continue
    if ! should_skip_mise_target "$target"; then
      printf '%s\n' "$target"
    fi
  done < <(_mise_all_targets)
}

activate_mise_for_current_session() {
  local mise_bin_dir="$HOME/.local/bin"
  local mise_shims_dir="${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims"

  if [ "$DRY_RUN" = true ]; then
    info "[DRY-RUN] 跳过当前会话 mise 激活"
    return 0
  fi

  export PATH="$mise_bin_dir:$PATH"
  case ":$PATH:" in
    *":$mise_shims_dir:"*) ;;
    *) export PATH="$mise_shims_dir:$PATH" ;;
  esac

  if ! have_cmd mise; then
    warn "mise 未找到，无法激活当前会话"
    return 1
  fi

  # shellcheck disable=SC1091
  eval "$(mise activate bash)"
}

install_mise_toolchain() {
  local targets=()
  local target

  while IFS= read -r target; do
    [ -n "$target" ] && targets+=("$target")
  done < <(build_mise_install_targets)

  if [ ${#targets[@]} -eq 0 ]; then
    info "所有 mise targets 都因 --skip 过滤被跳过"
    return 0
  fi

  if [ "$DRY_RUN" = true ]; then
    info "[DRY-RUN] mise install ${targets[*]}"
    return 0
  fi

  if ! have_cmd mise; then
    warn "mise 未找到，跳过 toolchain 安装"
    return 1
  fi

  log "通过 mise 安装语言运行时和工具..."
  if ! safe_exec mise install "${targets[@]}"; then
    warn "mise toolchain 安装失败"
    return 1
  fi

}

# ================= Shell 配置 =================
change_default_shell_to_zsh() {
  log "切换默认 Shell 到 zsh..."

  # 检查 zsh 是否已安装
  if ! have_cmd zsh; then
    warn "zsh 未安装，跳过切换默认 Shell"
    return
  fi

  # 获取 zsh 路径
  local zsh_path
  zsh_path="$(command -v zsh)"

  # 检查当前默认 Shell
  local current_shell
  case "$OS" in
    linux)
      current_shell="$(getent passwd "$USER" | cut -d: -f7)"
      ;;
    macos)
      current_shell="$(dscl . -read ~/ UserShell | awk '{print $2}')"
      ;;
  esac

  if [ "$current_shell" = "$zsh_path" ]; then
    return
  fi

  # 检查 zsh 是否在 /etc/shells 中
  if ! grep -qx "$zsh_path" /etc/shells 2>/dev/null; then
    info "将 zsh 添加到 /etc/shells..."
    if [ "$DRY_RUN" = true ]; then
      info "[DRY-RUN] 将 zsh 添加到 /etc/shells: $zsh_path"
    else
      if ! echo "$zsh_path" | ${SUDO} tee -a /etc/shells >/dev/null; then
        warn "将 zsh 添加到 /etc/shells 失败"
      fi
    fi
  fi

  # 切换默认 Shell
  info "正在切换默认 Shell 到 zsh..."
  if [ "$OS" = "macos" ]; then
    # macOS chsh 需要密码，无法通过脚本自动化
    info "macOS 需要手动切换默认 shell（需要输入密码）："
    info "  chsh -s $zsh_path"
    info "或稍后在\"系统设置 > 用户与群组\"中修改"
  else
    if safe_exec chsh -s "$zsh_path"; then
      info "默认 Shell 已切换到 zsh（重新登录生效）"
    else
      warn "切换默认 Shell 失败"
      info "您可以稍后手动执行: chsh -s $zsh_path"
    fi
  fi
}

configure_shell() {
  log "配置 Shell 环境..."

  # 切换默认 Shell 到 zsh
  change_default_shell_to_zsh

  # starship
  if ! have_cmd starship; then
    if ! pkg_install starship; then
      warn "包管理器安装 starship 失败，尝试官方脚本..."
      if ! run_remote_install_script "安装 starship" sh "https://starship.rs/install.sh" -y; then
        warn "starship 安装失败"
      fi
    fi
  fi

  # 注意：如果使用了配置文件部署（configs/.zshrc），则跳过修改 shell rc 文件
  # configs/.zshrc 已包含完整配置，避免重复添加
  if [ "$SKIP_CONFIG" = true ]; then
    # 仅在跳过配置部署时添加配置块
    # shellcheck disable=SC2016
    append_block_if_missing_pattern "MANAGED-STARSHIP" 'starship init bash' \
      'eval "$(starship init bash)"' "$BASHRC"
    # shellcheck disable=SC2016
    append_block_if_missing_pattern "MANAGED-STARSHIP" 'starship init zsh' \
      'eval "$(starship init zsh)"' "$ZSHRC"
    # shellcheck disable=SC2016
    append_block_if_missing_pattern "MANAGED-ZOXIDE" 'zoxide init bash' \
      'eval "$(zoxide init bash)"' "$BASHRC"
    # shellcheck disable=SC2016
    append_block_if_missing_pattern "MANAGED-ZOXIDE" 'zoxide init zsh' \
      'eval "$(zoxide init zsh)"' "$ZSHRC"
  fi
}

# ================= 阶段 3: 配置文件部署 =================

# 部署单个配置项（文件或目录）的辅助函数
# _deploy_config_item SRC DST IS_DIR
# 参数：
#   SRC: 源路径
#   DST: 目标路径
#   IS_DIR: "true" 表示目录，"false" 表示文件
_deploy_config_item() {
  local src="$1"
  local dst="$2"
  local is_dir="$3"

  # 检查源是否存在
  if [ ! -e "$src" ]; then
    if [ "$is_dir" = "true" ]; then
      warn "配置目录不存在，跳过: $src"
    else
      warn "配置文件不存在，跳过: $src"
    fi
    return 1
  fi

  if [ "$DRY_RUN" = true ]; then
    info "[DRY-RUN] 将部署配置: $src -> $dst"
    return 0
  fi

  # 备份现有配置
  if [ -e "$dst" ]; then
    if [ -L "$dst" ]; then
      # 如果是软链接，直接删除
      if ! rm "$dst"; then
        warn "删除软链接失败: $dst"
        return 1
      fi
    else
      # 备份现有文件/目录
      local backup="${dst}.backup.$BACKUP_TS"
      if ! mv "$dst" "$backup"; then
        warn "备份失败: $dst"
        return 1
      fi
    fi
  fi

  # 创建父目录
  if ! mkdir -p "$(dirname "$dst")"; then
    warn "创建目录失败: $(dirname "$dst")"
    return 1
  fi

  # 复制文件或目录
  if [ "$is_dir" = "true" ]; then
    if ! cp -r "$src" "$dst"; then
      warn "复制目录失败: $src -> $dst"
      return 1
    fi
  else
    if ! cp "$src" "$dst"; then
      warn "复制文件失败: $src -> $dst"
      return 1
    fi
  fi
  
  return 0
}

deploy_config_files() {
  [ "$SKIP_CONFIG" = true ] && return

  step "部署配置文件..."

  if [ ! -d "$CONFIG_DIR" ]; then
    err "配置目录不存在: $CONFIG_DIR"
    err "请确保将 configs/ 目录与脚本放在同一位置"
    return
  fi

  # 定义配置文件映射（源文件 -> 目标位置）
  # 注意：所有配置文件都直接复制，不创建软链接
  declare -A CONFIG_FILES_COPY=(
    ["$CONFIG_DIR/.zshrc"]="$HOME/.zshrc"
    ["$CONFIG_DIR/.bashrc"]="$HOME/.bashrc"
    ["$CONFIG_DIR/.config/starship.toml"]="$HOME/.config/starship.toml"
    ["$CONFIG_DIR/.config/shell/env"]="$HOME/.config/shell/env"
    ["$CONFIG_DIR/.config/mise/config.toml"]="$HOME/.config/mise/config.toml"
  )

  declare -A CONFIG_DIRS_COPY=(
    ["$CONFIG_DIR/.config/zellij"]="$HOME/.config/zellij"
    ["$CONFIG_DIR/.config/btop"]="$HOME/.config/btop"
    ["$CONFIG_DIR/.config/nvim"]="$HOME/.config/nvim"
    ["$CONFIG_DIR/.config/ghostty"]="$HOME/.config/ghostty"
    ["$CONFIG_DIR/.config/yazi"]="$HOME/.config/yazi"
  )

  # 支持非交互式模式
  if [ -t 0 ]; then
    local deploy_choice
    echo
    info "配置文件部署选项："
    info "  1. 部署（默认）"
    info "  2. 跳过"

    while true; do
      read -p "请选择 [1/2，默认 1]: " -n 1 -r deploy_choice
      echo
      deploy_choice="${deploy_choice:-1}"

      case "$deploy_choice" in
        1) break ;;
        2)
          info "跳过配置文件部署"
          return 0
          ;;
        *) warn "无效选择，请输入 1 或 2" ;;
      esac
    done
  else
    [ "${DEPLOY_CONFIGS:-yes}" = "no" ] && return
  fi

  # 处理需要复制的配置文件
  for src in "${!CONFIG_FILES_COPY[@]}"; do
    dst="${CONFIG_FILES_COPY[$src]}"
    _deploy_config_item "$src" "$dst" "false"
  done

  # 处理需要复制的配置目录
  for src in "${!CONFIG_DIRS_COPY[@]}"; do
    dst="${CONFIG_DIRS_COPY[$src]}"
    _deploy_config_item "$src" "$dst" "true"
  done

  log "配置文件部署完成"
}

# ================= SELinux 配置 =================
configure_selinux() {
  if ! have_cmd restorecon; then
    return
  fi

  step "恢复 SELinux 上下文..."
  safe_exec restorecon -Rv "$HOME/.cargo/bin" 2>/dev/null || true
  safe_exec restorecon -Rv "$HOME/.local/bin" 2>/dev/null || true
}

# ================= 版本验证 =================
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

  check_cmd_alias() {
    local label="$1"
    local primary="$2"
    local fallback="$3"
    shift 3

    if have_cmd "$primary"; then
      printf "  %-15s " "$label:"
      "$primary" "$@" 2>/dev/null | head -n1
      return 0
    fi

    if [ -n "$fallback" ] && have_cmd "$fallback"; then
      printf "  %-15s " "$label:"
      "$fallback" "$@" 2>/dev/null | head -n1
      return 0
    fi

    printf "  %-15s %s\n" "$label:" "❌ 未找到"
  }

  check_telegram_installation() {
    if have_cmd telegram-desktop; then
      printf "  %-15s " "telegram:"
      telegram-desktop --version 2>/dev/null | head -n1
      return 0
    fi

    if have_cmd flatpak && flatpak list --app --columns=application 2>/dev/null | grep -qx "org.telegram.desktop"; then
      printf "  %-15s %s\n" "telegram:" "Flatpak org.telegram.desktop"
      return 0
    fi

    printf "  %-15s %s\n" "telegram:" "❌ 未找到"
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
  check_cmd_alias fd fd fdfind --version
  check_cmd_alias bat bat batcat --version
  check_cmd eza --version
  check_cmd btop --version
  check_cmd gh --version
  check_cmd just --version
  check_cmd lazygit --version
  check_cmd yazi --version
  check_cmd ffmpeg -version
  check_cmd ghostty --version
  check_cmd code --version
  check_telegram_installation
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

# ================= 使用说明 =================
usage() {
  cat <<EOF
跨平台开发环境一键安装配置脚本 v${SCRIPT_VERSION}
支持：Linux (Fedora/Debian/Ubuntu) 和 macOS

用法: $0 [选项]

选项:
  -h, --help              显示此帮助信息
  -d, --dry-run           仅显示将执行的命令，不实际执行
  -m, --minimal           最小模式（跳过 ffmpeg、Docker 等非核心包）
  -s, --skip LANG         跳过指定语言组（rust|node|go|python|bun|zig）
                          会同时跳过该语言组对应的 mise tools
  --skip-config           跳过配置文件部署
  -V, --version           显示版本信息

环境变量:
  INSTALL_NERD_FONTS=yes  非交互模式下自动安装 Nerd Fonts
  DEPLOY_CONFIGS=no       非交互模式下跳过配置文件部署
  DOCKER_CHOICE=1         Fedora 非交互模式下选择 Docker 方式（1=podman-docker, 2=Docker CE）

范例:
  $0                                    # 完整安装和配置（自动检测 OS）
  $0 --minimal                          # 最小安装
  $0 -s rust -s bun                     # 跳过 Rust 和 Bun
  $0 --skip-config                      # 只安装软件，不部署配置
  $0 --dry-run                          # 预览操作
  INSTALL_NERD_FONTS=yes $0             # 非交互模式安装 Nerd Fonts
  DOCKER_CHOICE=2 $0                    # Fedora 上安装 Docker CE（Linux）

支持的平台:
  Linux:
    - Fedora (tested: 39, 40, 41)
    - Ubuntu (tested: 22.04 LTS, 24.04 LTS)
    - Debian (tested: 12 Bookworm)
    - Linux Mint, Pop!_OS (基于 Ubuntu)

  macOS:
    - macOS 12 (Monterey) 及以上
    - 支持 Intel 和 Apple Silicon (M1/M2/M3)
    - 自动安装 Homebrew 和 Xcode Command Line Tools

特别说明:
  macOS 用户:
    - 首次运行会自动安装 Xcode CLT 和 Homebrew（需要网络）
    - vicinae 启动器将跳过（推荐使用 Raycast 或 Alfred）
    - Docker 将安装 Docker Desktop（需要手动启动）
    - 部分 Linux 专用软件将自动跳过

EOF
}

# ================= 参数解析 =================
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      -V|--version)
        echo "v${SCRIPT_VERSION}"
        exit 0
        ;;
      -d|--dry-run)
        DRY_RUN=true
        shift
        ;;
      -m|--minimal)
        MINIMAL_MODE=true
        shift
        ;;
      -s|--skip)
        if [ -z "${2:-}" ]; then
          err "--skip 需要指定语言参数"
          exit 1
        fi
        SKIP_LANGS+=("$2")
        shift 2
        ;;
      --skip-config)
        SKIP_CONFIG=true
        shift
        ;;
      *)
        err "未知选项: $1"
        usage
        exit 1
        ;;
    esac
  done
}

# ================= 主流程 =================
# 阶段 0: 系统检测与初始化
_stage0_system_detection() {
  step "阶段 0/4: 系统检测与初始化"
  detect_os
  setup_sudo
  check_arch

  # macOS 专用前置
  if [ "$OS" = "macos" ]; then
    ensure_xcode_clt
    ensure_homebrew
    ensure_homebrew_taps
  fi
}

# 阶段 1: 系统配置
_stage1_system_configuration() {
  step "阶段 1/4: 系统配置"

  # Linux 专用配置
  if [ "$OS" = "linux" ]; then
    configure_package_manager
    configure_flatpak
    ensure_extra_repos
  fi

  # 通用：更新系统
  update_system

  # 通用：安装字体和依赖
  install_fonts_and_dependencies
  install_nerd_fonts
}

# 阶段 3: 软件安装
_stage3_software_installation() {
  step "阶段 3/4: 软件安装"
  
  install_base_packages
  install_ffmpeg
  install_docker

  # 语言运行时
  install_mise
  install_mise_toolchain
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

# 阶段 4: 验证和清理
_stage4_verification() {
  step "阶段 4/4: 验证和清理"

  [ "$OS" = "linux" ] && configure_selinux

  verify_installations

  log "安装完成"

  local current_shell
  case "$OS" in
    linux) current_shell="$(getent passwd "$USER" | cut -d: -f7)" ;;
    macos) current_shell="$(dscl . -read ~/ UserShell | awk '{print $2}')" ;;
  esac

  if [[ "$current_shell" == *"zsh"* ]]; then
    info "Shell 已切换，重新登录生效或执行: exec zsh"
  else
    info "载入环境: source ~/.bashrc 或 source ~/.zshrc"
  fi
}

main() {
  parse_args "$@"

  [ "$DRY_RUN" = true ] && warn "DRY-RUN 模式"
  [ "$MINIMAL_MODE" = true ] && info "最小模式"
  [ ${#SKIP_LANGS[@]} -gt 0 ] && info "跳过: ${SKIP_LANGS[*]}"

  # curl 检查
  if ! have_cmd curl; then
    err "需要 curl (Fedora: dnf install curl / Debian: apt install curl)"
    exit 1
  fi

  _stage0_system_detection
  _stage1_system_configuration
  
  # 阶段 2: 配置文件部署
  step "阶段 2/4: 配置文件部署"
  deploy_config_files
  
  _stage3_software_installation
  _stage4_verification
}

# 执行主流程
main "$@"
