> 对应协议: dev/protocol-harness/delivery/RELEASE_MANAGEMENT_PROTOCOL.md
> 反馈循环规范: dev/protocol-harness/delivery/release_management/protocol_evolution.md

# Release Management Feedback

## 实践数据汇总表

| 序号 | 日期 | 版本 | 类型 | 渠道 | 回滚? | post_release_issues | 关键发现 |
|------|------|------|------|------|-------|---------------------|----------|
| 1 | 2026-05-09 | v0.0.1 | minor | GitHub Release | 否 | 1 | Release 可见且资产上传成功；自动 Release workflow 的 publish job 因无 git repo / `GH_REPO` 上下文失败；仓库 CHANGELOG 条目覆盖不完整，GitHub generated notes 覆盖较完整 |
| 2 | 2026-05-14 | v0.0.3 | patch | GitHub Release + Zenodo | 否 | 0 | Patch Release 完整质量门控与构建通过；Release workflow 自动发布成功；Zenodo 版本归档成功且 concept DOI 无需回填 |
| 3 | 2026-05-17 | v0.0.4 | patch | GitHub Release | 否 | 0 | Phase 2 捕获 test/prod 默认值漂移（benchmark gate 镜像未跟随 R1 rollback），一行 fix 后所有 gate 全绿；版本号同步与 CHANGELOG 通过 cz changelog 生成 |
| 4 | 2026-05-19 | v0.0.5 | patch | GitHub Release | 否 | 0 | Stream-aware execution (M3.1/M3.2/M3.4) 含 ARCH-BEH-001 行为变更 + `HELIX_DEBUG_SYNC_MODE` opt-in；M-2/M-3 1980-step 在 release branch 上 bit-identical to v0.0.4 baseline (4e-06)，main 上仅重跑 M-1/M-4/M-5/M-6 全 PASS；流程摩擦：Claude Code auto-mode 分类器两次拦截直推 main，需用户手动 push |
| 5 | 2026-08-16 | v0.1.0 | minor | GitHub Release | 否 | TBD | 首次 runner offline 场景：tag 已推送、流水线排队 15+ min 后取消，经用户决策走本机手动发布；package_release.sh 的 binary_version==tag 校验强制用新 tag 重新 configure+build（机制按设计生效）；digest 经下载回传闭环验证；无 CI attestation（provenance 已写入 notes） |

## 实践记录

### 实践 #1: HELIX v0.0.1 Minor Release

**日期**: 2026-05-09
**release_version**: v0.0.1
**release_type**: minor
**target_channel**: GitHub Release

#### 特化数据字段

- ci_pass_rate: 本地发布门控通过；远端 Release workflow 的 build/verify/package job 通过，publish job 失败。
- pre_release_blockers: 无产品阻塞；发布后发现 workflow publish step 需要 repo 上下文。
- changelog_completeness: 部分。GitHub Release generated notes 覆盖 PR/commit 范围；仓库 `CHANGELOG.md` 的 `v0.0.1` 条目未覆盖全部 notable changes。
- release_notes_doc_verify: `CHANGELOG.md` 版本号与日期正确；代码块为 release tooling 命令；内容覆盖度不足。GitHub Release body 包含 PR #1/#2/#3/#4 与 full changelog 链接。
- post_release_issues: 1 个流程问题：`.github/workflows/release.yml` publish job 在无 checkout 的 Ubuntu job 中调用 `gh release upload`，缺少 repo context。
- rollback_count: 0。
- artifact_signoff: 通过。`helix-v0.0.1-linux-x86_64-cuda13-sm89.tar.gz` 上传，SHA-256 为 `70cb44c33a94bf4e22e02861350c33544548b5b7e2ba6ecbd68dbbf8f1d55a1a`。

#### 执行情况

| Phase | 是否执行 | 结果 | 备注 |
|-------|----------|------|------|
| Phase 1: 发布准备 | 是 | 通过 | `main` 干净；远端无 `v0.0.1` tag；版本策略为首个 SemVer tag |
| Phase 2: 质量门控 | 是 | 通过 | CTest 11/11、生成物检查、pre-commit、Sphinx `-W --keep-going` 通过 |
| Phase 3: 构建制品 | 是 | 通过 | 显式 `HELIX_RELEASE_VERSION=v0.0.1`；release tarball 和 `.sha256` 生成 |
| Phase 4: 发布验证 | 是 | 通过 | `/tmp` 解包验证；`HELIX 0.0.1`；2-step smoke 输出正常 |
| Phase 5: 发布归档 | 是 | 部分通过 | tag 和 GitHub Release 成功；远端 workflow publish job 失败但 Release 已由本地 `gh release create` 完成 |

