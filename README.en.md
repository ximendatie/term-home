<p align="center">
  <a href="./README.md">中文</a> |
  <a href="./README.en.md">English</a>
</p>

# term-home

A macOS top-layer runtime for CLI tools and AI agents.

## Current status (Core MVP shipped)

This repo now includes a first working V0 focused on the core loop:

- Unified event protocol + event ingestion API
- Task state model and normalization
- Top-layer UI (web notch-style simulation)
- Human actions (stop/retry/approve/reject)
- Real-time updates via SSE

> Note: this is a fast-landing version to validate the runtime interaction model first. Native macOS UI comes later.

## Inspiration repos

- [claude-island](https://github.com/farouqaldori/claude-island)
- [boring.notch](https://github.com/TheBoredTeam/boring.notch)

## Quick start

### 1) Run

```bash
python3 app.py
```

Then open <http://127.0.0.1:8765>

### 2) Send a demo event

```bash
curl -X POST http://127.0.0.1:8765/events \
  -H 'content-type: application/json' \
  -d '{
    "type": "task.started",
    "task_id": "demo-1",
    "source": "codex-cli",
    "title": "Generate migration",
    "summary": "Scanning DB diff"
  }'
```

Progress update:

```bash
curl -X POST http://127.0.0.1:8765/events \
  -H 'content-type: application/json' \
  -d '{
    "type": "task.progress",
    "task_id": "demo-1",
    "summary": "60% done",
    "progress": 60
  }'
```

Snapshot:

```bash
curl http://127.0.0.1:8765/tasks
```

## OpenSpec (Spec-Coding)

OpenSpec is initialized under:

- `openspec/README.md`
- `openspec/specs/core-mvp/spec.md`
- `openspec/specs/core-mvp/plan.md`
- `openspec/specs/core-mvp/tasks.md`

These files define goals, constraints, implementation plan, and acceptance criteria.
