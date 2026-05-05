# Synapse 待改进项

> 基于 ClaudeMem 对比调研后的务实改进计划，按投入产出比排序

---

## 🥇 第一优先：低投入、高回报

### 1. 轻量级语义回退 —— 解决标签脆弱性

**问题**：标签作为唯一发现机制，同一概念可能用不同标签（`auth` vs `authentication` vs `login`），同一标签可能匹配过多节点导致宽度超限。

**思路**：在 `generate_memory_map.sh` 中额外生成 TF-IDF 关键词索引。标签匹配失败或超限时回退到关键词匹配。不需要引入向量数据库。

**关键词提取规则**：
- API 路径：`POST /api/v1/auth/refresh`
- 函数/方法名：`validate_token()`
- 表名：`users`, `refresh_tokens`
- 配置键：`TOKEN_EXPIRY`, `JWT_SECRET`

**落地文件**：`scripts/generate_memory_map.sh` 增加关键词提取 + `MEMORY_MAP.md` 增加 `## Keyword Index` 章节

**状态**：✅ 已完成（Claude-Mem 启发：混合检索，关键词作为标签的同义词回退）

---

### 2. BFS 协议运行时守卫 —— 解决合规性不可验证

**问题**：Agent 可以不遵守 BFS 协议直接暴力读所有 meta/*.md，故障完全静默。

**思路**：写一个 PreToolUse 钩子，当 Agent 连续读取 meta/ 文件时注入提醒。不阻断，只提醒。

```bash
# scripts/hooks/pre-read-check.sh
# 检测连续 Read meta/ 文件超过阈值时触发
```

**落地文件**：`scripts/hooks/pre-read-check.sh` + `.claude/settings.json` 增加 PreToolUse 钩子配置

**提醒内容**：
```
⚠ Synapse: 已加载 N 个记忆节点。请确认是否在按 BFS 协议遍历？
   预期：目标节点 + depends_on (depth≤2, width≤5)
```

**状态**：✅ 已完成（v0.3.0 落地为 pre-read-check.sh：连续读取 meta/ 触发 BFS 协议提醒；配套 pre-modify-check.sh 在 Write/Edit 源文件前推送下游影响面）

---

## 🥈 第二优先：中等投入、结构性改善

### 3. 边的自动建议脚本 —— 缓解边维护负担

**问题**：Agent 手动声明所有 depends_on，维护成本 O(N²)，边漂移是必然收敛状态。

**思路**：写 `scripts/suggest_edges.sh`，从节点内容中自动检测可能的依赖关系。

**检测规则**：
- 在节点 A 的 Connection Points 中提取 API 路径（如 `POST /api/v1/auth/session`）
- 在其他节点中搜索谁引用了同一 API 路径
- 递归检测概念关键词的交叉引用

**输出示例**：
```
💡 建议添加边: feat_checkout depends_on meta/mod_auth-api.md
   原因: feat_checkout 的 Connection Points 引用了 POST /api/v1/auth/session
💡 建议添加边: feat_user-profile depends_on meta/mod_auth-api.md
   原因: feat_user-profile 的 Connection Points 引用了 GET /api/v1/auth/session
```

Agent 的职责从"凭空创造边"变成"确认/拒绝系统建议"。

**落地文件**：`scripts/suggest_edges.sh`

---

### 4. MEMORY_MAP 双格式冗余 —— 解决脚本解析脆弱性

**问题**：`generate_memory_map.sh` 用 awk/sed 手写 YAML 解析器，对 frontmatter 格式错误极不宽容。MAP 一旦损坏就是单点故障。

**思路**：同时输出 `MEMORY_MAP.json` 作为程序化验证用：

```
MEMORY_MAP.md  → 给人读 + 给 Agent 读（保留现有行为）
MEMORY_MAP.json → 给脚本内部验证用（新增）
```

如果 Markdown 解析失败可回退到 JSON。JSON 解析也失败则说明 frontmatter 有严重问题。

**落地文件**：`scripts/generate_memory_map.sh` 增加 JSON 输出

---

## 🥉 第三优先：体验性改善

### 5. 冷启动一键向导

**问题**：Synapse 需要先创建目录、先创建节点、先运行脚本——见到价值前需要相当的投资。

**思路**：写 `scripts/init.sh`，自动检测项目并生成初始图：

```bash
# 自动检测
- 从 package.json/go.mod/pyproject.toml 检测技术栈
- 从目录结构（src/api/, src/components/, src/db/）推断模块划分
- 生成初始 mod_project.md + 模块骨架节点
- 自动运行 generate_memory_map.sh
```

**落地文件**：`scripts/init.sh`

---

### 6. 更公平的 benchmark

**问题**：当前 benchmark 假设 flat 模式 Agent 读取整个文件。实际 Agent 可以先 grep 再选择性读。

**思路**：在 benchmark 中增加"智能 flat"模拟——Agent 先按关键词筛选再读相关段落。让对比更诚实。

**落地文件**：`scripts/benchmark.sh` 增加智能 flat 对比模式

---

---

## 🆕 Claude-Mem 启发的新改进（本次已完成）

### 7. 渐进式披露检索协议

**启发来源**：Claude-Mem 的三层 Progressive Disclosure（Session Priming → Search Index → Full Details）

**问题**：Synapse 的 Agent 在 Layer 1（读 MAP）后直接跳到 Layer 2（读完整 Node），没有中间摘要层。对于大节点（150 行，~1500 tokens），Agent 在确认相关性前就已经付出了高成本。

**方案**：给每个 Node frontmatter 增加 `summary` 字段（1-2 句话）。MEMORY_MAP.md 的 Status Digest 和 Tag Index 都展示 summary。检索协议升级为三层：
- Layer 1: MAP triage — 读 summary + token 估算，确认相关性
- Layer 2: 读完整 Node — 只有在确认相关后才加载
- Layer 3: Bounded BFS deps — 按需展开

**落地文件**：`SKILL.md` 检索协议升级 + `template.md` frontmatter 增加 summary

**状态**：✅ 已完成

---

### 8. Token 成本可见性

**启发来源**：Claude-Mem 的 "Context is currency" 设计原则

**问题**：Agent 不知道加载一个节点要多少 token，无法做成本感知的检索决策。

**方案**：`generate_memory_map.sh` 计算每个节点的 `wc -c / 4` token 估算，在 MEMORY_MAP.md 的每个节点条目中标注 `~N tok`。

**落地文件**：`scripts/generate_memory_map.sh`

**状态**：✅ 已完成

---

### 9. Observation 格式的 Change Log

**启发来源**：Claude-Mem 的 Observation 模型（自动捕获 context/change/impact）

**问题**：当前 Change Log 是扁平列表（"2026-05-01 加了登录"），丢失了因果链。Agent 无法回答"为什么当时这么设计"或"改了什么影响"。

**方案**：Change Log 改为结构化 Observation 格式：
```markdown
- [YYYY-MM-DD] **Context**: [背景]
  **Change**: [做了什么]
  **Impact**: [影响了什么]
  **Affected**: [受影响的模块]
```

**落地文件**：`template.md`

**状态**：✅ 已完成

---

## 💎 改进总览

| 改进 | 解决的问题 | 难度 | 改动范围 | 状态 |
|------|-----------|------|---------|------|
| 关键词回退索引 | 标签脆弱性 | 🟢 低 | generate_memory_map.sh | ✅ 已完成 |
| PreToolUse 协议守卫 | 合规性不可测 | 🟢 低 | 新增 hook + settings.json | ✅ 已完成（pre-read-check.sh 强制三层渐进式披露 + pre-modify-check.sh 修改前影响面提示） |
| 边的自动建议 | 维护负担 | 🟡 中 | 新增 suggest_edges.sh | ✅ 已完成 |
| MAP 双格式冗余 | 单点故障 | 🟡 中 | generate_memory_map.sh | ✅ 已完成 |
| 冷启动向导 | 采用率 | 🟡 中 | 新增 init.sh | ✅ 已完成 |
| 更公平的 benchmark | 方法论证 | 🟢 低 | benchmark.sh | ✅ 已完成 |
| **渐进式披露检索协议** | 大节点加载成本高 | 🟢 低 | SKILL.md + template.md | ✅ 已完成 |
| **Token 成本可见性** | 检索无成本意识 | 🟢 低 | generate_memory_map.sh | ✅ 已完成 |
| **Observation 格式 Change Log** | 因果链丢失 | 🟢 低 | template.md | ✅ 已完成 |
