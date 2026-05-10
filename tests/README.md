# HELIX Test Contract

CTest labels are part of the shared test-suite contract:

- `unit`: deterministic host-side or small self-contained tests. These tests do not reserve a GPU.
- `cuda`: ordinary CUDA correctness tests that execute CUDA kernels or require a CUDA runtime device.
- `numerical`: reference-value or invariant checks with documented tolerances.
- `integration`: tests that exercise multiple HELIX components together.
- `baseline`: tests that compare against legacy executable outputs or fixtures.
- `sanitizer`: GPU resource-locked tests intended to run under CUDA or memory sanitizer tooling.
- `benchmark`: performance measurements. These should report trends, not block correctness gates.

Register tests with `helix_add_test()` in `CMakeLists.txt`. GPU tests must use the `GPU` option; the helper adds `RESOURCE_LOCK gpu`, applies a timeout, and prevents them from being mixed into the `unit` label. Sanitizer profiles are intentionally kept out of the ordinary `cuda` label so `ctest -L cuda` remains a fast correctness gate.

## V0.1 Library Foundation Gate Map

The v0.1 library foundation plan started with explicit expected-fail gates. T1 through T6 have replaced their placeholders with real tests; remaining placeholders are registered through `helix_add_test(... EXPECTED_FAIL ...)`, use only the label contract above, and are backed by `tests/planned/expected_fail_gate.cmake`. Each downstream task must replace its placeholder with the real test and remove `EXPECTED_FAIL` when that contract is implemented.

| Gate | Labels | GPU lock | Initial state | Turns green in | Contract |
| --- | --- | --- | --- | --- | --- |
| `v01_public_header_compile_gate` | `unit` | no | real test | T1 | A consumer can compile by including only `<helix/helix.h>`. |
| `v01_external_consumer_cmake_gate` | `integration` | no | real test | T1 | A downstream CMake project can `find_package(HELIX CONFIG REQUIRED)` and link `HELIX::helix`. |
| `v01_api_schema_validation_gate` | `unit` | no | real test | T2 | CSR schema validation and unsupported execution diagnostics are covered by unit tests. |
| `v01_public_lifecycle_numerical_gate` | `numerical`, auto `cuda` | yes | real test | T3 | Public create/run/destroy/recreate lifecycle is repeatable within numerical tolerance. |
| `v01_public_solver_spin_glass_gate` | `numerical`, auto `cuda` | yes | real test | T4 | Public `HEOMSolver` runs the legacy spin-glass compatibility adapter for a short GPU smoke and rejects arbitrary sparse execution. |
| `v01_result_shape_no_file_output_gate` | `numerical`, `integration`, auto `cuda` | yes | real test | T5 | `RunResult` shape, diagnostics, and no-file-output library behavior are verified against the legacy CLI output contract. |
| `v01_cli_compatibility_wrapper_gate` | `integration`, `baseline`, auto `cuda` | yes | real test | T6 | The `helix` executable preserves version flags, step env aliases, legacy output files, and short energy prefix compatibility. |
| `v01_python_smoke_gate` | `integration`, auto `cuda` | yes | expected-fail | T7 | Optional Python binding imports, runs the smoke path, and reports result shape. |

Existing gates remain part of the v0.1 plan: `helix_smoke_integration` and `HELIX_STEPS=2 scripts/verify_examples.sh` cover T6 CLI compatibility, while the final T8 signoff re-runs the full label matrix plus `HELIX_STEPS=1000 scripts/verify_examples.sh`.

Useful CTest selectors:

```sh
ctest --test-dir build/cmake -L unit --output-on-failure
ctest --test-dir build/cmake -L cuda --output-on-failure
ctest --test-dir build/cmake -L numerical --output-on-failure
ctest --test-dir build/cmake -L integration --output-on-failure
ctest --test-dir build/cmake -L baseline --output-on-failure
ctest --test-dir build/cmake -L sanitizer --output-on-failure
```

## Test Matrix And Gate Ownership

| Label / gate | Environment | Expected local time | Failure meaning | Gate |
| --- | --- | --- | --- | --- |
| `unit` | CUDA toolkit available; no GPU device required | <1s for current unit gates | host helper, PSD reference, parameter default, public API, or comparator regression | CUDA CI and local pre-commit |
| `cuda` | single NVIDIA GPU | ~3s for current cuda-labelled gates on RTX 4070 class hardware | CUDA micro, numerical GPU, integration smoke, or planned v0.1 GPU gate regression | CUDA CI on self-hosted GPU runner |
| `numerical` | single NVIDIA GPU | ~2s for current numerical gates | sparse dRho, one-step invariant, lifecycle repeatability, or planned public numerical gate drift beyond documented tolerance | CUDA CI on self-hosted GPU runner |
| `integration` | single NVIDIA GPU | ~2s for current integration gates | legacy CLI output contract, isolated run directory, external consumer, or planned integration gate failure | CUDA CI on self-hosted GPU runner |
| `baseline` | single NVIDIA GPU | ~2s for CTest smoke; ~1min for `HELIX_STEPS=1000 scripts/verify_examples.sh` | checked-in energy fixture mismatch or full trajectory drift | CTest in CUDA CI; full baseline in scheduled/manual/release gates |
| `sanitizer` | single NVIDIA GPU with `compute-sanitizer` | usually <1min for the micro target | CUDA memory error, sanitizer tool failure, or report artifact failure | manual workflow dispatch only |
| `benchmark` | pinned GPU host | non-blocking | performance trend shift, not correctness failure | manual only |

