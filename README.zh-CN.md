# Synapse

<p align="center">
  <img src="docs/images/synapse-logo.png" alt="Synapse" width="200"><br>
  <em>基于图拓扑的 AI Agent 分区记忆系统</em>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache%202.0-blue.svg" alt="License"></a>
</p>

---

## 这是什么？

Synapse 是一套图拓扑记忆系统。每个 Markdown 节点通过 frontmatter 中的 `depends_on` 字段声明跨模块依赖关系。Agent 只遍历与当前任务相关的子图——通过有界 BFS 遍历（depth ≤ 2, width ≤ 5），除此之外什么都不加载。

> **核心机制**：通过图拓扑实现上下文的分区加载，在保持信息完整性的同时消除跨域噪音。

> **实测数据**：7 类任务平均减少 73% 记忆 Token 消耗（每次加载 2-5 个节点 vs 扁平方案的全部 ~2,600 tokens）。跨模块上下文零丢失。[完整报告 →](USAGE.md#testing--benchmarking)

如果说 RecallLoom 回答的是「发生了什么」，Synapse 回答的是「我现在需要知道什么」。

---

## 解决什么问题？

扁平记忆文件（RecallLoom 风格）在中小项目里完全够用。但项目一旦膨胀——前端、后端、数据库、鉴权、支付——那个 `rolling_summary.md` 就会变成垃圾场。Agent 只想修个按钮颜色，却被迫把数据库表结构也塞进上下文。

**这就是扁平记忆的信息密度超载。**

Synapse 把记忆组织成图来解决这个问题。Agent 通过有界 BFS 只加载相关子图，不扫全量。
> [ `docs/images/Synapse.png`]
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

> [ `docs/images/synapse-architecture.png`]

---

## 工作原理

### LLM 上下文管理中的三个 CS 原语

| Synapse 概念 | CS 原语 | 为什么有效 |
|---|---|---|
| `MEMORY_MAP` + 标签索引 | **倒排索引** | O(1) 查找，不扫全表 |
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

## 快速开始

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
depends_on: []
blocks: []
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
│   ├── generate_memory_map.sh ← 索引生成器 + 拓扑校验器
│   └── hooks/
│       ├── post-tool-use.sh   ← 编辑后即时校验
│       └── session-end.sh     ← 会话结束自动重建
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
