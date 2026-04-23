#!/usr/bin/env zsh
# shellcheck shell=bash
############################################
# 加载共享环境变量
############################################
# shellcheck disable=SC1091
[ -f "$HOME/.config/shell/env" ] && . "$HOME/.config/shell/env"

############################################
# Zinit 插件管理器
############################################
if [[ ! -f $HOME/.local/share/zinit/zinit.git/zinit.zsh ]]; then
    print -P "%F{33} %F{220}Installing %F{33}ZDHARMA-CONTINUUM%F{220} Initiative Plugin Manager (%F{33}zdharma-continuum/zinit%F{220})…%f"
    command mkdir -p "$HOME/.local/share/zinit" && command chmod g-rwX "$HOME/.local/share/zinit"
    if command git clone https://github.com/zdharma-continuum/zinit "$HOME/.local/share/zinit/zinit.git"; then
        print -P "%F{33} %F{34}Installation successful.%f%b"
    else
        print -P "%F{160} The clone has failed.%f%b"
    fi
fi
if [[ -f "$HOME/.local/share/zinit/zinit.git/zinit.zsh" ]]; then
    # shellcheck disable=SC1091
    source "$HOME/.local/share/zinit/zinit.git/zinit.zsh"
    autoload -Uz _zinit
    # shellcheck disable=SC2154
    (( ${+_comps} )) && _comps[zinit]=_zinit

    ############################################
    # Zinit 插件（syntax-highlighting 必须最后加载）
    ############################################
    zinit light zsh-users/zsh-autosuggestions
    zinit light zsh-users/zsh-completions
    zinit light zsh-users/zsh-history-substring-search
    zinit light zsh-users/zsh-syntax-highlighting
fi

############################################
# 历史记录设置
############################################
HISTFILE=~/.zsh_history
HISTSIZE=50000
# shellcheck disable=SC2034
SAVEHIST=50000
setopt append_history
setopt share_history
setopt hist_ignore_all_dups
setopt hist_ignore_space
setopt hist_reduce_blanks

############################################
# Starship 提示符
############################################
eval "$(starship init zsh)"

############################################
# Yazi 文件管理器
############################################
function y() {
    local tmp cwd
    tmp="$(mktemp -t "yazi-cwd.XXXXXX")" || return
    if yazi "$@" --cwd-file="$tmp"; then
        cwd="$(<"$tmp")"
        if [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
            if ! builtin cd -- "$cwd"; then
                rm -f -- "$tmp"
                return 1
            fi
        fi
    fi
    rm -f -- "$tmp"
}

############################################
# Zoxide
############################################
eval "$(zoxide init zsh)"

############################################
# FZF
############################################
if command -v fzf >/dev/null 2>&1; then
    if fzf_zsh_init="$(fzf --zsh 2>/dev/null)"; then
        # shellcheck disable=SC1090
        eval "$fzf_zsh_init"
        unset fzf_zsh_init
    else
        for fzf_script in \
            /usr/share/fzf/completion.zsh \
            /usr/share/doc/fzf/examples/completion.zsh \
            /usr/local/share/fzf/completion.zsh; do
            if [[ -f "$fzf_script" ]]; then
                # shellcheck disable=SC1090
                source "$fzf_script"
                break
            fi
        done

        for fzf_script in \
            /usr/share/fzf/key-bindings.zsh \
            /usr/share/doc/fzf/examples/key-bindings.zsh \
            /usr/local/share/fzf/key-bindings.zsh; do
            if [[ -f "$fzf_script" ]]; then
                # shellcheck disable=SC1090
                source "$fzf_script"
                break
            fi
        done
    fi
fi

############################################
# Claude Code 快捷命令
############################################
function ccv() {
    local env_vars=(
        "ENABLE_BACKGROUND_TASKS=true"
        "FORCE_AUTO_BACKGROUND_TASKS=true"
        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=true"
        "CLAUDE_CODE_ENABLE_UNIFIED_READ_TOOL=true"
    )

    local claude_args=("--dangerously-skip-permissions")

    if [[ "$1" == "r" ]]; then
        claude_args+=("--resume")
    fi

    env "${env_vars[@]}" claude "${claude_args[@]}"
}

############################################
# Eza (现代版 ls)
############################################
if command -v eza >/dev/null 2>&1; then
    alias ls='eza'
    alias ll='eza -l'
    alias la='eza -la'
    alias lt='eza --tree'
fi

############################################
# Zellij 终端多工器
############################################
if command -v zellij >/dev/null 2>&1; then
    alias zj='zellij'
    alias zja='zellij attach'
    alias zjl='zellij list-sessions'
fi

############################################
# GPG TTY 设置（Git 签名需要）
############################################
if [ -n "$TTY" ]; then
    GPG_TTY="$TTY"
    export GPG_TTY
fi

# 全局搜索
frg() {
  local depth=""
  case "$1" in
    l|1)   depth="--max-depth 1" ;;   # 输入 frg l 或 frg 1 表示仅当前目录
  esac

  fzf --ansi \
    --bind "change:reload:
      if [[ -n {q} ]]; then
        rg $depth --line-number --no-heading --color=always {q};
      else
        rg $depth --files;
      fi || true" \
    --preview "bat --style=numbers --color=always --highlight-line {2} {1}" \
    --delimiter ":"
}

# 合并txt
hbtxt() {
  local out="merged_unique.txt"
  local tmp

  tmp="$(mktemp "${out}.XXXXXX")" || return

  if find . -type f -name "*.txt" ! -name "$out" \
    -exec awk 'NF && !seen[$0]++' {} + \
    > "$tmp"; then
    mv -- "$tmp" "$out"
  else
    rm -f -- "$tmp"
    return 1
  fi
}
#
