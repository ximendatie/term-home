# 为 term-home 提供显式 `th` 前缀的 zsh 集成，避免自动包裹全部 shell 命令。
TERM_HOME_SCRIPTS_DIR="${${(%):-%N}:A:h}"

# 用显式前缀将任意命令接入 term-home，保持普通 shell 命令行为不变。
th() {
  python3 "${TERM_HOME_SCRIPTS_DIR}/term_home.py" run "$@"
}
