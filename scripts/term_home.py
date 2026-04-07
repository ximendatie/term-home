#!/usr/bin/env python3
"""term-home 的统一命令行入口。"""

from __future__ import annotations

import sys

try:
    from scripts import run_command
except ModuleNotFoundError:
    import run_command


def print_usage() -> None:
    """输出当前统一入口支持的最小用法。"""
    print("Usage: term_home.py run [run options] -- <command>", file=sys.stderr)


def main(argv: list[str] | None = None) -> int:
    """只解析一级子命令，其余参数原样转发给具体 bridge。"""
    args = list(argv if argv is not None else sys.argv[1:])
    if not args:
        print_usage()
        return 2

    subcommand = args[0]
    forwarded = args[1:]

    if subcommand == "run":
        return run_command.main(forwarded)

    print(f"Unsupported subcommand: {subcommand}", file=sys.stderr)
    print_usage()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
