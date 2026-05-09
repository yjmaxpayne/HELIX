# Contributing

This repository is a legacy CUDA HEOM codebase under active refactoring and modernization. Keep changes small, reviewable, and reproducible.

## Development Workflow

1. Create a branch from `main`.
2. Install the local Git hooks once per checkout:

   ```bash
   python -m pip install -e ".[dev]"
   pre-commit install --hook-type pre-commit --hook-type commit-msg
   ```

   Run the full hook set before sending larger changes:

   ```bash
   pre-commit run --all-files
   ```

   The default hooks cover file hygiene, Python linting/formatting, shell syntax,
   generated-output guards, and Conventional Commit message validation. The
   C++/CUDA clang-format hook is available as a manual hook because the legacy
   source tree is still being modernized incrementally:

   ```bash
   pre-commit run clang-format --all-files --hook-stage manual
   ```

3. Build with CMake before opening a pull request:

   ```bash
   cmake -S . -B build/cmake -DCMAKE_BUILD_TYPE=Release
   cmake --build build/cmake --parallel "$(nproc)"
   ```

4. Run the quick example smoke test:

   ```bash
   HELIX_STEPS=2 scripts/verify_examples.sh
   ```

5. For changes affecting numerics, also run the full baseline:

   ```bash
   HELIX_STEPS=1980 scripts/verify_examples.sh
   ```

## Numerical Changes

- Do not change core HEOM numerical semantics in cleanup-only pull requests.
- If a numerical change is intentional, document the reason, affected parameters, and expected baseline differences.
- Compare `outputEnergy.txt` against `examples/outputEnergy.txt`; timing in `output.txt` is not a numerical baseline.

## Generated Files

Do not commit generated run outputs from local experiments:

- `build/`
- `output.txt`
- `outputEnergy.txt`
- `output_rho*.txt`
- `snapshot_rho*.dat`

Historical reference files under `examples/` are intentionally tracked.

## Dependencies

Avoid adding new dependencies unless they are required for build, verification, or reproducibility. Document any new dependency in `README.md`.
