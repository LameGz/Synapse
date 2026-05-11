# 一人公司如何让 Coding Agent 稳定记住项目上下文？我做了一个轻量工程记忆图 Synapse v0.4

项目地址：<https://github.com/LameGz/Synapse>

## 前言：一人公司最怕的不是写代码，而是上下文断掉

如果你是一个人做产品，可能会同时扮演这些角色：

- 产品经理：想功能、拆需求、定优先级；
- 前端工程师：写页面、组件、状态管理；
- 后端工程师：写 API、数据库、鉴权；
- UI/UX：调交互、样式、设计系统；
- 测试和运维：查 bug、发版、修线上问题；
- 还要和 Claude Code、Codex、Cursor 这类 Coding Agent 一起协作。

一开始项目小的时候，问题不明显。

你可以直接对 Agent 说：

> 继续做登录页面。

Agent 大概还能猜到你想干什么。

但项目一旦变大，问题就来了：

- 登录页面依赖哪个 auth API？
- `refresh_token` 存在哪里？
- `/api/v1/auth/login` 返回哪些字段？
- UI 组件规范是什么？
- 上次为什么把某个模块拆开？
- 支付模块和用户模块有什么依赖？
- 这个功能做到哪一步了？
- Agent 上次改过什么？现在还缺什么？

如果每次都把所有文档、README、接口说明、历史记录、代码片段都塞给 Agent，上下文很快爆炸。

如果什么都不塞，Agent 又会开始猜，甚至编。

这就是我做 Synapse 的核心原因：

> Coding Agent 做项目时，如何在不塞爆上下文的情况下，稳定记住工程状态和模块依赖？

Synapse v0.4 的目标不是做一个重型知识图谱，也不是 GraphRAG，而是一个更轻量、更工程化的东西：

> 让用户用自然语言记录工程上下文，系统自动抽取节点与依赖关系，生成一个可解释、可维护、可被 Coding Agent 按需遍历的轻量记忆图。

---

## 一人公司的真实痛点

### 1. 一个人负责太多模块

一人公司不是只写一个页面。

真实项目里通常会有：

- 前端页面；
- 后端接口；
- 数据库表；
- 鉴权系统；
- 支付系统；
- 设计系统；
- 部署脚本；
- 第三方服务；
- Agent 协作记录。

这些东西互相依赖。

比如一个登录功能，看起来只是一个页面，但它实际依赖：

```text
feat_login
  ├── mod_auth-api
  ├── mod_design-system
  └── mod_user-session
```

如果 Agent 只知道“登录页面”，不知道 auth API 的返回字段，就很容易写错。

如果 Agent 每次都加载所有模块，又会浪费上下文。

### 2. 项目记忆不是线性的，而是图状的

传统做法通常是写一个 `project-memory.md` 或 `rolling-summary.md`。

这种扁平文件在项目小的时候很好用。

但项目大了之后，它会变成这样：

```text
登录改动
支付改动
数据库改动
UI 改动
部署问题
用户反馈
接口变更
历史 bug
...
```

所有东西都堆在一起。

Agent 为了改一个按钮颜色，可能会读到数据库迁移、支付回调、部署日志。

这会带来两个问题：

1. 上下文污染：无关信息太多，Agent 注意力被干扰。
2. 上下文浪费：token 花在当前任务不需要的信息上。

所以项目记忆不应该只是一篇长文，而应该是：

```text
树状存储 + 图状依赖
```

也就是说：

- 文件上仍然是 Markdown，方便人类读写；
- 结构上用图记录模块之间的关系，方便 Agent 按需遍历。

---

## Synapse 的核心思路

Synapse 的设计非常简单：

```text
meta/
  mod_auth-api.md
  mod_design-system.md
  feat_login.md
  feat_checkout.md

MEMORY_MAP.md
MEMORY_MAP.json
```

每个 `meta/*.md` 是一个记忆节点。

节点可以是模块：

```text
mod_auth-api.md
mod_payment.md
mod_design-system.md
```

也可以是功能：

```text
feat_login.md
feat_checkout.md
feat_dashboard.md
```

每个节点内部包含：

