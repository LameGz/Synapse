# Changelog

All notable changes to Synapse Graph Memory System.

## [0.3.0] — 2026-05-04

> 投稿前工程补全：Filtered BFS 索引层落地、读取侧运行时强制、跨平台兼容、设置自动合并、标签解析修复。

---

### P0：立即做

#### 1. Change Log 时间索引（`generate_memory_map.sh`）

**问题**：Filtered BFS 协议要求"按时间窗口过滤 Change Log"，但 0.2.1 版本仅在 SKILL.md 中描述协议，索引层（MEMORY_MAP）没有任何时间维度的数据结构——Agent 必须在 Layer 2 读完节点全文后自行用日期匹配。

**解决**：
- 新增 `extract_changelog_entries()`：用 awk 扫描每个节点的 `## Change Log` section，提取 `[YYYY-MM-DD]` 日期 + 第一行摘要
- 新增 `CHANGELOG_INDEX` 关联数组：按 `YYYY-MM` 月份分桶，建立时间倒排索引
- `MEMORY_MAP.md` 新增 `## Change Log Index` 章节，按月分组、日期倒序排列
- `MEMORY_MAP.json` 每个节点新增 `changelog: [{date, summary}]` 数组
- 统计输出增加 `${#CHANGELOG_INDEX[@]} change-log months`

**改动文件**：
- `.claude/skills/synapse-graph-memory/scripts/generate_memory_map.sh`
- `scripts/generate_memory_map.sh`

---

#### 2. 读取侧 PreToolUse 强制 hook（`pre-read-check.sh`）

**问题**：BFS 检索协议要求 Agent 先读 `MEMORY_MAP.md`（Layer 1）再读节点文件（Layer 2），但完全依赖 Agent 自律——没有运行时强制手段。

**解决**：新增 `pre-read-check.sh`，注册为 `PreToolUse` hook（matcher: `Read`）：
- 当 Agent 准备 Read `meta/*.md` 节点文件时，检查 `.claude/.synapse_cache/.map_read` marker 是否存在
- 如果 Read 的是 `MEMORY_MAP.md` → touch marker 并放行
- 如果 marker 不存在 → inject 协议警告到上下文，提示 Agent 先读 MAP
- `session-end.sh` 新增 marker 清理逻辑，确保每次新会话从零开始
- `settings.json` / `settings.template.json` 同步注册新 hook

**改动文件**：
- `.claude/skills/synapse-graph-memory/scripts/hooks/pre-read-check.sh`（新增）
- `scripts/hooks/pre-read-check.sh`（同步）
- `.claude/skills/synapse-graph-memory/scripts/hooks/session-end.sh`（marker 清理）
- `scripts/hooks/session-end.sh`（同步）
- `.claude/skills/synapse-graph-memory/settings.template.json`（注册 Read hook）
- `.claude/settings.json`（注册 Read hook）

---

#### 3. init.sh macOS 兼容

**问题**：`init.sh` 使用 GNU sed 扩展 `\u`（首字母大写），macOS 默认的 BSD sed 不支持，导致模块名首字母无法大写。

**解决**：将 `sed 's/.*/\u&/'` 替换为 POSIX 标准的 `awk '{print toupper(substr($0,1,1)) substr($0,2)}'`，两处均更新。

**改动文件**：
- `.claude/skills/synapse-graph-memory/scripts/init.sh`
- `scripts/init.sh`

---

#### 4. init.sh settings.json 自动合并

**问题**：`init.sh` 仅在 `.claude/settings.json` 不存在时复制模板；如果用户已有 settings 文件（常见），只会 print 一句"请手动 merge"然后跳过——所谓"一键初始化"名不副实。

**解决**：新增 `merge_settings()` 函数：
- 检测 `python3` 可用性
- 用 Python json 模块做 deep merge：遍历 template 的 hooks，按 `command` 字符串去重，追加到现有 settings
- 如果 merge 成功 → 输出确认；如果 `python3` 不可用 → fallback 到提示手动 merge

