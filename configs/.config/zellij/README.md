# Zellij 配置说明

这是一个增强型 Zellij 配置，**保留所有默认快捷键**，只添加常用的额外快捷键。

---

## 文件说明

| 文件 | 说明 |
|------|------|
| `zellij-config.kdl` | 配置文件（安装到 `~/.config/zellij/config.kdl`） |
| `zellij-readme.md` | 本文档（详细说明） |
| `zellij-cheatsheet.md` | 快捷键速查表（打印或随时查看） |

---

## 快速安装

### 1. 备份现有配置（如果有）

```bash
cp ~/.config/zellij/config.kdl ~/.config/zellij/config.kdl.backup
```

### 2. 安装新配置

```bash
cp ~/Documents/4/zellij-config.kdl ~/.config/zellij/config.kdl
```

### 3. 重新载入配置

```bash
# 方法 1：在 Zellij 中按 Ctrl+o 然后按 c（打开配置插件）
# 方法 2：重启 Zellij
zellij
```

---

## 新增快捷键

此配置在默认快捷键基础上，添加了以下快捷键：

### 🚀 全局快捷键（任何模式下可用）

```
Alt + -         水平分割面板（向下分割）
Alt + \         垂直分割面板（向右分割）
Alt + h         向左移动焦点
Alt + j         向下移动焦点
Alt + k         向上移动焦点
Alt + l         向右移动焦点
Alt + x         关闭当前面板
Alt + X         关闭当前标签（大写 X）
Alt + 1-9       快速跳转到第 N 个标签
Alt + t         新建标签
Alt + f         切换全屏
Alt + s         进入滚动模式（查看历史输出）
Ctrl + e        打开文件选择器
```

### 📜 滚动模式增强

进入滚动模式后（`Ctrl+s` 或 `Alt+s`）：

```
/               进入搜索模式
g               跳到顶部
G               跳到底部
```

### 🔍 搜索模式增强

在搜索模式中：

```
N               向上搜索（原本只有 n 向下搜索）
```

---

## 默认快捷键仍然可用

所有 Zellij 默认快捷键都保留，包括：

### 模式切换

```
Ctrl + p        面板模式（管理面板）
Ctrl + t        标签模式（管理标签）
Ctrl + n        调整大小模式
Ctrl + h        移动面板模式
Ctrl + s        滚动模式
Ctrl + o        会话模式
Ctrl + b        Tmux 兼容模式
Ctrl + g        锁定模式（快捷键透传给终端）
```

### 基本操作

```
Ctrl + q        退出 Zellij
Esc / Enter     返回普通模式
```

在各个模式中，还有大量默认快捷键可用。详见 `zellij-cheatsheet.md` 速查表。

---

## UI 优化

此配置启用了以下 UI 优化：

```
simplified_ui true              简化界面，减少装饰性元素
default_layout "compact"        使用紧凑布局
show_startup_tips false         隐藏启动提示
show_release_notes false        隐藏版本更新提示
```

**效果**：界面更简洁，减少英文文本显示。

---

## 使用场景

### 场景 1：快速创建工作布局

```bash
1. Alt + \          # 垂直分割，右侧开编辑器
2. Alt + h          # 切回左边
3. Alt + -          # 水平分割，下方开终端
4. Alt + l          # 切到右边编辑器
```

### 场景 2：多标签工作流

```bash
Alt + t             # 新建标签（前端）
Alt + t             # 再新建标签（后端）
Alt + t             # 再新建标签（数据库）
Alt + 1             # 切到第 1 个标签
Alt + 2             # 切到第 2 个标签
Alt + 3             # 切到第 3 个标签
```

### 场景 3：查看历史输出

```bash
Alt + s             # 进入滚动模式
/                   # 搜索关键字（如 "error"）
n                   # 下一个匹配
N                   # 上一个匹配
q                   # 退出滚动模式
```

### 场景 4：配合 Claude Code 和 Lazygit

