#!/usr/bin/env python3
"""运行 Coco CLI，并将其一次性 JSON 输出桥接到本地 term-home 事件总线。"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
import uuid
from typing import Any
from urllib import error, request


DEFAULT_BUS_URL = "http://127.0.0.1:8765"


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


def post_event(bus_url: str, payload: dict[str, Any]) -> None:
    """向本地 term-home 总线发送一条归一化任务事件。"""
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    req = request.Request(
        f"{bus_url.rstrip('/')}/events",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with request.urlopen(req, timeout=2):
            return
    except error.URLError as exc:
        print(f"[term-home] failed to post event: {exc}", file=sys.stderr)


def summarize_text(text: str) -> str:
    """将原始输出裁剪成适合界面展示的摘要长度。"""
    compact = " ".join(text.strip().split())
    if not compact:
        return ""
    if len(compact) <= 200:
        return compact
    return f"{compact[:197]}..."


def build_coco_command(args: argparse.Namespace) -> list[str]:
    """为当前执行组装完整的 `coco -p --json` 命令。"""
    cmd = ["coco", "-p", "--json"]
    if args.query_timeout:
        cmd.extend(["--query-timeout", args.query_timeout])
    if args.yolo:
        cmd.append("--yolo")

    extra = list(args.coco_args)
    if extra and extra[0] == "--":
        extra = extra[1:]
    cmd.extend(extra)
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


def main() -> int:
    """运行 Coco，转发生命周期事件，并发布最终任务结果。"""
    args = parse_args()
    task_id = args.task_id or f"coco-{uuid.uuid4().hex[:12]}"
    title = args.title
    workdir = os.path.abspath(args.cd)
    cmd = build_coco_command(args)

    post_event(
        args.bus_url,
        {
            "type": "task.started",
            "task_id": task_id,
            "source": "coco-cli",
            "title": title,
            "summary": f"Running `coco -p --json` in {workdir}",
        },
    )

    started_at = time.time()
    result = subprocess.run(
        cmd,
        cwd=workdir,
        capture_output=True,
        text=True,
    )
    duration = max(1, int(time.time() - started_at))
    stdout = result.stdout.strip()
    stderr = result.stderr.strip()

    if stdout:
        try:
            payload = json.loads(stdout)
        except json.JSONDecodeError:
            post_event(
                args.bus_url,
                {
                    "type": "task.log",
                    "task_id": task_id,
                    "source": "coco-cli",
                    "title": title,
                    "line": summarize_text(stdout),
                },
            )
            payload = {}
        else:
            session_id = payload.get("session_id")
            if isinstance(session_id, str) and session_id:
                post_event(
                    args.bus_url,
                    {
                        "type": "task.summary",
                        "task_id": task_id,
                        "source": "coco-cli",
                        "title": title,
                        "summary": f"Coco session: {session_id}",
                    },
                )
    else:
        payload = {}

    final_message = extract_message_content(payload)

    if result.returncode == 0:
        summary = final_message or f"Coco task completed in {duration}s"
        post_event(
            args.bus_url,
            {
                "type": "task.completed",
                "task_id": task_id,
                "source": "coco-cli",
                "title": title,
                "summary": summary,
            },
        )
        return 0

    summary = extract_error_summary(stdout, stderr) or f"Coco task failed with exit code {result.returncode}"
    post_event(
        args.bus_url,
        {
            "type": "task.failed",
            "task_id": task_id,
            "source": "coco-cli",
            "title": title,
            "summary": summary,
        },
    )
    return result.returncode


if __name__ == "__main__":
    raise SystemExit(main())