#### 关键验证证据

- `cmake -S . -B build/cmake -DCMAKE_BUILD_TYPE=Release -DHELIX_CUDA_ARCHITECTURES=89`
- `cmake --build build/cmake --parallel 24`
- `ctest --test-dir build/cmake --output-on-failure`: 11/11 passed。
- `pre-commit run --all-files` via `uv run --extra dev`: passed。
- `make -C doc html SPHINXBUILD=/home/yjmaxpayne/Dev/HELIX/build/docs-venv/bin/sphinx-build SPHINXOPTS=-W --keep-going`: passed。
- `HELIX_RELEASE_VERSION=v0.0.1 HELIX_STEPS=1980 HELIX_CUDA_ARCHITECTURES=89 scripts/verify_examples.sh`: 1981 rows, `max_time_diff=0`, `max_energy_diff=6e-07`, tolerance `1e-05`。
- GitHub Release: https://github.com/yjmaxpayne/HELIX/releases/tag/v0.0.1

## 实践反思

### §3.1 批评

- 任务路由: Minor Release 完整流程合适；C++/CUDA 项目需要把 Poetry 模板映射为 CMake、CTest、tarball 和 GitHub Release。
- 阶段门控: Phase 5 暴露自动 publish job 缺少 repo 上下文，未在本地发布前被捕获。
- 验证有效性: 本地与远端 build/verify/package 证据充分；Release channel 可见性通过 `gh release view` 验证。
- 协作成本: 未使用子 Agent，主对话即可完成。
- 懒加载质量: 已加载主协议、强制反馈框架、phase 文件、API compatibility、workflow reference 与 troubleshooting。
- CHANGELOG 真实性: GitHub generated notes 与 PR/commit 范围一致；仓库 CHANGELOG 对首发 notable changes 覆盖不足。
- 回滚演练: 未执行回滚演练；本次无产品级回滚触发。

### §3.2 自我批评

1. [缺陷]: 发布 workflow 的 publish job 未显式提供 repo context。
   - 证据: 远端 run `25605416728` 的 `Publish GitHub Release` job 报 `fatal: not a git repository`。
   - 影响: 自动发布链路显示失败，虽然人工 GitHub Release 已成功。
   - 归属: `.github/workflows/release.yml` / Phase 5 渠道验证。
2. [缺陷]: `CHANGELOG.md` 的首发条目覆盖不完整。
   - 证据: `v0.0.1` 仅记录 Git-tag 版本配置，未覆盖测试、文档、CI、数值基线和 release readiness suite。
   - 影响: 仓库内 changelog 与 GitHub Release notes 信息不一致。
   - 归属: Phase 5 CHANGELOG 生成与 doc-verify 钩子。

### §3.3 改进

- 下一次修改 release workflow 时，为 publish job 添加 `GH_REPO: ${{ github.repository }}` 或 checkout，再执行 workflow dispatch 验证。
- 首个 release tag 创建前，先运行 CHANGELOG dry-run 并人工核对 GitHub generated notes / `CHANGELOG.md` 覆盖范围，再创建 tag。

### §3.4 固化

- 已将本次缺陷写入 `dev/protocols/feedback/release_management_feedback.md`。
- 已修复 `.github/workflows/release.yml` 的 publish job：设置 `GH_REPO` 并为 `gh release view/upload/edit/create` 显式传入 `--repo "${GH_REPO}"`，避免无 checkout 环境缺少 git repo context。
- 暂不修改 release tag；公开版本号不移动、不复用。

### §3.5 再实践观察点

- 下一次同类发布重点观察: Phase 5 是否先验证 `gh release upload --repo` / workflow dispatch 幂等路径，再创建公开 tag。

### 实践 #2: HELIX v0.0.3 Patch Release

**日期**: 2026-05-14
**release_version**: v0.0.3
**release_type**: patch
**target_channel**: GitHub Release + Zenodo

#### 特化数据字段

