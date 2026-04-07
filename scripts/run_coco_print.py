#!/usr/bin/env python3
"""运行 Coco CLI，并通过 print adapter 桥接到本地 term-home 事件总线。"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import uuid
from typing import Any
try:
    from scripts.cli_bridge_common import (
        DEFAULT_BUS_URL,
        BridgeContext,
        CommandOutcome,
        publish_log,
        publish_summary,
        run_print_bridge,
        summarize_text,
        trim_remainder_args,
    )
except ModuleNotFoundError:
    from cli_bridge_common import (
        DEFAULT_BUS_URL,
        BridgeContext,
        CommandOutcome,
        publish_log,
        publish_summary,
        run_print_bridge,
        summarize_text,
        trim_remainder_args,
    )


def parse_args() -> argparse.Namespace:
    """解析桥接脚本参数以及需要转发给 `coco -p --json` 的附加参数。"""
    parser = argparse.ArgumentParser(
        description="Run `coco -p --json` and publish lifecycle events to the local term-home bus."
    )
    parser.add_argument("prompt", help="Prompt passed to `coco -p --json`.")
    parser.add_argument("--task-id", help="Optional fixed task id. Defaults to a generated id.")
    parser.add_argument("--title", default="Coco CLI", help="Task title shown in the native shell.")
    parser.add_argument("--bus-url", default=DEFAULT_BUS_URL, help="term-home bus base URL.")
    parser.add_argument("--cd", default=".", help="Working directory for `coco`.")
    parser.add_argument("--query-timeout", help="Optional query timeout forwarded to `coco`.")
    parser.add_argument(
        "--yolo",
        action="store_true",
        help="Pass --yolo to `coco`.",
    )
    parser.add_argument(
        "coco_args",
        nargs=argparse.REMAINDER,
        help="Additional arguments forwarded to `coco`. Prefix with `--`.",
    )
    return parser.parse_args()


def build_coco_command(args: argparse.Namespace) -> list[str]:
    """为当前执行组装完整的 `coco -p --json` 命令。"""
    cmd = ["coco", "-p", "--json"]
    if args.query_timeout:
        cmd.extend(["--query-timeout", args.query_timeout])
    if args.yolo:
        cmd.append("--yolo")

    cmd.extend(trim_remainder_args(args.coco_args))
    cmd.append(args.prompt)
    return cmd


def extract_message_content(payload: dict[str, Any]) -> str:
    """从 Coco 的 JSON 输出中提取最终回复文本。"""
    message = payload.get("message")
    if isinstance(message, dict):
        content = message.get("content")
        if isinstance(content, str):
            return summarize_text(content)
        if isinstance(content, list):
            parts = [str(part) for part in content if isinstance(part, (str, int, float))]
            return summarize_text(" ".join(parts))
    return ""


def extract_error_summary(stdout: str, stderr: str) -> str:
    """从 Coco 的标准输出或错误输出中提取失败摘要。"""
    combined = "\n".join(part for part in [stdout.strip(), stderr.strip()] if part.strip())
    if not combined:
        return ""

    try:
        payload = json.loads(stdout)
    except json.JSONDecodeError:
        return summarize_text(combined)

    message = payload.get("message")
    if isinstance(message, dict):
        content = message.get("content")
        if isinstance(content, str) and content.strip():
            return summarize_text(content)
    return summarize_text(combined)


def build_outcome(
    context: BridgeContext,
    result: subprocess.CompletedProcess[str],
    duration: int,
) -> CommandOutcome:
    """根据 Coco 的标准输出构造统一执行结果，并补发必要摘要事件。"""
    stdout = result.stdout.strip()
    stderr = result.stderr.strip()

    if stdout:
        try:
            payload = json.loads(stdout)
        except json.JSONDecodeError:
            publish_log(context, stdout)
            payload: dict[str, Any] = {}
        else:
            session_id = payload.get("session_id")
            if isinstance(session_id, str) and session_id:
                publish_summary(context, f"Coco session: {session_id}")
    else:
        payload = {}

    final_message = extract_message_content(payload)

    if result.returncode == 0:
        return CommandOutcome(
            returncode=0,
            duration_seconds=duration,
            stdout=stdout,
            stderr=stderr,
            final_message=final_message or f"Coco task completed in {duration}s",
        )

    return CommandOutcome(
        returncode=result.returncode,
        duration_seconds=duration,
        stdout=stdout,
        stderr=stderr,
        final_message=extract_error_summary(stdout, stderr) or f"Coco task failed with exit code {result.returncode}",
    )


def main() -> int:
    """运行 Coco，转发生命周期事件，并发布最终任务结果。"""
    args = parse_args()
    task_id = args.task_id or f"coco-{uuid.uuid4().hex[:12]}"
    title = args.title
    workdir = os.path.abspath(args.cd)
    cmd = build_coco_command(args)
    context = BridgeContext(
        bus_url=args.bus_url,
        task_id=task_id,
        source="coco-cli",
        title=title,
        workdir=workdir,
    )
    return run_print_bridge(
        context=context,
        cmd=cmd,
        started_summary=f"Running `coco -p --json` in {workdir}",
        build_outcome=build_outcome,
    )


if __name__ == "__main__":
    raise SystemExit(main())
