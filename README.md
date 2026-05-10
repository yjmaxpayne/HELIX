# HELIX

<p align="center">
  <img src="doc/source/_static/logo.png" alt="HELIX logo" width="180">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/C%2B%2B-17-00599C.svg?logo=cplusplus&logoColor=white" alt="C++17">
  <img src="https://img.shields.io/badge/CUDA-13.0%2B-76B900.svg?logo=nvidia&logoColor=white" alt="CUDA 13.0+">
  <img src="https://img.shields.io/badge/CMake-3.24%2B-064F8C.svg?logo=cmake&logoColor=white" alt="CMake 3.24+">
  <img src="https://img.shields.io/badge/License-MIT-orange.svg" alt="License: MIT">
  <img src="https://img.shields.io/badge/Status-Modernizing-yellow.svg" alt="Project Status">
  <img src="https://img.shields.io/badge/HEOM-GPU--Accelerated-6A5ACD.svg" alt="GPU-accelerated HEOM">
  <img src="https://img.shields.io/badge/NVIDIA-GPU%20Required-76B900.svg?logo=nvidia&logoColor=white" alt="NVIDIA GPU required">
  <img src="https://img.shields.io/badge/cuBLAS%20%2F%20cuSPARSE-Required-76B900.svg?logo=nvidia&logoColor=white" alt="cuBLAS/cuSPARSE required">
</p>

HELIX (HEOM Library for Integrated eXecution) is a modernization effort built around a legacy GPU-accelerated HEOM CUDA implementation. The project keeps the original executable buildable and numerically verifiable while the codebase is gradually shaped into a portable HEOM library for larger-scale simulations of non-Markovian open quantum systems.

CMake is the supported build system. The executable remains the compatibility and regression harness while library-facing APIs, model configuration, backend boundaries, and structured results are introduced incrementally.

## Project direction

The short-term goal is to preserve the validated CUDA numerical path and baseline outputs while making the implementation easier to test, link, and evolve. The longer-term direction is to provide a portable HEOM solver library with clearer separation between public API, model and bath construction, numerical core, CUDA backend strategy, and diagnostics.

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
- `helix::Bath::drude_lorentz_pade()` and `helix::HierarchySpec::compiled_default()` map the current compiled Drude-Lorentz/Pade and hierarchy defaults. v0.1 reports non-default bath or hierarchy fields as constrained.
- CUDA 13 removed legacy `cusparseCcsrmm/csrmm2`; this tree uses a compatibility wrapper around `cusparseSpMM`.

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