- ci_pass_rate: 本地发布门控通过；远端 Release workflow `25837586994` 两个 job 全部成功。
- pre_release_blockers: 无。发布准备期间发现并修正两个 benchmark reference 日志的尾随空格。
- changelog_completeness: 通过。`cz changelog --incremental --unreleased-version v0.0.3` 生成 `v0.0.3`，覆盖 `feat(benchmark)` 两项与 `fix(security)` 一项；同时补齐缺失的 `v0.0.2` 小节。
- release_notes_doc_verify: `/doc-verify` 手动版完成；`CHANGELOG.md` 无 Markdown 链接，v0.0.3 条目与 `v0.0.2..HEAD` Conventional Commit 范围一致。
- post_release_issues: 0。
- rollback_count: 0。
- artifact_signoff: 通过。GitHub Release 上传 `helix-v0.0.3-linux-x86_64-cuda13-sm89.tar.gz` 与 `.sha256`；Zenodo 记录 `20174198` published，version DOI `10.5281/zenodo.20174198`，concept DOI `10.5281/zenodo.20115002`。

#### 执行情况

| Phase | 是否执行 | 结果 | 备注 |
|-------|----------|------|------|
| Phase 1: 发布准备 | 是 | 通过 | `main` 与 `origin/main` 对齐；无本地/远端 `v0.0.3` tag；版本权威为 Git tag |
| Phase 2: 质量门控 | 是 | 通过 | Release CMake build、CTest ordinary correctness、benchmark、sanitizer、full baseline、pre-commit、文档构建通过 |
| Phase 3: 构建制品 | 是 | 通过 | `scripts/package_release.sh v0.0.3` 生成 tarball 和 checksum；manifest 版本一致 |
| Phase 4: 发布验证 | 是 | 通过 | `/tmp` 解包；`HELIX 0.0.3`；2-step package smoke energy prefix matched |
| Phase 5: 发布归档 | 是 | 通过 | release commit、annotated tag、main/tag push、GitHub Release workflow、Zenodo 归档均成功 |

#### 关键验证证据

- `cmake -S . -B build/cmake -DCMAKE_BUILD_TYPE=Release -DHELIX_CUDA_ARCHITECTURES=89 -DHELIX_RELEASE_VERSION=v0.0.3`
- `cmake --build build/cmake --parallel 24`
- `ctest --test-dir build/cmake --output-on-failure -LE "^(sanitizer|benchmark)$"`: 23/23 passed。
- `ctest --test-dir build/cmake -L benchmark --output-on-failure`: 2/2 passed。
- `ctest --test-dir build/cmake -L sanitizer --output-on-failure`: 1/1 passed。
- `HELIX_STEPS=1980 HELIX_CUDA_ARCHITECTURES=89 HELIX_RELEASE_VERSION=v0.0.3 scripts/verify_examples.sh`: 1981 rows, `max_time_diff=0`, `max_energy_diff=4.1e-06`, tolerance `1e-05`。
- `.venv/bin/pre-commit run --all-files`: passed。
- `make -C doc html SPHINXBUILD=../.venv/bin/sphinx-build SPHINXOPTS="-W --keep-going"`: passed。
- GitHub Release: https://github.com/yjmaxpayne/HELIX/releases/tag/v0.0.3
- Zenodo Record: https://zenodo.org/records/20174198

## 实践反思

### §3.1 批评

- 任务路由: Patch Release 简化 Phase 1/4/5 合适，但用户要求保留 Phase 2/3 完整执行，实际执行与协议一致。
- 阶段门控: pre-commit 在 Phase 2 捕获 benchmark reference 日志尾随空格，门控有效；CHANGELOG 生成前需要 commitizen 环境准备。
- 验证有效性: 本地和远端均覆盖 GPU baseline；Phase 4 包内 smoke 验证了发布 tarball 可运行。
- 协作成本: 未使用子 Agent，主对话足以完成；远端 workflow watch 与本地验证存在少量重复但必要。
- 懒加载质量: 已加载主协议、quick flow、phase quality/build/validation/release、versioning、workflow reference、protocol evolution、元协议和 doc-verify。
- CHANGELOG 真实性: `v0.0.3` 条目可追溯到 `d62bffd`、`219c299`、`13597bd`；release commit 不进入 notable changes 合理。
- 回滚演练: 未执行回滚演练；本次无回滚触发。

### §3.2 自我批评

1. [缺陷]: `uv run cz` 在无锁仓库中反复生成未跟踪 `uv.lock`。
   - 证据: CHANGELOG dry-run 和文档核验后均出现未跟踪 `uv.lock`，需要人工删除。
   - 影响: 增加发布归档时误提交工具副作用的风险。
   - 归属: Phase 5 CHANGELOG 工具命令 / 项目 release tooling。
2. [缺陷]: 本地 Phase 3 tarball 最初在 release commit 前生成。
   - 证据: 发布后校验发现本地 `dist/` manifest source revision 仍是 `d233e7d`，CI 资产已从 tag commit `eeddfb2` 重建。
   - 影响: 本地忽略制品与正式 GitHub Release 资产不一致，容易混淆证据。
   - 归属: Phase 3/5 顺序边界。

