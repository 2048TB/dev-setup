# Mise Migration Design

**日期:** 2026-04-13

**目标:** 用全局 `mise` 配置统一替换当前脚本里分散的 `rustup`、`nvm`、手动 `Go`/`Zig`、`uv`、`bun` 运行时安装逻辑，并把常用语言工具一并迁入 `~/.config/mise/config.toml`。

## 背景

当前仓库的多语言环境由几部分拼起来：

- `setup.sh` 里分别维护 `Rust`、`Node.js`、`Go`、`uv`、`Bun`、`Zig` 的安装流程
- `configs/.config/shell/env` 里手动注入 `cargo`、`nvm`、`Go`、`Bun` 的环境变量和 `PATH`
- `configs/.zshrc` 里依赖 `BUN_INSTALL` 的补全逻辑

这套方案的问题是：

- 语言管理逻辑重复分散，安装、升级、激活分别由不同代码路径负责
- 不同语言各自使用不同工具，维护成本高
- shell 初始化文件承担了过多运行时细节
- 新增语言工具时需要同时改脚本和环境文件

## 已确认决策

### 方案

采用“仓库跟踪一份全局 `mise` 配置，`setup.sh` 只负责安装 `mise`、部署配置、执行 `mise install`”。

不采用以下方案：

- 保留旧逻辑作为 fallback：会继续留下双轨维护
- 用 `setup.sh` 逐条执行 `mise use -g`：配置会分散进脚本，不利于维护

### 替换边界

本次迁移只保留 `mise`。

旧的以下路径将全部移除，而不是保留 fallback：

- `rustup`
- `nvm`
- 手动 `Go` 下载/替换逻辑
- 手动 `Zig` 下载/替换逻辑
- `uv` 官方 installer
- `bun` 官方 installer
- `cargo install` 方式安装语言相关工具

### 工具范围

除运行时之外，额外按参考配置把常用语言工具也迁进 `mise` 全局配置。

## 目标状态

迁移完成后，仓库的职责边界应该是：

- `configs/.config/mise/config.toml`
  - 仓库唯一的多语言运行时与语言工具声明来源
- `setup.sh`
  - 安装 `mise`
  - 部署 `mise` 配置
  - 调用 `mise install`
  - 验证关键工具是否可用
- `configs/.config/shell/env`
  - 只负责通用 `PATH` 和 `mise` 激活前置
  - 不再维护 `NVM_DIR`、`BUN_INSTALL`、`cargo/env`、`/usr/local/go/bin`
- `configs/.zshrc` / `configs/.bashrc`
  - 只通过共享环境文件拿到 `mise` 激活后的工具
  - 不再直接依赖旧运行时变量

## 参考配置落地原则

基于参考文件，保留这类结构：

- `[settings]`
  - `all_compile = false`
  - `not_found_auto_install = false`
- `[settings.python]`
  - `precompiled_flavor = "install_only_stripped"`
- `[tools]`
  - runtime：`node`、`python`、`go`、`rust`、`bun`、`zig`
  - language servers / formatters / linters / package tools：`zls`、`uv`、`pnpm`、`biome`、`shfmt`、`golangci-lint`、`staticcheck`
  - `npm:` backend：`typescript`、`typescript-language-server`、`pyright`
  - `go:` backend：`gopls`、`goimports`、`dlv`、`garble`
  - `cargo:` backend：`cargo-nextest`
  - `pipx:` backend：`black`、`ruff`、`pipx`、`pytest`

需要做的本地化调整：

- `rust.targets = "x86_64-pc-windows-gnu"` 不适合作为通用默认值，默认不写死跨平台目标
- 版本号保持参考风格，但允许使用当前 `mise` 支持的版本写法
- `config.toml` 放在仓库 `configs/.config/mise/config.toml`，部署目标为 `~/.config/mise/config.toml`

## 文件变更设计

### 1. 新增 `mise` 配置

新增：

- `configs/.config/mise/config.toml`

职责：

- 承载全局 `mise` settings
- 承载所有 runtime 与语言工具定义

### 2. 收敛 `setup.sh`

修改：

- `setup.sh`

具体变化：

- 新增 `install_mise()`，统一负责安装 `mise`
- 删除或废弃以下函数及其调用：
  - `install_rust()`
  - `install_cargo_tools()`
  - `install_nodejs()`
  - `_download_and_install_go()`
  - `install_go()`
  - `install_uv()`
  - `install_bun()`
  - `_get_zig_version_info()`
  - `_download_and_install_zig()`
  - `install_zig()`
- 新增 `install_mise_toolchain()` 或同等职责函数：
  - 确保 `~/.config/mise/config.toml` 已部署
  - 执行 `mise install`
