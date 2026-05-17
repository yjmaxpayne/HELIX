# HELIX benchmark summary

This file is a release/PR handoff summary for benchmark trends. It is not a correctness gate, and HELIX does not apply a default speed threshold to this benchmark. It does not replace the `examples/outputEnergy.txt` numerical baseline.

## Artifacts

- Schema version: `helix.benchmark.v1`
- Artifact root: `/tmp/helix-t9-ref-20260515-001`
- JSONL: `/tmp/helix-t9-ref-20260515-001/helix_benchmark.jsonl`
- Summary: `/tmp/helix-t9-ref-20260515-001/helix_benchmark_summary.md`
- Nsight directory: `/tmp/helix-t9-ref-20260515-001/nsight`
- Retention: benchmark artifacts are separate from ordinary CUDA correctness logs; manual or scheduled benchmark workflows should upload only this artifact root.

## Run metadata

| Field | Value |
| --- | --- |
| Run ID | `20260515T023103Z-legacy-spin-glass-sm89` |
| Timestamp UTC | `2026-05-15T02:31:03Z` |
| HELIX version | `0.0.3` |
| Version source | `HELIX_RELEASE_VERSION` |
| Git commit | `unknown` |
| Git dirty | `unknown` |
| Build type | `Release` |
| CUDA architectures | `89` |
| Compiler | `GNU 13.3.0` |
| Host OS | `linux` |
| Host runner | `ctest_or_manual` |
| GPU | `NVIDIA GeForce RTX 4070 SUPER` |
| GPU device | `0` |
| GPU driver | `13.0` |
| GPU total memory bytes | 12447776768 |
| CUDA runtime | `13.0` |
| CUDA driver | `13.0` |

## Case metadata

| Field | Value |
| --- | --- |
| Name | `legacy_spin_glass_default` |
| Backend | `LegacyCudaSparse` |
| Precision | `single` |
| Result mode | `FinalState` |
| N | 1024 |
| KMax | 2 |
| JMax | 3 |
| Hierarchy size | 10 |
| Time step | 0.100 |
| Integration order | 4 |
| Steps | 2 |
| Warmup steps | 1 |
| Steady steps | 1 |
| Result shape | 1 x 1024 x 1024 |

## Timing (ms)

| Phase | Milliseconds | Notes |
| --- | ---: | --- |
| Init | 82.235 | Context construction |
| Warmup | 95.273 | Warmup propagation |
| Steady propagation | 85.718 | excludes_init_warmup_result_extraction |
| Result extraction | 7.910 | Final reduced-density copy |
| Teardown | 9.516 | Context destruction |

## Measurement scope

Main timing fields are the benchmark measurement aggregation. Calibration is a separate cross-check scope and is never included in main aggregation.

| Field | Value |
| --- | --- |
| Main measurement scope | `benchmark.main` |
| Main measurement status | `captured` |
| Calibration scope | `benchmark.calibration` |
| Calibration status | `captured` |
| Calibration captured | `true` |
| Calibration excluded from main aggregation | `true` |
| NVTX naming convention | `benchmark.main.init,benchmark.main.warmup,benchmark.main.steady_propagation,benchmark.main.result_extraction,benchmark.main.teardown,benchmark.calibration` |

## Memory

| Metric | Value |
| --- | ---: |
| Peak device bytes | 1821900800 |
| Device delta bytes | 551550976 |
| Measurement method | `cudaMemGetInfo_delta` |

## Gate status

| Gate | Status | Meaning |
| --- | --- | --- |
| Correctness | `passed` | One of `not_run`, `passed`, or `failed`; benchmark runs default to `not_run`. |
| Baseline | `passed` | One of `not_run`, `passed`, or `failed`; benchmark runs default to `not_run`. |

## Profiling counters

`profiling.counters` uses numeric values when collected and `not_collected` for reserved fields that were not observed in this run.

