# GitHub Repository Setup

These settings should be configured in GitHub after pushing the repository.

## Required Before Public Release

- Add a `LICENSE` file selected by the project owner.
- Confirm whether `dev/ref_docs/` materials can be redistributed in the public repository.
- Enable private vulnerability reporting if the repository is public.

## Branch Protection

Recommended rule for `main`:

- Require pull request reviews before merging.
- Require status checks to pass before merging.
- Require `Repository Health / Metadata and script checks`.
- Require `CUDA Smoke / Build and smoke on CUDA runner`.
- Require branches to be up to date before merging.
- Prevent force pushes.

## CUDA CI

The `CUDA Smoke`, `Numerical Baseline`, and `Release` workflows target a CUDA-capable self-hosted runner through:

```yaml
runs-on: self-hosted
```

The runner should provide:

- NVIDIA driver
- CUDA toolkit with `nvcc`
- CMake
- A host compiler compatible with the CUDA toolkit
- GitHub Actions runner access to this repository

The default CI CUDA architecture is `89`, matching the verified RTX 4070 class environment. Override `HELIX_CUDA_ARCHITECTURES` or the manual workflow input when validating another GPU target.

## Workflows

- `Repository Health`: runs on pull requests and pushes to `main`; checks required metadata, shell syntax, and tracked generated artifacts.
- `CUDA Smoke`: runs on pull requests and pushes to `main`; builds with CMake and verifies the first `HELIX_STEPS=2` output rows.
- `Numerical Baseline`: runs weekly or manually; runs the full `HELIX_STEPS=1980` baseline and uploads generated outputs.
- `Release`: runs on tags matching `v*.*.*` or manual dispatch; performs the full baseline, packages `helix`, uploads checksums, and publishes a GitHub Release.

## Releases

Create a release by pushing an annotated version tag:

```bash
git tag -a v0.1.0 -m "HELIX v0.1.0"
git push origin v0.1.0
```

The release package name is:

```text
helix-<tag>-linux-x86_64-cuda13-sm89.tar.gz
```

Public repositories also get build provenance through `actions/attest`. Private repositories skip attestation unless the GitHub plan supports private artifact attestations.

## Remote

The expected remote is:

```text
git@github.com:yjmaxpayne/HELIX.git
```
