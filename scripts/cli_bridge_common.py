#!/usr/bin/env python3
"""term-home CLI bridge 的通用抽象。

这个模块负责沉淀不同 CLI 适配器共享的最小能力：
- 向本地事件总线发布统一任务事件
- 提供 started / progress / summary / log / completed / failed 的公共封装
- 提供“流式输出型 CLI”和“一次性输出型 CLI”的通用执行器

这样新增 CLI 时，只需要补各自的命令组装和输出映射逻辑。
"""

from __future__ import annotations

import json
import subprocess
import sys
import time
from dataclasses import dataclass
from typing import Any, Callable
from urllib import error, request


DEFAULT_BUS_URL = "http://127.0.0.1:8765"


@dataclass(frozen=True)
class BridgeContext:
    """描述单次 CLI 任务桥接所需的稳定上下文。"""

    bus_url: str
    task_id: str
    source: str
    title: str
    workdir: str


@dataclass(frozen=True)
class CommandOutcome:
    """封装一次 CLI 执行后的结果，用于统一生成完成态和失败态。"""

    returncode: int
    duration_seconds: int
    stdout: str = ""
    stderr: str = ""
    final_message: str = ""


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


def summarize_text(text: str, limit: int = 200) -> str:
    """将原始输出压缩成适合界面展示的一行摘要。"""
    compact = " ".join(text.strip().split())
    if not compact:
        return ""
    if len(compact) <= limit:
        return compact
    return f"{compact[: max(0, limit - 3)]}..."


def publish_started(context: BridgeContext, summary: str) -> None:
    """发布任务开始事件。"""
    post_event(
        context.bus_url,
        {
            "type": "task.started",
            "task_id": context.task_id,
            "source": context.source,
            "title": context.title,
            "summary": summary,
        },
    )


def publish_progress(context: BridgeContext, summary: str, progress: int | None = None) -> None:
    """发布任务进行中事件。"""
    payload: dict[str, Any] = {
        "type": "task.progress",
        "task_id": context.task_id,
        "source": context.source,
        "title": context.title,
        "summary": summary,
    }
    if progress is not None:
        payload["progress"] = progress
    post_event(context.bus_url, payload)


def publish_summary(context: BridgeContext, summary: str) -> None:
    """发布任务摘要事件。"""
    post_event(
        context.bus_url,
        {
            "type": "task.summary",
            "task_id": context.task_id,
            "source": context.source,
            "title": context.title,
            "summary": summary,
        },
    )


def publish_log(context: BridgeContext, line: str) -> None:
    """发布一条结构化日志事件。"""
    compact = summarize_text(line)
    if not compact:
        return
    post_event(
        context.bus_url,
        {
            "type": "task.log",
            "task_id": context.task_id,
            "source": context.source,
            "title": context.title,
            "line": compact,
        },
    )


def publish_completed(context: BridgeContext, summary: str) -> None:
    """发布任务完成事件。"""
    post_event(
        context.bus_url,
        {
            "type": "task.completed",
            "task_id": context.task_id,
            "source": context.source,
            "title": context.title,
            "summary": summary,
        },
    )


def publish_failed(context: BridgeContext, summary: str) -> None:
    """发布任务失败事件。"""
    post_event(
        context.bus_url,
        {
            "type": "task.failed",
            "task_id": context.task_id,
            "source": context.source,
            "title": context.title,
            "summary": summary,
        },
    )


def publish_cancelled(context: BridgeContext, summary: str) -> None:
    """发布任务取消事件。"""
    post_event(
        context.bus_url,
        {
            "type": "task.cancelled",
            "task_id": context.task_id,
            "source": context.source,
            "title": context.title,
            "summary": summary,
        },
    )


def echo_stream_line(line: str) -> None:
    """将子进程输出原样回显到当前终端，保持前台命令的可观察性。"""
    print(line, flush=True)


def trim_remainder_args(values: list[str]) -> list[str]:
    """清理 `argparse.REMAINDER` 前缀中的哨兵 `--`。"""
    if values and values[0] == "--":
        return values[1:]
    return list(values)


def run_streaming_bridge(
    context: BridgeContext,
    cmd: list[str],
    started_summary: str,
    handle_line: Callable[[BridgeContext, str], None],
    build_outcome: Callable[[int, int], CommandOutcome],
) -> int:
    """运行一个流式输出型 CLI，并把每一行交给适配器处理。"""
    publish_started(context, started_summary)
    started_at = time.time()
    process = subprocess.Popen(
        cmd,
        cwd=context.workdir,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )

    assert process.stdout is not None
    try:
        for raw_line in process.stdout:
            line = raw_line.rstrip("\n")
            if not line:
                continue
            echo_stream_line(line)
            handle_line(context, line)
        exit_code = process.wait()
    except KeyboardInterrupt:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)
        duration = max(1, int(time.time() - started_at))
        publish_cancelled(context, f"{context.source} task interrupted by user after {duration}s")
        return 130

    duration = max(1, int(time.time() - started_at))
    outcome = build_outcome(exit_code, duration)
    if outcome.returncode == 0:
        publish_completed(
            context,
            outcome.final_message or f"{context.source} task completed in {outcome.duration_seconds}s",
        )
        return 0

    publish_failed(
        context,
        outcome.final_message or f"{context.source} task failed with exit code {outcome.returncode}",
    )
    return outcome.returncode


def run_print_bridge(
    context: BridgeContext,
    cmd: list[str],
    started_summary: str,
    build_outcome: Callable[[BridgeContext, subprocess.CompletedProcess[str], int], CommandOutcome],
) -> int:
    """运行一个一次性输出型 CLI，并在结束后由适配器解释结果。"""
    publish_started(context, started_summary)
    started_at = time.time()
    result = subprocess.run(
        cmd,
        cwd=context.workdir,
        capture_output=True,
        text=True,
    )
    duration = max(1, int(time.time() - started_at))
    outcome = build_outcome(context, result, duration)
    if outcome.returncode == 0:
        publish_completed(
            context,
            outcome.final_message or f"{context.source} task completed in {outcome.duration_seconds}s",
        )
        return 0

    publish_failed(
        context,
        outcome.final_message or f"{context.source} task failed with exit code {outcome.returncode}",
    )
    return outcome.returncode
