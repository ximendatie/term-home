# PROJECT_NAME

A macOS live status layer for CLI and AI agents.

`PROJECT_NAME` is a macOS top-layer status center for CLI tools and autonomous agents.  
It turns long-running terminal workflows into something visible, controllable, and interruptible — with a notch-style UI, real-time task state, and a unified event protocol for multiple CLIs.

## Why

Modern CLI tools are getting more powerful:

- coding agents
- build and deploy tools
- scraping and automation scripts
- AI-assisted terminal workflows
- long-running local or remote jobs

But the UX is still primitive:

- status is buried in terminal output
- users need to keep watching the shell
- errors are easy to miss
- approvals and follow-up actions are hard to surface
- every CLI invents its own way to emit state

`PROJECT_NAME` is built to solve that.

It provides:

- a **macOS top-layer UI** for task status and quick actions
- a **unified event bus** for multiple CLIs and agents
- a **lightweight protocol** that can sit between raw terminal output and structured agent workflows

The goal is not to replace the terminal.  
The goal is to make CLI workflows **observable, operable, and human-friendly**.

---

## What it is

`PROJECT_NAME` has two core parts:

### 1. macOS Status Layer
A notch-style / top-center live UI for:

- running task status
- completion / failure notifications
- approval-required prompts
- quick actions like stop / retry / open logs / open terminal
- multi-task overview

### 2. Unified CLI Event Bus
A common event model for:

- AI coding agents
- shell commands
- build/test/deploy tools
- browser automation runners
- custom internal CLIs

Instead of parsing raw terminal text everywhere, `PROJECT_NAME` introduces a standard event contract so different tools can publish structured state consistently.

---

## Core ideas

### Visible
You should not need to stare at a terminal to know what your agent is doing.

### Actionable
A status surface is only useful if you can act on it:
- approve
- reject
- stop
- retry
- inspect
- jump back to context

### Tool-agnostic
This should work across multiple CLIs, not just one vendor or one agent framework.

### Human-in-the-loop
Autonomous tools are useful, but users still need a clear control point for sensitive or important actions.

### Event-first
The reliable abstraction is not “terminal text”, but “structured events”.

---

## Use cases

### AI coding agents
- Claude Code
- Codex CLI
- Aider
- OpenCode
- OpenClaw
- custom internal agents

### Developer workflows
- build / test / lint
- long-running scripts
- deploy jobs
- migration tools
- local automation pipelines

### Browser / ops automation
- Playwright runners
- browser agents
- form-filling automation
- repetitive operational tasks

---

## Problem statement

Today’s CLI workflows have a gap between execution power and runtime UX.

### The current state
- output streams are noisy
- task state is implicit, not explicit
- progress is hard to summarize
- notifications are fragmented
- approvals are often trapped inside terminal sessions
- multiple concurrent jobs are difficult to manage

### What we want
A unified runtime layer where any CLI can say:

- I started
- I’m running
- I need approval
- I completed
- I failed
- here is the next best action

And where macOS can surface that cleanly in one place.

---

## Architecture

```text
+--------------------+       +----------------------+       +----------------------+
|   CLI / Agent      | ----> |  PROJECT_NAME Bus    | ----> |  macOS Status Layer  |
|                    |       |                      |       |                      |
| - Claude Code      |       | - Event intake       |       | - notch/live island  |
| - Codex CLI        |       | - Normalization      |       | - quick actions      |
| - Aider            |       | - Routing            |       | - notifications      |
| - Shell scripts    |       | - Task state model   |       | - task details       |
| - Playwright jobs  |       | - History / storage  |       | - jump to terminal   |
+--------------------+       +----------------------+       +----------------------+
```

---

## MVP roadmap

The repository already contains a runnable Core prototype for validating the event model and the basic interaction loop:

- `app.py`: unified event bus service (`POST /events`, `GET /tasks`, `GET /stream`, `POST /tasks/{id}/actions`).
- `web/`: notch-style top-layer web prototype with human action buttons.
- `openspec/`: spec, plan, and task breakdown.

This build is useful for fast validation, but it is not the final definition of the MVP.  
For `term-home`, the real MVP should be a small but genuinely usable native macOS top-layer app.

### Version 1 (Native MVP)

Version 1 stays intentionally narrow:

- a native macOS resident app
- a top capsule / notch-like collapsed state
- a simple expanded panel on click
- a single active-task view
- only the core states: `running`, `awaiting_approval`, `completed`, `failed`
- only the core actions: `approve`, `reject`, `retry`
- one real CLI / Agent integration
- minimal local state plus a few recent tasks

The goal is not feature breadth. The goal is to be:

- native instead of browser-based
- always present at the top of macOS
- useful in one real workflow

### Version 2 (Enhanced)

Only after V1 is stable:

- multi-task list and switching
- recent task history and more detail
- log preview and jump back to terminal
- system notification integration
- launch at login and basic settings
- multiple CLI / Agent integrations
- refined motion and interaction details

### Explicitly out of scope for V1

- music controls, calendar, file shelf, or other desktop utility features
- HUD replacement
- complex plugin systems
- XPC helper and heavier system extensions
- deep compatibility work for multi-display, lock screen, and fullscreen
- a full conversation history viewer

### Run the current prototype

```bash
python3 app.py
```

Open: <http://127.0.0.1:8765>