```markdown
---
id: feat_login
type: feature
status: in-progress
updated: 2026-05-11
summary: "Login feature"
depends_on: []
auto_linked:
  - meta/mod_auth-api.md
tags: [login, auth, frontend]
aliases: [signin]
---

# Login Feature

## Current State
- 登录页面调用 `POST /api/v1/auth/login`。
- 成功后保存 `access_token` 和 `refresh_token`。
- 后端返回 `expires_in: 900`。

## Key Decisions
- [2026-05-11] 使用机器建议边 `auto_linked`，避免用户手写 depends_on。

## Cross-Module Connection Points

### To mod_auth-api
- **Endpoint**: `POST /api/v1/auth/login`
- **Request**: `{ email: string, password: string }`
- **Response**: `{ access_token: string, refresh_token: string, expires_in: 900 }`

## Open Issues
None.

## Change Log
- [2026-05-11] 登录页面接入 auth API。
```

这里最关键的是两个字段：

```yaml
depends_on: []
auto_linked:
  - meta/mod_auth-api.md
```

### depends_on 是什么？

`depends_on` 是明确确认过的人工/Agent 依赖边。

比如：

```text
feat_checkout depends_on mod_payment
```

意思是：

> checkout 功能需要 payment 模块的信息才能被正确理解。

### auto_linked 是什么？

`auto_linked` 是机器根据自然语言、接口路径、标签、字段等信号自动建议出来的边。

比如用户输入：

> 登录页面已经接好了，调用 POST /api/v1/auth/login。成功后保存 access_token 和 refresh_token。

系统会发现：

- 文本里出现了 `POST /api/v1/auth/login`；
- `mod_auth-api.md` 里也有这个接口；
- 两者都和 `auth / login` 标签相关。

于是它会生成一条候选边：

```text
meta/feat_login.md -> meta/mod_auth-api.md
```

并给出证据：

```text
exact endpoint match: POST /api/v1/auth/login
tag/alias overlap: api, auth, login
```

高置信度的边会进入 `auto_linked`。

最后 Synapse 会生成：

```text
effective_edges = depends_on + auto_linked
```

也就是说，Agent 遍历图的时候用的是完整有效边，但系统仍然保留：

- 哪些边是人工确认的；
- 哪些边是机器建议的；
- 每条边为什么存在。

---

## v0.4 这次重点解决了什么？

Synapse 之前的版本已经有图记忆的基础，但有一个很大的问题：

> 用户是否需要手写 `depends_on`？

如果用户每次都要手写依赖关系，那就不够轻量。

尤其是一人公司场景里，用户已经很忙了，不可能每次记录工程状态时还去维护图边。

所以 v0.4 的目标是：

```text
自然语言输入
  ↓
机器抽取结构化信息
  ↓
机器建议节点与边
  ↓
高置信边进入 auto_linked
  ↓
生成可解释、可遍历的轻量记忆图
```

这次实现的核心链路是：

```text
用户自然语言记录
  ↓
scripts/ingest_memory.py
  ↓
proposal.json
  ↓
scripts/apply_memory_proposal.py
  ↓
meta/*.md 节点更新
  ↓
scripts/generate_memory_map.sh
  ↓
MEMORY_MAP.md / MEMORY_MAP.json
  ↓
Coding Agent 按需加载相关子图
```

---

## 具体工作流

假设我正在做一个 Solo SaaS 项目。

现在登录页面接好了，我只想用自然语言记录一下：

```bash
python scripts/ingest_memory.py \
  --project . \
  --text "登录页面已经接好了，调用 POST /api/v1/auth/login。成功后保存 access_token 和 refresh_token。后端返回 expires_in: 900。"
```

系统会输出一个 proposal，大致类似：

```json
{
  "version": 1,
  "action": "update_node",
  "target_node": "meta/feat_login.md",
  "extracted": {
    "api_endpoints": [
      "POST /api/v1/auth/login"
    ],
    "fields": [
      "access_token",
      "refresh_token",
      "expires_in"
    ],
    "topics": [
      "auth",
      "login"
    ]
  },
  "node_update": {
    "current_state_bullets": [
      "登录页面已经接好了，调用 POST /api/v1/auth/login。成功后保存 access_token 和 refresh_token。后端返回 expires_in: 900。"
    ]
  },
  "edge_candidates": [
    {
      "from": "meta/feat_login.md",
      "to": "meta/mod_auth-api.md",
      "confidence": 10.0,
      "evidence": [
        "exact endpoint match: POST /api/v1/auth/login",
        "tag/alias overlap: api, auth, login"
      ],
      "apply_to": "auto_linked"
    }
  ]
}
```