**改动文件**：
- `.claude/skills/synapse-graph-memory/scripts/init.sh`
- `scripts/init.sh`

---

#### 5. suggest_edges.sh 多行 tags 解析

**问题**：`suggest_edges.sh` 的 `collect_node_metadata` 解析 tags 时只用了 `sed -n 's/^tags:[[:space:]]*//p'`，仅能识别 inline 格式 `tags: [a, b]`；YAML 多行 list（`tags:\n  - a\n  - b`）会被静默忽略，导致 tag-based 弱信号边建议完全失效。

**解决**：新增 `extract_list_items()` 函数（与 `generate_memory_map.sh` 的 `extract_list` 逻辑一致）：
- 先尝试 inline 格式匹配
- fallback 到多行 YAML list 解析
- `collect_node_metadata` 替换为 `extract_list_items "tags" "$fm"`

**改动文件**：
- `.claude/skills/synapse-graph-memory/scripts/suggest_edges.sh`
- `scripts/suggest_edges.sh`

---

### 改动总览

| 优先级 | 修改项 | 解决的问题 | 改动文件 |
|--------|--------|-----------|----------|
| 🔴 P0 | Change Log 时间索引 | Filtered BFS 无索引支撑 | `generate_memory_map.sh` (×2) |
| 🔴 P0 | 读取侧 PreToolUse 强制 | BFS 协议无运行时强制 | `pre-read-check.sh` (新, ×2), `session-end.sh` (×2), settings (×2) |
| 🔴 P0 | init.sh macOS 兼容 | BSD sed 不支持 `\u` | `init.sh` (×2) |
| 🔴 P0 | settings.json 自动合并 | 已有 settings 时初始化失败 | `init.sh` (×2) |
| 🔴 P0 | suggest_edges tags 修复 | 多行 YAML tags 静默失效 | `suggest_edges.sh` (×2) |

---

## [0.2.1] — 2026-05-04

> 基于 SessionEnd hook 的自动化依赖推断、增量 MAP 重建、aliases 多语言同义词检索、复合查询 Filtered BFS、以及聚合进度摘要——五项 P0 级可用性改进。

---

### P0：立即做（检索效率与运维自动化）

#### 1. 半自动依赖推断（`session-end.sh`）

**问题**：`depends_on` 全靠手工维护，30+ 模块时 O(N²) 潜在边数不可持续。

**解决**：在 `session-end.sh` Step 2 与 Step 3 之间新增 **co-read 分析**（Step 2.5）：
- 扫描本次会话中 `git diff` 检测到的所有变更/新增节点文件对
- 对没有 `depends_on` 边的节点对，检查双方正文是否互相引用对方的 `id`
- 双向引用则标记为候选依赖，输出到会话结束报告
- 纯 grep 字符串匹配，零新依赖

**改动文件**：
- `.claude/skills/synapse-graph-memory/scripts/hooks/session-end.sh`（新增 Step 2.5 co-read 分析）
- `scripts/hooks/session-end.sh`（同步更新）

---

#### 2. 增量 MAP 更新（`generate_memory_map.sh`）

**问题**：每次 `session-end` 全量重建 MEMORY_MAP，节点数增长后 O(N) 解析 + O(N²) 输出变慢。

**解决**：
- 新增 `--changed <file>` 参数：只重新解析指定节点
- 新增 `--full` 参数：强制全量重建（定期校正用）
- **默认行为变更为增量**：基于 mtime 比较，跳过未变化的节点，从 `.claude/.synapse_cache/` 读缓存结果
- 输出重建统计："re-parsed N changed node(s), loaded M from cache"

**改动文件**：
- `.claude/skills/synapse-graph-memory/scripts/generate_memory_map.sh`（新增 CLI 参数解析、缓存层 4 个 helper、增量解析循环）

---

