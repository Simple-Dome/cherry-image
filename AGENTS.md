# AGENTS.md

本文档用于约束本项目中的 AI / 自动化开发行为。开发时优先遵循本文件，其次遵循用户当前消息。

## 基本原则

- 先读现有代码，再动手修改，优先沿用项目已有结构和写法。
- 写代码保持最少行数，能简单实现就不要引入复杂抽象。
- 标准格式、协议、解析、压缩、加密、日期等通用能力优先使用成熟稳定的库，不要手写底层实现，除非用户明确要求或项目已有实现必须沿用。
- 不要为了“兼容更多场景”写大量分支，只实现当前明确需要的功能。
- 项目尚未上线，不需要兼容旧数据；本地存储结构调整时直接按新设计修改，不写旧字段兼容或数据迁移兜底，除非用户明确要求。
- 每次写完代码，不需要检查语法，不需要执行构建，用户会自己做。
- 不要改无关文件，不要顺手重构。
- 如果工作区已有用户改动，不要回滚，不要覆盖；只在必要范围内追加修改。

## 反复提醒沉淀

- 如果开发过程中总是遇到某个问题，或者用户反复提醒同一个注意事项，需要把该注意事项补充到本文件。
- 补充时写成明确、可执行的规则，避免只写模糊描述。
- 新规则应放到最相关的章节；找不到合适章节时放到“项目注意事项”。

## 前端规范

- 前端使用 Vite、React、React Router、TypeScript、Ant Design、Tailwind、Zustand。
- 编写 Ant Design 相关代码时，参考 https://ant.design/llms-full.txt 理解组件 API、示例和设计规范，并优先结合项目当前 antd 版本与既有写法。
- 外部服务请求统一放在 `web/src/services/api/`，由浏览器前端直连，不假设存在项目后端。
- 全局或跨页面状态优先放在 `web/src/stores/`。
- 已经放在全局 store 或全局 hook 中的状态/动作，组件需要时直接使用对应 store/hook，不要为了“纯组件”层层透传 props；避免一个组件传递过多参数。
- 全局组件、全局常量、全局配置等全局性质的内容不要作为 props 或参数层层传递；哪里需要就在哪里直接从对应全局入口获取。
- 多个页面重复出现的 UI 副作用动作，例如复制文本并提示、下载并提示、统一确认弹窗，优先抽成 `web/src/hooks/` 下的全局 hook；不要放进 store，除非它确实是需要共享/订阅的状态。
- 路由页面放在 `web/src/pages/`，页面布局放在 `web/src/layouts/`，路由配置放在 `web/src/router.tsx`。
- 画布页面放在 `web/src/pages/canvas/`，画布组件放在 `web/src/components/canvas/`，画布状态放在 `web/src/stores/canvas/`，画布工具函数放在 `web/src/lib/canvas/`。
- 页面按目录组织，例如 `web/src/pages/image/index.tsx`；页面里只有一个主业务组件时直接写在对应页面入口中，不要单独拆 `Manager` 组件再传一堆 props。
- 不要新增只做简单转发的组件，例如只 `return <X>{children}</X>` 或只换个名字透传 props；直接在使用处使用真实组件或把逻辑写进当前文件。
- 页面私有 hook 放在对应页面目录下，例如 `admin/assets/use-admin-assets.ts`；只有多个页面真实复用的 hook 才放到外层 `hooks/`。
- 管理后台页面私有组件放到各自页面目录的 `components/` 下，例如 `admin/assets/components/`、`admin/prompts/components/`；不要为了单页面使用放到 `admin/components/` 共享目录。
- 管理后台主题、背景、卡片阴影、表格配色等统一在 `web/src/lib/app-theme.ts`、`AppProviders` 或必要的全局 CSS 作用域中配置；页面私有组件不要自己写 `dark ? ...` 主题分支。
- 组件优先使用函数组件和现有 hooks，不新增大型状态管理方案。
- UI 图标优先使用 `lucide-react` 或项目已经使用的 Ant Design 图标。
- 页面文案保持中文。
- 不要在组件里堆太多无关逻辑；复杂逻辑优先抽成同目录工具函数或小组件。
- 样式优先由组件自己管理；组件私有样式优先使用 Tailwind className 或少量内联 style，不要为单个组件新增大量全局 CSS。
- 全局 CSS 只放基础变量、全局重置、跨页面通用样式和少量第三方组件必要覆盖；不要在 `globals.css` 堆页面私有样式。
- 代码尽量短小直接，少拆不必要组件，少做多层 props 传递，避免为了抽象堆出更多代码。
- 前端业务数据需要浏览器本地持久化时，默认使用 `localforage`；`localStorage` 只用于极小的简单配置，不要用来保存业务列表、生成记录、图片、base64 或大 JSON。

