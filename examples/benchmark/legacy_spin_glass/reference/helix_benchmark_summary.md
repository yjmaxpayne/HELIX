# HELIX benchmark summary

This file is a release/PR handoff summary for benchmark trends. It is not a correctness gate, and HELIX does not apply a default speed threshold to this benchmark. It does not replace the `examples/outputEnergy.txt` numerical baseline.

## Artifacts

- Schema version: `helix.benchmark.v1`
- Artifact root: `/tmp/helix-t5-benchmark-20260514-passed-v2`
- JSONL: `/tmp/helix-t5-benchmark-20260514-passed-v2/helix_benchmark.jsonl`
- Summary: `/tmp/helix-t5-benchmark-20260514-passed-v2/helix_benchmark_summary.md`
- Nsight directory: `/tmp/helix-t5-benchmark-20260514-passed-v2/nsight`
- Retention: benchmark artifacts are separate from ordinary CUDA correctness logs; manual or scheduled benchmark workflows should upload only this artifact root.

## Run metadata

| Field | Value |
| --- | --- |
| Run ID | `20260514T143451Z-legacy-spin-glass-sm89` |
| Timestamp UTC | `2026-05-14T14:34:51Z` |
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
| Init | 83.638 | Context construction |
| Warmup | 93.878 | Warmup propagation |
| Steady propagation | 85.101 | excludes_init_warmup_result_extraction |
| Result extraction | 8.134 | Final reduced-density copy |
| Teardown | 9.358 | Context destruction |

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
| Peak device bytes | 1199112192 |
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
| transpose | call_count | `not_collected` |
| transpose | time_ms | `not_collected` |
| d2d_copy | copy_count | `not_collected` |
| d2d_copy | bytes | `not_collected` |
| sync | device_synchronize_count | `1` |
| sync | sync_wait_ms | `0.000` |
| result_extraction | sync_wait_ms | `0.000` |
| result_extraction | host_allocation_ms | `2.252` |
| result_extraction | d2h_copy_ms | `0.601` |
| result_extraction | conversion_ms | `5.278` |
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

Rollback switch: set `HELIX_CUSPARSE_REUSE_PLAN=0` to route sparse calls through the `cuda_types.h` compatibility wrappers. This is a correctness triage fallback and reintroduces per-call wrapper setup, so it is not a performance evidence path.

## Profiling evidence

- Instrumentation: `runner_wall_clock, cudaDeviceSynchronize_phase_boundaries`
- NVTX enabled: `false`
- Nsight artifact (`profiling.nsight_artifact`): `not_collected`
- Nsight directory: `/tmp/helix-t5-benchmark-20260514-passed-v2/nsight`

| Hypothesis | Status | Fields | Method | Interpretation | Downstream action |
| --- | --- | --- | --- | --- | --- |
| H-001 descriptor/workspace rebuild cost | `collected` | context_init_ms=83.638 ms; spmm_call_count=320 count; descriptor_create_count=0 count; buffer_size_query_count=0 count; workspace_alloc_count=0 count; workspace_bytes=183 bytes; spmm_time_ms=not_collected ms | private CudaSparseBackendPlan SpMM counters captured in the steady propagation scope after warmup | Descriptor creation, workspace allocation, buffer-size query, and SpMM call counters are separated from aggregate timing; warmed compatible calls should report zero setup counters. | Use these counters to gate downstream H-diagonal, D2D traffic, layout, and graph feasibility tasks. |
| H-002 host copy / result extraction cost | `collected` | result_extraction_ms=8.134 ms; sync_wait_ms=0.000 ms; host_allocation_ms=2.252 ms; d2h_copy_ms=0.601 ms; conversion_ms=5.278 ms; d2h_bytes=8388608 bytes; element_count=1048576 count; result_extraction_entrypoint=helix::Context::reduced_density | internal ResultExtractor substage counters captured by the private backend profiling sink | Result extraction is split into sync wait, host allocation, D2H copy, conversion, bytes, and element count. | Use the substage distribution to decide whether final-state extraction needs buffer/layout changes. |
| H-003 device-wide sync serialization | `inconclusive` | runner_phase_boundary_sync_count=10 count; internal_device_synchronize_count=1 count; internal_sync_wait_ms=0.000 ms; known_sync_locations=before/after init,warmup,steady_propagation,result_extraction,teardown | explicit runner cudaDeviceSynchronize calls around each measured phase | Runner sync boundaries are known, but internal library synchronization is not independently counted. | Replace device-wide timing fences with stream/event timing where redesign experiments need overlap evidence. |
| H-004 stream/handle ownership cost | `inconclusive` | context_init_ms=83.638 ms; stream_count=not_collected count; cublas_handle_count=not_collected count; cusparse_handle_count=not_collected count | runner wall-clock timing around Context construction; no public API profiling sink is enabled | Handle ownership cost is only visible through aggregate init timing in this P0 evidence. | Add opt-in internal handle lifetime counters outside public headers. |
| H-005 transpose/layout hotspot | `not_collected` | transpose_count=not_collected count; transpose_time_ms=not_collected ms; transpose_bytes=not_collected bytes; d2d_copy_count=not_collected count; d2d_copy_time_ms=not_collected ms; d2d_copy_bytes=not_collected bytes; future_marker_names=transpose_initial_rho,transpose_density_snapshot | reserved evidence slot for future internal counters or optional NVTX markers | No transpose/layout hotspot data is collected by the current runner. | Instrument transpose/layout markers in PLAN-T7 or backend redesign profiling runs. |

## Release / PR handoff snippet

- Environment: `NVIDIA GeForce RTX 4070 SUPER`, CUDA runtime `13.0`, driver `13.0`, build `Release`, arch `89`.
- Case: `legacy_spin_glass_default` using `LegacyCudaSparse` / `single`, N=1024, KMax=2, JMax=3, hierarchy=10, steps=2.
- Phase timing ms: init=83.638, warmup=93.878, steady=85.101, extraction=8.134, teardown=9.358.
- Measurement scope: main=`benchmark.main`, calibration=`benchmark.calibration`, calibration_captured=`true`, calibration_excluded_from_main=`true`.
- Memory: peak_device_bytes=1199112192, device_delta_bytes=551550976, method=`cudaMemGetInfo_delta`.
- Gates: correctness=`passed`, baseline=`passed`; speed threshold=`none`.
- Profiling evidence: H-001..H-005 slots are populated in `profiling.hypotheses`; `not_collected` marks intentionally deferred counters. CUDA 13 API decisions and the structural legacy-vs-reuse comparison are recorded in this summary.
