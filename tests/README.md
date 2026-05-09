# HELIX Test Contract

CTest labels are part of the shared test-suite contract:

- `unit`: deterministic host-side or small self-contained tests. These tests do not reserve a GPU.
- `cuda`: tests that execute CUDA kernels or require a CUDA runtime device.
- `numerical`: reference-value or invariant checks with documented tolerances.
- `integration`: tests that exercise multiple HELIX components together.
- `baseline`: tests that compare against legacy executable outputs or fixtures.
- `sanitizer`: tests intended to run under CUDA or memory sanitizer tooling.
- `benchmark`: performance measurements. These should report trends, not block correctness gates.

Register tests with `helix_add_test()` in `CMakeLists.txt`. GPU tests must use the `GPU` option; the helper adds `RESOURCE_LOCK gpu`, applies a timeout, and prevents them from being mixed into the `unit` label.

Useful CTest selectors:

```sh
ctest --test-dir build/cmake -L unit --output-on-failure
ctest --test-dir build/cmake -L cuda -N
ctest --test-dir build/cmake -L numerical -N
```

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

## Host Core Boundary

`helix_host_core` owns host-side helpers that are shared by the executable and unit tests, including PSD pole/residue reference logic and default parameter definitions. Unit tests may compile with the CUDA toolkit because current public headers still expose CUDA types, but the host target must not link `CUDA::cublas` or `CUDA::cusparse`.

Short-term dependency to split later:

- `InitializeDetail.h` includes `Matrixes.h` for `host_vector`, which also exposes global device storage.
- `Matrixes.h` includes `TypeDef.h`, which pulls cuBLAS/cuSPARSE type declarations into host-only tests.

The split point is a future lightweight host types header for `host_vector` and scalar aliases, leaving device globals and cuBLAS/cuSPARSE wrappers in CUDA backend headers.
