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
</p>

HELIX (HEOM Library for Integrated eXecution) is a C++17/CUDA implementation of the hierarchical equations of motion (HEOM) for GPU-accelerated simulations of non-Markovian open quantum systems. The repository contains the validated legacy CUDA executable path and a public C++ API that wraps the same solver path.

CMake is the supported build system. The executable is still available for compatibility and regression checks. Library calls return structured results instead of writing the legacy output files.

## Current scope

The current public API exposes the validated legacy spin-glass CUDA path. Model and bath construction, backend selection, and diagnostics are visible through public types, but runtime execution is still constrained to the compiled legacy configuration described below.

## Requirements

Tested environment:

- Ubuntu 24.04, Linux 6.17
- NVIDIA driver 580.105.08
- CUDA toolkit 13.0.88
- NVIDIA GeForce RTX 4070 class GPU, CUDA architecture `sm_89`
- GCC 13.3.0
- CMake 3.28.3

`helix` requires a CUDA-capable NVIDIA GPU and links against cuBLAS and cuSPARSE from the CUDA toolkit. If CMake cannot detect the right GPU architecture, pass `-DHELIX_CUDA_ARCHITECTURES=<arch>`, for example `89`.

## Build

```bash
cmake -S . -B build/cmake -DCMAKE_BUILD_TYPE=Release
cmake --build build/cmake --parallel "$(nproc)"
```

The executable is `build/cmake/helix`.

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

The Python binding is an experimental thin wrapper over the public C++ API. It is disabled by
default, does not change solver semantics, and is a build-tree smoke path only.
There is no wheel, conda package, or packaging compatibility promise.
`HELIX_BUILD_PYTHON=ON` requires `pybind11` in the selected Python environment.

One tested local setup uses a Python 3.13 virtual environment managed by `uv`:

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

Use a fresh build directory, or clear the CMake cache, when switching the configured
`Python3_EXECUTABLE`; stale CMake cache entries can mix a Python 3.13 interpreter with headers from a
different Python installation.

## CLI compatibility

The `helix` executable is kept as a compatibility wrapper around the legacy GPU-HEOM run path. It supports `--version` and `-V`, reads `HELIX_STEPS` with `HEOM_STEPS` as a compatibility alias, and continues to write the legacy output files in the current working directory. Library runs return structured results instead of writing these files.

## Run the example baseline

`helix` writes output files in the current directory. Use a scratch directory so generated files do not land next to the sources:

```bash
mkdir -p build/example-run
cd build/example-run
HELIX_STEPS=1000 ../cmake/helix
```

`HELIX_STEPS` is optional. When it is unset, HELIX uses the legacy default of `1000000` steps. The legacy `HEOM_STEPS` variable is still accepted as a compatibility alias. The checked-in `examples/outputEnergy.txt` contains 1981 rows for `1980` steps plus the final output row; the default verification wrapper runs `1000` steps and compares the 1001-row prefix to keep the full baseline gate shorter.

Generated files include:

- `outputEnergy.txt`: time and energy trace
- `output.txt`: CUDA event time per step in milliseconds
- `output_rho<N>.txt`: diagonal density output chunks
- `snapshot_rho<N>.dat`: binary snapshots

## Notes

- The default numerical path uses sparse host cuBLAS/cuSPARSE. The old `DYNAMIC_DENSE` path depends on device-side cuBLAS patterns from older CUDA releases and is disabled.
- The public C++ adapter `helix::examples::legacy_spin_glass_system()` is a compatibility example for the current hard-coded spin-glass model, not a generic `System` schema. Arbitrary sparse systems return unsupported execution diagnostics rather than silently running the hard-coded model.
- `helix::Bath::drude_lorentz_pade()` and `helix::HierarchySpec::compiled_default()` map the current compiled Drude-Lorentz/Pade and hierarchy defaults. Non-default bath or hierarchy fields are reported as constrained.
- CUDA 13 removed legacy `cusparseCcsrmm/csrmm2`; this tree uses a compatibility wrapper around `cusparseSpMM`.

## Support matrix

| Surface | Status | Notes |
| --- | --- | --- |
| `HELIX::helix` CMake target | supported | Build-tree and install-tree consumers are covered by CTest. |
| `<helix/helix.h>` public header | supported | Public headers avoid private legacy CUDA/Thrust/cuBLAS/cuSPARSE types. |
| Legacy spin-glass C++ example | supported compatibility path | Uses `helix::examples::legacy_spin_glass_system()` and default compiled bath/hierarchy settings. |
| Arbitrary sparse schema validation | validation only | `System::from_sparse()` validates CSR shape, but production execution is not wired to arbitrary sparse systems. |
| Core solver file output | intentionally unsupported | Library calls return `RunResult`; only the CLI writes legacy output files. |
| `helix` executable | supported compatibility path | Preserves step env vars, version flags, and legacy generated files. |
| Python binding | experimental | Build-tree pybind11 smoke only, disabled by default. |

Known limits:

- Only `Backend::LegacyCudaSparse` and `Precision::Single` are accepted by the current runtime.
- Concurrent contexts are rejected; the supported lifecycle is sequential create/run/destroy/recreate.
- `ResultMode::FinalState` is the supported result mode. Observable traces and full trajectories are not exposed by the current API.
- The public spin-glass adapter is a compatibility bridge for the current compiled model, not a general model builder.

## Credit

This repository keeps the original CUDA code usable while the project moves toward a maintainable, portable HEOM library.

Masashi Tsuchimoto and Yoshitaka Tanimura wrote the original GPU-HEOM CUDA code. The Kyoto University Theoretical Chemistry Group research activity page lists "GPU-HEOM (HEOM code for CUDA)" as work by M. Tsuchimoto and Y. Tanimura:

- http://theochem.kuchem.kyoto-u.ac.jp/resarch/resarch_activity.htm

Ye Jun <yjmaxpayne@hotmail.com> maintains HELIX and handled the Linux/CMake/CUDA 13 migration, verification, and documentation work.

## Citation

If you use HELIX in your research, please cite the following:

```bibtex
@article{doi:10.1021/acs.jctc.5b00488,
author = {Tsuchimoto, Masashi and Tanimura, Yoshitaka},
title = {Spins Dynamics in a Dissipative Environment: Hierarchal Equations of Motion Approach Using a Graphics Processing Unit (GPU)},
journal = {Journal of Chemical Theory and Computation},
volume = {11},
number = {8},
pages = {3859-3865},
year = {2015},
doi = {10.1021/acs.jctc.5b00488}
}

@software{helix,
  title = {HELIX: HEOM Library for Integrated eXecution},
  author = {Ye, Jun},
  year = {2026},
  url = {https://github.com/yjmaxpayne/HELIX},
  note = {Contact: yjmaxpayne@hotmail.com}
}
```

## License

This repository is released under the MIT License. See `LICENSE`.

## Support

Use GitHub Issues or contact Ye Jun at yjmaxpayne@hotmail.com.