- 更新 `verify_installations()`：
  - 保留用户可见工具校验
  - 版本来源改为 `mise` 激活环境，而不是旧 `PATH`

### 3. 简化共享环境文件

修改：

- `configs/.config/shell/env`

具体变化：

- 保留：
  - `~/.local/bin`
  - `~/bin`
  - `Homebrew shellenv`
  - 其他与语言管理无关的通用环境
- 删除：
  - `cargo/env`
  - `NVM_DIR` 与 `nvm.sh`
  - `/usr/local/go/bin`
  - `BUN_INSTALL`
- 新增：
  - `mise` 的 shell 激活逻辑，使用适用于 `sh`/`bash`/`zsh` 的统一写法

### 4. 清理 shell 配置对旧变量的依赖

修改：

- `configs/.zshrc`
- 如有必要，少量调整 `configs/.bashrc`

具体变化：

- 删除依赖 `BUN_INSTALL` 的补全加载
- 不在 rc 文件里额外引入 `nvm`、`cargo`、`bun`、`go` 相关环境
- 保持 `starship`、`zoxide`、`fzf` 等与 `mise` 无关的现有功能不变

### 5. 部署映射更新

修改：

- `setup.sh` 的 `deploy_config_files()`

具体变化：

- 把 `configs/.config/mise/config.toml` 部署到 `~/.config/mise/config.toml`

## 安装与激活流程

目标流程：

1. `setup.sh` 安装系统基础包
2. `setup.sh` 安装 `mise`
3. `setup.sh` 部署 `configs/.config/mise/config.toml`
4. `setup.sh` 部署 shell 配置
5. `setup.sh` 在非 `DRY_RUN` 下执行 `mise install`
6. 新 shell 会话通过 `mise activate` 自动获得工具

约束：

- `DRY_RUN` 下不能真正安装 `mise` 或执行 `mise install`
- shell 激活必须放在共享环境路径里，保证 `bash` 和 `zsh` 都一致
- 不要求在脚本里手动逐个 export runtime 路径

## 错误处理

`setup.sh` 中新的 `mise` 路径需要满足：

- 安装 `mise` 失败时，给出明确 `warn` 或 `err`
- `mise install` 失败时，脚本返回失败并指出是 `mise` toolchain 安装失败
- `DRY_RUN` 下只输出将执行的 `mise` 操作，不做真实写入
- 如果部署了 `mise` 配置但 `mise` 命令不存在，`verify_installations()` 应明确报告

## 非目标

本次不做这些事：

- 不为每个项目新增局部 `mise.toml`
- 不引入 `mise tasks`
- 不重构与语言管理无关的包安装逻辑
- 不更改 `starship`、`zellij`、`yazi` 等现有配置语义

## 验证设计

实现后至少需要验证：

### 静态验证

- `bash -n setup.sh`
- `bash -n configs/.config/shell/env`
- `bash -n configs/.bashrc`
- `zsh -n configs/.zshrc`
- `shellcheck -x setup.sh configs/.config/shell/env configs/.bashrc configs/.zshrc`
- `python3` + `tomllib` 校验 `configs/.config/mise/config.toml`

### 运行验证

- `bash setup.sh --help`
- `bash setup.sh --dry-run`
- 用临时 `HOME` 验证部署后存在：
  - `~/.config/mise/config.toml`
- 若本机已有 `mise`：
  - 在临时 `HOME` + `XDG_CONFIG_HOME` 下执行 `mise install`
  - 验证 `mise ls` 或等价命令能看到配置中的工具条目

### 回归验证

- 共享环境文件加载后，`bash` 和 `zsh` 都不会因缺失 `nvm`/`cargo`/`bun` 旧路径报错
- `setup.sh` 不再引用已移除的旧语言安装函数

## 风险与注意点

### 1. `mise` backend 可用性

参考配置里的 `npm:`、`go:`、`cargo:`、`pipx:` backend 依赖 `mise` 当前版本支持。实现时必须以本机 `mise` 版本做实际校验，不假定所有写法都可直接用。

### 2. 全局配置是强默认

迁移后，用户所有目录都会默认落到这份全局配置上；这符合目标，但也意味着全局工具数量会明显增多。

### 3. 旧路径兼容性会消失

因为明确决定“只保留 `mise`”，迁移后旧的 `nvm`、`rustup`、手动 `Go`/`Zig` 路径不会再作为保底逻辑存在。

## 实施摘要

最终实现应呈现为：

- 一份仓库跟踪的 `mise` 全局配置
- 一个明显更短的 `setup.sh`
- 一个更干净的 `configs/.config/shell/env`
- shell 启动时通过 `mise activate` 获得 runtime 和工具

这就是本次迁移的完成标准。