这一步做了几件事：

1. 判断这条记录应该更新哪个节点；
2. 抽取 API endpoint；
3. 抽取字段；
4. 抽取主题标签；
5. 找出可能相关的模块；
6. 给出依赖边建议；
7. 给出置信度和证据。

然后应用这个 proposal：

```bash
python scripts/apply_memory_proposal.py \
  --project . \
  --proposal proposal.json
```

它会安全更新对应节点：

- 如果节点不存在，就创建；
- 如果节点存在，就追加 Current State；
- 不重复插入已有 bullet；
- 写入 Change Log；
- 把高置信候选边写入 `auto_linked`。

然后可以查看候选边解释：

```bash
bash scripts/suggest_edges.sh --proposal proposal.json
```

输出类似：

```text
Synapse Proposal Edge Suggestions
   (Explainable edges from natural-language memory ingestion)

Suggested edge: meta/feat_login.md -> meta/mod_auth-api.md
   Confidence: 10.0/10
   Evidence:
     - exact endpoint match: POST /api/v1/auth/login
     - tag/alias overlap: api, auth, login
   Action:
     [AUTO] Apply to auto_linked when applying this proposal.
```

最后重建记忆图索引：

```bash
bash scripts/generate_memory_map.sh --full
```

会生成：

```text
MEMORY_MAP.md
MEMORY_MAP.json
```

里面包含：

```text
depends_on
auto_linked
effective_edges
tags
aliases
summary
keywords
blocks
```

其中 `effective_edges` 是核心：

```text
effective_edges = depends_on + auto_linked
```

Agent 以后就可以根据这个图按需加载上下文。

---

## Agent 如何避免塞爆上下文？

Synapse 的检索逻辑不是“把所有记忆都读出来”。

它是分层读取。

### 第 1 层：先读 MEMORY_MAP

`MEMORY_MAP.md` 是自动生成的轻量索引。

它包含：

- Tag Index；
- Keyword Index；
- Status Digest；
- Progress Summary；
- All Active Nodes；
- Topology Health。

当用户问：

> 登录做得怎么样了？

Agent 不需要立刻读所有节点。

它先读 `MEMORY_MAP.md`，通过 tag / alias / keyword 找到：

```text
feat_login.md
```

### 第 2 层：读取目标节点

然后 Agent 读取目标节点：

```text
meta/feat_login.md
```

如果只是问状态，读这一个文件可能就够了。

### 第 3 层：按边读取依赖节点

如果用户问的是跨模块问题，比如：

> 登录接口返回字段改了，会影响前端什么？

Agent 再沿着边读取：

```text
feat_login
  -> mod_auth-api
  -> mod_design-system
```

但它不会无限递归，而是有边界：

```text
depth <= 2
width <= 5
```

这样就实现了：

> 需要什么读什么，不需要的模块不进入上下文。

这对 Coding Agent 很重要。

因为 Agent 的问题不是“没有信息”，而是“相关信息和无关信息混在一起”。

Synapse 做的是上下文路由。

---

## 为什么不是直接用 GraphRAG？

GraphRAG 很强，但它更适合：

- 大规模知识库；
- 企业文档；
- 非结构化语料；
- 复杂语义检索；
- 多跳问答。

但一人公司的工程记忆不是这个问题。

我的真实需求是：

- 记住接口路径；
- 记住字段名；
- 记住模块状态；
- 记住功能做到哪一步；
- 记住模块之间依赖；
- 让 Coding Agent 改代码时别忘上下游影响；
- 不要引入数据库、embedding、向量索引、图数据库。

所以 Synapse 的设计是：

```text
Markdown + Bash/Python + JSON + Git
```

它不追求“智能黑盒”，而是追求：

- 可解释；
- 可维护；
- 可 diff；
- 可手动修；
- 可被 Agent 稳定执行；
- 不依赖复杂服务。

这很适合一人公司。

因为一人公司最怕的是维护一个比项目还复杂的知识系统。