CI alignment:

| Workflow | Trigger | Local equivalent | Artifact contract |
| --- | --- | --- | --- |
| `CUDA CI` | pull request, push, manual dispatch | configure, build, `ctest --test-dir build/cmake --output-on-failure -LE "^(sanitizer\|benchmark)$"`, `HELIX_STEPS=2 scripts/verify_examples.sh` | CTest logs, compatibility smoke outputs, compare summary |
| `CUDA CI` sanitizer job | manual dispatch with `run_sanitizer=true` | `ctest --test-dir build/cmake -L sanitizer --output-on-failure` | sanitizer stdout/stderr/summary/log files |
| `Numerical Baseline` | weekly schedule and manual dispatch | `HELIX_STEPS=1000 scripts/verify_examples.sh` | full baseline outputs and `energy_compare_summary.txt` |
| `Repository Health` | pull request and push | metadata checks, `bash -n` shell checks, generated-artifact tracking check | no generated HELIX outputs tracked except `examples/outputEnergy.txt` |
| `Release` | SemVer tag or manual dispatch | full baseline plus package script | release package, checksum, release verification outputs |

## Sanitizer And CI Resource Governance

`helix_cuda_memcheck_sanitizer` runs `compute-sanitizer --tool memcheck` against the smallest CUDA micro test target. The CTest timeout is 600 seconds and the test uses `RESOURCE_LOCK gpu`.

Sanitizer reports default to `build/cmake/sanitizer/`. CI can override the report location with `HELIX_SANITIZER_REPORT_DIR`, and the wrapper writes a sanitizer log plus stdout/stderr/summary text files.

Resource-lock audits should inspect generated CTest properties rather than GitHub Actions concurrency:

```sh
ctest --test-dir build/cmake -N -V
```

GitHub Actions job `concurrency` controls runner-level workflow cancellation. CTest `RESOURCE_LOCK gpu` controls GPU reuse inside one configured test run; both are kept because they protect different scheduling layers.

## Numerical Reference Tests

T4 numerical tests intentionally use the default compiled configuration as the MVP input profile:

- precision: `SINGLE` (`single`)
- system size: `Param::N=1024`, `Param::N2=1048576`
- hierarchy size: `KMax=2`, `JMax=3`, `hierarchySize=10`
- sparse dRho reference: default `Step=0.1`, default `IntegrationNum=4`
- one-step evolution reference: default `Step=0.1`, local test override `IntegrationNum=1`
- tolerance: `1e-5` absolute and relative for single precision
- toy profile: disabled for now because `Param::N`, `KMax`, and `JMax` are compile-time defaults; a smaller 2x2/4x4 profile should be added through a test profile or facade rather than by changing production defaults.

Each numerical executable prints `reference_input`, `max_abs_diff`, `max_rel_diff`, absolute tolerance, relative tolerance, and reference source. GPU numerical tests must be registered through `helix_add_test(... LABELS numerical GPU TIMEOUT 180)` so they also receive the `cuda` label and `RESOURCE_LOCK gpu`.

## Lifecycle Contract Tests

`tests/support/legacy_heom_run.h` is a test-only lifecycle facade, not a public solver API. It provides the smallest current sketch of the future context contract:

- `HeomContextConfig`: local test config for `step`, `integrationOrder`, and `stepCount`.
- `create()`: calls the legacy `initialize()` path after applying the local integration settings.
- `run()`: calls `develop()` for the configured number of steps and synchronizes the CUDA device.
- `destroy()`: calls `clearLiouvilleStorage()`, `clearMatrixStorage()`, and `cublasDestroy()`.

`heom_lifecycle_contract_tests` runs create/run/destroy/recreate twice in one process, compares the reduced density block, and prints `lifecycle_recreate_repeatability` with max absolute/relative diff and tolerance. It is registered as `numerical` with `GPU` and `TIMEOUT 180`, so it also receives the `cuda` label and `RESOURCE_LOCK gpu`.

`v01_public_lifecycle_numerical_gate` exercises the production `helix::Context` RAII boundary over the same legacy sparse path. It verifies move-only semantics, public create/run/destroy/recreate repeatability, explicit storage release after `destroy()`, and the v0.1 one-active-context guard.

Remaining context-ownership risks are intentionally visible: `Param::*`, `hierarchySize`, and the global `matrix_storage.*` device vectors are still process-global, and this test does not claim support for multiple simultaneous contexts. The contract only proves sequential create/run/destroy/recreate for the legacy sparse path.

## Host Core Boundary

`helix_host_core` owns host-side helpers that are shared by the executable and unit tests, including PSD pole/residue reference logic and default parameter definitions. The public `<helix/helix.h>` surface is kept free of legacy private headers and CUDA/Thrust/cuBLAS/cuSPARSE types; unit tests may still compile in a CUDA-enabled build because the project target graph requires the CUDA toolkit.

Short-term dependency to split later:

- `initialize_detail.h` includes `matrix_storage.h` for `host_vector`, which also exposes global device storage.
- `matrix_storage.h` includes `cuda_types.h`, which pulls cuBLAS/cuSPARSE type declarations into host-only tests.

The split point is a future lightweight host types header for `host_vector` and scalar aliases, leaving device globals and cuBLAS/cuSPARSE wrappers in CUDA backend headers.
