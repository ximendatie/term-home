# Tasks: core-mvp

- [x] 初始化 openspec 工作区（spec-coding 目录结构）。
- [x] 编写 `core-mvp` 规格文档（目标、事件模型、验收标准）。
- [x] 实现事件总线服务（`/events`, `/tasks`, `/stream`）。
- [x] 实现任务状态机与动作映射（stop/retry/approve/reject）。
- [x] 更新项目 README，补充核心版本启动方式。
- [x] 完成基础运行验证。
- [x] 移除 Web 原型，收敛仓库到事件总线基础能力。

## V1 / Native MVP

- [x] 建立原生 macOS app 壳层。
- [x] 实现顶部胶囊 / notch 收起态。
- [x] 实现点击展开的简单详情面板。
- [x] 在原生界面中展示当前 1 个活动任务。
- [x] 支持 `running` / `completed` / `failed` / `cancelled` 为核心的状态监测展示。
- [x] 移除原生壳层中的 `approve` / `reject` / `retry` 反馈式动作区。
- [x] 接入 1 个真实 CLI / Agent 事件源（Codex CLI bridge）。
- [x] 增加第 2 个真实 CLI 事件源（Coco CLI bridge）。
- [x] 抽象统一 CLI bridge adapter，拆分 streaming / print 两类公共能力。
- [x] 增加通用命令 bridge，支持包装任意本地命令并发布 started/running/completed/failed。
- [x] 增加统一入口 `term_home.py run`，封装通用命令 bridge。
- [x] 增加 zsh 快捷函数 `th`，支持显式前缀接入 term-home。
- [x] 增加 `th-codex` 快捷函数，供需要直接占用 TTY 的 Codex 走专用 bridge。
- [x] 让 `th-codex` 自动透传 session / terminal 元信息，并在缺少 prompt 时返回清晰用法提示。
- [x] 将 `ssh` 默认纳入 term-home 监测，并通过 shell 包装补发 started / completed / failed / cancelled 事件。
- [x] 为 `th` 增加 shell session id 注入，让同一 shell / tab 内的任务可归并到同一会话。
- [x] 为 `th` 任务补充 `terminal_app` / `tty` / `cwd` 等元信息。
- [x] 增加空状态、断连、非法事件兜底。
- [x] 增加最小本地状态与最近少量任务展示。
- [x] 修正主位任务选择逻辑，优先展示真实来源任务。
- [x] 修正动作回写污染任务标题 / 来源的问题。
- [x] 增加开发态任务清理入口，支持按 `task_id/status/source` 清理残留任务。
- [x] 补充收起态命中展开、展开态点外部收起的宿主层交互。
- [x] 展开时主动刷新快照，降低 SSE 漏刷带来的空状态问题。
- [x] 将展开态排版收敛为仅展示 `title` / `detail` / `status`，字号风格向系统 Terminal 靠拢。

## V2 / Enhanced

- [ ] 支持多任务列表与切换。
- [ ] 增加最近任务历史与详情。
- [ ] 增加日志预览。
- [ ] 增加回跳终端能力。
- [ ] 增加系统通知联动。
- [ ] 增加开机启动与基础设置。
- [ ] 支持更多 CLI / Agent 接入。
- [ ] 优化动效与交互细节。

## 当前待补强

- [ ] 稳定真实 CLI `completed` 状态的最终落地，不再偶发停留在 `running`。
- [ ] 继续对齐 `claude-island` 的动画稳定性，减少展开 / 收起偶发抖动。
- [ ] 继续排查 native 壳层与总线快照 / SSE 的同步稳定性。
- [x] 修正 `th` / 通用命令 bridge 的输出回显行为，确保包装后原命令日志仍能持续显示在当前终端。
- [x] 修正 `th` / 通用命令 bridge 的 `Ctrl+C` 行为，避免前台长命令中断时输出 Python traceback，并将中断回写为 `cancelled`。
- [x] 在 shell 退出时按 `session_id` 清理该 tab 对应的任务历史。
- [x] 让展开态右箭头优先回跳到原始 terminal tab/session。
- [x] 为回跳按钮增加明显的 hover 高亮，并拉开 enabled / disabled 差异。
- [x] 让当前任务区也提供与最近任务一致的终端回跳入口。
- [x] 让最近任务整行可展开 / 收起 detail，同时保留箭头单独负责 tab 回跳。
- [x] 进一步增强箭头可见度与整行 hover 高亮，避免交互信号过弱。
- [x] 修正最近任务箭头点击误触发展开 detail 的事件冲突。
- [x] 对不支持回跳的任务隐藏箭头，并将可用箭头统一成白色高对比样式。
- [x] 将最近列表改为按 shell session 近似 tab 聚合，并以该 tab 最新任务标题作为列表 title。
- [x] 将 recent 列表限制为仍存活的 shell session/tab，关闭 tab 后不再展示对应列表项。
- [x] 将 recent 区域文案统一改为 `terminal list`。
- [x] 将 tab 列表的 title/detail 基准改为“最近发起的任务”，而不是“最近更新的任务”。
