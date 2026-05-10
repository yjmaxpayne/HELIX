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

HELIX (HEOM Library for Integrated eXecution) is a modernization of a legacy CUDA codebase for GPU-accelerated HEOM. The maintained build system is the CMake configuration in this tree.

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

CTest labels split fast correctness gates from longer or specialized checks:

```bash
ctest --test-dir build/cmake -L unit --output-on-failure
ctest --test-dir build/cmake -L cuda --output-on-failure
ctest --test-dir build/cmake -L numerical --output-on-failure
ctest --test-dir build/cmake -L integration --output-on-failure
ctest --test-dir build/cmake -L baseline --output-on-failure
ctest --test-dir build/cmake -L sanitizer --output-on-failure
```

The `sanitizer` label runs `compute-sanitizer --tool memcheck` and writes reports under `build/cmake/sanitizer/` unless `HELIX_SANITIZER_REPORT_DIR` is set.

Gate ownership is split by cost: the CUDA CI workflow runs the ordinary CTest suite except `sanitizer` and `benchmark`, then runs the `HELIX_STEPS=2` compatibility smoke; `sanitizer` is a manual workflow dispatch option; the full 1980-step baseline runs in the scheduled/manual numerical baseline workflow and in release packaging.

Current full verification on the environment above, from the 2026-05-09 final baseline:

- Command: `HELIX_STEPS=1980 scripts/verify_examples.sh`, running `build/cmake/helix` from `build/cmake/example-run`
- Runtime: `real 113.14s`
- Output rows: `1981`
- `outputEnergy.txt` maximum absolute time difference versus `examples/outputEnergy.txt`: `0`
- `outputEnergy.txt` maximum absolute energy difference versus `examples/outputEnergy.txt`: `5e-7`
- `output.txt` differs from the historical file because it records performance timing, not a physics baseline

## Notes

- The default numerical path is the sparse host cuBLAS/cuSPARSE path. The old `DYNAMIC_DENSE` path depends on device-side cuBLAS patterns from older CUDA releases and is not enabled.
- The public C++ adapter `helix::examples::legacy_spin_glass_system()` exposes the current hard-coded spin-glass model only as a compatibility example. It is not a generic `System` schema, and arbitrary sparse systems still return unsupported execution diagnostics rather than silently running the hard-coded model.
- `helix::Bath::drude_lorentz_pade()` and `helix::HierarchySpec::compiled_default()` map the current compiled Drude-Lorentz/Pade and hierarchy defaults. Non-default bath or hierarchy fields are reported as constrained in v0.1.
- CUDA 13 removed legacy `cusparseCcsrmm/csrmm2`; this tree uses a compatibility wrapper around `cusparseSpMM`.

## Documentation

Sphinx documentation lives in `doc/source`. API pages are generated from
`include/` and selected `src/` headers with Doxygen and Breathe. Python autodoc
support is already enabled for future bindings:

```bash
python3 -m venv build/docs-venv
build/docs-venv/bin/python -m pip install -e ".[docs]"
SPHINXBUILD="$PWD/build/docs-venv/bin/sphinx-build" \
  make -C doc html SPHINXOPTS="-W --keep-going"
```

The HTML output is written to `doc/build/html`. Doxygen is required for local
C++/CUDA API builds and in the documentation CI workflow. The tracked
`doc/Doxyfile.in` template is materialized under `doc/_doxygen/` during builds.

The `Documentation` GitHub Actions workflow builds docs for pull requests and
publishes `doc/build/html` to GitHub Pages on pushes to `main`. The HELIX
repository is configured to use **GitHub Actions** as the Pages publishing
source; forks need the same Pages setting if they want automatic publication.
After the first successful `main` deployment, the site is available at
<https://yjmaxpayne.github.io/HELIX/>.

## Release Management

The first HELIX product version is `v0.0.1`. Product versions come from SemVer
Git tags; CMake embeds the resolved version in the executable:

```bash
build/cmake/helix --version
```

For the initial release candidate, pass the tag explicitly so the binary,
package manifest, and GitHub Release stay synchronized:

```bash
HELIX_RELEASE_VERSION=v0.0.1 HELIX_STEPS=1980 scripts/verify_examples.sh
scripts/package_release.sh v0.0.1
```

Use Conventional Commit subjects and generate formal changelog entries with
`cz changelog --incremental` from the optional `.[release]` tooling.

## Credit

This repository keeps the original CUDA implementation usable while moving it toward a maintainable HEOM library.

The original GPU-HEOM CUDA code is by Masashi Tsuchimoto and Yoshitaka Tanimura. The Kyoto University Theoretical Chemistry Group research activity page lists "GPU-HEOM (HEOM code for CUDA)" as work by M. Tsuchimoto and Y. Tanimura:

- http://theochem.kuchem.kyoto-u.ac.jp/resarch/resarch_activity.htm

HELIX modernization, Linux/CMake/CUDA 13 migration, verification workflow, documentation, ongoing library maintenance and further developments are by Ye Jun <yjmaxpayne@hotmail.com>.

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

## Supports

For questions, issues, or collaboration requests, please use GitHub Issues or contact Ye Jun at yjmaxpayne@hotmail.com.