| Group | Counter | Value |
| --- | --- | ---: |
| spmm | call_count | `320` |
| spmm | descriptor_create_count | `0` |
| spmm | workspace_alloc_count | `0` |
| spmm | workspace_bytes | `183` |
| spmm | buffer_size_query_count | `0` |
| transpose | call_count | `320` |
| transpose | time_ms | `not_collected` |
| transpose | bytes | `2684354560` |
| d2d_copy | copy_count | `2` |
| d2d_copy | bytes | `167772160` |
| sync | device_synchronize_count | `1` |
| sync | sync_wait_ms | `0.000` |
| result_extraction | sync_wait_ms | `0.000` |
| result_extraction | host_allocation_ms | `2.249` |
| result_extraction | d2h_copy_ms | `0.588` |
| result_extraction | conversion_ms | `5.069` |
| result_extraction | d2h_bytes | `8388608` |
| result_extraction | element_count | `1048576` |

## CUDA 13 cuSPARSE API decision

| API | Decision | Reason | Correctness risk | Workspace lifetime risk | Graph capture impact |
| --- | --- | --- | --- | --- | --- |
| `cusparseDnMatSetValues` | adopt | Dense input/output pointers change between hierarchy blocks while shape stays fixed; the backend plan updates only those pointers before `cusparseSpMM`. | Low if shape/leading dimensions are unchanged; CUDA micro tests cover pointer update with different buffers. | No workspace ownership change; existing workspace remains plan-owned. | Positive precondition for future capture because descriptors stay stable, but graph capture is not implemented in T4. |
| `cusparseSpMatSetValues` | reject for T4 | Current H/V sparse values are stable and use separate reusable plans; values-only rebinding is unnecessary. | Avoids silently rebinding the wrong sparse operator into a cached plan. | No additional workspace lifetime state. | Neutral; revisit only for a future values-only mutable sparse operator. |
| `cusparseCsrSetPointers` | defer | Full CSR pointer rebinding would need topology/nnz lifetime rules beyond the current stable H/V descriptors. | Medium; row/column/value pointer mismatches can corrupt the sparse operator if reused incorrectly. | Could invalidate preprocess/workspace assumptions if topology changes. | Potentially useful for future dynamic CSR or layout work, not required for this reuse proof. |
| `cusparseSpMM_bufferSize` | adopt | Query once when a plan is created; reuse the resulting workspace for compatible calls. | Low; incompatible shapes are rejected by the plan. | Workspace is plan-owned and released by `destroy()` / `clearLiouvilleStorage()`. | Stable workspace ownership is a prerequisite for graph capture, but capture validation is deferred. |
| `cusparseSpMM_preprocess` | defer | CUDA 13 preprocess may help selected algorithms, but active-buffer and pointer-stability constraints need separate numerical and capture gates. | Medium until algorithm-specific determinism and pointer update behavior are tested. | Medium; preprocess can add state tied to the active external buffer. | Potentially positive for graph capture, but T4 does not claim capture readiness. |

## Structural SpMM reuse comparison

The legacy wrapper row is a static before estimate from `src/cuda_types.h` for the same observed steady-scope SpMM call count. The reuse row is measured from `profiling.counters.spmm` after warmup has primed the backend plan.

| Path | Evidence | SpMM calls | Descriptor creates | Buffer-size queries | Workspace allocations | Per-SpMM setup behavior |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| Legacy wrapper compatibility path | Static wrapper structure: `cusparseCreateCsr` + two `cusparseCreateDnMat` + `cusparseSpMM_bufferSize` per wrapper call | `320` | `960` | `320` | `320` | Rebuilds descriptors and queries workspace per SpMM call. |
| Reusable backend plan | Measured `CudaSparseBackendPlan` counters in the profiled steady scope | `320` | `0` | `0` | `0` | Dense pointers are updated with `cusparseDnMatSetValues`; descriptor/workspace setup is zero after warmup for compatible calls. |

