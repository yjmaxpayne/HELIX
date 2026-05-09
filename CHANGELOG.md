# Changelog

All notable changes to HELIX will be documented in this file.

The format is based on Keep a Changelog, and this project uses Semantic
Versioning with `vMAJOR.MINOR.PATCH` Git tags as the version authority.

Formal release entries should be generated from Conventional Commit history with:

```bash
python -m pip install -e ".[release]"
cz changelog --incremental
```

## v0.0.1 (2026-05-09)

### Added

- Git-tag-based version configuration for CMake builds, release packaging, and
  documentation metadata.
