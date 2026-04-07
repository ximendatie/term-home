<p align="center">
  <a href="./README.md">中文</a> |
  <a href="./README.en.md">English</a>
</p>

# term-home

一个面向 CLI 与 AI Agent 的 macOS 顶部状态层与统一事件总线。

`term-home` 试图解决一个越来越明显的问题：  
CLI 越来越强，Agent 越来越能干，但它们的运行状态、交互入口和人工接管能力，依然大多被困在终端里。

这个项目希望在 macOS 上提供一个统一的运行时体验层：

- 用顶部悬浮层 / notch 风格 UI 展示 CLI 和 Agent 的实时状态
- 用统一事件协议接入不同的 CLI 工具
- 让长任务、审批、失败、中断、重试这些关键动作变得可见、可控、可回跳

它不是为了替代终端。  
它是为了给现代 CLI 工作流补上一层更适合人的运行时交互界面。

---

## 为什么要做这个

现在很多开发工作流已经越来越依赖 CLI：

- AI Coding Agent
- 构建 / 测试 / 部署工具
- 自动化脚本
- 浏览器自动化
- 本地或远程长任务
- 各种命令行编排流程

但它们在使用体验上仍然有几个明显问题：

- 状态埋在终端输出里，不直观
- 用户必须持续盯着 shell
- 错误很容易错过
- 审批、确认这类关键动作缺乏统一入口
- 每个 CLI 都在用自己的方式表达“我现在在干什么”
- 多个任务并发时，很难快速知道哪个任务卡住了、哪个任务完成了、哪个任务需要人介入

`term-home` 想解决的，就是这个“执行能力很强，但运行时体验很弱”的断层。

---

## 这是什么

`term-home` 由两部分组成：

### 1. macOS 顶部状态层
一个常驻在顶部的轻量 UI，用来展示：

- 当前任务状态
- 运行中 / 成功 / 失败 / 等待输入 / 需要审批
- 关键摘要信息
- 快捷动作入口
- 多任务切换
- 回跳终端 / 查看日志 / 重试 / 停止

它可以是 notch 风格、灵动岛风格，也可以是更克制的顶部胶囊状态条。

### 2. 统一 CLI 事件总线
一个面向多 CLI / 多 Agent 的统一事件模型，用来表达：

- 任务开始
- 状态更新
- 进度变化
- 日志摘要
- 需要审批
- 任务完成
- 任务失败
- 任务取消
- 动作执行结果

核心目标是：  
不要让上层 UI 到处解析零散的终端文本，而是建立一个统一、稳定、可扩展的事件层。

---

## 核心理念

### 可见
用户不应该靠盯终端猜测任务状态。

### 可操作
状态不只是展示，还应该支持：
- 停止
- 重试
- 审批
- 拒绝
- 打开日志
- 回到原始上下文

### 工具无关
这个项目不应该只服务某一个 CLI 或某一个模型供应商。

### 人在回路中
Agent 可以自动执行，但用户必须始终拥有清晰、低成本的介入点。

### 事件优先
真正可靠的抽象不是“终端文本”，而是“结构化事件”。

---

## 适用场景

### AI Coding Agent
- Claude Code
- Codex CLI
- Aider
- OpenCode
- OpenClaw
- 自定义内部 Agent

### 开发者工作流
- build / test / lint
- deploy
- migration
- 长时间运行脚本
- 批处理任务
- 本地自动化管线

### 自动化执行场景
- Playwright Runner
- 浏览器自动化
- 表单填写 / 运营自动化
- 需要人工最终确认的自动执行任务

---

## 我们要解决的问题

当前 CLI 工作流在“执行力”和“交互体验”之间存在明显落差。

### 现状
- 输出噪音大，难以快速提炼状态
- 任务状态是隐式的，不是显式的
- 进度难以总结
- 通知分散且不统一
- 审批经常被困在终端会话里
- 多任务并发时缺少统一视图

### 理想状态
任何一个 CLI 或 Agent 都可以清晰表达：

- 我开始了
- 我正在运行
- 我当前在做什么
- 我需要你审批
- 我完成了
- 我失败了
- 你现在最适合执行的下一步动作是什么

而 macOS 顶部状态层则负责把这些信息以最小打扰、但足够有效的方式呈现出来。

---

## 项目架构

```text
+--------------------+       +----------------------+       +----------------------+
|   CLI / Agent      | ----> |  term-home Bus    | ----> |  macOS 顶部状态层    |
|                    |       |                      |       |                      |
| - Claude Code      |       | - 事件接收           |       | - 顶部胶囊 / notch   |
| - Codex CLI        |       | - 事件标准化         |       | - 状态展示           |
| - Aider            |       | - 状态机             |       | - 快捷动作           |
| - Shell Script     |       | - 路由分发           |       | - 通知 / 详情        |
| - Playwright Job   |       | - 历史记录           |       | - 回跳终端 / 日志    |
+--------------------+       +----------------------+       +----------------------+
```

---

## MVP 规划

当前仓库里已经有一个可运行的 Core 原型，用于验证事件总线和基础状态闭环：

- `app.py`：统一事件总线服务（`POST /events`, `GET /tasks`, `GET /stream`, `POST /tasks/{id}/actions`）。
- `Sources/TermHomeNative/`：原生 macOS 壳层脚手架（顶部胶囊窗口 + 展开面板 + 动作占位）。
- `Package.swift`：用于本地构建原生壳层。
- `openspec/`：规格、计划和任务拆解。