## H_DIAGONAL elementwise specialization comparison

The compiled `H_DIAGONAL` path now evaluates `-i * (H[row] - H[column]) * rho[row,column]` with one elementwise CUDA kernel per hierarchy block/RHS evaluation. This removes the previous H-path DGMM, H-path SpMM, and two H-path physical transposes while leaving the generic non-diagonal sparse commutator fallback unchanged.

| Path | Evidence | Steady SpMM calls | H SpMM calls avoided | H transpose calls avoided |
| --- | --- | ---: | ---: | ---: |
| Previous compiled diagonal-H sparse path | Structural estimate: measured specialized SpMM calls plus one H SpMM per hierarchy block per integration substep | `360` | `0` | `0` |
| Elementwise H_DIAGONAL path | Measured `profiling.counters.spmm.call_count`; expected V-path-only calls `320` | `320` | `40` | `80` |

## Structured V specialization spike decision

Decision: `defer_legacy_spin_glass_only`. The default legacy spin-glass `V` operator has a known diagonal plus single-spin-flip structure, but replacing the current generic sparse SpMM path with a model-specific kernel is deferred to a separate spike with its own reference and baseline gates.

| Field | Value |
| --- | --- |
| Decision | `defer_legacy_spin_glass_only` |
| Candidate scope | private default legacy spin-glass adapter only |
| Generic sparse contract | `System::from_sparse()` remains validation-only and unaffected |
| Public API expansion | rejected for v0.0.4 |
| Speed threshold | none; benchmark evidence is trend evidence only |
| Spin count inferred from N | `10` |
| Structured V nnz estimate | `11264` |
| Current V-path SpMM calls in steady scope | `320` |
| Current V-path physical transpose calls in steady scope | `320` |

Boundary: this decision does not promote arbitrary sparse HEOM runtime support. If structured V is revisited, it should live behind the existing private legacy spin-glass compatibility adapter, keep the reusable sparse plan as the generic fallback, and prove equivalence with CUDA reference-kernel tests plus quick and `HELIX_STEPS=1980` baselines.

## Integrator D2D recurrence comparison

The Taylor-like recurrence now keeps the accumulated result in a private scratch buffer and alternates the current recurrence state between `dRho` and the derivative scratch buffer. This removes the previous full-buffer `B -> dRho` copy after each integration order. Final ownership is unchanged: before `develop()` returns, the accumulator is copied back into global `dRho`, and result extraction reads block 0 from `dRho`.

| Metric | Value |
| --- | ---: |
| integrator_order_count | `4` |
| steady_steps_profiled | `1` |
| full_hierarchy_copy_bytes | `83886080` |
| previous_copy_based_copy_count | `6` |
| previous_copy_based_copy_bytes | `503316480` |
| swap_recurrence_expected_copy_count | `2` |
| swap_recurrence_expected_copy_bytes | `167772160` |
| avoided_copy_count | `4` |
| avoided_copy_bytes | `335544320` |
| measured_d2d_copy_count | `2` |
| measured_d2d_copy_bytes | `167772160` |

## Layout / transpose option matrix

Current benchmark evidence records physical transpose call count and bytes in `profiling.counters.transpose`. `transpose.time_ms` intentionally remains `not_collected`: adding event timing inside the production wrapper would introduce stream synchronization pressure into the path being measured. Use Nsight or a separate event-timing experiment when wall-clock attribution is needed.

| Metric | Value |
| --- | ---: |
| transpose_call_count | `320` |
| expected_current_physical_transpose_call_count | `320` |
| transpose_bytes | `2684354560` |
| transpose_time_ms | `not_collected` |
| transpose_time_ms_policy | `not_collected_without_extra_stream_sync` |

