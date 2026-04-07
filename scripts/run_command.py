#!/usr/bin/env python3
"""运行任意本地命令，并将其最小生命周期桥接到本地 term-home 事件总线。"""

from __future__ import annotations

import argparse
import os
import re
import uuid
from dataclasses import dataclass

try:
    from scripts.cli_bridge_common import (
        DEFAULT_BUS_URL,
        BridgeContext,
        CommandOutcome,
        publish_log,
        publish_progress,
        publish_summary,
        run_streaming_bridge,
        summarize_text,
        trim_remainder_args,
    )
except ModuleNotFoundError:
    from cli_bridge_common import (
        DEFAULT_BUS_URL,
        BridgeContext,
        CommandOutcome,
        publish_log,
        publish_progress,
        publish_summary,
        run_streaming_bridge,
        summarize_text,
        trim_remainder_args,
    )


@dataclass
class CommandRuntimeState:
    """记录通用命令桥接过程中需要跨输出行共享的运行时状态。"""

    ready_reported: bool = False
    first_output_reported: bool = False
    last_meaningful_line: str = ""


def derive_title(command: list[str]) -> str:
    """根据原始命令推导一个更自然的默认标题。"""
    return summarize_text(" ".join(command), limit=48) or "Shell Command"


def build_parser() -> argparse.ArgumentParser:
    """构建通用命令桥接的参数解析器。"""
    parser = argparse.ArgumentParser(
        description="Run an arbitrary command and publish lifecycle events to the local term-home bus."
    )
    parser.add_argument("--task-id", help="Optional fixed task id. Defaults to a generated id.")
    parser.add_argument(
        "--session-id",
        default=os.environ.get("TERM_HOME_SESSION_ID", ""),
        help="Optional shell session id used to group tasks by tab-like session.",
    )
    parser.add_argument("--title", help="Task title shown in the native shell.")
    parser.add_argument("--source", default="shell-command", help="Task source shown in the native shell.")
    parser.add_argument("--bus-url", default=DEFAULT_BUS_URL, help="term-home bus base URL.")
    parser.add_argument("--cd", default=".", help="Working directory for the command.")
    parser.add_argument(
        "--ready-pattern",
        action="append",
        default=[],
        help="Regex pattern that marks the command as ready, can be specified multiple times.",
    )
    parser.add_argument(
        "command",
        nargs=argparse.REMAINDER,
        help="Command to execute. Prefix with `--`.",
    )
    return parser


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    """解析通用命令桥接参数以及需要执行的目标命令。"""
    return build_parser().parse_args(argv)


def compile_ready_patterns(raw_patterns: list[str]) -> list[re.Pattern[str]]:
    """编译 ready pattern 列表，忽略空白输入。"""
    return [re.compile(pattern) for pattern in raw_patterns if pattern.strip()]


def handle_stream_line(
    context: BridgeContext,
    state: CommandRuntimeState,
    ready_patterns: list[re.Pattern[str]],
    line: str,
) -> None:
    """根据通用命令输出更新最小运行态，并转发结构化日志。"""
    compact = summarize_text(line)
    if not compact:
        return

    state.last_meaningful_line = compact
    publish_log(context, compact)

    if not state.first_output_reported:
        publish_progress(context, f"Command produced output: {compact}")
        state.first_output_reported = True

    if not state.ready_reported and any(pattern.search(line) for pattern in ready_patterns):
        publish_summary(context, f"Command ready: {compact}")
        state.ready_reported = True


def build_outcome(state: CommandRuntimeState, exit_code: int, duration: int) -> CommandOutcome:
    """根据退出码和最后有效输出生成通用命令结果。"""
    if exit_code == 0:
        return CommandOutcome(
            returncode=0,
            duration_seconds=duration,
            final_message=state.last_meaningful_line or f"Command completed in {duration}s",
        )
    return CommandOutcome(
        returncode=exit_code,
        duration_seconds=duration,
        final_message=state.last_meaningful_line or f"Command failed with exit code {exit_code}",
    )


def main(argv: list[str] | None = None) -> int:
    """运行目标命令，并把最小生命周期事件发布到本地总线。"""
    args = parse_args(argv)
    command = trim_remainder_args(args.command)
    if not command:
        raise SystemExit("run_command.py requires a command after `--`")

    context = BridgeContext(
        bus_url=args.bus_url,
        task_id=args.task_id or f"cmd-{uuid.uuid4().hex[:12]}",
        source=args.source,
        title=args.title or derive_title(command),
        workdir=os.path.abspath(args.cd),
        session_id=args.session_id,
    )
    ready_patterns = compile_ready_patterns(args.ready_pattern)
    state = CommandRuntimeState()

    return run_streaming_bridge(
        context=context,
        cmd=command,
        started_summary=f"Running `{command[0]}` in {args.cd}",
        handle_line=lambda ctx, line: handle_stream_line(ctx, state, ready_patterns, line),
        build_outcome=lambda exit_code, duration: build_outcome(state, exit_code, duration),
    )


if __name__ == "__main__":
    raise SystemExit(main())
