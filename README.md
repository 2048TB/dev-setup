# dev-setup

跨平台开发环境一键安装脚本，面向 `Linux (Fedora/Debian/Ubuntu 系)` 和 `macOS`。

## 一键安装

```bash
curl -fsSL https://raw.githubusercontent.com/2048TB/dev-setup/main/install.sh | bash
```

传参示例：

```bash
curl -fsSL https://raw.githubusercontent.com/2048TB/dev-setup/main/install.sh | bash -s -- --help
curl -fsSL https://raw.githubusercontent.com/2048TB/dev-setup/main/install.sh | bash -s -- --minimal
curl -fsSL https://raw.githubusercontent.com/2048TB/dev-setup/main/install.sh | bash -s -- -s rust -s bun
```

## 本地执行

```bash
git clone https://github.com/2048TB/dev-setup.git
cd dev-setup
bash setup.sh
```

## 作用范围

- 基础开发工具与常用 CLI
- `mise` 语言运行时与相关工具
- `Docker`
- `Ghostty`、`VS Code`、`Telegram Desktop`
- 配置文件部署：`zsh`、`bash`、`starship`、`mise`、`zellij`、`btop`、`nvim`、`ghostty`、`yazi`

## 支持目标

- `Linux`: `Fedora`、`Debian`、`Ubuntu`、`Linux Mint`、`Pop!_OS`
- `macOS`: `macOS 12+`

## 运行方式

- `install.sh` 会先下载完整仓库压缩包，再执行其中的 `setup.sh`
- 这样可以同时拿到 `configs/`，避免直接执行单个 `setup.sh` 时缺少配置文件
- `setup.sh` 需要 `Bash 4+`
- `mise` 负责语言运行时和常用开发工具

## 常用选项

```bash
bash setup.sh --help
bash setup.sh --dry-run
bash setup.sh --minimal
bash setup.sh --skip-config
bash setup.sh -s rust -s bun
```

## 非交互环境变量

- `INSTALL_NERD_FONTS=yes`
  - 非交互模式下自动安装 `Nerd Fonts`
- `DEPLOY_CONFIGS=no`
  - 非交互模式下跳过配置文件部署
- `DOCKER_CHOICE=1`
  - `Fedora` 非交互模式下选择 `Docker` 安装方式
  - `1=podman-docker`
  - `2=Docker CE`

## 说明

- 默认会出现少量交互提示，例如 `Nerd Fonts`、配置文件部署、`Fedora Docker` 选择
- `Debian/Ubuntu` 上会自动处理 `fd/fdfind`、`bat/batcat` 这类命令名差异
- 脚本支持重复执行；已有命令和已有配置会尽量跳过或备份后覆盖
- `macOS` 如果没有 `Bash 4+`，`install.sh` 会直接提示先安装新版 `bash`