## 画布 UI 规范

- 做 canvas 前端 UI 时必须遵循当前画布主题。
- 优先使用 `canvasThemes`、`useThemeStore` 或 Ant Design `ConfigProvider` token。
- 不要硬编码黑白、stone、slate 等颜色导致浅色/深色主题不一致。
- 新增画布按钮、弹窗、浮层时，尽量复用已有工具栏、节点面板、Modal 的视觉风格。
- 画布顶部工具栏和状态信息优先采用极简扁平风格：无边框、无阴影、无胶囊背景，融入整体背景，弱化按钮感，仅保留轻微 hover 反馈，保持简洁现代、低视觉重量。
- 左侧画布面板等列表里的节点/元素缩略图容器，非图片类型（文本、配置、视频、音频等）不要使用 `theme.node.fill`（`#e7e5df`/`#292524`）这类灰色背景，图标直接无背景展示，尽量不要给多余底色，保持干净。
- 画布内的操作按钮（如面板里的「添加」「导出」「选择」等）默认用扁平无底色样式：透明背景、仅 `hover:bg-black/5 dark:hover:bg-white/10` 轻微反馈，靠图标+文字表达，不要用 `theme.toolbar.activeBg`（`#e7e5df`/`#3a3631`）或 `theme.node.fill` 之类的灰色作为按钮填充底色。灰色 `activeBg` 只允许用于「选中态」等需要表达状态的高亮，不要当普通装饰底色。
- 图片节点尺寸逻辑要尊重原始比例，除非功能明确要求自由变形。
- 批量生成、多图展示、助手面板等画布交互要尽量简洁，不要占用过多画布空间。

## 文档规范

- README 保持简洁，只放项目介绍、核心功能、快速开始和文档入口。
- `docs/index.md` 放给 AI 使用的文档索引，不要再放到 `docs/content/docs/` 内容目录里。
- 详细功能介绍写到 `docs/content/docs/overview/features.mdx`。
- 后续待办写到 `docs/content/docs/progress/todo.mdx`。
- 已实现但还需要用户测试确认的事项写到 `docs/content/docs/progress/pending-test.mdx`。
- `docs/content/docs/progress/pending-test.mdx` 用来记录这个版本实际做了哪些可测试变更；`CHANGELOG.md` 的 `Unreleased` 只保留对这些变更的版本级归纳，避免逐条照搬实现细节。
- 每次重大改动（新增/调整/删除功能、接口或工具，影响用户可感知行为）完成后，都要在 `CHANGELOG.md` 的 `Unreleased` 追加一条记录，按 `[新增]` / `[调整]` / `[修复]` / `[优化]` 前缀分类，用一句中文归纳；纯内部重构、格式化、无用户可感知影响的小改动可不记。
- 每次 todo 事项完成后，先从 `docs/content/docs/progress/todo.mdx` 移到 `docs/content/docs/progress/pending-test.mdx`，不要直接写进正式功能说明；用户确认测试通过后再更新 `docs/content/docs/overview/features.mdx`。
- 每次任务完成前，都要根据实际变更检查并更新 `docs/content/docs/progress/todo.mdx` 和 `docs/content/docs/progress/pending-test.mdx`；如果功能或待办没有变化，也要确认无需修改。
- 文档不要写过期日期；除非用户明确要求记录具体时间。

## 发版本流程

