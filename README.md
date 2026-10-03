# HELIX

<p align="center">
  <img src="doc/source/_static/logo.png" alt="HELIX logo" width="180">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/C%2B%2B-17-00599C.svg?logo=cplusplus&logoColor=white" alt="C++17">
  <img src="https://img.shields.io/badge/CUDA-13.0%2B-76B900.svg?logo=nvidia&logoColor=white" alt="CUDA 13.0+">
  <img src="https://img.shields.io/badge/CMake-3.24%2B-064F8C.svg?logo=cmake&logoColor=white" alt="CMake 3.24+">
  <img src="https://img.shields.io/badge/License-MIT-orange.svg" alt="License: MIT">
  <img src="https://img.shields.io/badge/Status-Experimental-yellow.svg" alt="Project Status">
  <img src="https://img.shields.io/badge/HEOM-GPU--Accelerated-6A5ACD.svg" alt="GPU-accelerated HEOM">
  <img src="https://img.shields.io/badge/NVIDIA-GPU%20Required-76B900.svg?logo=nvidia&logoColor=white" alt="NVIDIA GPU required">
  <img src="https://img.shields.io/badge/cuBLAS%20%2F%20cuSPARSE-Required-76B900.svg?logo=nvidia&logoColor=white" alt="cuBLAS/cuSPARSE required">
  <a href="https://doi.org/10.5281/zenodo.20115002"><img src="https://zenodo.org/badge/DOI/10.5281/zenodo.20115002.svg" alt="DOI"></a>
</p>

HELIX (HEOM Library for Integrated eXecution) is a C++17/CUDA implementation of the hierarchical equations of motion (HEOM). It simulates non-Markovian open quantum systems on NVIDIA GPUs. The repository contains the validated legacy CUDA executable and a public C++ API that wraps the same solver path.

CMake is the supported build system. The `helix` executable remains available for compatibility and regression checks. Library calls return structured results and do not write the legacy output files.

Documentation: <https://yjmaxpayne.github.io/HELIX/>. The site publishes `latest/` from `main` and one path for each release tag.

## Current scope

The current release is v0.1.0. See [CHANGELOG.md](CHANGELOG.md) for release history.