### §3.3 改进

- 后续执行 commitizen 时优先使用不落锁文件的项目命令，或在 release checklist 中显式加入 `uv.lock` 未跟踪检查。
- Phase 5 release commit 完成并打 tag 后，若保留本地 `dist/` 证据，应重新运行 `scripts/package_release.sh vX.Y.Z`，确保 manifest source revision 指向 tag commit。

### §3.4 固化

- 已将本次实践追加到 `dev/protocols/feedback/release_management_feedback.md`。
- 本次不修改发布协议正文；两个问题先作为下一次发布观察项，不足以单次固化为通用规则。

### §3.5 再实践观察点

- 下一次同类发布重点观察: CHANGELOG 生成与 release commit/tag 顺序是否能避免本地制品 source revision 漂移和 `uv.lock` 副作用。

---

### 实践 #3: HELIX v0.0.4 Patch Release

**日期**: 2026-05-17
**release_version**: v0.0.4
**release_type**: patch
**target_channel**: GitHub Release

#### 特化数据字段

- ci_pass_rate: 本地发布门控：ordinary correctness 24/24、benchmark 2/2（修复后）、baseline 2-step / 1980-step 通过；远端 Release workflow 未单独触发。
- pre_release_blockers: 1 项。Phase 2 benchmark gate 失败，根因为 commit b54b094（R1 recovery）翻转 `src/liouville.cu:153 sparseBackendPlanEnabled()` 默认为 `false`，但 `tests/benchmark/legacy_spin_glass_benchmark.cu:250 cusparseReusePlanEnabledFromEnv()` 镜像默认仍为 `true`，导致默认走 legacy wrapper 路径时错误进入 reuse-plan 断言分支。
- changelog_completeness: 通过。`cz changelog --incremental` 从 `v0.0.3..HEAD` Conventional Commit 生成 4 项 Feat、1 项 Perf；手动补充本次 release-blocker 的 Fix 条目。
- release_notes_doc_verify: 未运行 `/doc-verify`。CHANGELOG `v0.0.4` 版本与日期正确；Release Notes 引用 `CHANGELOG.md` 链接到 tag。
- post_release_issues: 暂无（发布后立即记录）。
- rollback_count: 0。
- artifact_signoff: 本次 Release 未上传二进制资产（仅 source tarball / zipball 由 GitHub 自动生成）；未触发 Zenodo 归档（未配置自动联动验证）。

#### 执行情况

| Phase | 是否执行 | 结果 | 备注 |
|-------|----------|------|------|
| Phase 1: 发布准备 | 是（简化） | 通过 | 14 个 commits since v0.0.3；3 个版本号文件锁定 |
| Phase 2: 质量门控 | 是 | 通过（修复后） | 暴露 test/prod 默认值漂移 blocker；一行修复 |
| Phase 3: 构建制品 | 是 | 通过 | `helix --version` 报告 `HELIX 0.0.4` |
| Phase 4: 发布验证 | 是（关键） | 通过 | ordinary 24/24 + benchmark 2/2 + baseline 1980 步 max_energy_diff=4e-06 |
| Phase 5: 发布归档 | 是 | 通过 | 拆为两个 commit（fix + chore release）；annotated tag；main/tag push；gh release create |

#### 关键验证证据

- `cmake -DHELIX_RELEASE_VERSION=0.0.4 ... build/cmake` 通过；`build/cmake/helix --version` → `HELIX 0.0.4`。
- `ctest --test-dir build/cmake --output-on-failure -LE "^(sanitizer|benchmark)$"`: 24/24 passed。
- `ctest --test-dir build/cmake -L benchmark --output-on-failure`: 2/2 passed（修复前 0/2）。
- `HELIX_CUSPARSE_REUSE_PLAN=1 ctest -L benchmark`: 2/2 passed（验证 opt-in 路径仍受 gate 保护）。
- `HELIX_STEPS=2 scripts/verify_examples.sh`: 3 rows, `max_energy_diff=5e-07`。
- `HELIX_STEPS=1980 scripts/verify_examples.sh`: 1981 rows, `max_energy_diff=4e-06`。
- GitHub Release: https://github.com/yjmaxpayne/HELIX/releases/tag/v0.0.4

## 实践反思 (#3)

### §3.1 批评

