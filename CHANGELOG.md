# Changelog

All notable changes to HELIX will be documented in this file.

The format is based on Keep a Changelog, and this project uses Semantic
Versioning with `vMAJOR.MINOR.PATCH` Git tags as the version authority.

Formal release entries should be generated from Conventional Commit history with:

```bash
python -m pip install -e ".[release]"
cz changelog --incremental
```

## v0.0.3 (2026-05-14)

### Feat

- **benchmark**: add user-facing benchmark reference
- **benchmark**: add v0.0.3 profiling foundation

### Fix

- **security**: remove tracked Nsight profiler capture

## v0.0.2 (2026-05-11)

### BREAKING CHANGE

- RunResult::reducedDensity is replaced by RunResult::reduced_density and reduced_density_shape.

### Feat

- **api**: add Python binding and C++ example gates
- **cli**: add compatibility wrapper baseline gates
- **result**: add structured RunResult extraction

### Fix

- **CI/CD**: resolving issues associated cuda.temp env

### Refactor

- **layout**: standardize HELIX source naming

## v0.0.1 (2026-05-09)

### Added

- Git-tag-based version configuration for CMake builds, release packaging, and
  documentation metadata.
