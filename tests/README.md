# HELIX test contract

CTest labels are part of the shared test-suite contract:

- `unit`: deterministic host-side or small self-contained tests. These tests do not reserve a GPU.
- `cuda`: ordinary CUDA correctness tests that execute CUDA kernels or require a CUDA runtime device.
- `numerical`: reference-value or invariant checks with documented tolerances.
- `integration`: tests that exercise multiple HELIX components together.
- `baseline`: tests that compare against legacy executable outputs or fixtures.
- `sanitizer`: GPU resource-locked tests intended to run under CUDA or memory sanitizer tooling.
- `benchmark`: performance measurements. These should report trends, not block correctness gates.

Register tests with `helix_add_test()` in `CMakeLists.txt`. GPU tests must use the `GPU` option; the helper adds `RESOURCE_LOCK gpu`, applies a timeout, and prevents them from being mixed into the `unit` label. Sanitizer and benchmark profiles are intentionally kept out of the ordinary `cuda` label so `ctest -L cuda` remains a correctness selector instead of a profiling or sanitizer entrypoint.

## API and compatibility gates

The table below records what each named gate protects. New expected-fail gates must be registered through `helix_add_test(... EXPECTED_FAIL ...)`, use only the label contract above, and be backed by `tests/planned/expected_fail_gate.cmake`.

| Gate | Labels | GPU lock | Contract |
| --- | --- | --- | --- |
| `v01_public_header_compile_gate` | `unit` | no | A consumer can compile by including only `<helix/helix.h>`. |
| `v01_external_consumer_cmake_gate` | `integration` | no | A downstream CMake project can `find_package(HELIX CONFIG REQUIRED)` and link `HELIX::helix`. |
| `v01_api_schema_validation_gate` | `unit` | no | CSR schema validation and unsupported execution diagnostics are covered by unit tests. |
| `benchmark_schema_validation_tests` | `unit` | no | Internal `helix.benchmark.v1` sample records, JSONL emission, and schema validation stay stable. |
| `benchmark_artifact_hygiene_tests` | `unit` | no | Benchmark artifact root resolution, legacy generated-output detection, and JSONL/summary containment are covered without a GPU. |
| `v003_legacy_spin_glass_benchmark_gate` | `benchmark` | yes | Default legacy spin-glass benchmark writes `helix_benchmark.jsonl`, `helix_benchmark_summary.md`, and an `nsight/` artifact directory under the benchmark artifact root. |
| `v003_legacy_spin_glass_benchmark_example_gate` | `benchmark` | yes | User-facing benchmark example script runs the same artifact path contract from `examples/benchmark/legacy_spin_glass/`. |
| `v003_ctest_label_resource_lock_review` | `integration` | no | Generated CTest properties keep benchmark labels, GPU resource locking, ordinary CUDA labels, and the CI selector contract aligned. |
| `v01_public_lifecycle_numerical_gate` | `numerical`, auto `cuda` | yes | Public create/run/destroy/recreate lifecycle is repeatable within numerical tolerance. |
| `v01_public_solver_spin_glass_gate` | `numerical`, auto `cuda` | yes | Public `HEOMSolver` runs the legacy spin-glass compatibility adapter for a short GPU smoke and rejects arbitrary sparse execution. |
| `v01_result_shape_no_file_output_gate` | `numerical`, `integration`, auto `cuda` | yes | `RunResult` shape, diagnostics, and no-file-output library behavior are verified against the legacy CLI output contract. |
| `v01_cli_compatibility_wrapper_gate` | `integration`, `baseline`, auto `cuda` | yes | The `helix` executable preserves version flags, step env aliases, legacy output files, and short energy prefix compatibility. |
| `v01_python_smoke_gate` | `integration`, auto `cuda` | yes | Optional `HELIX_BUILD_PYTHON=ON` gate imports the Python binding, runs the smoke path, and reports result shape. |
| `v01_cpp_library_example_gate` | `integration`, auto `cuda` | yes | The documented C++ library example compiles with public headers and runs a two-step legacy spin-glass smoke without legacy file outputs. |

`helix_smoke_integration` and `HELIX_STEPS=2 scripts/verify_examples.sh` cover the legacy CLI path. For a fuller local check, run the CTest label matrix plus `HELIX_STEPS=1000 scripts/verify_examples.sh`.

