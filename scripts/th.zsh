# 为 term-home 提供显式 `th` 前缀的 zsh 集成，避免自动包裹全部 shell 命令。
TERM_HOME_SCRIPTS_DIR="${${(%):-%N}:A:h}"

# 为当前 shell 生成稳定的会话标识，近似代表一个 terminal tab。
if [[ -z "${TERM_HOME_SESSION_OWNER_PID:-}" ]]; then
  export TERM_HOME_SESSION_ID="${TERM_HOME_SESSION_ID:-session-$$}"
  export TERM_HOME_SESSION_OWNER_PID="$$"
fi

# 保存终端回跳所需的最小上下文，供 bridge 自动上报。
export TERM_HOME_TERMINAL_APP="${TERM_HOME_TERMINAL_APP:-${TERM_PROGRAM:-}}"
if [[ -z "${TERM_HOME_TTY:-}" ]]; then
  export TERM_HOME_TTY="${TTY:-$(tty 2>/dev/null)}"
fi

# 用显式前缀将任意命令接入 term-home，保持普通 shell 命令行为不变。
th() {
  python3 "${TERM_HOME_SCRIPTS_DIR}/term_home.py" run "$@"
}

# 为需要直接占用 TTY 的 Codex 提供专用入口，避免被通用命令包装器截断终端语义。
th-codex() {
  if [[ $# -lt 1 ]]; then
    echo 'usage: th-codex "<prompt>" [extra codex exec args...]'
    return 2
  fi

  local prompt="$1"
  shift

  python3 "${TERM_HOME_SCRIPTS_DIR}/run_codex_exec.py" \
    --title "codex" \
    --cd "$PWD" \
    --session-id "${TERM_HOME_SESSION_ID:-}" \
    --terminal-app "${TERM_HOME_TERMINAL_APP:-}" \
    --tty "${TERM_HOME_TTY:-}" \
    "$prompt" \
    -- "$@"
}

# 在 shell 正常退出时清理该 session 下的任务，避免关闭 tab 后残留历史。
_term_home_close_session() {
  if [[ -z "${TERM_HOME_SESSION_ID:-}" || "${TERM_HOME_SESSION_OWNER_PID:-}" != "$$" ]]; then
    return 0
  fi

  python3 "${TERM_HOME_SCRIPTS_DIR}/term_home.py" close-session --session-id "${TERM_HOME_SESSION_ID}" >/dev/null 2>&1
}

autoload -Uz add-zsh-hook
add-zsh-hook zshexit _term_home_close_session
