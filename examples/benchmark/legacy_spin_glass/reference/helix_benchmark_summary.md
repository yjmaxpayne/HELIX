# HELIX benchmark summary

This file is a release/PR handoff summary for benchmark trends. It is not a correctness gate, and HELIX does not apply a default speed threshold to this benchmark.

## Artifacts

- Schema version: `helix.benchmark.v1`
- Artifact root: `/home/yjmaxpayne/Dev/HELIX/examples/benchmark/legacy_spin_glass/reference`
- JSONL: `/home/yjmaxpayne/Dev/HELIX/examples/benchmark/legacy_spin_glass/reference/helix_benchmark.jsonl`
- Summary: `/home/yjmaxpayne/Dev/HELIX/examples/benchmark/legacy_spin_glass/reference/helix_benchmark_summary.md`
- Nsight directory: `/home/yjmaxpayne/Dev/HELIX/examples/benchmark/legacy_spin_glass/reference/nsight`
- Retention: benchmark artifacts are separate from ordinary CUDA correctness logs; manual or scheduled benchmark workflows should upload only this artifact root.

## Run metadata

| Field | Value |
| --- | --- |
| Run ID | `20260513T130853Z-legacy-spin-glass-sm89` |
| Timestamp UTC | `2026-05-13T13:08:53Z` |
| HELIX version | `0.0.2-2-gd62bffd-dirty` |
| Version source | `git tag` |
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
| Init | 131.462 | Context construction |
| Warmup | 83.644 | Warmup propagation |
| Steady propagation | 64.683 | excludes_init_warmup_result_extraction |
| Result extraction | 13.021 | Final reduced-density copy |
| Teardown | 10.511 | Context destruction |

## Memory

| Metric | Value |
| --- | ---: |
| Peak device bytes | 4629397504 |
| Device delta bytes | 551550976 |
| Measurement method | `cudaMemGetInfo_delta` |

## Gate status

| Gate | Status | Meaning |
| --- | --- | --- |
| Correctness | `passed` | One of `not_run`, `passed`, or `failed`; benchmark runs default to `not_run`. |
| Baseline | `passed` | One of `not_run`, `passed`, or `failed`; benchmark runs default to `not_run`. |

## Profiling evidence

- Instrumentation: `runner_wall_clock, cudaDeviceSynchronize_phase_boundaries, nsight_systems`
- NVTX enabled: `false`
- Nsight artifact (`profiling.nsight_artifact`): `nsight/20260513T130852Z-legacy-spin-glass-systems.nsys-rep`
- Nsight directory: `/home/yjmaxpayne/Dev/HELIX/examples/benchmark/legacy_spin_glass/reference/nsight`

| Hypothesis | Status | Fields | Method | Interpretation | Downstream action |
| --- | --- | --- | --- | --- | --- |
| H-001 descriptor/workspace rebuild cost | `inconclusive` | context_init_ms=131.462 ms; wrapper_call_count=not_collected count; descriptor_rebuild_time_ms=not_collected ms | runner wall-clock timing around helix::Context construction with CUDA sync boundaries | Context init timing is available as a P0 proxy, but descriptor/workspace rebuild counters are not separated yet. | Add internal descriptor/workspace counters before backend redesign comparison. |
| H-002 host copy / result extraction cost | `collected` | result_extraction_ms=13.021 ms; d2h_bytes=not_collected bytes; result_extraction_entrypoint=helix::Context::reduced_density | runner wall-clock timing around final reduced-density extraction with CUDA sync boundaries | Result extraction time is captured; D2H byte attribution remains a future internal counter. | Split reduced-density copy bytes and host allocation cost in the backend redesign harness. |
| H-003 device-wide sync serialization | `inconclusive` | runner_phase_boundary_sync_count=10 count; known_sync_locations=before/after init,warmup,steady_propagation,result_extraction,teardown | explicit runner cudaDeviceSynchronize calls around each measured phase | Runner sync boundaries are known, but internal library synchronization is not independently counted. | Replace device-wide timing fences with stream/event timing where redesign experiments need overlap evidence. |
| H-004 stream/handle ownership cost | `inconclusive` | context_init_ms=131.462 ms; stream_count=not_collected count; cublas_handle_count=not_collected count; cusparse_handle_count=not_collected count | runner wall-clock timing around Context construction; no public API profiling sink is enabled | Handle ownership cost is only visible through aggregate init timing in this P0 evidence. | Add opt-in internal handle lifetime counters outside public headers. |
| H-005 transpose/layout hotspot | `not_collected` | transpose_count=not_collected count; transpose_time_ms=not_collected ms; future_marker_names=transpose_initial_rho,transpose_density_snapshot | reserved evidence slot for future internal counters or optional NVTX markers | No transpose/layout hotspot data is collected by the current runner. | Instrument transpose/layout markers in PLAN-T7 or backend redesign profiling runs. |

## Release / PR handoff snippet

- Environment: `NVIDIA GeForce RTX 4070 SUPER`, CUDA runtime `13.0`, driver `13.0`, build `Release`, arch `89`.
- Case: `legacy_spin_glass_default` using `LegacyCudaSparse` / `single`, N=1024, KMax=2, JMax=3, hierarchy=10, steps=2.
- Phase timing ms: init=131.462, warmup=83.644, steady=64.683, extraction=13.021, teardown=10.511.
- Memory: peak_device_bytes=4629397504, device_delta_bytes=551550976, method=`cudaMemGetInfo_delta`.
- Gates: correctness=`passed`, baseline=`passed`; speed threshold=`none`.
- Profiling evidence: H-001..H-005 slots are populated in `profiling.hypotheses`; `not_collected` marks intentionally deferred counters.