#### 3. aliases 关键词扩展（frontmatter + SKILL.md + template.md）

**问题**：纯 tag 匹配漏同义词——用户说"认证"但 tags 里只有 `auth`，Step 2 的 Tag Affinity 只能捕获已在节点间共现的 tag 对，无法覆盖用户使用的自然语言。

**解决**：
- 每个节点 frontmatter 新增 `aliases` 字段，写入用户可能使用的自然语言表述（中文、英文、缩写、口语）
- `generate_memory_map.sh` 将 aliases 与 tags 一同索引到 `## Tag Index`，作为额外查找键
- `SKILL.md` 检索协议新增 **Step 2c**：tag + tag affinity 都失败时，纯字符串包含匹配 aliases
- 不引入 embedding 模型，零新依赖，grep 即可

**改动文件**：
- `.claude/skills/synapse-graph-memory/scripts/generate_memory_map.sh`（parse_node 提取 aliases、TAG_MAP 索引 aliases、输出展示 aliases、JSON 含 aliases）
- `.claude/skills/synapse-graph-memory/SKILL.md`（frontmatter schema 新增 aliases、Step 2c 别名匹配、Quick Reference 更新为 "match tags → aliases → keywords"）
- `.claude/skills/synapse-graph-memory/template.md`（三个模板全部新增 aliases 字段及注释）

---

#### 4. 复合查询协议 — Filtered BFS（`SKILL.md` + `template.md`）

**问题**：用户说"今天的前端UI改了什么"，包含时间、领域、子领域、动作四个维度，当前的 tag 匹配只能处理单一维度。

**解决**：新增 **Filtered BFS** 查询模式：
- **查询分解**：领域词 → tag 匹配，时间词（今天/昨天/最近）→ Change Log 日期过滤，动作词（改了/新增/修复）→ section 定位
- **多维求交**：节点必须同时满足 tag 匹配 + Change Log 时间窗口
- **前置条件**：Change Log 日期格式从建议升级为**强制 `YYYY-MM-DD`**，非合规条目在 Topology Health 标志
- 新增 trigger patterns 和 Query Routing 表项

**改动文件**：
- `.claude/skills/synapse-graph-memory/SKILL.md`（Query Routing 新增 Filtered BFS 行、Filtered BFS 分解协议、STEP 1 分类新增 compound query 分支、trigger patterns 新增时间+领域组合、Change Log 格式标注为 REQUIRED）
- `.claude/skills/synapse-graph-memory/template.md`（三个 Change Log section 标题均标注 YYYY-MM-DD REQUIRED）

---

#### 5. Progress Summary（`generate_memory_map.sh` + `SKILL.md`）

**问题**：用户说"咱们现在干到什么程度了"，需要的不是节点列表，而是聚合后的进度结论。

**解决**：在 `generate_memory_map.sh` 中新增 **`## Progress Summary`** section：
- 自动计算：stable/in-progress 节点数及百分比、全项目 open issues 总数
- **建议下一步优先级**：按 open issues 数量降序列出受阻节点 + 所有 in-progress 节点作为焦点候选
- 零 open issues + 零 in-progress 时输出 "All nodes stable. No immediate action suggested."
- `SKILL.md` 新增 "Progress / next steps" query routing 入口，直接读取 Progress Summary（~300 tokens）

**改动文件**：
- `.claude/skills/synapse-graph-memory/scripts/generate_memory_map.sh`（Status Digest 与 Topology Health 之间新增 ~60 行 Progress Summary 生成逻辑）
- `.claude/skills/synapse-graph-memory/SKILL.md`（Query Routing 新增 Progress Summary 行、Quick Reference 更新、STEP 1 新增 progress query 分支、trigger patterns 新增进度查询）

---

### 改动总览

