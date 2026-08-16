> 对应协议: dev/protocol-harness/delivery/PR_WRITING_PROTOCOL.md
> 反馈循环规范: dev/protocol-harness/delivery/pr_writing/protocol_evolution.md

# PR Writing Feedback

## 主汇总表

| ID | 日期 | 任务 | 层级 | PR 类型 | Commits | 文件数 | Issues | PR 状态 | 关键发现 | 再实践观察点 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| PRW-2026-05-10-001 | 2026-05-10 | `cont_refactoring` -> `main` HELIX library foundation | Tier 3 | Feature | 10 | 107 | 0 | Draft PR #5 已创建 | 复杂 PR 可以用计划交接和 validation registry 作为主事实源，避免重新拼测试矩阵；用户确认后通过 `gh pr create --draft` 创建并验证 PR | 下一次同类任务重点观察：PR writing 是否应把“仅起草”和“创建/更新 GitHub PR”作为两个显式交付状态记录。 |
| PRW-2026-05-13-001 | 2026-05-13 | `v0.0.3-backend-profiling-benchmark` -> `main` benchmark/profiling foundation | Tier 3 | Feature | 3 | 28 | 0 | Open PR #6 已创建 | PR 正文需明确 benchmark 是 trend/reporting evidence，不替代 correctness/baseline gate；第三个 security commit 移除了 tracked `.nsys-rep`，doc-verify 校准了 `nsight_artifact=null/not_collected` 的事实 | 下一次同类任务重点观察：Phase 4 是否应支持“用户已在启动指令中授权提交”作为审核门控的显式满足条件。 |
| PRW-2026-08-14-001 | 2026-08-14 | `release/v0.1.0` -> `main` v0.1.0 release merge | Tier 3 | Release | 17 | 13 | 2 (Refs) | Open PR #43 已创建 | 发布前置审计（29/29 CTest + 1980 步基线前缀匹配）为 Test Plan 提供全部可溯源事实；`cz changelog` 对历史重复提交生成重复条目，需人工去重（协议未覆盖 changelog 质量检查）；phase_submission §4.1 授权例外条款按预期生效，直接创建未阻塞 | 下一次同类任务重点观察：release 型 PR 的 Phase 1 是否应把 CHANGELOG 生成与去重纳入“发布工程事实”收集清单。 |

## 实践记录

### 实践 #1: HELIX library foundation PR draft

**日期**: 2026-05-10  
**PR 编号**: #5（https://github.com/yjmaxpayne/HELIX/pull/5）  
**PR 类型**: Feature  

#### 基本信息

- 复杂度层级: 复杂 / Tier 3
- 当前分支: `cont_refactoring`
- 基准分支: `main`
- Commit 范围: `main..HEAD`
- Commits 数量: 10
- 变更文件数: 107
- 关联 Issues 数量: 0（用户指定“否”）
- 语言: 英文（对齐 `.github/PULL_REQUEST_TEMPLATE.md`）
- 草稿路径: `/tmp/helix-pr-cont_refactoring.md`

#### 执行情况

| 阶段 | 是否执行 | 实际耗时 | 备注 |
| --- | --- | --- | --- |
| Phase 0: 启动确认 | ✅ | ~5m | 当前分支、base、commit range、Issue 策略、复杂度已确认；工作区干净 |
| Phase 1: 信息收集 | ✅ | ~15m | 收集 `git log`, `git diff --stat`, `git diff --name-status`, plan registry, validation registry, final baseline handoff |
| Phase 2: 信息汇总 | ✅ | ~10m | 汇总 API/runtime、CLI、bindings/examples/tests/CI、docs 和验证矩阵 |
| Phase 3: PR 撰写 | ✅ | ~15m | 生成英文 PR 标题和正文草稿到 `/tmp/helix-pr-cont_refactoring.md` |
| Phase 4: 审核与提交 | ✅ | ~10m | 用户确认提交草稿后执行 `gh pr create --draft`，并用 `gh pr view 5 --json ...` 验证 title/body/base/head/draft 状态 |

#### 效果评估

- 用户满意度: 待用户确认
- 是否有跳过的阶段: 否。
- 是否有冗余的步骤: 否。
- Agent 数量是否合适: 适中；当前会话规则要求用户显式请求后才可 spawn agent，因此 Tier 3 由主流程完成。

#### doc-verify 钩子

