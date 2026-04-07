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
- [x] 支持 `running` / `awaiting_approval` / `completed` / `failed` 四种核心状态。
- [x] 支持 `approve` / `reject` / `retry` 三个核心动作。
- [x] 接入 1 个真实 CLI / Agent 事件源（Codex CLI bridge）。
- [x] 增加第 2 个真实 CLI 事件源（Coco CLI bridge）。
- [x] 抽象统一 CLI bridge adapter，拆分 streaming / print 两类公共能力。
- [x] 增加空状态、断连、非法事件兜底。
- [x] 增加最小本地状态与最近少量任务展示。
- [x] 修正主位任务选择逻辑，优先展示真实来源任务。
- [x] 修正动作回写污染任务标题 / 来源的问题。
- [x] 补充收起态命中展开、展开态点外部收起的宿主层交互。
- [x] 展开时主动刷新快照，降低 SSE 漏刷带来的空状态问题。

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
- [ ] 完成 `approve / reject / retry` 到真实后端恢复执行的闭环。
- [ ] 继续对齐 `claude-island` 的动画稳定性，减少展开 / 收起偶发抖动。
- [ ] 继续排查 native 壳层与总线快照 / SSE 的同步稳定性。
