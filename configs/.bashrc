#!/usr/bin/env bash
# shellcheck shell=bash
############################################
# 非交互式 shell 检查
############################################
[[ $- != *i* ]] && return

############################################
# 加载共享环境变量
############################################
# shellcheck disable=SC1091
[ -f "$HOME/.config/shell/env" ] && . "$HOME/.config/shell/env"

############################################
# 加载 ~/.bashrc.d/
############################################
if [ -d ~/.bashrc.d ]; then
    for rc in ~/.bashrc.d/*; do
        # shellcheck disable=SC1090
        [ -f "$rc" ] && . "$rc"
    done
fi
unset rc
