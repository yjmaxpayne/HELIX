# HELIX

HELIX (HEOM Library for Integrated eXecution) is a modernization of a legacy CUDA codebase for GPU-accelerated HEOM. The historical Visual Studio 2012 / CUDA 6.5 project file is still under `src/hEquationNew.vcxproj`; for current Linux development, use the CMake build in this tree.

## Credit and Citation

This repository keeps the original CUDA implementation usable while moving it toward a maintainable HEOM library.

The HEOM method comes from work by Yoshitaka Tanimura and collaborators. Useful starting references are:

- Y. Tanimura and R. Kubo, "Time evolution of a quantum system in contact with a nearly Gaussian-Markoffian noise bath," J. Phys. Soc. Jpn. 58, 101-114 (1989).
- Y. Tanimura and P. G. Wolynes, "Quantum and classical Fokker-Planck equations for a Gaussian-Markovian noise bath," Phys. Rev. A 43, 4131-4142 (1991).
- Y. Tanimura, "Perspective: Numerically 'Exact' Approach to Open Quantum Dynamics: The Hierarchical Equations of Motion (HEOM)," J. Chem. Phys. 153, 020901 (2020).

The original GPU-HEOM CUDA code is by Masashi Tsuchimoto and Yoshitaka Tanimura. The Kyoto University Theoretical Chemistry Group research activity page lists "GPU-HEOM (HEOM code for CUDA)" as work by M. Tsuchimoto and Y. Tanimura:

- http://theochem.kuchem.kyoto-u.ac.jp/resarch/resarch_activity.htm

If you use this code, cite the original GPU-HEOM paper:

> Masashi Tsuchimoto and Yoshitaka Tanimura, "Spins Dynamics in a Dissipative Environment: Hierarchal Equations of Motion Approach Using a Graphics Processing Unit (GPU)," Journal of Chemical Theory and Computation 11, 3859-3865 (2015). https://doi.org/10.1021/acs.jctc.5b00488

## Requirements

Verified environment:

- Ubuntu 24.04, Linux 6.17
- NVIDIA driver 580.105.08
- CUDA toolkit 13.0.88
- NVIDIA GeForce RTX 4070 class GPU, CUDA architecture `sm_89`
- GCC 13.3.0
- CMake 3.28.3

The program requires a CUDA-capable NVIDIA GPU and links against cuBLAS and cuSPARSE from the CUDA toolkit. If CMake cannot detect the right GPU architecture, pass `-DHELIX_CUDA_ARCHITECTURES=<arch>`, for example `89`.

## Build

```bash
cmake -S . -B build/cmake -DCMAKE_BUILD_TYPE=Release
cmake --build build/cmake --parallel "$(nproc)"
```

The executable is `build/cmake/helix`.

## Run The Example Baseline

The main program writes outputs into the current working directory. Run from a separate directory to avoid mixing generated files with sources:

```bash
mkdir -p build/example-run
cd build/example-run
HELIX_STEPS=1980 ../cmake/helix
```

`HELIX_STEPS` is optional; if it is not set, the legacy default remains `1000000`. The legacy `HEOM_STEPS` variable is still accepted as a compatibility alias. The checked-in `examples/outputEnergy.txt` contains 1981 rows, corresponding to `1980` steps plus the final output row.

Generated files include:

- `outputEnergy.txt`: time and energy trace
- `output.txt`: CUDA event time per step in milliseconds
- `output_rho<N>.txt`: diagonal density output chunks
- `snapshot_rho<N>.dat`: binary snapshots

## Verify

Use the helper script to build, run, and compare `outputEnergy.txt` against the checked-in baseline with a default energy tolerance of `1e-5`:

```bash
scripts/verify_examples.sh
```

For a quick smoke test:

```bash
HELIX_STEPS=2 scripts/verify_examples.sh
```

Current full verification on the environment above:

- Command: `HELIX_STEPS=1980 build/cmake/helix` from `build/run-example-1980`
- Runtime: `real 119.08s`
- Output rows: `1981`
- `outputEnergy.txt` maximum absolute energy difference versus `examples/outputEnergy.txt`: `8e-7`
- `output.txt` differs from the historical file because it records performance timing, not a physics baseline

## Notes

- The default numerical path is the sparse host cuBLAS/cuSPARSE path. The old `DYNAMIC_DENSE` path depends on device-side cuBLAS patterns from older CUDA releases and is not enabled.
- CUDA 13 removed legacy `cusparseCcsrmm/csrmm2`; this tree uses a compatibility wrapper around `cusparseSpMM`.

## License

This repository is released under the MIT License. See `LICENSE`.