- 目标文档: `/tmp/helix-pr-cont_refactoring.md`
- 文档类型: Markdown PR draft
- 代码块: 0 个 fenced code blocks，无需运行代码块。
- 核查结果: 通过。
- 事实来源:
  - `git log main..HEAD --oneline --decorate`
  - `git diff main...HEAD --stat`
  - `git diff main...HEAD --name-status`
  - `.plan/v0.1-helix_library_foundation-plan/10-final-baseline-handoff.md`
  - `.claude/validation-registry.md`
  - `CMakeLists.txt`
  - `pyproject.toml`
  - `git diff --quiet main...HEAD -- examples/outputEnergy.txt`
- 修正: 无。

## 实践反思

### §3.1 批评

- 任务路由: Tier 3 判定正确；PR 覆盖 10 commits、107 个文件，跨 public API、CMake/install、runtime bridge、CLI、Python binding、CI、docs 和 tests。
- 阶段门控: Phase 0/1 捕获了“无关联 Issue”和“无已有 PR”；Phase 4 在用户确认后创建 draft PR 并读回验证。
- 验证有效性: 最终测试矩阵来自 plan handoff 和 validation registry，并通过源码/配置只读核查；未重新运行昂贵 GPU gate。
- 协作成本: 未使用子 Agent，避免违反当前会话规则；主流程承担分析、写作和审核。
- 懒加载质量: 已加载主协议、Quick Flow、Tier 3 phase 文件、reference、workflow reference、protocol evolution、元协议和 doc-verify Markdown 适配。

### §3.2 自我批评

1. [缺陷]: PR writing 协议没有显式区分“草稿已交付”和“GitHub PR 已创建”两种结束状态。
   - 证据: Phase 4 要求用户审核后才能 `gh pr create`，但元协议又要求最后 Phase 后立即反馈落盘。
   - 影响: 总结中必须非常明确地说明 PR 尚未创建，避免把草稿交付误报成 PR 提交完成。
   - 归属: `phase_submission.md` / PR writing protocol 状态表达。
2. [缺陷]: 产出文档型协议要求 `/doc-verify <output-path>`，但 PR 草稿常直接产出在对话里。
   - 证据: 本次为满足核查路径，先将草稿写入 `/tmp/helix-pr-cont_refactoring.md`。
   - 影响: 额外一步临时文件管理；质量收益存在，但流程语义不够清晰。
   - 归属: `PROTOCOL_FEEDBACK_FRAMEWORK.md` / doc-verify 集成约定。

### §3.3 改进

- 本次不修改协议本体；在实践记录中明确 “草稿待用户确认” 是 Phase 4 的合法停点，而非 GitHub PR 已提交。
- 后续若同类 PR writing 再出现，应考虑在 `phase_submission.md` 中补充状态字段：`draft_ready`、`user_approved`、`submitted`。

### §3.4 固化

- 已创建 `dev/protocols/feedback/pr_writing_feedback.md` 并写入本次实践记录。
- 已将 PR 草稿保存到 `/tmp/helix-pr-cont_refactoring.md`，用于本次 doc-verify 等价核查和 GitHub PR 创建。
- 已创建并验证 Draft PR #5: https://github.com/yjmaxpayne/HELIX/pull/5
- 未修改 PR writing 协议文件；缺陷先作为待验证假说保留。

### §3.5 再实践观察点

- 下一次同类任务重点观察：PR writing 是否应把“仅起草”和“创建/更新 GitHub PR”作为两个显式交付状态记录。

### 实践 #2: HELIX v0.0.3 benchmark/profiling PR submission

**日期**: 2026-05-13  
**PR 编号**: #6（https://github.com/yjmaxpayne/HELIX/pull/6）  
**PR 类型**: Feature  

#### 基本信息

- 复杂度层级: 复杂 / Tier 3
- 当前分支: `v0.0.3-backend-profiling-benchmark`
- 基准分支: `main`
- Commit 范围: `origin/main..HEAD`
- Commits 数量: 3
- 变更文件数: 28
- 关联 Issues 数量: 0（`gh issue list --search "benchmark profiling"` 无结果）
- 语言: 英文（对齐仓库 README/Sphinx/test docs）
- 草稿路径: `/tmp/helix_v003_pr_body.md`

#### 执行情况