```bash
# 标签 1：编辑器
Alt + 1
claude              # 使用 Claude Code 编写代码

# 标签 2：Git 管理
Alt + 2
lazygit             # 提交代码

# 标签 3：测试
Alt + 3
npm test
```

---

## 常见问题

### Q1: 新快捷键不生效？

**A**: 确保配置已重新载入：
- 在 Zellij 中按 `Ctrl+o` → `c`
- 或重启 Zellij

### Q2: 快捷键冲突？

**A**: 此配置只添加 `Alt` 系列快捷键，不会与默认快捷键冲突。

### Q3: 想恢复默认配置？

**A**: 使用备份恢复：
```bash
cp ~/.config/zellij/config.kdl.backup ~/.config/zellij/config.kdl
```

或删除配置文件：
```bash
rm ~/.config/zellij/config.kdl
# Zellij 会使用内建默认配置
```

### Q4: Alt 键在我的终端不工作？

**A**: 检查终端设置：
- **iTerm2/Terminal.app**: Preferences → Profiles → Keys → 启用 "Use Option as Meta key"
- **Alacritty**: 配置文件中设置 `alt_send_esc: true`
- **GNOME Terminal**: Preferences → Shortcuts → 禁用菜单快捷键

### Q5: 如何自定义快捷键？

**A**: 编辑 `~/.config/zellij/config.kdl`，在 `normal` 区块中添加：

```kdl
normal {
    // 现有快捷键...

    // 添加你的自定义快捷键
    bind "Alt g" { Run "lazygit"; }
}
```

---

## 配置特点

✅ **不覆盖默认** - 所有默认快捷键仍然可用
✅ **易于记忆** - Alt 系列快捷键符合直觉
✅ **减少英文** - 简化 UI，减少英文提示
✅ **提高效率** - 常用操作无需进入模式
✅ **兼容性好** - 可随时恢复默认配置

---

## 记忆技巧

### Alt 系列（快速操作）

- `Alt + -`：减号像水平线 → 水平分割
- `Alt + \`：反斜杠像竖线 → 垂直分割
- `Alt + h/j/k/l`：Vim 风格导航
- `Alt + x`：X 是关闭符号 → 关闭面板
- `Alt + t`：T = Tab → 新建标签
- `Alt + f`：F = Fullscreen → 全屏
- `Alt + s`：S = Scroll → 滚动模式

### Ctrl 系列（进入模式）

- `Ctrl + p`：P = Pane → 面板模式
- `Ctrl + t`：T = Tab → 标签模式
- `Ctrl + s`：S = Scroll → 滚动模式
- `Ctrl + o`：O = Option/Session → 会话模式
- `Ctrl + q`：Q = Quit → 退出

---

## 相关文档

- **快速查看速查表**：
  ```bash
  cat ~/Documents/4/zellij-cheatsheet.md
  ```

- **完整配置指南**：
  ```bash
  cat ~/Documents/4/zellij-keybinds-guide.md
  ```

- **中文化方案**：
  ```bash
  cat ~/Documents/4/zellij-chinese-ui-guide.md
  ```

---

## 学习路线

### 第一天：熟悉新增全局快捷键

```
Alt + -/\       分割面板
Alt + h/j/k/l   导航
Alt + x         关闭
Alt + 1-5       跳转标签
```

### 第二天：结合默认模式快捷键

```
Ctrl + p        进入面板模式（更多操作）
Ctrl + t        进入标签模式（更多操作）
Ctrl + s        进入滚动模式
```

### 第三天：高级功能

```
Ctrl + o        会话管理
Ctrl + e        文件选择器
Alt + s → /     搜索历史输出
```

---

## 更新日志

**v1.0** (2025-11-05)
- 初始版本
- 添加 Alt 系列全局快捷键
- 启用简化 UI
- 添加滚动模式和搜索模式增强

---

**配置文件位置**：`~/.config/zellij/config.kdl`
**快速查看速查表**：`cat ~/Documents/4/zellij-cheatsheet.md`
**官方文档**：https://zellij.dev/documentation/