Useful CTest selectors:

```sh
ctest --test-dir build/cmake -L unit --output-on-failure
ctest --test-dir build/cmake -L cuda --output-on-failure
ctest --test-dir build/cmake -L numerical --output-on-failure
ctest --test-dir build/cmake -L integration --output-on-failure
ctest --test-dir build/cmake -L baseline --output-on-failure
ctest --test-dir build/cmake -L sanitizer --output-on-failure
ctest --test-dir build/cmake -L benchmark --output-on-failure
ctest --test-dir build/cmake --output-on-failure -LE "^(sanitizer|benchmark)$"
```

## Test matrix

| Label / gate | Environment | Expected local time | Failure meaning | Used in |
| --- | --- | --- | --- | --- |
| `unit` | CUDA toolkit available; no GPU device required | <1s for current unit gates | host helper, PSD reference, parameter default, public API, or comparator regression | CUDA CI and local pre-commit |
| `cuda` | single NVIDIA GPU | ~3s for current cuda-labelled gates on RTX 4070 class hardware | CUDA micro test, GPU numerical test, or integration smoke regression | CUDA CI on self-hosted GPU runner |
| `numerical` | single NVIDIA GPU | ~2s for current numerical gates | sparse dRho, one-step invariant, or lifecycle repeatability drift beyond documented tolerance | CUDA CI on self-hosted GPU runner |
| `integration` | single NVIDIA GPU | ~2s for current default integration gates | legacy CLI output contract, isolated run directory, external consumer, C++ example failure, or optional Python smoke failure | CUDA CI on self-hosted GPU runner |
| `baseline` | single NVIDIA GPU | ~2s for CTest smoke; ~1min for `HELIX_STEPS=1000 scripts/verify_examples.sh` | checked-in energy fixture mismatch or full trajectory drift | CTest in CUDA CI; full baseline in scheduled/manual/release gates |
| `sanitizer` | single NVIDIA GPU with `compute-sanitizer` | usually <1min for the micro target | CUDA memory error, sanitizer tool failure, or report artifact failure | manual workflow dispatch only |
| `benchmark` | pinned GPU host | non-blocking | performance trend shift, not correctness failure | manual only; select explicitly with `ctest -L benchmark` |

## Benchmark artifacts

`v003_legacy_spin_glass_benchmark_gate` writes benchmark artifacts under `HELIX_BENCHMARK_OUTPUT_DIR`. If the variable is unset or empty, the runner defaults to `build/cmake/benchmark/` for the current build tree. The generated files are:

- `helix_benchmark.jsonl`
- `helix_benchmark_summary.md`
- `nsight/`

The runner prints `benchmark_artifact_root: <path>` at startup and preserves the existing stdout JSONL plus stderr summary line for interactive runs. Benchmark artifacts are separate from ordinary correctness logs; manual or scheduled benchmark workflows should set `HELIX_BENCHMARK_OUTPUT_DIR=${RUNNER_TEMP}/helix-benchmark` and upload only that directory.

Example:

```sh
HELIX_BENCHMARK_OUTPUT_DIR="$(mktemp -d)" \
  ctest --test-dir build/cmake -L benchmark --output-on-failure
```

The user-facing example wrapper is:

```sh
examples/benchmark/legacy_spin_glass/run.sh
HELIX_BENCHMARK_WITH_NSIGHT=systems examples/benchmark/legacy_spin_glass/run.sh
```

The checked-in sample output lives in `examples/benchmark/legacy_spin_glass/reference/` and includes
the JSONL, Markdown summary, and `test_results/` evidence for the ordinary correctness, benchmark,
quick/full baseline, Python-smoke status, and Nsight tool checks from the same validation session.
Raw Nsight Systems / Nsight Compute reports are not checked in because they can embed environment
variables, credentials, and local paths.

Benchmark CTest entries use `RESOURCE_LOCK gpu` when registered with `helix_add_test(... GPU ...)`,
but they do not receive the `cuda` label. `cuda` remains the ordinary correctness selector; benchmark
data is opt-in development/reporting evidence and is not a speed-threshold gate by default.