| 阶段 | 是否执行 | 实际耗时 | 备注 |
| --- | --- | --- | --- |
| Phase 0: 启动确认 | ✅ | ~5m | 当前分支、base、commit range、远端跟踪和工作区 clean 已确认；刷新 `origin/main` 后范围仍为 3 commits |
| Phase 1: 信息收集 | ✅ | ~15m | 收集 `git log`, `git diff --stat`, changed files, `.claude/*-registry.md`, plan status, final handoff, checked-in test evidence |
| Phase 2: 信息汇总 | ✅ | ~8m | 汇总 schema/runner、CTest label boundary、artifact hygiene、docs/example、reference benchmark snapshot 和验证矩阵 |
| Phase 3: PR 撰写 | ✅ | ~12m | 生成英文标题 `feat(benchmark): add v0.0.3 profiling foundation` 和正文 |
| Phase 4: 审核与提交 | ✅ | ~8m | 用户启动指令已要求提交到远端；执行 `gh pr create` 创建 Open PR #6，并用 `gh pr view` / `gh pr checks` 验证正文和 CI 启动 |

#### 效果评估

- 用户满意度: 待用户确认
- 是否有跳过的阶段: 否；未使用子 Agent，因为当前会话规则要求用户显式请求 sub-agent。
- 是否有冗余的步骤: 轻微；Phase 4 的“用户审核”门控与用户启动指令中的“提交到远程端”存在重叠。
- Agent 数量是否合适: 适中；主流程完成标准/Tier 3 信息收集、写作、doc-verify 和提交后验证。

#### doc-verify 钩子

- 目标文档: `/tmp/helix_v003_pr_body.md`
- 文档类型: Markdown PR body
- 代码块: 0 个 fenced code blocks，无需运行代码块。
- Markdown 链接: 0 个，无需链接目标验证。
- 核查结果: 通过，且修正 1 条事实表述。
- 事实来源:
  - `git log origin/main..HEAD --oneline --decorate`
  - `git diff origin/main...HEAD --stat`
  - `.plan/v0.0.3-helix_backend_profiling_benchmark-plan/08-任务状态.md`
  - `.plan/v0.0.3-helix_backend_profiling_benchmark-plan/10-final-baseline-handoff.md`
  - `.claude/validation-registry.md`
  - `examples/benchmark/legacy_spin_glass/reference/helix_benchmark.jsonl`
  - `examples/benchmark/legacy_spin_glass/reference/helix_benchmark_summary.md`
  - `examples/benchmark/legacy_spin_glass/reference/test_results/validation_summary.md`
- 修正: 将 “checked-in JSONL/summary recording the relative Nsight artifact path” 改为当前事实：raw `.nsys-rep` 不保留，JSONL/summary 记录 `profiling.nsight_artifact` 为 `null` / `not_collected`。

## 实践反思（实践 #2）

### §3.1 批评

- 任务路由: Tier 3 判定合理；虽只有 3 commits，但跨 CMake、CI、benchmark runner、test support、docs、examples 和 reference artifacts。
- 阶段门控: Phase 1/2 成功捕获 security follow-up 对 Nsight artifact 语义的影响；Phase 4 验证了 PR #6 title/body/base/head 与 CI 启动状态。
- 验证有效性: Test Plan 采用 recorded validation evidence，避免误报当前会话重新执行了 GPU/baseline gates。
- 协作成本: 未启用 sub-agent，符合当前会话规则；主流程中读取计划/registry/test evidence 足以支撑 PR 正文。
- 懒加载质量: 已加载主协议、protocol_evolution、PROTOCOL_FEEDBACK_FRAMEWORK、Phase workflow/analysis/writing/submission，以及 doc-verify Markdown 适配。

### §3.2 自我批评

1. [缺陷]: Phase 4 “用户审核”门控没有显式覆盖“用户启动指令已经要求创建/提交 PR”的情况。
   - 证据: 本次用户明确要求“构造一个PR，而后提交到远程端”，若再次停下等待确认会违背任务意图。
   - 影响: 执行者需要自行判断授权是否足够，存在流程解释成本。
   - 归属: `phase_submission.md`
2. [缺陷]: PR writing 协议要求反馈记录同次落盘，但用户任务限定“当前分支领先 main 的几个 commits”，反馈 commit 若推送会污染 PR 范围。
   - 证据: 本次选择本地落盘反馈，不推送反馈文件，以保持 PR #6 只覆盖原 3 commits。
   - 影响: 协议“同次提交内”措辞与“不改变 PR scope”之间存在张力。
   - 归属: `PROTOCOL_FEEDBACK_FRAMEWORK.md` / `phase_submission.md`

### §3.3 改进

- 本次不修改协议本体；将两点作为待验证假说记录。
- 若再次出现，应考虑在 `phase_submission.md` 增加“explicit submit authorization”门控解释，并在元协议反馈规则中区分“本地落盘”与“随 PR 推送”。