这个版本适合快速验证事件模型与任务状态流转，但它不是最终定义的 MVP。  
对于 `term-home`，真正的 MVP 应该是一个功能收敛、但已经真实可用的原生 macOS 顶部状态层。

### 第一版（Native MVP）

第一版只做最小闭环，不做桌面工具箱：

- 原生 macOS 常驻 app。
- 顶部入口采用顶部胶囊 / notch 风格收起态。
- 点击后展开一个简单面板。
- 只展示当前 1 个活动任务。
- 只支持基础状态：`running` / `awaiting_approval` / `completed` / `failed`。
- 只提供少量核心动作：`approve` / `reject` / `retry`。
- 只接入 1 个真实 CLI / Agent 事件源。
- 只保留最小本地状态与少量最近任务。

第一版的目标不是“功能丰富”，而是：

- 真正脱离浏览器。
- 真正常驻在 macOS 顶部。
- 真正能用于一个实际工作流。

### 第二版（增强版）

第二版在第一版稳定之后扩展：

- 多任务列表与任务切换。
- 最近任务历史与更多详情。
- 日志预览与回跳终端。
- 系统通知联动。
- 开机启动与基础设置项。
- 多 CLI / 多 Agent 接入。
- 动效与交互细节优化。

### 明确不属于第一版的范围

以下内容不进入第一版：

- 音乐控制、日历、文件 shelf 等桌面工具能力。
- HUD replacement。
- 复杂插件系统。
- XPC helper 和重度系统级扩展。
- 多屏、锁屏、全屏等深度兼容打磨。
- 完整聊天记录查看器。

### 开发约束

- 所有新增代码模块必须包含模块级说明。
- 所有新增函数、方法和关键构造入口必须包含简洁的函数级注释。
- 注释目标是解释职责和边界，不写无信息量的逐行翻译。
- 后续需求、修复和功能迭代继续遵循项目内 `openspec/` 工作流。
- 任何继续开发都应先更新 `openspec/specs/core-mvp/spec.md`、`plan.md`、`tasks.md`，再进入实现。

### 当前原型如何运行

事件总线：

```bash
python3 app.py
```

可用接口：

- `GET /health`
- `GET /tasks`
- `GET /stream`
- `POST /events`
- `POST /tasks/{id}/actions`

原生壳层：

```bash
swift run TermHomeNative
```

当前原生壳层已具备：

- 顶部胶囊形态
- 点击展开详情面板
- 基于 SSE 的实时状态同步
- 与 `app.py` 事件总线打通
- 原生动作按钮可回写本地总线
- 最近少量任务展示与断连兜底

当前原生壳层尚未完成：

- 更完整的任务历史
- 更细粒度的流式状态映射

### Codex CLI 接入（第一版真实来源）

当前仓库已提供一个最小可用的 Codex CLI 桥接脚本：

```bash
python3 scripts/run_codex_exec.py "总结当前仓库里 native MVP 还缺什么"
```

推荐按下面顺序运行：

```bash
python3 app.py
swift run TermHomeNative
python3 scripts/run_codex_exec.py "总结当前仓库里 native MVP 还缺什么"
```

桥接脚本会：

- 启动 `codex exec --json`
- 将生命周期事件转成 `term-home` 任务事件
- 把最终结果写成 `completed` 或 `failed`

可选参数示例：

```bash
python3 scripts/run_codex_exec.py \
  --cd /Users/bytedance/Desktop/term-home \
  --full-auto \
  --title "Codex native MVP check" \
  "检查当前原生 MVP 还缺哪些能力"
```

### Coco CLI 接入（新增真实来源）

当前仓库也提供了一个最小可用的 Coco CLI 桥接脚本：

```bash
python3 scripts/run_coco_print.py "请用一句话说明当前 native MVP 是否已经接入真实 CLI。"
```

推荐按下面顺序运行：

```bash
python3 app.py
swift run TermHomeNative
python3 scripts/run_coco_print.py "请用一句话说明当前 native MVP 是否已经接入真实 CLI。"
```

桥接脚本会：

- 启动 `coco -p --json`
- 将最终 JSON 输出映射成 `term-home` 任务结果
- 把最终结果写成 `completed` 或 `failed`

当前 `coco` bridge 先保证最小闭环：

- 有 `started`
- 有 `completed / failed`
- 能展示最终摘要

由于 `coco -p --json` 默认是一次性输出，所以当前不会像 Codex bridge 那样提供细粒度流式进度事件。

### 通用命令监听

如果你只想监听最简单的命令生命周期，可以直接用统一入口：

```bash
python3 scripts/term_home.py run -- npm run dev
```

它会把命令纳入 `term-home`，并提供最小状态链路：

- started
- running
- completed
- failed

如果命令会输出“服务已启动”之类的文案，可以加 ready pattern：

```bash
python3 scripts/term_home.py run \
  --ready-pattern "ready in|Local:|compiled successfully|running at" \
  -- npm run dev
```

默认标题会从原始命令自动推导，所以可以直接写：

```bash
python3 scripts/term_home.py run -- npm run dev
```

也可以显式指定标题：

```bash
python3 scripts/term_home.py run --title "web dev" -- npm run dev
```

### zsh 集成

如果你希望用显式前缀而不是手敲完整命令，可以在 `~/.zshrc` 里加入：

```zsh
source /Users/bytedance/Desktop/term-home/scripts/th.zsh
```

之后就可以这样用：

```bash
th npm run dev
th pnpm dev
th python app.py
th --title "api dev" -- npm run dev
```

这种方式只会监听你显式加了 `th` 前缀的命令，不会自动包裹全部 shell 指令。
