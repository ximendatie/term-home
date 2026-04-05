#!/usr/bin/env python3
"""Run Codex CLI and bridge its lifecycle into the local term-home event bus."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path
from typing import Any
from urllib import error, request


DEFAULT_BUS_URL = "http://127.0.0.1:8765"


def parse_args() -> argparse.Namespace:
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


def post_event(bus_url: str, payload: dict[str, Any]) -> None:
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


def summarize_line(line: str) -> str:
    line = line.strip()
    if not line:
        return ""
    if len(line) <= 160:
        return line
    return f"{line[:157]}..."


def build_codex_command(args: argparse.Namespace, output_file: str) -> list[str]:
    cmd = ["codex", "exec", "--json", "-o", output_file]
    if args.model:
        cmd.extend(["--model", args.model])
    if args.skip_git_repo_check:
        cmd.append("--skip-git-repo-check")
    if args.full_auto:
        cmd.append("--full-auto")
    if args.dangerously_bypass_approvals_and_sandbox:
        cmd.append("--dangerously-bypass-approvals-and-sandbox")

    extra = list(args.codex_args)
    if extra and extra[0] == "--":
        extra = extra[1:]
    cmd.extend(extra)
    cmd.append(args.prompt)
    return cmd


def handle_json_event(bus_url: str, task_id: str, title: str, event: dict[str, Any]) -> None:
    event_type = event.get("type")
    if event_type == "thread.started":
        post_event(
            bus_url,
            {
                "type": "task.summary",
                "task_id": task_id,
                "source": "codex-cli",
                "title": title,
                "summary": f"Codex thread started: {event.get('thread_id', 'unknown')}",
            },
        )
        return

    if event_type == "turn.started":
        post_event(
            bus_url,
            {
                "type": "task.progress",
                "task_id": task_id,
                "source": "codex-cli",
                "title": title,
                "summary": "Codex turn started",
            },
        )
        return

    if event_type == "error":
        message = summarize_line(str(event.get("message", "Codex emitted an error event.")))
        post_event(
            bus_url,
            {
                "type": "task.summary",
                "task_id": task_id,
                "source": "codex-cli",
                "title": title,
                "summary": message,
            },
        )
        return

    compact = summarize_line(json.dumps(event, ensure_ascii=False))
    if compact:
        post_event(
            bus_url,
            {
                "type": "task.log",
                "task_id": task_id,
                "source": "codex-cli",
                "title": title,
                "line": compact,
            },
        )


def read_output_file(path: str) -> str:
    try:
        data = Path(path).read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        return ""
    return summarize_line(data)


def main() -> int:
    args = parse_args()
    task_id = args.task_id or f"codex-{uuid.uuid4().hex[:12]}"
    title = args.title
    workdir = os.path.abspath(args.cd)

    with tempfile.NamedTemporaryFile(prefix="term-home-codex-", suffix=".txt", delete=False) as tmp:
        output_file = tmp.name

    cmd = build_codex_command(args, output_file)

    post_event(
        args.bus_url,
        {
            "type": "task.started",
            "task_id": task_id,
            "source": "codex-cli",
            "title": title,
            "summary": f"Running `codex exec` in {workdir}",
        },
    )

    started_at = time.time()
    process = subprocess.Popen(
        cmd,
        cwd=workdir,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )

    assert process.stdout is not None
    for raw_line in process.stdout:
        line = raw_line.rstrip("\n")
        if not line:
            continue

        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            post_event(
                args.bus_url,
                {
                    "type": "task.log",
                    "task_id": task_id,
                    "source": "codex-cli",
                    "title": title,
                    "line": summarize_line(line),
                },
            )
            continue

        if isinstance(event, dict):
            handle_json_event(args.bus_url, task_id, title, event)

    exit_code = process.wait()
    duration = max(1, int(time.time() - started_at))
    final_message = read_output_file(output_file)

    if exit_code == 0:
        summary = final_message or f"Codex task completed in {duration}s"
        post_event(
            args.bus_url,
            {
                "type": "task.completed",
                "task_id": task_id,
                "source": "codex-cli",
                "title": title,
                "summary": summary,
            },
        )
        return 0

    summary = final_message or f"Codex task failed with exit code {exit_code}"
    post_event(
        args.bus_url,
        {
            "type": "task.failed",
            "task_id": task_id,
            "source": "codex-cli",
            "title": title,
            "summary": summary,
        },
    )
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