---

## 方法设计：节点、边、索引、检查

### 1. 节点：Markdown 记忆单元

每个节点都是一个 Markdown 文件。

节点有固定结构：

```markdown
## Current State
当前状态

## Key Decisions
关键决策

## Cross-Module Connection Points
跨模块连接点

## Open Issues
未解决问题

## Change Log
变更记录
```

这样 Agent 读节点时，不是读一段散文，而是读结构化工程记忆。

### 2. 边：depends_on + auto_linked

边分两种：

```yaml
depends_on:
  - meta/mod_auth-api.md
```

这是明确确认过的依赖。

```yaml
auto_linked:
  - meta/mod_design-system.md
```

这是机器建议的高置信边。

两者合并为：

```text
effective_edges
```

用于 Agent 遍历。

### 3. 索引：MEMORY_MAP

`MEMORY_MAP.md` 是人类和 Agent 都能读的索引。

`MEMORY_MAP.json` 是机器可读镜像。

它们由脚本生成，不手写。

```bash
bash scripts/generate_memory_map.sh --full
```

### 4. 检查：doctor

为了避免图坏掉，v0.4 增加了健康检查：

```bash
bash scripts/doctor.sh --project .
```

它会检查：

- `meta/` 是否存在；
- frontmatter 是否完整；
- `depends_on` 是否有死链；
- `auto_linked` 是否有死链。

这对长期维护很重要。

否则图记忆很容易变成另一种形式的技术债。

---

## 部署方法

### 方式一：直接在项目里使用

项目结构建议：

```text
your-project/
  meta/
    mod_project.md
    mod_auth-api.md
    feat_login.md
  scripts/
    ingest_memory.py
    apply_memory_proposal.py
    suggest_edges.sh
    generate_memory_map.sh
    doctor.sh
  MEMORY_MAP.md
  MEMORY_MAP.json
```

初始化：

```bash
mkdir -p meta/archive scripts
```

然后复制 Synapse 脚本到 `scripts/`。

首次生成索引：

```bash
bash scripts/generate_memory_map.sh --full
```

健康检查：

```bash
bash scripts/doctor.sh --project .
```

### 方式二：使用 init 脚本

如果项目里已经安装 Synapse skill，可以运行：

```bash
bash .claude/skills/synapse-graph-memory/scripts/init.sh
```

它会自动：

- 创建 `meta/`；
- 推断项目模块；
- 生成初始节点；
- 拷贝脚本；
- 注册 hooks；
- 生成 `MEMORY_MAP.md`。

### 方式三：配合 Claude Code / Codex 使用

推荐工作流是：

1. 用户自然语言记录工程状态；
2. Agent 调用 `ingest_memory.py`；
3. 用户或 Agent 查看 proposal；
4. Agent 调用 `apply_memory_proposal.py`；
5. 生成 `MEMORY_MAP`；
6. 后续任务开始时，Agent 先读 `MEMORY_MAP`，再按图加载节点。

例如：

```bash
python scripts/ingest_memory.py \
  --project . \
  --text "新增仪表盘页面 /dashboard，包含 MetricCard 和 ActivityFeed 两个组件。"
```

如果没有对应节点，系统会建议创建：

```text
meta/feat_dashboard.md
```

并抽取：

```json
{
  "routes": ["/dashboard"],
  "components": ["MetricCard", "ActivityFeed"],
  "topics": ["dashboard"]
}
```

---

## 当前 v0.4 达到了什么程度？

现在 v0.4 已经不是概念设计，而是一个可以真实试用的 stable-MVP。

已经实现：

| 能力 | 状态 |
|---|---|
| 自然语言输入工程记忆 | 已实现 |
| 自动抽取 API、字段、路由、组件、主题 | 已实现基础版 |
| 自动判断目标节点 | 已实现基础版 |
| 自动生成候选依赖边 | 已实现 |
| 边带置信度和证据 | 已实现 |
| 高置信边写入 `auto_linked` | 已实现 |
| 生成 `effective_edges` 给 Agent 遍历 | 已实现 |
| Markdown 节点更新 | 已实现 |
| 去重状态记录 | 已实现 |
| Change Log 写入 | 已实现 |
| 健康检查 | 已实现 |
| 示例项目 | 已实现 |
| 单元测试 | 已实现 |