Manual Nsight capture is optional and requires local NVIDIA Nsight Systems / Nsight Compute tools.
It is not an ordinary CI dependency, and capture failure does not fail ordinary correctness CI. Run
the default benchmark executable directly and write reports under the benchmark artifact root. Start
captures from an environment without API keys, tokens, secrets, passwords, or credential paths:

```sh
cmake --build build/cmake --target legacy_spin_glass_benchmark --parallel "$(nproc)"

export HELIX_BENCHMARK_OUTPUT_DIR="${HELIX_BENCHMARK_OUTPUT_DIR:-$(pwd)/build/cmake/benchmark}"
run_id="$(date -u +%Y%m%dT%H%M%SZ)-legacy-spin-glass"
mkdir -p "${HELIX_BENCHMARK_OUTPUT_DIR}/nsight"

nsys profile \
  --force-overwrite true \
  --trace=cuda,nvtx,osrt \
  --output "${HELIX_BENCHMARK_OUTPUT_DIR}/nsight/${run_id}-systems" \
  build/cmake/legacy_spin_glass_benchmark

ncu \
  --force-overwrite \
  --target-processes all \
  --set full \
  --export "${HELIX_BENCHMARK_OUTPUT_DIR}/nsight/${run_id}-compute" \
  build/cmake/legacy_spin_glass_benchmark
```

The naming convention is `nsight/<run_id>-systems.*` and `nsight/<run_id>-compute.*`.
`profiling.nsight_artifact` is `null` when no capture is collected, and the generated Markdown
summary renders that state as `not_collected`. If a future opt-in build/run adds NVTX markers, reuse
the benchmark scope names recorded in `measurement_scope.nvtx_naming_convention`:
`benchmark.main.init`, `benchmark.main.warmup`, `benchmark.main.steady_propagation`,
`benchmark.main.result_extraction`, `benchmark.main.teardown`, and `benchmark.calibration`.
Future internal markers should keep these evidence mappings: `helix.develop` for H-003,
`helix.getdRhoSparse` for H-001/H-003, `helix.cuda_sparse_backend_plan` for H-001/H-004,
`helix.transpose` for H-005, and `helix.result_extraction` for H-002.

When the example script runs with `HELIX_BENCHMARK_WITH_NSIGHT=systems`, it sets
`HELIX_BENCHMARK_NSIGHT_ARTIFACT=nsight/<run_id>-systems.nsys-rep` so the JSONL and Markdown summary
record the expected Nsight report path. The wrapper removes environment variables whose names contain
`KEY`, `TOKEN`, `SECRET`, `PASSWORD`, or `CREDENTIAL` before launching Nsight.
When correctness or baseline gates are run separately in the same validation session, set
`HELIX_BENCHMARK_CORRECTNESS_GATE_STATUS=passed|failed` and
`HELIX_BENCHMARK_BASELINE_GATE_STATUS=passed|failed` before invoking the benchmark. Standalone
benchmark runs must leave those fields at the default `not_run`.
Use `HELIX_BENCHMARK_CAPTURE_CALIBRATION=0` for a main-only artifact, or leave it at the default
`1` to run the separate HEOMSolver calibration cross-check. In both cases calibration is excluded
from main timing aggregation.

No Nsight workflow runs on the default pull-request path. A future workflow must use
`workflow_dispatch` or a scheduled trigger. Raw profiler reports must not be committed; if a workflow
uploads them for internal review, keep them in an access-controlled benchmark artifact root rather
than baseline output paths.

`helix_benchmark.jsonl` uses the internal `helix.benchmark.v1` schema. Each line is one run record
with these top-level fields:

```json
{
  "schema_version": "helix.benchmark.v1",
  "run_id": "20260513T000000Z-legacy-spin-glass-sm89",
  "helix": {"version": "v0.0.3", "git_commit": "unknown", "git_dirty": null},
  "build": {"type": "Release", "cuda_architectures": "89"},
  "gpu": {"name": "NVIDIA GPU", "driver": "13.0", "memory_total_bytes": 0},
  "case": {"name": "legacy_spin_glass_default", "backend": "LegacyCudaSparse", "precision": "single"},
  "problem": {"N": 1024, "KMax": 2, "JMax": 3, "hierarchy_size": 10, "steps": 2},
  "timing_ms": {"init": 0.0, "warmup": 0.0, "steady_propagation": 0.0, "result_extraction": 0.0, "teardown": 0.0},
  "measurement_scope": {
    "main_measurement_scope": "benchmark.main",
    "main_measurement_status": "captured",
    "calibration_scope": "benchmark.calibration",
    "calibration_status": "captured",
    "calibration_captured": true,
    "calibration_excluded_from_main": true,
    "nvtx_naming_convention": "benchmark.main.init,benchmark.main.warmup,benchmark.main.steady_propagation,benchmark.main.result_extraction,benchmark.main.teardown,benchmark.calibration"
  },
  "memory": {"peak_device_bytes": 0, "device_delta_bytes": 0, "measurement_method": "cudaMemGetInfo_delta"},
  "gates": {"correctness_gate_status": "not_run", "baseline_gate_status": "not_run"},
  "profiling": {
    "instrumentation": ["runner_wall_clock", "cudaDeviceSynchronize_phase_boundaries"],
    "nvtx_enabled": false,
    "nsight_artifact": null,
    "counters": {
      "spmm": {
        "call_count": 320,
        "descriptor_create_count": 0,
        "workspace_alloc_count": 0,
        "workspace_bytes": 183,
        "buffer_size_query_count": 0
      },
      "result_extraction": {
        "sync_wait_ms": 0.0,
        "host_allocation_ms": 0.0,
        "d2h_copy_ms": 0.0,
        "conversion_ms": 0.0,
        "d2h_bytes": 8388608,
        "element_count": 1048576
      }
    },
    "hypotheses": [
      {
        "id": "H-001",
        "name": "descriptor/workspace rebuild cost",
        "status": "collected",
        "fields": [{"name": "spmm_call_count", "value": "320", "unit": "count"}],
        "method": "private CudaSparseBackendPlan SpMM counters captured in the steady propagation scope after warmup",
        "interpretation": "Descriptor creation, workspace allocation, buffer-size query, and SpMM call counters are separated from aggregate timing; warmed compatible calls should report zero setup counters.",
        "downstream_action": "Use these counters to gate downstream H-diagonal, D2D traffic, layout, and graph feasibility tasks."
      }
    ]
  }
}
```

`helix_benchmark_summary.md` is the human-readable release/PR handoff generated from the same record.
It includes the schema version, artifact paths, run environment, case metadata, phase timing table,
measurement scope table, memory table, correctness/baseline gate status, profiling counter table,
CUDA 13 cuSPARSE API decision table, structural legacy-wrapper versus reusable-plan comparison,
`H_DIAGONAL` elementwise specialization comparison,
structured profiling evidence slots for H-001..H-005, and a short release-note snippet. Each
hypothesis records `id`,
`name`, `status`, `fields`, `method`, `interpretation`, and `downstream_action`. Allowed evidence
statuses are `not_collected`, `collected`, `inconclusive`, `supported`, and `not_supported`; missing
counters must use `not_collected` rather than a blank field.

`examples/outputEnergy.txt` is still the checked-in numerical correctness baseline. Do not compare it
to benchmark JSONL or use benchmark artifacts as a replacement for numerical or baseline gates.

CI workflows:

| Workflow | Trigger | Local equivalent | Artifacts |
| --- | --- | --- | --- |
| `CUDA CI` | pull request, push, manual dispatch | configure, build, `ctest --test-dir build/cmake --output-on-failure -LE "^(sanitizer\|benchmark)$"`, `HELIX_STEPS=2 scripts/verify_examples.sh` | CTest logs, compatibility smoke outputs, compare summary |
| `CUDA CI` sanitizer job | manual dispatch with `run_sanitizer=true` | `ctest --test-dir build/cmake -L sanitizer --output-on-failure` | sanitizer stdout/stderr/summary/log files |
| `Numerical Baseline` | weekly schedule and manual dispatch | `HELIX_STEPS=1000 scripts/verify_examples.sh` | full baseline outputs and `energy_compare_summary.txt` |
| `Repository Health` | pull request and push | metadata checks, `bash -n` shell checks, generated-artifact tracking check | no generated HELIX outputs tracked except `examples/outputEnergy.txt` |
| `Release` | SemVer tag or manual dispatch | full baseline plus package script | release package, checksum, release verification outputs |