- 发版本时，先把 `CHANGELOG.md` 的 `Unreleased` 变更整理成新的版本记录，并保留空的 `Unreleased` 标题。
- 按当前版本号提升一个版本，更新根目录 `VERSION`。
- 将当前未提交的代码全部提交到 Git。
- 提交完成后，给当前提交打最新版本号对应的 tag，例如 `v0.0.5`。
- 发版本流程中不要执行编译、测试或构建，除非用户明确要求。

## Image 发布与部署规范

本仓库的 `main` 分支只绑定 `artworkers.online` Image 发布，不得把它用于其他域名或其他服务。Image 发布覆盖 `/image/`、`/canvas/` 与 `/canvas-uploads/`；根路径、`/v1`、`/api`、New API、数据库、Redis、MinIO 数据目录及其他域名不在普通 Image 发布范围内。

### 主机边界

- 本机是 Git/SSH 控制端，只允许做只读 discovery、提交校验、隔离 detached worktree、Canvas gitlink 校验和 composite source archive 准备；本机不得使用 Docker daemon 构建、检查、保存、加载或传输 release 镜像。
- `newapi-16`（`103.85.227.193`）是唯一构建与测试主机。所有 Shell、Canvas 和变更中的 uploads edge 镜像必须在该主机以 `linux/amd64` 使用 Docker Buildx 构建、验证并保存归档；该主机保留构建证据直到生产验证结束。
- `root@155.103.156.90` 是生产部署主机，只能接收经过校验的归档、比较 SHA 和镜像身份、执行 `docker load`、启动候选、健康检查及明确授权的 Nginx 切换；禁止在生产机编译、安装依赖、构建或打包测试镜像。
- 源码只发送到 `newapi-16`；生产机只接收精确的已校验镜像归档。向生产传输时默认由 `newapi-16` 直连 `root@155.103.156.90`，本机控制端只允许通过 SSH agent forwarding 提供认证，不得中继镜像内容；使用 `set -o pipefail` 的 Base64 文本传输，按原始归档每块 3 MiB 传输，目标端逐块校验 SHA-256、全部完成后再拼接并校验完整归档 SHA-256，校验失败或存在 `.partial` 文件时禁止 `docker load`，不得传输源码目录。

### Source Pair 与证据

- Image release 永远是 parent + Canvas source pair，不是单独一个 parent SHA。必须记录当前 parent commit 和精确的 `vendor/infinite-canvas` gitlink commit；prepared worktree 必须 materialize 该 gitlink，parent 与 Canvas worktree 都必须干净。
- 不得使用当前 attached checkout、attached branch worktree、其他任务 worktree 或 `/Users/ming/project/image` 共享工作区作为发布源。每次发布必须创建独立 task id，并运行：
  `scripts/deploy/release-control.sh prepare-worktree --task-id <id> --domain artworkers.online --source-ref <完整40位SHA>`。
- `release-control.sh` 只负责控制端的 source preparation；它不负责、也不得在本机执行 Docker 构建。`prepare-composite` 生成的归档才是发送给 `newapi-16` 的唯一源码输入。
- parent commit 必须已推送到匹配的 `origin/main`；缺少 gitlink、gitlink 不匹配、Canvas checkout 脏、parent 脏、短 SHA、未推送 commit 或跨域 source 都必须终止发布，不能用当前本地子模块内容替代。
- task manifest 必须保留 selected domain、profile status、允许路由、Shell/Canvas/Uploads 拓扑、parent/Canvas commit、Dockerfile SHA-256、composite archive SHA-256、两种颜色的镜像 tag/ID、两份镜像归档路径/校验和及验证状态。候选只有在记录的平台为 `linux/amd64` 且验证达到 `production-loaded-verified` 后才可视为可用。
- 必须记录不可变 parent commit、Canvas commit、源码归档 SHA、Shell/Canvas Dockerfile SHA、镜像 tag/ID、平台架构、保存归档 SHA，并保留构建目录、source marker 和归档到最终生产验证结束。
- 对 Canvas source 必须要求唯一静态 `OPENAI_BASE_URL = "https://artworkers.online"`；禁止缺失、动态、重复、带路径或跨域地址。Shell 的 `DEFAULT_API_URL`、`INFINITE_CANVAS_URL`、Canvas 的 `NEXT_BASE_PATH`、`NEXT_PUBLIC_DOC_URL`、上传存储地址和公开上传地址必须绑定同一个 selected domain。