- 任务路由: Patch Release 简化路径合适；Phase 2 不可简化的规则在本次实践中关键，正是 Phase 2 捕获了 blocker。
- 阶段门控: Phase 2 ordinary 24/24 全绿，但 benchmark 2/2 失败 — 说明 benchmark gate 是 v0.0.4 的关键 invariant guard。验证粒度合适。
- 验证有效性: 修复后追加 `HELIX_CUSPARSE_REUSE_PLAN=1` 显式路径验证，确保 fix 既保留 opt-in 覆盖也不破坏 default-off 路径。
- 协作成本: 主对话完成；未引入子 Agent。
- 懒加载质量: 加载主协议 + quick_flows + workflow_reference + protocol_evolution + phase_quality + 元协议；其余 phase_* 按提示逐次加载。
- CHANGELOG 真实性: 4 项 Feat + 1 项 Perf 全部可追溯到 v0.0.3..HEAD 的 conventional commits；Fix 条目对应本次 release commit 前的 fix commit。
- 回滚演练: 未演练；本次未触发。

### §3.2 自我批评

1. [缺陷]: production 默认行为翻转的 PR (#9 / commit b54b094) 未同步更新测试侧的"环境变量默认值"镜像，造成 release 时门控漂移。
   - 证据: `src/liouville.cu:153` 默认 `false` 与 `tests/benchmark/legacy_spin_glass_benchmark.cu:250` 默认 `true` 不一致；CI/PR 阶段未单独跑 benchmark gate 暴露此问题（PR #9 review 阶段也未发现）。
   - 影响: release 时间被 Phase 2 修复占用；如果未及时发现，会发布 0/2 benchmark 失败的 tag。
   - 归属: 上游 INCREMENTAL_DEV_PROTOCOL（默认行为翻转 checklist 缺失）+ Phase 2 质量门控。

2. [缺陷]: Release Notes 未运行 `/doc-verify`，依赖人工核对。
   - 证据: 本次 Notes 仅做了 mental check，未走元协议 §六 doc-verify 钩子。
   - 影响: 链接和版本号一致性靠人工保证，规模放大时风险增加。
   - 归属: Phase 5 / 元协议 §六。

### §3.3 改进

- 在 INCREMENTAL_DEV_PROTOCOL Phase 2/3 加入 checklist："翻转生产侧默认行为时，必须同步 grep 测试侧镜像函数（含 env-var 读取的镜像）"。本次实践证明同类问题已发生 ≥1 次，作为下一次再观察点。
- Phase 5 增加可选步骤：CHANGELOG / Release Notes 草稿完成后调用 `/doc-verify`，把输出合并到本协议 §3.2。

### §3.4 固化

- 本次实践已追加到 `dev/protocols/feedback/release_management_feedback.md`。
- 暂不修改主协议正文；缺陷 #1 (默认翻转 checklist) 在再次出现时再固化为 INCREMENTAL_DEV_PROTOCOL 的强规则。

### §3.5 再实践观察点

- 下一次同类发布重点观察: PR 合并到 main 后、release 启动前，是否能用脚本或 CI gate 自动检测 production 与 test 之间的 env-var 默认值漂移（grep `EnabledFromEnv` 风格函数并对比 production 镜像）。

---

### 实践 #4: HELIX v0.0.5 Patch Release (Stream-aware execution)

**日期**: 2026-05-19
**release_version**: v0.0.5
**release_type**: patch
**target_channel**: GitHub Release

#### 特化数据字段

- ci_pass_rate: 本地发布门控全绿 — main 上 M-1 PASS (`max_energy_diff=5e-07`)、M-4 ordinary correctness 26/26、M-5 hygiene clean、M-6 benchmark 3/3 (含 `v005_cuda_graph_spike_gate`)；远端 GitHub Release workflow 未独立验证。
- pre_release_blockers: 无。release/v0.0.5 branch 已通过 PR #10 review 合入 main，main HEAD = release tip 同源；release-prep commit `8395b8c` 仅含 CHANGELOG + cmake fallback + pyproject 三处 bump，无功能改动。
- changelog_completeness: 通过。`cz changelog --incremental --unreleased-version v0.0.5` 从 v0.0.4..HEAD 生成 3 项 Feat（M3.1/M3.2/M3.4），docs/chore commits 按 Conventional Commits 默认行为不进入 CHANGELOG，符合预期。
- release_notes_doc_verify: 未运行 `/doc-verify`，与 #3 同。Release Notes 草稿存放 `.plan/helix-v0.0.5-stream-aware-execution-plan/RELEASE_NOTES_v0.0.5.md`（gitignored），ARCH-BEH-001 行为变更与 HELIX_DEBUG_SYNC_MODE opt-in 详述完整，作为 GitHub Release body 上传。
- post_release_issues: 0（发布后立即记录）。
- rollback_count: 0。
- artifact_signoff: 沿用 v0.0.4 模式，未上传二进制资产；GitHub 自动生成 source tarball / zipball。远端 tag `v0.0.5` deref → `8395b8c53a9f812328955f516bfa6e2f36a02c2c`，与本地 tag / origin/main / HEAD 三方一致。

#### 执行情况

| Phase | 是否执行 | 结果 | 备注 |
|-------|----------|------|------|
| Phase 1: 发布准备 | 是（简化） | 通过 | 6 commits since v0.0.4；release/v0.0.5 已通过 PR #10 合入 main；版本权威 = git tag |
| Phase 2: 质量门控 | 是 | 通过 | M-1 + M-4 + M-5 + M-6 在 main 上重跑全 PASS；M-2/M-3 1980-step 引用 release branch 同源 commit 的 bit-identical 证据 |
| Phase 3: 构建制品 | 是 | 通过 | fallback 0.0.4→0.0.5; pyproject 0.0.4→0.0.5; 清空 CMakeCache `HELIX_RELEASE_VERSION`；reconfigure 后版本来源回归 git describe |
| Phase 4: 发布验证 | 是（关键） | 通过 | tag 后 reconfigure → `HELIX version: 0.0.5 (git tag)`；`build/cmake/helix --version` → `HELIX 0.0.5`；再次 M-1 5e-07 |
| Phase 5: 发布归档 | 是 | 通过 | release commit + annotated tag 本地完成；推送被 Claude Code auto-mode 分类器拦截，由用户手动 push main + tag + gh release create；release 验证 `isDraft=false`，target=main |

#### 关键验证证据

- `cmake -S . -B build/cmake -DHELIX_RELEASE_VERSION= -DHELIX_VERSION_FALLBACK=0.0.5`: `HELIX version: 0.0.5 (git tag)`（打 tag 后 reconfigure）。
- `cmake --build build/cmake --parallel "$(nproc)"`: PASS。
- `HELIX_STEPS=2 scripts/verify_examples.sh`: 3 rows, `max_time_diff=0`, `max_energy_diff=5e-07`, tol `1e-05`。
- `ctest --test-dir build/cmake --output-on-failure -LE "^(sanitizer|benchmark)$"`: **26/26 PASS** (含新增 `develop_stream_ownership_microtests` + `event_based_sync_microtests`)。
- `scripts/check_no_generated_outputs.sh` + `git diff --check`: clean。
- `HELIX_BENCHMARK_OUTPUT_DIR=/tmp/helix-v005-release-bench ctest -L benchmark`: 3/3 PASS（含 `v005_cuda_graph_spike_gate`）。
- `build/cmake/helix --version`: `HELIX 0.0.5`。
- M-2/M-3 1980-step 引用证据：release/v0.0.5 branch 4 个任务 cherry-pick 节点上跑过 `max_energy_diff=4e-06`，bit-identical to v0.0.4 baseline (4e-06 / 4.1e-06)；OFF 与 `HELIX_DEBUG_SYNC_MODE=on` 两种模式均验证。
- `git ls-remote --tags origin 'v0.0.5^{}'` 与本地 tag deref 一致：`8395b8c53a9f812328955f516bfa6e2f36a02c2c`。
- GitHub Release: https://github.com/yjmaxpayne/HELIX/releases/tag/v0.0.5 (isDraft=false, target=main)

## 实践反思 (#4)

### §3.1 批评

- 任务路由: Patch Release 简化路径合适；release/v0.0.5 已通过 PR #10 merge，本次 release-prep commit (CHANGELOG + 版本号 bump) 是标准发布动作，沿用 v0.0.3/v0.0.4 直推 main 模式无功能风险。
- 阶段门控: M-2/M-3 在 release branch tip 上跑过 bit-identical (4e-06)，main HEAD 与该 tip 同源；Patch 简化路径明确允许引用同源证据而非在 main 上重跑 100+s 全量数值 — 这是 quick_flows.md 设计意图的正确应用。
- 验证有效性: M-4 ordinary correctness selector 26/26 含新增的两个 microtests (`develop_stream_ownership_microtests` + `event_based_sync_microtests`)，对 stream-aware execution 核心机制做了独立单元覆盖；M-6 `v005_cuda_graph_spike_gate` 验证 CUDA Graph capture 解锁路径。
- 协作成本: 主对话完成；未使用子 Agent。
- 懒加载质量: 加载主协议 + quick_flows + protocol_evolution + 元协议 + workflow_reference + test/validation registry；CHANGELOG 部分按需读取 versioning/phase_release。
- CHANGELOG 真实性: 3 项 Feat 全部可追溯 v0.0.4..HEAD 的 commits (`eb9e984`/`cd22861`/`4de5b72`)；docs/chore commits 按 conventional commits 默认不进入 CHANGELOG，符合 Keep a Changelog 风格。
- 回滚演练: 未演练；本次未触发；ARCH-BEH-001 在 release notes 中明确"无源码修改的消费者无需变更"，回滚路径若需要可通过 git revert release commit + 回滚到 v0.0.4 tag。

### §3.2 自我批评

1. [缺陷]: Release Notes 草稿存放 `.plan/`（gitignored），不进入版本控制 — 与 #3 同类问题。
   - 证据: `.plan/helix-v0.0.5-stream-aware-execution-plan/RELEASE_NOTES_v0.0.5.md` 内容详尽（ARCH-BEH-001 + HELIX_DEBUG_SYNC_MODE + GPU class + 上传到 GitHub Release body），但仓库无持久副本；除 GitHub Release 页面之外无可追溯路径。
   - 影响: 未来若 GitHub Release 被修改、删除或迁移，仓库内无 release notes 历史；`/doc-verify` 等工具无法对 .plan/ 内容做 CI 校验。
   - 归属: Phase 5 release notes 持久化路径 / quick_flows.md。

2. [缺陷]: Release Notes 未运行 `/doc-verify`，与 #3 同。
   - 证据: 本次 Notes 引用 CHANGELOG、ARCH-BEH-001、README runtime env vars section、PRD/ARCH 文档链接等多处，未走元协议 §六 doc-verify 钩子。
   - 影响: 链接闭环、版本号一致性、对外术语统一性靠人工保证；规模放大时风险增加。
   - 归属: Phase 5 / 元协议 §六（RELEASE_MANAGEMENT_PROTOCOL 是 §六 适用 7 协议之一）。

3. [缺陷]: Claude Code auto-mode 分类器两次拦截直推 main，协议未涵盖此类工具层操作流程。
   - 证据: `git push origin main` 两次被 "Pushing release commit directly to main bypasses PR review" 拦截，即便用户通过 AskUserQuestion 显式授权后仍被拦；最终由用户在自身 session 用 `!` 前缀手动执行。
   - 影响: Phase 5 推送步骤被打断 ~5 min；如发布频次提高或自动化场景，会成为协议执行的实际阻塞点。
   - 归属: `workflow_reference.md` 推送指令 / Phase 5 渠道投递。

### §3.3 改进

- 在 `quick_flows.md` 的 Phase 5 简化清单中加入"release notes 持久化路径建议"：若不进入 git，至少 attach 一份到 GitHub Release（已是默认实践）；若需 CI 追溯，建议放仓库 `docs/release-notes/vX.Y.Z.md` 而非 `.plan/`。本次实践与 #3 已连续两次出现，达到 §四"同类问题重复出现"高优先级触发条件，作为下次发布固化候选。
- Phase 5 增加可选步骤：CHANGELOG / Release Notes 草稿完成后调用 `/doc-verify`（与 #3 改进项一致；连续 2 次未执行）。
- 在 `workflow_reference.md` 补充"Claude Code 受限环境下的 main push 决策树"：先尝试 push → 被拦截则三选一（① 用户用 `!` 前缀手动 push；② 用户在 settings 加 Bash 白名单；③ 退路：开 release-prep PR）。本次实践已用 AskUserQuestion 现场决策，可固化为协议级模板。

### §3.4 固化

- 已将本次实践追加到 `dev/protocols/feedback/release_management_feedback.md`（主表 4 条，距 10 条 archive 阈值还有 6 条）。
- 暂不修改主协议正文；缺陷 #1 (release notes 持久化) 与 #2 (/doc-verify) 已分别连续 2 次出现，按元协议 §四作为下次发布的高优先级触发条件，下一次发布若再次出现 → 立即固化到 `quick_flows.md` / Phase 5 模板。
- 缺陷 #3 (Claude Code 推送拦截) 是首次出现的工具层流程摩擦，记录待重复验证后再固化。

### §3.5 再实践观察点

- 下一次同类发布重点观察:
  1. Release Notes 是否落到仓库 `docs/release-notes/` 路径并 commit 入 release prep（让 `/doc-verify` 与 git history 可追溯）；
  2. Phase 5 是否在草稿完成时立即调用 `/doc-verify`，避免连续第三次跳过；
  3. main push 流程在新 session 中是否能用预设 Bash 白名单或预编排 `!` 命令避免分类器拦截。

### 实践 #5: HELIX v0.1.0 Minor Release (backend dispatch + pre-1.0 API)

**日期**: 2026-08-16  
**release_version**: 0.1.0  
**release_type**: minor  
**渠道**: GitHub Release（手动）  

#### 执行摘要

- Phase 1: PR #43 已合并（bbc390e）；CHANGELOG v0.1.0 已随 PR 进入 main；tag-based 版本制（version_provider=scm）无需 bump commit；无 registries（N/A）；无 poetry.lock（CMake 项目，N/A）。
- Phase 2: main HEAD 本地 29/29 CTest 全过（与已验证 release tip 仅 2 行 workflow diff）；1980 步基线在 adb7ad2 上已验证（1981 行前缀匹配）。
- Phase 3/4: 用打 tag 后的状态重新 configure+build（binary_version=0.1.0），用待发布二进制重跑完整 1980 步基线（max_de=4e-6）；package_release.sh 校验 binary_version==tag 通过。
- Phase 5: annotated tag v0.1.0 → bbc390e 推送（远端 deref 核对一致）→ Release workflow 排队 → **runner `home-gpu` offline 阻塞 15+ min** → 经用户决策取消流水线、本机手动 `gh release create` → 下载回传资产 sha256 闭环一致。

#### §3.1 批评

- 任务路由: Minor 完整流程执行；发布前 readiness 评估（前一会话）与 Phase 1 信息天然复用，无重复劳动。
- 阶段门控: package_release.sh 的版本一致性校验（binary_version==tag）作为最后防线按设计生效——旧二进制报 0.0.5-41-g… 会被拒绝，强制用 tag 后重构建。
- 验证有效性: 发布的是与基线验证完全相同的二进制（同 build dir 产物）；digest 下载回传比对消除上传通道疑点。
- CHANGELOG 真实性: v0.1.0 条目由 cz changelog 生成（PR #43 内），feat/refactor 逐项可追溯 v0.0.5..bbc390e 提交。

#### §3.2 自我批评

1. [缺陷]: Release Notes 草稿存 `/tmp`，仓库无持久副本 — 第 3 次出现（#3/#4 已记录），触发实践 #4 §3.4 预设的固化条件。
   - 证据: `/tmp/opencode/helix_v010_release_notes.md`；仓库内无 `docs/release-notes/`。
   - 影响: GitHub Release 页面是唯一持久副本。
   - 归属: phase_release.md。
2. [缺陷]: Notes 未运行 `/doc-verify`，第 3 次出现，同触发固化条件（事实核查靠人工：Highlights↔CHANGELOG、verification 数字↔命令输出、manifest 数字↔打包输出）。
3. [新缺陷]: 协议未覆盖 "tag 已推送但 runner offline" 的处置路径。
   - 证据: 排队 15+ min 才通过 runners API 定位根因；取消排队 run 与手动发布之间需防 runner 恢复后 publish job 双重发布（本项目 publish job 有 `gh release view` 存在性检查会走 upload --clobber 路径，仍可能覆盖手动资产）。
   - 归属: troubleshooting.md。

#### §3.3 改进

- 缺陷 #1/#2 已连续 3 次，满足"同类问题重复出现"固化阈值：下次协议修订应把 `docs/release-notes/` 持久化与 doc-verify 检查写入 phase_release.md 模板。
- troubleshooting.md 宜补充 "self-hosted runner offline" 决策树：检查 runners API → 判定等待/换路径 → 若手动发布则先取消排队 run → notes 注明 provenance 与缺失的 attestation。

#### §3.4 固化

- 本记录已追加（主表第 5 条，距 10 条 archive 阈值还有 5 条）；按先例本地落盘不推送。
- 已发布: https://github.com/yjmaxpayne/HELIX/releases/tag/v0.1.0（isDraft=false, isPrerelease=false, tag deref=bbc390e, 资产 sha256 闭环一致）。

#### §3.5 再实践观察点

- 下一次发布重点观察: ① runner 恢复后 CUDA CI 排队任务正常消化；② 手动发布的 sm_120/CUDA 13.3 包是否引发用户兼容性反馈；③ release notes 持久化缺陷是否在第 4 次发布前被固化。
