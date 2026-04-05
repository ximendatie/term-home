#!/usr/bin/env python3
"""term-home 原生 MVP 的本地事件总线。

这个模块刻意保持很小的运行时边界：
- 通过 HTTP 接收结构化任务事件
- 将事件归一化为任务状态快照
- 通过 JSON 和 SSE 对外暴露任务状态
- 接收少量用户动作并回写成任务状态变化
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
    """单个任务的归一化运行时视图。"""

    task_id: str
    source: str = "unknown"
    status: str = "running"
    title: str = "Untitled task"
    summary: str = ""
    progress: int | None = None
    updated_at: float = field(default_factory=lambda: time.time())
    logs: list[str] = field(default_factory=list)


class EventBus:
    """带 SSE 分发能力的线程安全内存任务存储。"""

    def __init__(self) -> None:
        """初始化任务存储、历史缓冲区和订阅者列表。"""
        self._lock = threading.Lock()
        self._tasks: dict[str, TaskState] = {}
        self._history: list[dict[str, Any]] = []
        self._subscribers: list[queue.Queue[str]] = []

    def snapshot(self) -> dict[str, Any]:
        """返回按最近更新时间排序的稳定任务快照。"""
        with self._lock:
            tasks = [asdict(t) for t in sorted(self._tasks.values(), key=lambda x: x.updated_at, reverse=True)]
            return {"tasks": tasks, "history_size": len(self._history)}

    def publish(self, event: dict[str, Any]) -> None:
        """校验输入事件、折叠进任务状态并广播给订阅者。"""
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
        """为一个已连接客户端创建 SSE 订阅队列。"""
        q: queue.Queue[str] = queue.Queue()
        with self._lock:
            self._subscribers.append(q)
        return q

    def unsubscribe(self, q: queue.Queue[str]) -> None:
        """在客户端断开后移除对应的 SSE 订阅队列。"""
        with self._lock:
            self._subscribers = [x for x in self._subscribers if x is not q]

    def action(self, task_id: str, action: str) -> dict[str, Any]:
        """将用户动作转换成一条合成任务事件。"""
        if action not in VALID_ACTIONS:
            raise ValueError(f"unsupported action: {action}")

        with self._lock:
            existing = self._tasks.get(task_id)

        event: dict[str, Any] = {
            "type": "task.summary",
            "task_id": task_id,
            "source": existing.source if existing else "term-home-ui",
            "summary": f"Action requested: {action}",
            "title": existing.title if existing else "User intervention",
        }

        if action == "stop":
            event = {**event, "type": "task.cancelled", "summary": "Stopped by user"}
        elif action == "retry":
            event = {**event, "summary": "Retry requested by user"}
        elif action == "approve":
            event = {**event, "summary": "Approved by user, waiting for backend resume"}
        elif action == "reject":
            event = {**event, "type": "task.failed", "summary": "Rejected by user"}

        self.publish(event)
        return event


BUS = EventBus()


class Handler(BaseHTTPRequestHandler):
    """提供健康检查、任务读取、事件写入和 SSE 的 HTTP 接口。"""

    server_version = "term-home/0.1"

    def _json(self, status: int, data: dict[str, Any]) -> None:
        """按给定状态码写出 JSON 响应。"""
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self) -> dict[str, Any]:
        """将请求体解析为 JSON，并在空请求体时返回空对象。"""
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        return json.loads(raw.decode("utf-8") or "{}")

    def do_GET(self) -> None:  # noqa: N802
        """处理健康检查、任务快照和 SSE 读取请求。"""
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
        """接收任务事件以及来自界面的任务动作。"""
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
    """在默认回环地址上启动本地 HTTP 事件总线。"""
    host, port = "127.0.0.1", 8765
    server = ThreadingHTTPServer((host, port), Handler)
    print(f"term-home core listening on http://{host}:{port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
