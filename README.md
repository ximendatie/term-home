<p align="center">
  <a href="./README.md">中文</a> |
  <a href="./README.en.md">English</a>
</p>

# term-home

一个面向 CLI 与 AI Agent 的 macOS 顶部状态层与统一事件总线。

## 当前进展（Core MVP 已落地）

本仓库现已完成首个核心闭环版本（V0），遵循“先核心、后扩展”的策略：

- 统一事件协议 + 事件接入 API
- 任务状态机与状态归一化
- 顶部状态层（Web 模拟 notch 风格）
- 人工干预动作（stop/retry/approve/reject）
- SSE 实时推送

> 说明：当前为快速落地版本，优先验证运行时交互闭环；后续再演进为原生 macOS UI。

## 参考实现

用于快速实践和 UI 学习：

- [claude-island](https://github.com/farouqaldori/claude-island)
- [boring.notch](https://github.com/TheBoredTeam/boring.notch)

## 快速开始

### 1) 启动服务

```bash
python3 app.py
```

启动后打开：<http://127.0.0.1:8765>

### 2) 注入一个任务事件

```bash
curl -X POST http://127.0.0.1:8765/events \
  -H 'content-type: application/json' \
  -d '{
    "type": "task.started",
    "task_id": "demo-1",
    "source": "codex-cli",
    "title": "生成迁移脚本",
    "summary": "正在扫描数据库差异"
  }'
```

再更新进度：

```bash
curl -X POST http://127.0.0.1:8765/events \
  -H 'content-type: application/json' \
  -d '{
    "type": "task.progress",
    "task_id": "demo-1",
    "summary": "已完成 60%",
    "progress": 60
  }'
```

查看任务快照：

```bash
curl http://127.0.0.1:8765/tasks
```

## OpenSpec（Spec-Coding）

已初始化 `openspec/` 目录并启用 spec-coding 推进方式：

- `openspec/README.md`
- `openspec/specs/core-mvp/spec.md`
- `openspec/specs/core-mvp/plan.md`
- `openspec/specs/core-mvp/tasks.md`

核心目标、实施计划、任务拆解和验收标准都在上述文件中维护。