| 优先级 | 修改项 | 解决的问题 | 改动文件 |
|--------|--------|-----------|----------|
| 🔴 P0 | 半自动依赖推断 | depends_on 手工不可持续 | `session-end.sh` (×2) |
| 🔴 P0 | 增量 MAP 更新 | 全量重建随节点数变慢 | `generate_memory_map.sh` |
| 🔴 P0 | aliases 关键词扩展 | tag 遗漏自然语言同义词 | `generate_memory_map.sh` + `SKILL.md` + `template.md` |
| 🔴 P0 | 复合查询 Filtered BFS | 多维查询无法处理 | `SKILL.md` + `template.md` |
| 🔴 P0 | Progress Summary | 无聚合进度结论 | `generate_memory_map.sh` + `SKILL.md` |

---

## [0.2.0] — 2026-05-03

> 基于对 Synapse 系统的深度诊断与对比调研，针对"BFS 协议不可验证"、"边漂移必然性"、"快照与代码脱节"三大致命问题进行的结构性升级。

---

### 🔴 P0 — 致命级修复（系统正确性）

#### 1. 协议合规性审计（`scripts/parse-session.sh`）

**问题**：BFS 检索协议依赖 Agent 自律，Agent 暴力读取 `meta/*.md` 时故障完全静默。`parse-session.sh` 仅能统计 Read 次数，无法区分"合规 BFS"与"暴力扫描"。

**解决**：重写 `parse-session.sh`，增加**事后审计**能力：
- 从 `MEMORY_MAP.json` 重建理论合法 BFS 路径（目标节点 + depth≤2 的 depends_on）
- 对比实际会话中的 Read 路径与理论路径
- 输出三项指标：
  - **合规率**：实际加载节点中位于 BFS 边界内的比例
  - **越界读取**：哪些节点被读了但不在 BFS 路径上
  - **遗漏风险**：哪些节点在 BFS 路径上但未被读取

**为什么事后审计优于 PreToolUse 提醒**：提醒无法阻止违规，但审计可让用户发现"这次会话漏读了 3 个关键依赖"，从而手动补读。

**改动文件**：
- `scripts/parse-session.sh`（重写审计逻辑）
- `MEMORY_MAP.json`（确保包含完整图拓扑数据供审计使用）

---

#### 2. PreToolUse 影响面强制推送（新 hook）

**问题**：`SKILL.md` 要求修改模块前检查 `blocks`，但完全依赖 Agent 自律。这是**安全性关键路径**——修改共享模块前不知道下游影响，可能导致静默破坏。

**解决**：新增 `scripts/hooks/pre-modify-check.sh`，注册为 `PreToolUse` hook：
- 当 Agent 准备 `Write|Edit` 源码文件（非 meta/）时触发
- 在 `MEMORY_MAP.json` 中查找：哪些节点的 Connection Points 引用了该文件
- 自动向 Agent 注入影响面提示（不阻断，只推送信息）

**关键转变**：从"要求 Agent 记得去查 blocks"变为"系统直接把答案放在 Agent 面前"。

**改动文件**：
- `scripts/hooks/pre-modify-check.sh`（新增）
- `.claude/settings.json`（注册 PreToolUse hook）

---

#### 3. 边漂移检测（`scripts/suggest_edges.sh --check-drift`）

**问题**：`depends_on` 手动维护，O(N²) 潜在边数，每个会话只触及部分节点。调研结论："边漂移是系统输入条件下的必然收敛状态"。现有 `suggest_edges.sh` 只建议新边，不检测已声明边是否已过期。

**解决**：给 `suggest_edges.sh` 增加 `--check-drift` 模式：
- 遍历所有已声明的 `depends_on` 边
- 检查源节点的正文中是否仍引用目标节点的 API/表/配置
- 如果源节点不再引用目标节点的任何标识符，标记为"可能过时边"

**核心理念**：维护已有边的正确性比发现新边更能防止 BFS 断链。

**改动文件**：
- `scripts/suggest_edges.sh`（新增 `--check-drift` 模式）

---