| Option | Decision | Reason | Compatibility boundary |
| --- | --- | --- | --- |
| Current physical transpose around sparse commutator outputs | adopt for v0.0.4 | It preserves the tested row-major density buffer semantics while exposing the remaining cost through counters. | Keep `transpose()` shape-safe and profiled; revisit only with small reference and baseline gates. |
| cuSPARSE dense descriptor order/opB rewrite | defer | The current reusable plan uses stable column-major descriptors plus explicit transposes; changing order/opB would couple cuSPARSE assumptions to cuBLAS accumulation and needs a dedicated reference gate. | Prototype behind a local option before replacing the production path. |
| Internal row-major density storage | adopt/retain | `dRho`, result extraction, public shape tests, and energy helpers already agree on row-major flat indexing. | Any future backend-local layout must convert at the result extraction boundary. |
| Public result order | adopt/lock | public result order remains row-major via `ReducedDensityShape::storageOrder`. | `ResultExtractor::final_reduced_density()` is the public conversion boundary. |
| Full public layout abstraction | reject for v0.0.4 | T7 only needs a backend decision and compatibility statement, not a public API expansion. | Reconsider only when multiple public storage orders are actually supported and tested. |

## Synchronization audit and replacement plan

T8 does not remove production synchronizations. Each site below keeps an explicit correctness and error boundary until the listed stream/event dependency is implemented and tested.

| Site | Current synchronization | Retain or replacement reason | Event/stream dependency plan | Error/debug boundary |
| --- | --- | --- | --- | --- |
| `measureCudaPhase()` | `cudaDeviceSynchronize()` before and after each measured phase (`init`, `warmup`, `steady_propagation`, `result_extraction`, `teardown`; 10 runner fences per benchmark record). | Retain in benchmark timing path so wall-clock phases are closed intervals and memory snapshots have a complete device boundary. | Use CUDA events only in a future profiling mode that does not need whole-device timing fences; keep default runner fences for release artifacts. | Benchmark runner throws immediately on CUDA errors at phase boundaries. |
| `LegacyRuntimeSession::run_steps()` | `cudaDeviceSynchronize()` after every `develop()` call. | Retain as the public `Context::run_steps()` completion and error boundary while legacy global state has no explicit stream owner. | Replace only after runtime session owns an integration stream/event and callers have an explicit completion contract. | Debug/profile mode should keep this fence or an equivalent terminal stream synchronize. |
| `develop()` | Device-wide fence after `getdRhoSparse()`, `cublasScal`, and `cublasAxpy` in each integration order. | Required today because per-hierarchy sparse streams produce the derivative while the global cuBLAS handle consumes it and later iterations may read swapped buffers. | Record completion events for sparse streams, wait on the integration/cuBLAS stream before scale/accumulate, then make sparse streams wait on the integration event before the next order. | Check CUDA status after each event wait and keep a debug sync mode for first-failure attribution. |
| `getdRhoSparse()` stage barrier | Device-wide fence between the L/V sparse commutator stage and hierarchy-coupling stage. | Phase 2 reads `buffer` and `pdRho` entries produced by other hierarchy streams; per-stream ordering alone is insufficient. | Record one event per hierarchy stream after stage 1; stage 2 waits on the producer events for each referenced hierarchy block (or a tested fan-in barrier). | Preserve a stage boundary error check before launching dependent BLAS/SpMM work. |
| `getdRhoSparse()` exit barrier | Device-wide fence after all hierarchy-coupling work. | Caller `develop()` immediately consumes `drhoVec` from a different cuBLAS stream/handle. | Record per-stream completion events and wait on the integration/cuBLAS stream before `cublasScal`/`cublasAxpy`. | Keep an explicit post-derivative error boundary in debug/profile sync mode. |
| `clearLiouvilleStorage()` | Device-wide fence at entry plus per-stream synchronizes before destroying streams/handles/descriptors. | Resource teardown must not race queued kernels, cuBLAS work, cuSPARSE descriptors, or plan-owned workspaces. | Prefer per-stream synchronize/event joins for owned streams; retain a device fence while legacy global state can queue work outside tracked streams. | Teardown remains a hard synchronization boundary. |

