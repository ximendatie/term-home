#!/usr/bin/env python3
"""运行 Codex CLI，并通过 streaming adapter 桥接到本地 term-home 事件总线。"""

from __future__ import annotations

import argparse
import json
import os
import tempfile
import uuid
from pathlib import Path
from typing import Any
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


def parse_args() -> argparse.Namespace:
    """解析桥接脚本参数以及需要转发给 `codex exec` 的附加参数。"""
    parser = argparse.ArgumentParser(
        description="Run `codex exec` and publish lifecycle events to the local term-home bus."
    )
    parser.add_argument("prompt", help="Prompt passed to `codex exec`.")
    parser.add_argument("--task-id", help="Optional fixed task id. Defaults to a generated id.")
    parser.add_argument("--title", default="Codex CLI", help="Task title shown in the native shell.")
    parser.add_argument("--bus-url", default=DEFAULT_BUS_URL, help="term-home bus base URL.")
    parser.add_argument("--cd", default=".", help="Working directory for `codex exec`.")
    parser.add_argument("--model", help="Optional model passed to `codex exec`.")
    parser.add_argument(
        "--skip-git-repo-check",
        action="store_true",
        help="Pass --skip-git-repo-check to `codex exec`.",
    )
    parser.add_argument(
        "--full-auto",
        action="store_true",
        help="Pass --full-auto to `codex exec`.",
    )
    parser.add_argument(
        "--dangerously-bypass-approvals-and-sandbox",
        action="store_true",
        help="Pass --dangerously-bypass-approvals-and-sandbox to `codex exec`.",
    )
    parser.add_argument(
        "codex_args",
        nargs=argparse.REMAINDER,
        help="Additional arguments forwarded to `codex exec`. Prefix with `--`.",
    )
    return parser.parse_args()


def build_codex_command(args: argparse.Namespace, output_file: str) -> list[str]:
    """为当前执行组装完整的 `codex exec` 命令。"""
    cmd = ["codex", "exec", "--json", "-o", output_file]
    if args.model:
        cmd.extend(["--model", args.model])
    if args.skip_git_repo_check:
        cmd.append("--skip-git-repo-check")
    if args.full_auto:
        cmd.append("--full-auto")
    if args.dangerously_bypass_approvals_and_sandbox:
        cmd.append("--dangerously-bypass-approvals-and-sandbox")

    cmd.extend(trim_remainder_args(args.codex_args))
    cmd.append(args.prompt)
    return cmd


def handle_json_event(context: BridgeContext, event: dict[str, Any]) -> None:
    """将一条 Codex JSONL 事件映射成 term-home 的任务语义。"""
    event_type = event.get("type")
    if event_type == "thread.started":
        publish_summary(context, f"Codex thread started: {event.get('thread_id', 'unknown')}")
        return

    if event_type == "turn.started":
        publish_progress(context, "Codex turn started")
        return

    if event_type == "item.started":
        item = event.get("item") or {}
        item_type = str(item.get("type", "item"))
        publish_progress(context, f"Codex started {item_type}")
        return

    if event_type == "item.completed":
        item = event.get("item") or {}
        item_type = str(item.get("type", "item"))

        if item_type == "agent_message":
            text = summarize_text(str(item.get("text", "Agent message received.")))
            publish_summary(context, text or "Agent message received.")
            return

        publish_progress(context, f"Codex completed {item_type}")
        return

    if event_type == "turn.completed":
        usage = event.get("usage") or {}
        output_tokens = usage.get("output_tokens")
        token_suffix = f" ({output_tokens} output tokens)" if output_tokens else ""
        publish_progress(context, f"Codex turn completed{token_suffix}")
        return

    if event_type == "error":
        message = summarize_text(str(event.get("message", "Codex emitted an error event.")))
        publish_summary(context, message)
        return

    publish_log(context, json.dumps(event, ensure_ascii=False))


def read_output_file(path: str) -> str:
    """读取通过 `-o` 持久化下来的最终 Codex 消息。"""
    try:
        data = Path(path).read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        return ""
    return summarize_text(data)


def handle_stream_line(context: BridgeContext, line: str) -> None:
    """解析一行 Codex 输出，并映射成标准事件。"""
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        publish_log(context, line)
        return

    if isinstance(event, dict):
        handle_json_event(context, event)


def build_outcome(output_file: str, exit_code: int, duration: int) -> CommandOutcome:
    """根据 Codex 的退出码和输出文件构造统一执行结果。"""
    final_message = read_output_file(output_file)
    if exit_code == 0:
        return CommandOutcome(
            returncode=0,
            duration_seconds=duration,
            final_message=final_message or f"Codex task completed in {duration}s",
        )
    return CommandOutcome(
        returncode=exit_code,
        duration_seconds=duration,
        final_message=final_message or f"Codex task failed with exit code {exit_code}",
    )


def main() -> int:
    """运行 Codex，转发生命周期事件，并发布最终任务结果。"""
    args = parse_args()
    task_id = args.task_id or f"codex-{uuid.uuid4().hex[:12]}"
    title = args.title
    workdir = os.path.abspath(args.cd)

    with tempfile.NamedTemporaryFile(prefix="term-home-codex-", suffix=".txt", delete=False) as tmp:
        output_file = tmp.name

    cmd = build_codex_command(args, output_file)
    context = BridgeContext(
        bus_url=args.bus_url,
        task_id=task_id,
        source="codex-cli",
        title=title,
        workdir=workdir,
    )
    return run_streaming_bridge(
        context=context,
        cmd=cmd,
        started_summary=f"Running `codex exec` in {workdir}",
        handle_line=handle_stream_line,
        build_outcome=lambda exit_code, duration: build_outcome(output_file, exit_code, duration),
    )


if __name__ == "__main__":
    raise SystemExit(main())