### 🟡 P1 — 结构级改进（日常可用性）

#### 4. Connection Points 引用锚点（`template.md` + `session-end.sh`）

**问题**：Connection Points 是"Agent 对代码的文字快照"，与代码渐行渐远。`session-end.sh` 只能做二元检测（源码改了但 meta 没更新），无法定位**哪个** Connection Point 过期了——导致"虚假的安全感"。

**解决**：
1. `template.md` 的 Connection Points 格式支持可选的引用锚点注释：
   ```markdown
   - **Endpoint**: POST /api/v1/auth/refresh  <!-- @ref: src/auth/routes.ts:45 -->
   ```
2. `session-end.sh` 新增锚点验证：
   - 提取所有 `<!-- @ref: path:line -->` 标记
   - 验证文件是否存在、行号附近内容是否匹配
   - 在 drift 报告中**精确定位**哪个 API 契约已过期

**改动文件**：
- `.claude/skills/synapse-graph-memory/template.md`（更新 Connection Points 格式说明）
- `scripts/hooks/session-end.sh`（新增锚点验证逻辑）

---

#### 5. 轻量时序标记（`template.md` + `generate_memory_map.sh`）

**问题**：只有 `updated` 字段，无法表达"这个 API 在 2025-04 之前是 v1，之后是 v2"。无法回答"什么时候变的"这类时序问题。

**解决**：在 frontmatter 中新增可选的 `contracts` 字段：
```yaml
contracts:
  - version: "2.0"
    since: "2026-04-15"
    changes: "JWT → PASETO"
  - version: "1.0"
    since: "2025-11-01"
    deprecated: "2026-04-15"
```

`generate_memory_map.sh` 在生成 MAP 时：
- 检测带 `deprecated` 的契约版本
- 标记哪些节点引用了已弃用契约
- 输出到 Topology Health 章节

**改动文件**：
- `.claude/skills/synapse-graph-memory/template.md`（新增 contracts 字段示例）
- `.claude/skills/synapse-graph-memory/scripts/generate_memory_map.sh`（解析 contracts + 弃用检测）

---

#### 6. 标签同义词扩展（`generate_memory_map.sh` + `SKILL.md`）

**问题**：标签是唯一的发现机制，但同一概念可能用不同标签（`auth` vs `authentication` vs `login`）。关键词回退只能解决"无标签匹配"，不能解决"标签不匹配"。

**解决**：在 `generate_memory_map.sh` 中新增 **Tag Affinity** 计算：
- 基于标签共现频率推断同义词（两标签在超过 30% 节点中共同出现则关联）
- 输出到 `MEMORY_MAP.md` 的 `## Tag Affinity` 章节
- `SKILL.md` Layer 1 检索协议新增：标签匹配失败时，尝试同义词扩展

**改动文件**：
- `.claude/skills/synapse-graph-memory/scripts/generate_memory_map.sh`（新增 Tag Affinity 计算与输出）
- `.claude/skills/synapse-graph-memory/SKILL.md`（Layer 1 新增同义词回退步骤）

---

### 🟢 P2 — 工程级优化

#### 7. YAML 解析器严格模式（`generate_memory_map.sh`）

**问题**：手写 `awk/sed` YAML 解析器在 frontmatter 格式不规范时**静默失败**，可能生成损坏的 MEMORY_MAP.md——单点故障。

**解决**：
- `extract_scalar` / `extract_list` 函数增加解析失败检测：字段为空时输出 `ERROR` 到 stderr
- 主解析循环增加**严格模式**：必填字段（`id`）解析失败时标记节点为 corrupt，输出到 Topology Health
- `MEMORY_MAP.md` 新增 `## Parse Failures` 章节

**改动文件**：
- `.claude/skills/synapse-graph-memory/scripts/generate_memory_map.sh`（严格模式 + 错误报告）

---

#### 8. 冷发现 Benchmark（`scripts/benchmark.sh`）