### Profile、授权与锁

- 每次发布前必须设置唯一 `selected_domain=artworkers.online` 并做新的只读 discovery；profile 不是 `ready-for-bluegreen` 时只能做本地准备和只读 discovery，必须停止。`canvas-bluegreen-migration-required`、`upload-bluegreen-migration-required` 和 `bootstrap-required` 都是阻塞状态，不得隐藏或绕过。
- Profile 只有在 fresh discovery 同时证明 Shell Blue/Green、Canvas Blue/Green、Uploads Edge Blue/Green，以及该域名独立的 MinIO 容器、网络、持久目录、Bucket、凭据、对象命名空间和公开上传地址后，才能进入 `ready-for-bluegreen`。
- 构建、打包、push 或调用技能都不代表生产授权。第一次生产命令前必须拥有新鲜授权，并明确点名 `root@155.103.156.90` 及允许的具体动作；需要通过 `PRODUCTION_RELEASE_AUTHORIZED=yes` 校验。未授权时不得 image load、候选启动、候选记录或 Nginx cutover。
- 使用 `/root/.locks/new-api-release` 作为协调根，并使用窄语义锁：`build-artifact:image:<domain>:<parent-sha>:<canvas-sha>`（`newapi-16` 构建）、`image:<image-id>`（每个生产镜像）、`docker-load:global`（每次生产加载）、`domain:<domain>`（候选和回滚生命周期）、`nginx:global`（Nginx 事务及公共验证）。锁冲突必须输出 owner metadata 并以退出码 75 结束；不得隐式等待、抢锁或在构建/等待候选时持有 `nginx:global`。
- 生产协调器文件名保持兼容：`production-image-<id>`、`production-domain-<domain>`、`production-nginx-global`；Image 额外使用 `build-artifact-image-<domain>-<parent>-<canvas>` 和 `production-docker-load-global`。New API 协调器也必须在 `docker load` 前获取全局 Docker 锁，Image 不得单方面假设其他服务参与协调。

### 蓝绿、回滚与范围

- 每个被改变的无状态服务都必须有不重复的备用颜色、非公共候选端口、健康检查、回滚容器名和对应的 selected-domain Nginx upstream。Shell、Canvas 和 artworkers.online uploads edge 必须作为一个事务验收和切换；持久 MinIO 在普通应用发布中保持不变。
- Nginx 事务必须备份所有受影响的 selected-domain snippet，一次性修改 upstream，执行 `nginx -t`、reload 和公共验证；任一候选、语法、reload 或公共路由检查失败，都必须恢复全部备份并 reload。
- 通过最终健康检查、公共路由、CSS MIME、Canvas iframe、API 鉴权和专用上传探针后，每个独立服务只保留最新的已停止 `*-pre-*` rollback 容器；清理旧 rollback 时不得删除运行中的 Blue/Green、当前候选、其他服务/域名的 rollback、镜像、volume 或 active container。
- 两种无状态 uploads edge 颜色只能代理到该域名唯一且隔离的 MinIO；不得跨域共享 MinIO 容器、volume、Bucket、凭据、对象命名空间或公开上传地址。MinIO 镜像、数据目录和拓扑变更必须另行做有完整性证明和回滚点的 stateful migration。
- `scripts/deploy/bluegreen-host.sh` 是旧的单 Shell helper，不得用它绕过 release-control、Canvas source pair、profile gate、source provenance 或共享锁。

## 项目注意事项

- 当前画布项目和“我的素材”主要保存在浏览器本地，不要在文档中误写成已支持云同步。
- 当前 AI API Key 存在浏览器本地，并由前端直接请求 OpenAI 兼容接口；涉及安全说明时要写清楚。
- Docker 静态资源路径目前仍是待办项，文档中不要过度承诺生产部署已经完全验证。
- Agent 对话消息必须同时按 `threadId`、`turnId` 和 `itemId` 归属；实时事件只用于补充未物化的 turn，历史快照成为权威后不得重复合并同一条消息。