我会把它定位为：

```text
可用于个人真实项目试跑的 v0.4 alpha / stable-MVP
```

还不是成熟商业产品，但已经能验证核心价值。

---

## 还没解决的问题

这个版本仍然有一些限制。

### 1. 抽取规则还偏基础

现在主要依赖：

- API endpoint 正则；
- 字段名规则；
- 组件名规则；
- 路由规则；
- topic aliases；
- tag/alias overlap。

还不是 LLM 级别的复杂理解。

但好处是可解释、稳定、无依赖。

### 2. 节点合并还不够智能

如果用户频繁输入自然语言，可能会产生一些重复或过细节点。

后面需要做：

- 节点合并建议；
- 过小节点提示；
- 过大节点拆分建议。

### 3. 边确认体验还可以更好

目前是命令行 proposal。

未来可以做：

```text
[接受 auto_linked]
[提升为 depends_on]
[忽略]
[加入 Open Issues]
```

类似一个轻量 review UI。

### 4. 还没有完整产品化 UI

目前更适合开发者、Agent、命令行环境。

如果面向普通用户，还需要更好的交互界面。

---

## 为什么我觉得这个方向适合一人公司？

因为一人公司的核心需求不是“知识管理”，而是“工程连续性”。

普通知识管理关心：

> 我知道了什么？

工程记忆关心：

> 当前项目状态是什么？  
> 哪些模块依赖哪些模块？  
> Agent 现在改这个文件会影响谁？  
> 下次继续做时，需要加载哪些上下文？

Synapse 的价值不是替代 Notion，也不是替代 README。

它更像是 Coding Agent 的项目记忆层。

它解决的是：

```text
人类自然语言记录
  ↓
机器结构化整理
  ↓
Agent 按需读取
  ↓
避免上下文爆炸
  ↓
保持工程连续性
```

这对一人公司特别重要。

因为一个人不可能每天都完整记住：

- 每个接口；
- 每个字段；
- 每个历史决策；
- 每个模块依赖；
- 每个 Agent 上次做到哪一步。

但如果这些都能沉淀成一个轻量记忆图，Agent 就可以成为真正的长期协作者，而不是每次都从零开始的临时助手。

---

## 一个最小示例

假设有三个节点：

```text
meta/
  mod_auth-api.md
  mod_design-system.md
  feat_login.md
```

`feat_login.md` 里有：

```yaml
auto_linked:
  - meta/mod_auth-api.md
  - meta/mod_design-system.md
```

当用户问：

> 登录页面继续做，看看还缺什么。

Agent 的理想读取路径是：

```text
1. 读 MEMORY_MAP.md
2. 找到 feat_login
3. 读 feat_login.md
4. 根据 effective_edges 读取 mod_auth-api.md 和 mod_design-system.md
5. 回答当前状态和下一步
```

它不会去读支付模块、数据库迁移、部署文档。

这就是按需上下文加载。

---

## 总结

Synapse v0.4 的核心不是“做一个很炫的图谱”，而是解决一个非常实际的问题：

> 一个人做项目，如何让 Coding Agent 稳定记住工程状态和模块依赖，同时不把上下文塞爆？

它的答案是：

```text
自然语言输入
  +
结构化 Markdown 节点
  +
可解释 Auto-Link
  +
MEMORY_MAP 索引
  +
bounded BFS 按需遍历
```

对于一人公司来说，它的价值在于：

- 不要求用户维护复杂图谱；
- 不要求部署向量数据库；
- 不要求搭建 GraphRAG；
- 不要求每次手写 depends_on；
- 只需要自然语言记录工程状态；
- 系统自动抽取、建议、更新、检查；
- Coding Agent 后续按图加载上下文。

我认为这类工具未来会成为 Coding Agent 工作流里的一个基础层：

```text
代码仓库负责保存代码；
Git 负责保存变更历史；
Issue 系统负责保存任务；
Synapse 负责保存 Agent 可用的工程上下文和模块依赖。
```

对于一人公司，这可能比重型知识库更实用。

因为它不追求管理所有知识，只追求一件事：

> 让 Agent 下次继续干活时，知道现在项目到底是什么状态。