## Sanitizer and GPU resources

`helix_cuda_memcheck_sanitizer` runs `compute-sanitizer --tool memcheck` against the smallest CUDA micro test target. The CTest timeout is 600 seconds and the test uses `RESOURCE_LOCK gpu`.

Sanitizer reports default to `build/cmake/sanitizer/`. CI can override the report location with `HELIX_SANITIZER_REPORT_DIR`, and the wrapper writes a sanitizer log plus stdout/stderr/summary text files.

Sanitizer and benchmark GPU entries receive `RESOURCE_LOCK gpu` but are not auto-labelled `cuda`. Resource-lock audits should inspect generated CTest properties rather than GitHub Actions concurrency:

```sh
ctest --test-dir build/cmake -N -V
ctest --test-dir build/cmake --show-only=json-v1
```

GitHub Actions job `concurrency` controls runner-level workflow cancellation. CTest `RESOURCE_LOCK gpu` controls GPU reuse inside one configured test run; both are kept because they protect different scheduling layers.

## Numerical reference tests

The numerical tests use the compiled default input profile:

- precision: `SINGLE` (`single`)
- system size: `Param::N=1024`, `Param::N2=1048576`
- hierarchy size: `KMax=2`, `JMax=3`, `hierarchySize=10`
- sparse dRho reference: default `Step=0.1`, default `IntegrationNum=4`
- one-step evolution reference: default `Step=0.1`, local test override `IntegrationNum=1`
- tolerance: `1e-5` absolute and relative for single precision
- toy profile: disabled because `Param::N`, `KMax`, and `JMax` are compile-time defaults. Smaller 2x2/4x4 coverage needs a test profile or facade rather than production default changes.

Each numerical executable prints `reference_input`, `max_abs_diff`, `max_rel_diff`, absolute tolerance, relative tolerance, and reference source. GPU numerical tests must be registered through `helix_add_test(... LABELS numerical GPU TIMEOUT 180)` so they also receive the `cuda` label and `RESOURCE_LOCK gpu`.

## Lifecycle tests

`tests/support/legacy_heom_run.h` is a test-only lifecycle facade, not a public solver API. It captures the sequential context behavior currently expected from the legacy path:

- `HeomContextConfig`: local test config for `step`, `integrationOrder`, and `stepCount`.
- `create()`: calls the legacy `initialize()` path after applying the local integration settings.
- `run()`: calls `develop()` for the configured number of steps and synchronizes the CUDA device.
- `destroy()`: calls `clearLiouvilleStorage()`, `clearMatrixStorage()`, and `cublasDestroy()`.

`heom_lifecycle_contract_tests` runs create/run/destroy/recreate twice in one process, compares the reduced density block, and prints `lifecycle_recreate_repeatability` with max absolute/relative diff and tolerance. It is registered as `numerical` with `GPU` and `TIMEOUT 180`, so it also receives the `cuda` label and `RESOURCE_LOCK gpu`.

`v01_public_lifecycle_numerical_gate` exercises the production `helix::Context` RAII boundary over the same legacy sparse path. It verifies move-only semantics, public create/run/destroy/recreate repeatability, explicit storage release after `destroy()`, and the current one-active-context guard.

Known limits: `Param::*`, `hierarchySize`, and the global `matrix_storage.*` device vectors are still process-global. This test only covers sequential create/run/destroy/recreate for the legacy sparse path.

## Host core boundary

`helix_host_core` owns host-side helpers that are shared by the executable and unit tests, including PSD pole/residue reference logic and default parameter definitions. The public `<helix/helix.h>` surface is kept free of legacy private headers and CUDA/Thrust/cuBLAS/cuSPARSE types; unit tests may still compile in a CUDA-enabled build because the project target graph requires the CUDA toolkit.

Current dependency to isolate:

- `initialize_detail.h` includes `matrix_storage.h` for `host_vector`, which also exposes global device storage.
- `matrix_storage.h` includes `cuda_types.h`, which pulls cuBLAS/cuSPARSE type declarations into host-only tests.

A cleaner split would move `host_vector` and scalar aliases into a lightweight host types header, leaving device globals and cuBLAS/cuSPARSE wrappers in CUDA backend headers.
