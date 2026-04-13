# dev-setup

跨平台开发环境一键安装脚本，面向 `Linux (Fedora/Debian/Ubuntu)` 和 `macOS`。

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

## 仓库方式

```bash
git clone https://github.com/2048TB/dev-setup.git
cd dev-setup
bash setup.sh
```

## 说明

- `install.sh` 会先下载完整仓库压缩包，再执行其中的 `setup.sh`
- 这样可以同时拿到 `configs/`，避免直接执行单个 `setup.sh` 时缺少配置文件
- `setup.sh` 需要 `Bash 4+`
- `mise` 负责语言运行时和常用开发工具
