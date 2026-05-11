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

## Releases and Zenodo DOI

Citation metadata is split across two files: `CITATION.cff` (GitHub native, human and tool
facing) and `.zenodo.json` (consumed by Zenodo when a GitHub Release is published). Both
must be kept in sync on every release.

One-time setup (account owner only):

1. Sign in to <https://zenodo.org/account/settings/github/> with the same GitHub account that
   owns the repository and flip the toggle next to `yjmaxpayne/HELIX` to **On**.
2. Confirm the webhook appears under the repository's `Settings → Webhooks` page on GitHub.

Per release:

1. Bump the version with Conventional Commit history and tag it. The Git tag is the version
   authority (`tool.helix.version.authority` in `pyproject.toml`):

   ```bash
   git tag -a vMAJOR.MINOR.PATCH -m "Release vMAJOR.MINOR.PATCH"
   git push origin vMAJOR.MINOR.PATCH
   ```

2. Pushing the tag triggers the `Release` workflow (`.github/workflows/release.yml`), which
   builds the CUDA package and creates a GitHub Release. Publishing that Release fires the
   Zenodo webhook, which reads `.zenodo.json` and archives the tagged source tree.
3. After Zenodo finishes, copy the **concept DOI** (the one that always resolves to the
   latest version, shown on the Zenodo record page under "Cite all versions") and:
   - uncomment the `doi:` line in `CITATION.cff`;
   - uncomment the Zenodo badge `<a>` in `README.md` and remove the `DOI: pending`
     placeholder badge;
   - replace the `note = {... DOI: pending ...}` line in the README BibTeX block with
     `doi = {10.5281/zenodo.XXXXXXX}`.
4. Commit those three edits with a `docs: backfill Zenodo DOI for vX.Y.Z` message.

The version DOI (one per release) is also returned by Zenodo. Prefer the **concept DOI** for
the badge and `CITATION.cff` so that the canonical citation always points to "this software,
any version". Cite the version DOI only when reproducibility requires pinning to a specific
release.