The public API runs only the validated legacy spin-glass CUDA path. Public types describe models, baths, backends, and diagnostics. The runtime still executes only the compiled legacy configuration. The [support matrix](#support-matrix) lists each surface and its status.

## Requirements

Tested environment:

- Ubuntu 24.04, Linux 6.17
- NVIDIA driver 580.105.08
- CUDA toolkit 13.0.88
- NVIDIA GeForce RTX 4070 class GPU, CUDA architecture `sm_89`
- GCC 13.3.0
- CMake 3.28.3

`helix` requires a CUDA-capable NVIDIA GPU. It links against cuBLAS and cuSPARSE from the CUDA toolkit. `HELIX_CUDA_ARCHITECTURES` defaults to `native`. If CMake cannot detect the GPU architecture, pass `-DHELIX_CUDA_ARCHITECTURES=<arch>`, for example `89`.

## Build

```bash
cmake -S . -B build/cmake -DCMAKE_BUILD_TYPE=Release
cmake --build build/cmake --parallel "$(nproc)"
```

The executable is `build/cmake/helix`.

## Benchmark example

The opt-in benchmark path writes JSONL, a Markdown summary, and optional
Nsight artifacts. It does not change the correctness baseline:

```bash
examples/benchmark/legacy_spin_glass/run.sh
HELIX_BENCHMARK_WITH_NSIGHT=systems examples/benchmark/legacy_spin_glass/run.sh
```

Artifacts go to `build/cmake/example-benchmark/legacy_spin_glass/` by default.
Set `HELIX_BENCHMARK_OUTPUT_DIR` to change this location. The repository
includes a captured sample result in
`examples/benchmark/legacy_spin_glass/reference/` for format inspection.

The summary records the CUDA backend decisions. These include the structured
`V` specialization decision for the legacy spin-glass path. Benchmark data is
trend evidence only. No default speed threshold applies.

## C++ API

The C++ library target is `helix_core`, exported to consumers as `HELIX::helix`.
Use the public aggregate header only:

```cpp
#include <helix/helix.h>

#include <iostream>

int main()
{
    auto system = helix::examples::legacy_spin_glass_system();
    auto bath = helix::Bath::drude_lorentz_pade();
    auto hierarchy = helix::HierarchySpec::compiled_default(bath);

    helix::SolverOptions options;
    options.steps = 2;

    auto result = helix::HEOMSolver().run(system, hierarchy, options);
    if(!result.ok())
    {
        std::cerr << result.diagnostics.summary() << "\n";
        return 1;
    }

    std::cout << "rho shape: " << result.reduced_density_shape.rows << "x"
              << result.reduced_density_shape.cols << "\n";
    return 0;
}
```

The repository example is `examples/cpp/legacy_spin_glass.cpp`. CTest builds and
runs it as `v01_cpp_library_example_gate`.

Build-tree and install-tree consumers use the same imported target. In a
separate consumer project, the CMake entry point is:

```cmake
cmake_minimum_required(VERSION 3.24)
project(HELIXConsumer LANGUAGES CXX CUDA)

find_package(HELIX CONFIG REQUIRED)

add_executable(consumer main.cpp)
target_link_libraries(consumer PRIVATE HELIX::helix)
```

For an install-tree smoke, assuming that consumer project lives in `consumer/`:

```bash
cmake --install build/cmake --prefix build/install
cmake -S consumer -B build/consumer \
  -DCMAKE_PREFIX_PATH="$PWD/build/install" \
  -DCMAKE_CUDA_ARCHITECTURES=89
cmake --build build/consumer
```

The repository gate for this contract is:

```bash
ctest --test-dir build/cmake -R v01_external_consumer_cmake_gate --output-on-failure
```

Core library runs return `RunResult` and do not write `outputEnergy.txt`,
`output.txt`, `output_rho*.txt`, or `snapshot_rho*.dat`. Those generated files
belong to the `helix` executable compatibility path.

## Experimental Python binding

The Python binding is an experimental thin wrapper over the public C++ API.
The build disables it by default. It does not change solver semantics. It is a
build-tree smoke path only. HELIX ships no wheel or conda package and makes no
packaging compatibility promise.

`HELIX_BUILD_PYTHON=ON` requires Python 3.11 or later and `pybind11` in the
selected Python environment. One tested local setup uses a Python 3.13 virtual
environment that `uv` manages:

```bash
uv venv --python 3.13 .venv
uv pip install -e ".[dev]"
cmake -S . -B build/cmake-python-313 \
  -DCMAKE_BUILD_TYPE=Release \
  -DHELIX_BUILD_PYTHON=ON \
  -DPython3_EXECUTABLE="$PWD/.venv/bin/python"
cmake --build build/cmake-python-313 --parallel "$(nproc)"
ctest --test-dir build/cmake-python-313 -R v01_python_smoke_gate --output-on-failure
```

The smoke mirrors the C++ example:

```python
import helix

system = helix.examples.legacy_spin_glass_system()
bath = helix.Bath.drude_lorentz_pade()
hierarchy = helix.HierarchySpec.compiled_default(bath)
options = helix.SolverOptions()
options.steps = 2

result = helix.HEOMSolver().run(system, hierarchy, options)
assert result.ok(), result.diagnostics.summary()
print(result.times, result.reduced_density_shape.rows, result.reduced_density_shape.cols)
```

When you change the configured `Python3_EXECUTABLE`, use a fresh build
directory or clear the CMake cache. Stale cache entries can mix a Python 3.13
interpreter with headers from a different Python installation.

## CLI compatibility

The `helix` executable is a compatibility wrapper around the legacy GPU-HEOM run path. It has these properties:

- It supports `--version` and `-V`.
- It reads `HELIX_STEPS`, and accepts `HEOM_STEPS` as a compatibility alias.
- It writes the legacy output files in the current working directory.

Library runs return structured results and do not write these files.

## Run the example baseline

`helix` writes output files in the current directory. Use a scratch directory so generated files do not land next to the sources:

```bash
mkdir -p build/example-run
cd build/example-run
HELIX_STEPS=1000 ../cmake/helix
```

`HELIX_STEPS` is optional. When it is unset, HELIX uses the legacy default of `1000000` steps.

The checked-in `examples/outputEnergy.txt` contains 1981 rows: one row for each of the `1980` steps, plus the final output row. `scripts/verify_examples.sh` runs `1000` steps by default and compares the 1001-row prefix. This keeps the default check short. To run the full 1980-step baseline gate, use:

```bash
HELIX_STEPS=1980 scripts/verify_examples.sh
```

### Runtime environment variables

| Variable | Default | Purpose |
| --- | --- | --- |
| `HELIX_STEPS` (alias `HEOM_STEPS`) | `1000000` | Override the number of integration steps. |
| `HELIX_DEBUG_SYNC_MODE` | `off` | **Opt-in diagnostic only.** Values `1`, `on`, `ON`, `true`, and `TRUE` turn it on. HELIX then adds defensive `cudaDeviceSynchronize()` calls next to the event-based sync path at four Segment-2 sites. These sites are the Taylor-loop fence, the `getdRhoSparse` stage barrier, the `getdRhoSparse` exit barrier, and the per-step outer fence. Use it to find the first error during migration. ON mode **intentionally blocks CUDA Graph capture**, because CUDA forbids `cudaDeviceSynchronize()` inside `cudaStreamBeginCapture`. Leave it unset for production. |

Generated files include:

- `outputEnergy.txt`: time and energy trace
- `output.txt`: CUDA event time per step in milliseconds
- `output_rho<N>.txt`: diagonal density output chunks
- `snapshot_rho<N>.dat`: binary snapshots

## Notes

- The default numerical path uses sparse host cuBLAS/cuSPARSE. The old `DYNAMIC_DENSE` path depends on device-side cuBLAS patterns from older CUDA releases. The build disables it.
- The public C++ adapter `helix::examples::legacy_spin_glass_system()` is a compatibility example for the current hard-coded spin-glass model. It is not a generic `System` schema. Arbitrary sparse systems return unsupported execution diagnostics. They do not silently run the hard-coded model.
- `helix::Bath::drude_lorentz_pade()` and `helix::HierarchySpec::compiled_default()` map the current compiled Drude-Lorentz/Pade and hierarchy defaults. The runtime reports non-default bath or hierarchy fields as unsupported.
- CUDA 13 removed the legacy `cusparseCcsrmm/csrmm2` functions. This tree uses a compatibility wrapper around `cusparseSpMM`.

## Support matrix

| Surface | Status | Notes |
| --- | --- | --- |
| `HELIX::helix` CMake target | supported | CTest covers build-tree and install-tree consumers. |
| `<helix/helix.h>` public header | supported | Public headers avoid private legacy CUDA/Thrust/cuBLAS/cuSPARSE types. |
| Legacy spin-glass C++ example | supported compatibility path | Uses `helix::examples::legacy_spin_glass_system()` and default compiled bath/hierarchy settings. |
| Arbitrary sparse schema validation | validation only | `System::from_sparse()` validates the CSR shape. Production execution does not run arbitrary sparse systems. |
| User exponent baths | validation only | `Bath::user_exponents()` reports `BathExponentsInvalid` for an invalid exponent structure and `UnsupportedBath` for a valid one. Execution targets v0.3-lite. |
| Core solver file output | intentionally unsupported | Library calls return `RunResult`. Only the CLI writes legacy output files. |
| `helix` executable | supported compatibility path | Preserves step env vars, version flags, and legacy generated files. |
| Python binding | experimental | Build-tree pybind11 smoke only, disabled by default. |

Known limits:

- The current runtime accepts only `Backend::LegacyCudaSparse` and `Precision::Single`. `Backend::CudaSparse` targets v0.2-lite. `Precision::Double` targets v0.3-lite.
- The runtime rejects concurrent contexts. The supported lifecycle is sequential create/run/destroy/recreate.
- `ResultMode::FinalState` is the supported result mode. `ResultMode::ObservableTrace` and `ResultMode::Trajectory` are validation only and return `UnsupportedExecution`.
- The public spin-glass adapter is a compatibility bridge for the current compiled model, not a general model builder.

## Credit

This repository keeps the original CUDA code usable while the project moves toward a maintainable, portable HEOM library.

Masashi Tsuchimoto and Yoshitaka Tanimura wrote the original GPU-HEOM CUDA code. The Kyoto University Theoretical Chemistry Group research activity page lists "GPU-HEOM (HEOM code for CUDA)" as work by M. Tsuchimoto and Y. Tanimura:

- http://theochem.kuchem.kyoto-u.ac.jp/resarch/resarch_activity.htm

Ye Jun <yjmaxpayne@hotmail.com> maintains HELIX and handled the Linux/CMake/CUDA 13 migration, verification, and documentation work.

## Citation

Machine-readable metadata for HELIX lives in [`CITATION.cff`](CITATION.cff) (GitHub
"Cite this repository" button, Zotero, Mendeley) and [`.zenodo.json`](.zenodo.json)
(Zenodo software archive). The concept DOI [10.5281/zenodo.20115002](https://doi.org/10.5281/zenodo.20115002)
always resolves to the latest archived release. The Zenodo record page lists the
DOI for each version. See
[CONTRIBUTING.md](CONTRIBUTING.md#releases-and-zenodo-doi) for the release flow.

```bibtex
@software{helix,
  title  = {HELIX: HEOM Library for Integrated eXecution},
  author = {Ye, Jun},
  year   = {2026},
  url    = {https://github.com/yjmaxpayne/HELIX},
  doi    = {10.5281/zenodo.20115002},
  note   = {ORCID: 0000-0003-1963-0865}
}

@article{tsuchimoto2015heom,
  author  = {Tsuchimoto, Masashi and Tanimura, Yoshitaka},
  title   = {Spins Dynamics in a Dissipative Environment: Hierarchal Equations of Motion Approach Using a Graphics Processing Unit (GPU)},
  journal = {Journal of Chemical Theory and Computation},
  volume  = {11},
  number  = {8},
  pages   = {3859--3865},
  year    = {2015},
  doi     = {10.1021/acs.jctc.5b00488}
}
```

To cite a specific version, replace the concept DOI above with the version DOI
from the Zenodo record page (e.g. `10.5281/zenodo.20115003` for v0.0.2).

## License

HELIX uses the MIT License. See `LICENSE`.

## Support

Use GitHub Issues or contact Ye Jun at yjmaxpayne@hotmail.com.
