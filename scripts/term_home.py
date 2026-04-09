#!/usr/bin/env python3
"""term-home 的统一命令行入口。"""

from __future__ import annotations

import argparse
import json
import sys
from urllib import request

try:
    from scripts import run_command
except ModuleNotFoundError:
    import run_command


DEFAULT_BUS_URL = "http://127.0.0.1:8765"


def print_usage() -> None:
    """输出当前统一入口支持的最小用法。"""
    print("Usage: term_home.py run [run options] -- <command>", file=sys.stderr)
    print("       term_home.py close-session --session-id <id>", file=sys.stderr)
    print("       term_home.py emit --type <event> --task-id <id> [payload fields]", file=sys.stderr)


def build_close_session_parser() -> argparse.ArgumentParser:
    """构建 shell session 清理入口的参数解析器。"""
    parser = argparse.ArgumentParser(description="Clean up tasks bound to a shell session.")
    parser.add_argument("--session-id", required=True, help="Stable shell session id to clean up.")
    parser.add_argument("--bus-url", default=DEFAULT_BUS_URL, help="term-home bus base URL.")
    return parser


def close_session(argv: list[str]) -> int:
    """按 session id 清理该 shell / tab 对应的任务历史。"""
    args = build_close_session_parser().parse_args(argv)
    body = json.dumps({"session_ids": [args.session_id]}, ensure_ascii=False).encode("utf-8")
    req = request.Request(
        f"{args.bus_url.rstrip('/')}/admin/cleanup",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with request.urlopen(req, timeout=2):
        return 0


def build_emit_parser() -> argparse.ArgumentParser:
    """构建最小事件发送入口的参数解析器。"""
    parser = argparse.ArgumentParser(description="Emit a single term-home event to the local bus.")
    parser.add_argument("--type", required=True, help="Event type such as task.started or task.completed.")
    parser.add_argument("--task-id", required=True, help="Stable task id.")
    parser.add_argument("--source", default="shell-hook", help="Event source.")
    parser.add_argument("--title", default="", help="Task title.")
    parser.add_argument("--summary", default="", help="Task summary.")
    parser.add_argument("--line", default="", help="Log line for task.log.")
    parser.add_argument("--progress", type=int, help="Optional progress value.")
    parser.add_argument("--session-id", default="", help="Shell session id.")
    parser.add_argument("--terminal-app", default="", help="Terminal application name.")
    parser.add_argument("--tty", default="", help="TTY for jump-back support.")
    parser.add_argument("--cwd", default="", help="Working directory.")
    parser.add_argument("--bus-url", default=DEFAULT_BUS_URL, help="term-home bus base URL.")
    return parser


def emit_event(argv: list[str]) -> int:
    """向本地总线发送一条最小结构化事件。"""
    args = build_emit_parser().parse_args(argv)
    payload: dict[str, object] = {
        "type": args.type,
        "task_id": args.task_id,
        "source": args.source,
    }
    if args.title:
        payload["title"] = args.title
    if args.summary:
        payload["summary"] = args.summary
    if args.line:
        payload["line"] = args.line
    if args.progress is not None:
        payload["progress"] = args.progress
    if args.session_id:
        payload["session_id"] = args.session_id
    if args.terminal_app:
        payload["terminal_app"] = args.terminal_app
    if args.tty:
        payload["tty"] = args.tty
    if args.cwd:
        payload["cwd"] = args.cwd

    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = request.Request(
        f"{args.bus_url.rstrip('/')}/events",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with request.urlopen(req, timeout=2):
        return 0


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
    if subcommand == "close-session":
        return close_session(forwarded)
    if subcommand == "emit":
        return emit_event(forwarded)

    print(f"Unsupported subcommand: {subcommand}", file=sys.stderr)
    print_usage()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
