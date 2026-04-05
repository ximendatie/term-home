#!/usr/bin/env python3
"""term-home core MVP

A minimal local runtime that implements:
- unified CLI/Agent event bus (HTTP ingest)
- task state normalization
- SSE stream for UI updates
- simple notch-like top status web UI
"""

from __future__ import annotations

import json
import queue
import threading
import time
from dataclasses import dataclass, field, asdict
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import urlparse


VALID_EVENT_TYPES = {
    "task.started",
    "task.progress",
    "task.summary",
    "task.awaiting_approval",
    "task.completed",
    "task.failed",
    "task.cancelled",
    "task.log",
}

VALID_ACTIONS = {"stop", "retry", "approve", "reject"}


@dataclass
class TaskState:
    task_id: str
    source: str = "unknown"
    status: str = "running"
    title: str = "Untitled task"
    summary: str = ""
    progress: int | None = None
    updated_at: float = field(default_factory=lambda: time.time())
    logs: list[str] = field(default_factory=list)


class EventBus:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._tasks: dict[str, TaskState] = {}
        self._history: list[dict[str, Any]] = []
        self._subscribers: list[queue.Queue[str]] = []

    def snapshot(self) -> dict[str, Any]:
        with self._lock:
            tasks = [asdict(t) for t in sorted(self._tasks.values(), key=lambda x: x.updated_at, reverse=True)]
            return {"tasks": tasks, "history_size": len(self._history)}

    def publish(self, event: dict[str, Any]) -> None:
        event_type = event.get("type")
        task_id = event.get("task_id")
        if event_type not in VALID_EVENT_TYPES:
            raise ValueError(f"unsupported event type: {event_type}")
        if not isinstance(task_id, str) or not task_id:
            raise ValueError("event.task_id is required")

        with self._lock:
            task = self._tasks.get(task_id) or TaskState(task_id=task_id)
            task.source = event.get("source", task.source)
            task.title = event.get("title", task.title)
            task.updated_at = time.time()

            if event_type == "task.started":
                task.status = "running"
                task.summary = event.get("summary", task.summary)
            elif event_type == "task.progress":
                task.status = "running"
                prog = event.get("progress")
                task.progress = int(prog) if isinstance(prog, (int, float)) else task.progress
                task.summary = event.get("summary", task.summary)
            elif event_type == "task.summary":
                task.summary = event.get("summary", task.summary)
            elif event_type == "task.awaiting_approval":
                task.status = "awaiting_approval"
                task.summary = event.get("summary", task.summary)
            elif event_type == "task.completed":
                task.status = "completed"
                task.progress = 100
                task.summary = event.get("summary", task.summary)
            elif event_type == "task.failed":
                task.status = "failed"
                task.summary = event.get("summary", task.summary)
            elif event_type == "task.cancelled":
                task.status = "cancelled"
                task.summary = event.get("summary", task.summary)
            elif event_type == "task.log":
                line = event.get("line")
                if isinstance(line, str) and line:
                    task.logs = (task.logs + [line])[-50:]

            self._tasks[task_id] = task
            wrapped = {"ts": task.updated_at, "event": event, "task": asdict(task)}
            self._history.append(wrapped)
            self._history = self._history[-500:]
            payload = f"data: {json.dumps(wrapped, ensure_ascii=False)}\n\n"
            for sub in self._subscribers:
                sub.put(payload)

    def subscribe(self) -> queue.Queue[str]:
        q: queue.Queue[str] = queue.Queue()
        with self._lock:
            self._subscribers.append(q)
        return q

    def unsubscribe(self, q: queue.Queue[str]) -> None:
        with self._lock:
            self._subscribers = [x for x in self._subscribers if x is not q]

    def action(self, task_id: str, action: str) -> dict[str, Any]:
        if action not in VALID_ACTIONS:
            raise ValueError(f"unsupported action: {action}")

        event: dict[str, Any] = {
            "type": "task.summary",
            "task_id": task_id,
            "source": "term-home-ui",
            "summary": f"Action requested: {action}",
            "title": "User intervention",
        }

        if action == "stop":
            event = {**event, "type": "task.cancelled", "summary": "Stopped by user"}
        elif action == "retry":
            event = {**event, "type": "task.started", "summary": "Retry requested by user"}
        elif action == "approve":
            event = {**event, "type": "task.started", "summary": "Approved by user, resumed"}
        elif action == "reject":
            event = {**event, "type": "task.failed", "summary": "Rejected by user"}

        self.publish(event)
        return event


BUS = EventBus()


class Handler(BaseHTTPRequestHandler):
    server_version = "term-home/0.1"

    def _json(self, status: int, data: dict[str, Any]) -> None:
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        return json.loads(raw.decode("utf-8") or "{}")

    def do_GET(self) -> None:  # noqa: N802
        p = urlparse(self.path)
        if p.path == "/health":
            self._json(200, {"ok": True, "service": "term-home"})
            return
        if p.path == "/tasks":
            self._json(200, BUS.snapshot())
            return
        if p.path == "/stream":
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.end_headers()
            sub = BUS.subscribe()
            try:
                snap = json.dumps(BUS.snapshot(), ensure_ascii=False)
                self.wfile.write(f"event: snapshot\ndata: {snap}\n\n".encode("utf-8"))
                self.wfile.flush()
                while True:
                    try:
                        item = sub.get(timeout=15)
                        self.wfile.write(item.encode("utf-8"))
                    except queue.Empty:
                        self.wfile.write(b": keepalive\n\n")
                    self.wfile.flush()
            except (ConnectionResetError, BrokenPipeError):
                pass
            finally:
                BUS.unsubscribe(sub)
            return

        self._json(404, {"error": "not_found"})

    def do_POST(self) -> None:  # noqa: N802
        p = urlparse(self.path)
        try:
            body = self._read_json()
        except json.JSONDecodeError:
            self._json(400, {"error": "invalid_json"})
            return

        if p.path == "/events":
            try:
                BUS.publish(body)
            except ValueError as err:
                self._json(400, {"error": str(err)})
                return
            self._json(202, {"accepted": True})
            return

        if p.path.startswith("/tasks/") and p.path.endswith("/actions"):
            parts = p.path.strip("/").split("/")
            if len(parts) != 3:
                self._json(404, {"error": "bad_path"})
                return
            _, task_id, _ = parts
            action = body.get("action")
            try:
                emitted = BUS.action(task_id=task_id, action=action)
            except ValueError as err:
                self._json(400, {"error": str(err)})
                return
            self._json(200, {"ok": True, "emitted": emitted})
            return

        self._json(404, {"error": "not_found"})


def main() -> None:
    host, port = "127.0.0.1", 8765
    server = ThreadingHTTPServer((host, port), Handler)
    print(f"term-home core listening on http://{host}:{port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