### §3.4 固化

- 已将本次实践追加到 `dev/protocols/feedback/pr_writing_feedback.md`。
- 已创建并验证 Open PR #6: https://github.com/yjmaxpayne/HELIX/pull/6
- 未将反馈记录推送到 PR 分支，避免改变“当前分支领先 main 的 3 commits”这一 PR 范围。

### §3.5 再实践观察点

- 下一次同类任务重点观察：Phase 4 是否应支持“用户已在启动指令中授权提交”作为审核门控的显式满足条件。

### 实践 #3: HELIX v0.1.0 release merge PR submission

**日期**: 2026-08-14  
**PR 编号**: #43（https://github.com/yjmaxpayne/HELIX/pull/43）  
**PR 类型**: Release  

#### 基本信息

- 复杂度层级: 复杂 / Tier 3（release branch 合并，跨 backend/API/release engineering）
- 当前分支: `release/v0.1.0`
- 基准分支: `main`
- Commit 范围: `origin/main..HEAD`（17 commits）
- 变更文件数: 13
- 关联 Issues 数量: 2（Refs #31、#30，均为 epic，不使用关闭语义）
- 语言: 英文（用户显式要求）

#### 执行情况

| 阶段 | 是否执行 | 实际耗时 | 备注 |
| --- | --- | --- | --- |
| Phase 0: 启动确认 | ✅ | ~3m | 发布就绪评估先行：识别 CHANGELOG 缺失与 main 落后 4 commits 两个硬阻塞并先行解决 |
| Phase 1: 信息收集 | ✅ | ~10m | 本会话已实测 29/29 CTest、1980 步基线前缀匹配（max_de=3.8e-6）、pre-commit 全过；`gh issue list` 确认 epic 关联 |
| Phase 2: 信息汇总 | ✅ | ~5m | 按 backend dispatch / public API / release engineering 三主题组织变更 |
| Phase 3: PR 撰写 | ✅ | ~8m | 英文标题 `release(v0.1.0): backend dispatch contracts and pre-1.0 API baseline` + 正文 |
| Phase 4: 审核与提交 | ✅ | ~3m | 依据 §4.1 授权例外（用户指令"写作 PR 作为主要PR"）直接 `gh pr create`；`gh pr checks` 验证 CI 启动 |

#### 效果评估

- 用户满意度: 待用户确认
- 是否有跳过的阶段: 否；未使用子 Agent（主会话已持有全部一手验证事实）
- 是否有冗余的步骤: 否；发布评估与 Phase 1 信息收集天然复用
- Agent 数量是否合适: 适中（0 个，合理）

#### doc-verify 手动清单（GitHub-only PR body）

- 章节完整性: Summary / Related Issues / Changes / Test Plan 均存在 ✅
- 路径存在性: `tests/unit/{spmm,blas,transpose}_backend_dispatch_tests.cpp`、`examples/outputEnergy.txt` 均在 diff 或 tracked baseline 中 ✅
- Issue 语义: epic 用 `Refs`，无伪造 `Closes` ✅
- Test Plan 真实性: 每项均可追溯本会话命令输出；sanitizer 显式标注 N/A ✅

## 实践反思（实践 #3）

### §3.1 批评

- 任务路由: Tier 3 判定合理；release 合并天然跨模块。
- 阶段门控: §4.1 授权例外条款（实践 #2 反馈固化）按预期生效，避免了一次无意义的停顿。
- 验证有效性: Test Plan 全部来自发布前实测，无一项引用未执行命令。

### §3.2 自我批评

1. [缺陷]: `cz changelog --incremental` 对历史中的重复提交（cherry-pick 痕迹）生成重复条目，CHANGELOG 去重依赖人工检查。
   - 证据: `add validation-only user exponent baths` 与 `.gitignore` 条目各重复一次，手动删除。
   - 归属: `RELEASE_MANAGEMENT_PROTOCOL`（如适用）/ 本协议 Phase 1。

### §3.3 改进

- 本次不修改协议本体；将 changelog 去重作为待验证假说记录。

### §3.4 固化

- 反馈记录本地落盘，不推送，保持 PR #43 范围不变（沿用实践 #2 先例）。

### §3.5 再实践观察点

- 下一次同类任务重点观察：release 型 PR 的 Phase 1 是否应把 CHANGELOG 生成与去重纳入“发布工程事实”收集清单。
