# Synapse

<p align="center">
  <img src="docs/images/Synapse.png" alt="Synapse" width="200"><br>
  <em>基于图拓扑的 AI Agent 分区记忆系统</em>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-blue.svg" alt="License"></a>
</p>

---

## 这是什么？

Synapse 是一套图拓扑记忆系统。每个 Markdown 节点通过 frontmatter 中的 `depends_on` 字段声明跨模块依赖关系。Agent 只遍历与当前任务相关的子图——通过有界 BFS 遍历（depth ≤ 2, width ≤ 5），除此之外什么都不加载。

> **核心机制**：通过图拓扑实现上下文的分区加载，配合渐进式披露——先通过摘要筛选确认相关性，再加载完整节点——在保持信息完整性的同时消除跨域噪音。

> **实测数据（合成场景）**：在 10 模块项目上,8 类模拟任务相对"朴素全量加载"基线平均减少约 71% Token 消耗（每次约加载 ~750 tokens vs 扁平方案 ~2,600 tokens）。若改用"智能扁平"基线（搜索后只读相关段落），减少幅度约 46%。模拟过程中跨模块上下文零丢失。可通过 `bash scripts/benchmark.sh setup && bash scripts/benchmark.sh run` 复现。[完整报告 →](USAGE.md#testing--benchmarking)

如果说 RecallLoom 回答的是「发生了什么」，Synapse 回答的是「我现在需要知道什么」。

---

## 解决什么问题？

扁平记忆文件（RecallLoom 风格）在中小项目里完全够用。但项目一旦膨胀——前端、后端、数据库、鉴权、支付——那个 `rolling_summary.md` 就会变成垃圾场。Agent 只想修个按钮颜色，却被迫把数据库表结构也塞进上下文。

**这就是扁平记忆的信息密度超载。**

Synapse 把记忆组织成图来解决这个问题。Agent 通过有界 BFS 只加载相关子图，不扫全量。

---

## 架构

```
                    ┌─────────────────────┐
                    │    MEMORY_MAP.md     │  ← 自动生成的标签索引（O(1) 查找）
                    │  （请勿手工编辑）      │
                    └────────┬────────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
     ┌────────────┐  ┌────────────┐  ┌────────────┐
     │ mod_auth   │  │ feat_login │  │ mod_db     │
     │ -api.md    │◄─┤ .md         ├─►│ -schema.md │
     └──────┬─────┘  └────────────┘  └────────────┘
            │
            │  depends_on / blocks（脚本自动反推的入度）
            │
     ┌──────▼─────┐
     │ feat_oauth │
     │ .md        │
     └────────────┘
```

<p align="center">
  <img src="docs/images/synapse-architecture.png" alt="Synapse 架构" width="720">
</p>

---

## 工作原理

### LLM 上下文管理中的三个 CS 原语

| Synapse 概念 | CS 原语 | 为什么有效 |
|---|---|---|
| `MEMORY_MAP` + 标签索引 | **倒排索引** | O(1) 查找，不扫全表 |
| `MEMORY_MAP` + 关键词索引 | **语义回退** | 标签同义词或超限时，关键词匹配兜底 |
| 节点 `summary` 字段 | **渐进式披露 Layer 1** | 先读摘要确认相关性，再加载完整节点 |
| 按领域拆分节点、按需加载 | **数据库规范化** | 消除冗余，隔离无关数据 |
| `depends_on` 边 + 有界 BFS 遍历 | **外键引用** | 确定性路由——不靠语义相似度猜测 |

### 节点类型

| 前缀 | 类型 | 生命周期 |
|---|---|---|
| `mod_` | 持久架构模块 | 永远活跃（路由、状态管理、数据库结构） |
| `feat_` | 生命周期功能 | 进行中 → 稳定 → 归档 |

### 查询路由

| 用户说... | 模式 | 读取 |
|---|---|---|
| "咱们做的咋样了" | **Status Digest** | 只读 `MEMORY_MAP.md` (~200 tokens) |
| "还有什么没做完" | **Status Digest** | 同上，过滤 `in-progress` |
| "登录做得怎么样了" | **Bounded BFS** | `feat_login.md` + 依赖 |
| "FastAPI 接口写完没" | **Bounded BFS** | `mod_auth-api.md` + 依赖 |
| "支付超时怎么改" | **Bounded BFS + Impact** | 目标 + 依赖 + 下游契约 |

**Status Digest** 是 `MEMORY_MAP.md` 中自动生成的一个轻量级段落——每个节点一行，包含状态、最近更新、待解决问题数。用户问"项目怎么样了"时，Agent 只读这一段就能回答，不需要加载任何完整节点。

**触发模式**：Agent 检测到"XX做得怎么样了"/"XX的状态"/"继续做XX"等短语时，在回答之前自动执行记忆查找。

---

## 0.4.0 新增功能

| 功能 | 解决了什么 |
|---|---|
| **自然语言记忆写入** | `scripts/ingest_memory.py` 把普通工程记录转换成结构化 proposal：目标节点、抽取出的接口/字段/组件、节点更新和候选边 |
| **安全 proposal 应用器** | `scripts/apply_memory_proposal.py` 创建或更新 Markdown 节点，去重 Current State 条目，写入 Change Log，并把高置信机器边写入 `auto_linked` |
| **可解释候选边** | `scripts/suggest_edges.sh --proposal proposal.json` 输出候选边、置信度和证据，例如 exact endpoint match |
| **有效图边** | `MEMORY_MAP.md` 与 `MEMORY_MAP.json` 暴露 `effective_edges = depends_on + auto_linked`，同时保留显式边和机器建议边的区别 |
| **Doctor 健康检查** | `scripts/doctor.sh --project .` 在交付前检查 frontmatter、死 `depends_on` 和死 `auto_linked` 链接 |

## 0.3.0 新增功能

| 功能 | 解决了什么 |
|---|---|
| **复合查询的 Filtered BFS** | 形如「上周支付模块的鉴权改了什么」的查询会被分解为时间 + 领域 + 子领域 + 动作四个维度，BFS 只沿同时命中所有维度的边推进，不再加载整个支付子图 |
| **会话结束 Progress Summary** | `session-end.sh` 输出结构化摘要：本次触及的节点、frontmatter 变更、源码→记忆漂移提示，替代 Agent 自由发挥的总结文本 |
| **标签别名 (aliases)** | frontmatter 新增 `aliases:` 字段（如 `[auth, login, signin]`），用户问「登录」也能命中规范标签为 `auth` 的 `mod_auth-api` 节点，消除「标签写错就检索不到」的失败模式 |
| **`pre-read-check.sh` Hook** | 每次 `Read meta/*.md` 前强制执行 BFS 预算（depth ≤ 2, width ≤ 5）。超限时在 read 返回前注入提醒——协议不再可能被静默违反 |
| **`pre-modify-check.sh` Hook** | 任何 `Write`/`Edit` 源文件之前，扫描所有引用该文件的记忆节点，把它们的 `blocks`（下游消费者）列表推送给 Agent，让修改在完整影响面认知下进行 |
| **`init.sh` 冷启动向导** | 自动识别技术栈、推断模块边界、生成 `mod_*.md` 骨架、安装 hooks、注册 `.claude/settings.json`。从零到可用图，一条命令搞定 |

---

## 快速开始

> **运行环境要求**：bash 4+(macOS 自带 3.2，需 `brew install bash`)、`awk`、`grep`、`sed`。可选 `jq`（用于 `parse-session.sh` 完整 BFS 审计）。

### 方式 A —— 一键向导（推荐）

```bash
bash .claude/skills/synapse-graph-memory/scripts/init.sh
```

`init.sh` 会自动识别技术栈（Node/Go/Python/Rust/Java）和数据库，从目录结构（`src/api`、`src/auth`、`src/db` …）推断模块边界，生成 `mod_project.md` 和各模块骨架，拷贝 hooks 以及 v0.4 工作流脚本（`ingest_memory.py`、`apply_memory_proposal.py`、`suggest_edges.sh`、`doctor.sh`），注册到 `.claude/settings.json`，并构建首个 `MEMORY_MAP.md`。可重复运行：已存在的节点会被跳过，不会被覆盖。

### 自然语言工作流

```bash
python scripts/ingest_memory.py --project . --text "登录页面已经接好了，调用 POST /api/v1/auth/login。成功后保存 access_token 和 refresh_token。"
python scripts/apply_memory_proposal.py --project . --proposal proposal.json
bash scripts/suggest_edges.sh --proposal proposal.json
bash scripts/doctor.sh --project .
```

`examples/solo-saas/` 提供了一个前端登录 + Auth API + 设计系统的轻量示例，展示用户只写自然语言，机器生成 `auto_linked` 边。

### 方式 B —— 手动安装

```bash
# 1. 初始化
mkdir -p meta/archive scripts

# 2. 复制生成脚本
cp .claude/skills/synapse-graph-memory/scripts/generate_memory_map.sh scripts/
chmod +x scripts/generate_memory_map.sh

# 3. 创建第一个模块节点
cat > meta/mod_project.md << 'EOF'
---
id: mod_project
type: module
status: in-progress
updated: $(date +%Y-%m-%d)
summary: "项目总览和架构决策。新会话的入口点。"
depends_on: []
tags: [project, overview]
---

# 项目总览

## Current State
[描述项目架构。精确值（路径、版本号、配置）必须逐字保留。]

## Key Decisions
- 决策 — 理由

## Cross-Module Connection Points
暂无。

## Open Issues
暂无。

## Change Log
- 初始化
EOF

# 4. 生成索引
./scripts/generate_memory_map.sh

# 5. 安装 pre-commit hook
echo '#!/bin/sh' > .git/hooks/pre-commit
echo 'scripts/generate_memory_map.sh' >> .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

---

## Synapse vs RecallLoom

| | RecallLoom（扁平） | Synapse（图） |
|---|---|---|
| **适用场景** | 小项目、单领域 | 多领域项目、10+ 模块 |
| **上下文纯净度** | 低——所有内容挤在一起 | 高——只加载相关子图 |
| **接入成本** | 几乎为零 | 约 5 分钟 |
| **跨模块协作** | 所有上下文始终加载 | 沿边遍历找到相关节点 |
| **风险** | Token 浪费，噪音引发幻觉 | hook 配置错误会导致图腐化（默认自动执行） |
| **学习曲线** | 无 | 7 步检索协议 |

> **两者互补，不是替代。** 原型阶段用 RecallLoom 快速启动。跨域噪音变得不可忽视时，平滑迁移到 Synapse。

---

## 文件结构

```
project/
├── MEMORY_MAP.md              ← 自动生成的索引（请勿编辑）
├── meta/
│   ├── mod_*.md               ← 持久模块节点
│   ├── feat_*.md              ← 功能节点（进行中/稳定）
│   └── archive/               ← 已归档功能
├── scripts/
│   ├── generate_memory_map.sh ← 索引生成器 + 拓扑校验器 + JSON 镜像
│   ├── ingest_memory.py       ← 自然语言记录 → 结构化 proposal
│   ├── apply_memory_proposal.py ← 安全应用 proposal，更新节点 + auto_linked
│   ├── suggest_edges.sh       ← 自动检测依赖边，并解释 proposal 候选边
│   ├── doctor.sh              ← frontmatter 与图链接健康检查
│   ├── init.sh                ← 一键冷启动向导
│   ├── benchmark.sh           ← Token 效率模拟（Synapse vs 扁平）
│   └── hooks/
│       ├── pre-read-check.sh   ← 每次 Read 前强制 BFS 预算（depth ≤ 2, width ≤ 5）
│       ├── pre-modify-check.sh ← Write/Edit 源文件前推送下游消费者
│       ├── post-tool-use.sh    ← 编辑后即时校验
│       └── session-end.sh      ← 会话结束自动重建
├── .claude/
│   ├── settings.json          ← hook 注册配置
│   └── skills/synapse-graph-memory/
└── .git/hooks/pre-commit      ← commit 时自动重建索引
```

---

## Hooks：基础设施层强制执行

Synapse 使用 Claude Code hooks **自动保障记忆完整性**——不需要 Agent 自觉遵守。

| Hook | 触发时机 | 做什么 |
|---|---|---|
| `pre-read-check.sh` | 每次 `Read` `meta/*.md` 之前 | 跟踪连续节点加载次数，超出 BFS 预算（depth ≤ 2, width ≤ 5）时注入提醒，强制 Agent 回到目标子图 |
| `pre-modify-check.sh` | 每次 `Write`/`Edit` 修改非 `meta/` 源文件前 | 扫描引用该文件的记忆节点，列出其 `blocks`（下游消费者），让 Agent 在完整影响面认知下编辑 |
| `post-tool-use.sh` | 每次 `Write`/`Edit` 修改 `meta/*.md` 后 | 校验 frontmatter 完整、检查 `depends_on` 目标存在、验证 `updated` 字段 |
| `session-end.sh` | 会话结束时 | 重建 `MEMORY_MAP.md`、拓扑校验、输出变更摘要、标记源码→记忆漂移 |

配置在 `.claude/settings.json`。Agent 不需要记得会话收尾——hook 保证它一定发生。

## 配套 Skill

本项目配套的 `synapse-graph-memory` Skill 位于 `.claude/skills/synapse-graph-memory/SKILL.md`。加载到 Agent 中后，Agent 会自动强制执行检索协议、保真度规则和清理工作流。

详细使用说明见 [USAGE.md](USAGE.md)。

---

## 许可证

Apache 2.0 © 2026

---

## 相关项目

- [RecallLoom](https://github.com/Frappucc1no/RecallLoom) — 扁平记忆系统，适用于小型项目（Synapse 的前身）
- [Microsoft GraphRAG](https://github.com/microsoft/graphrag) — 企业级图谱检索（理论基础来源）