## CUDA Graph feasibility decision

Decision: `defer_fixed_shape_capture` for v0.0.4. Fixed-shape capture is promising because the default profile has stable dimensions and warmed reusable SpMM plans, but it should not enter production until the synchronization replacement plan above has a correctness gate.

| Constraint | Current evidence | Capture impact | Decision |
| --- | --- | --- | --- |
| Shape stability | N=`1024`, hierarchy=`10`, integration_order=`4`, steady_steps=`1` in this benchmark record. | Positive for fixed-shape one-step capture after warmup. | Adopt assumption for a spike only. |
| Workspace lifetime | `CudaSparseBackendPlan` owns descriptors/workspace and steady counters show descriptor creates, workspace allocations, and buffer-size queries are zero after warmup. | Positive precondition; capture must start after initialization and plan warmup. | Adopt pre-capture warmup requirement. |
| Pointer stability | `dRho`, scratch `F`/`B`, sparse buffers, and descriptor dense pointers are stable within the fixed compiled profile; `cusparseDnMatSetValues` updates values pointers before SpMM. | Promising, but captured graphs bake pointer values and update ordering. | Defer until pointer-role swap is covered by a graph replay test. |
| Preprocess / allocation APIs | `cusparseSpMM_bufferSize` is outside steady scope; `cusparseSpMM_preprocess` remains deferred. | Capture must exclude allocation, descriptor creation, and unvalidated preprocess calls. | Defer preprocess inside capture. |
| Synchronization APIs | `develop()`, `getdRhoSparse()`, `LegacyRuntimeSession::run_steps()`, and teardown still use device-wide fences. | Device synchronization is capture-hostile and hides real stream dependencies. | Blocker; implement event dependencies first. |
| Result extraction | `ResultExtractor` intentionally synchronizes before D2H copy and conversion; public order remains row-major. | Keep extraction outside propagation capture. | Capture propagation only. |
| Debug/profile mode | Current evidence relies on runner phase fences and internal sync counters. | Debug mode needs explicit error boundaries even if production replay becomes async. | Require a debug sync mode for any future graph path. |

Rollback switch: set `HELIX_CUSPARSE_REUSE_PLAN=0` to route sparse calls through the `cuda_types.h` compatibility wrappers. This is a correctness triage fallback and reintroduces per-call wrapper setup, so it is not a performance evidence path.

## Profiling evidence

- Instrumentation: `runner_wall_clock, cudaDeviceSynchronize_phase_boundaries`
- NVTX enabled: `false`
- Nsight artifact (`profiling.nsight_artifact`): `not_collected`
- Nsight directory: `/tmp/helix-t9-ref-20260515-001/nsight`