**问题**：现有 7 个任务都是"已知入口节点"的线性任务。真实场景中 Agent 经常需要**先发现节点**再加载，现有 benchmark 无法测试标签/关键词发现机制的有效性。

**解决**：新增任务 8——**冷发现**（无已知入口）：
- 场景："有一个跟用户登录后跳转到结算页相关的 bug"
- 期望路径：标签 `login` → `feat_login` → `depends_on` → `mod_auth` → `blocks` → `feat_checkout`
- 测试标签索引能否正确引导到相关节点

**改动文件**：
- `scripts/benchmark.sh`（新增冷发现任务与验证逻辑）

---

#### 9. SKILL.md 决策树格式（`SKILL.md`）

**问题**：Retrieval Protocol 当前是段落式描述（327 行），Agent 在长会话中容易遗忘步骤。Claude 对结构化决策树的遵循率显著高于段落描述。

**解决**：将 `## Retrieval Protocol` 从段落格式重写为**结构化决策树**：
```markdown
START: 用户任务涉及已知模块？
├─ YES → 在 Tag Index 查找该标签
│   ├─ ≤3 匹配 → 加载全部
│   ├─ 4-5 匹配 → 加载前 3
│   └─ >5 匹配 → 停止，请求用户缩小范围
...
```

**改动文件**：
- `.claude/skills/synapse-graph-memory/SKILL.md`（Retrieval Protocol 段落 → 决策树）

---

### 改动总览

| 优先级 | 修改项 | 解决的问题 | 改动文件 |
|--------|--------|-----------|----------|
| 🔴 P0 | 协议合规性审计 | BFS 不可验证 | `scripts/parse-session.sh` |
| 🔴 P0 | PreToolUse 影响面推送 | blocks 检查无执行 | `.claude/settings.json` + 新 hook |
| 🔴 P0 | 边漂移检测 | 边必然过期 | `scripts/suggest_edges.sh` |
| 🟡 P1 | Connection Points 引用锚点 | 快照与代码脱节 | `template.md` + `session-end.sh` |
| 🟡 P1 | 轻量时序标记 | 无版本历史 | `template.md` + `generate_memory_map.sh` |
| 🟡 P1 | 标签同义词扩展 | 标签脆弱性 | `generate_memory_map.sh` + `SKILL.md` |
| 🟢 P2 | YAML 解析器严格模式 | MAP 单点故障 | `generate_memory_map.sh` |
| 🟢 P2 | 冷发现 benchmark | 方法论证缺陷 | `scripts/benchmark.sh` |
| 🟢 P2 | SKILL.md 决策树 | Agent 遗忘协议 | `SKILL.md` |

---

## [0.1.0] — 2026-04-30

> 初始版本，基于 ClaudeMem 对比调研后的基础改进。

### 已完成（IMPROVEMENTS.md 记录）

- **关键词回退索引**：标签匹配失败时回退到关键词匹配（API 路径、函数名、表名、配置键）
- **渐进式披露检索协议**：三层检索（MAP summary → 节点全文 → BFS deps）
- **Token 成本可见性**：每个节点标注 `~N tok` 估算
- **Observation 格式 Change Log**：Context → Change → Impact → Affected
- **边的自动建议脚本**：`suggest_edges.sh` 从 Connection Points 自动检测依赖
- **MEMORY_MAP 双格式冗余**：同时输出 `.md`（人读）和 `.json`（机器读）
- **冷启动一键向导**：`init.sh` 自动检测技术栈并生成初始骨架
- **更公平的 benchmark**：增加"智能 flat"对比模式

### 已知限制（本次 0.2.0 重点解决）

- BFS 协议无运行时守卫，依赖 Agent 自律
- `blocks` 检查在修改前无强制执行
- `depends_on` 边漂移无法检测
- Connection Points 与源码可能脱节
- 无时序维度
- 标签作为唯一发现机制脆弱
