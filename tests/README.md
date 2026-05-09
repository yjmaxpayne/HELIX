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

## Host Core Boundary

`helix_host_core` owns host-side helpers that are shared by the executable and unit tests, including PSD pole/residue reference logic and default parameter definitions. Unit tests may compile with the CUDA toolkit because current public headers still expose CUDA types, but the host target must not link `CUDA::cublas` or `CUDA::cusparse`.

Short-term dependency to split later:

- `InitializeDetail.h` includes `Matrixes.h` for `host_vector`, which also exposes global device storage.
- `Matrixes.h` includes `TypeDef.h`, which pulls cuBLAS/cuSPARSE type declarations into host-only tests.

The split point is a future lightweight host types header for `host_vector` and scalar aliases, leaving device globals and cuBLAS/cuSPARSE wrappers in CUDA backend headers.