| Hypothesis | Status | Fields | Method | Interpretation | Downstream action |
| --- | --- | --- | --- | --- | --- |
| H-001 descriptor/workspace rebuild cost | `collected` | context_init_ms=82.235 ms; spmm_call_count=320 count; descriptor_create_count=0 count; buffer_size_query_count=0 count; workspace_alloc_count=0 count; workspace_bytes=183 bytes; spmm_time_ms=not_collected ms; structured_v_specialization_decision=defer_legacy_spin_glass_only; structured_v_generic_sparse_contract=unaffected:System::from_sparse_validation_only | private CudaSparseBackendPlan SpMM counters captured in the steady propagation scope after warmup | Descriptor creation, workspace allocation, buffer-size query, and SpMM call counters are separated from aggregate timing; warmed compatible calls should report zero setup counters. Structured V replacement remains deferred as a legacy spin-glass-only kernel decision, not a generic sparse contract. | Keep System::from_sparse() validation-only unchanged; revisit structured V only behind a private legacy adapter with reference-kernel, benchmark, and baseline gates. |
| H-002 host copy / result extraction cost | `collected` | result_extraction_ms=7.910 ms; sync_wait_ms=0.000 ms; host_allocation_ms=2.249 ms; d2h_copy_ms=0.588 ms; conversion_ms=5.069 ms; d2h_bytes=8388608 bytes; element_count=1048576 count; result_extraction_entrypoint=helix::Context::reduced_density | internal ResultExtractor substage counters captured by the private backend profiling sink | Result extraction is split into sync wait, host allocation, D2H copy, conversion, bytes, and element count. | Use the substage distribution to decide whether final-state extraction needs buffer/layout changes. |
| H-003 device-wide sync serialization | `inconclusive` | runner_phase_boundary_sync_count=10 count; internal_device_synchronize_count=1 count; internal_sync_wait_ms=0.000 ms; known_sync_locations=before/after init,warmup,steady_propagation,result_extraction,teardown; sync_audit_sites=measureCudaPhase,LegacyRuntimeSession::run_steps,develop,getdRhoSparse,clearLiouvilleStorage; event_replacement_plan=required_before_removing_sync; cuda_graph_decision=defer_fixed_shape_capture | explicit runner cudaDeviceSynchronize calls around each measured phase plus static audit of production synchronization sites | Production hot-path synchronizations remain correctness and error boundaries; replacing them requires explicit stream/event dependencies before fixed-shape graph capture is credible. | Implement and test event dependencies for develop/getdRhoSparse first, then run a dedicated CUDA Graph capture spike. |
| H-004 stream/handle ownership cost | `inconclusive` | context_init_ms=82.235 ms; stream_count=not_collected count; cublas_handle_count=not_collected count; cusparse_handle_count=not_collected count | runner wall-clock timing around Context construction; no public API profiling sink is enabled | Handle ownership cost is only visible through aggregate init timing in this P0 evidence. | Add opt-in internal handle lifetime counters outside public headers. |
| H-005 D2D copy / transpose hotspot | `collected` | transpose_count=320 count; transpose_time_ms=not_collected ms; transpose_bytes=2684354560 bytes; d2d_copy_count=2 count; d2d_copy_time_ms=not_collected ms; d2d_copy_bytes=167772160 bytes; future_marker_names=transpose_initial_rho,transpose_density_snapshot | transpose wrapper counters and integrator D2D copy counters captured in the steady propagation scope; transpose timing remains not_collected unless measured without adding stream synchronization | Physical transpose call count/bytes and integrator full-hierarchy D2D count/bytes are collected; transpose time is intentionally deferred to avoid adding synchronization to the production path. | Use the collected counts/bytes and layout option matrix to keep public row-major order while deferring descriptor-order rewrites to a separate correctness gate. |

## Release / PR handoff snippet

- Environment: `NVIDIA GeForce RTX 4070 SUPER`, CUDA runtime `13.0`, driver `13.0`, build `Release`, arch `89`.
- Case: `legacy_spin_glass_default` using `LegacyCudaSparse` / `single`, N=1024, KMax=2, JMax=3, hierarchy=10, steps=2.
- Phase timing ms: init=82.235, warmup=95.273, steady=85.718, extraction=7.910, teardown=9.516.
- Measurement scope: main=`benchmark.main`, calibration=`benchmark.calibration`, calibration_captured=`true`, calibration_excluded_from_main=`true`.
- Memory: peak_device_bytes=1821900800, device_delta_bytes=551550976, method=`cudaMemGetInfo_delta`.
- Gates: correctness=`passed`, baseline=`passed`; speed threshold=`none`.
- Profiling evidence: H-001..H-005 slots are populated in `profiling.hypotheses`; `not_collected` marks intentionally deferred counters. CUDA 13 API decisions, the structural legacy-vs-reuse comparison, the structured V specialization defer decision, the integrator D2D before-after comparison, the layout/transpose option matrix, the synchronization audit, and the CUDA Graph feasibility decision are recorded in this summary.
