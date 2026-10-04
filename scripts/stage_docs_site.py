#!/usr/bin/env python3
"""Stage versioned Sphinx HTML for GitHub Pages deployment."""

from __future__ import annotations

import argparse
import json
import re
import shutil
from pathlib import Path


SEMVER_TAG = re.compile(
    r"^v(?P<major>0|[1-9]\d*)\."
    r"(?P<minor>0|[1-9]\d*)\."
    r"(?P<patch>0|[1-9]\d*)"
    r"(?:-(?P<prerelease>[0-9A-Za-z][0-9A-Za-z.-]*))?$"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Stage HELIX documentation under latest/ or a release tag path."
    )
    parser.add_argument(
        "--site-dir",
        required=True,
        type=Path,
        help="Persistent static site directory, usually a gh-pages worktree.",
    )
    parser.add_argument(
        "--docs-dir",
        required=True,
        type=Path,
        help="Built Sphinx HTML directory to publish.",
    )
    parser.add_argument(
        "--version",
        required=True,
        help="Target documentation directory: latest or a vMAJOR.MINOR.PATCH tag.",
    )
    parser.add_argument(
        "--base-path",
        default="/HELIX/",
        help="Absolute GitHub Pages base path used in redirects and version links.",
    )
    return parser.parse_args()


def validate_version(version: str) -> None:
    if version == "latest" or SEMVER_TAG.fullmatch(version):
        return
    raise SystemExit(
        "Documentation version must be 'latest' or a SemVer release tag such as v0.1.0."
    )


def normalized_base_path(base_path: str) -> str:
    if not base_path.startswith("/"):
        base_path = f"/{base_path}"
    if not base_path.endswith("/"):
        base_path = f"{base_path}/"
    return base_path


def prerelease_key(prerelease: str | None) -> tuple[int, tuple[tuple[int, int | str], ...]]:
    if prerelease is None:
        return (1, ())

    parts: list[tuple[int, int | str]] = []
    for identifier in prerelease.split("."):
        if identifier.isdigit():
            parts.append((0, int(identifier)))
        else:
            parts.append((1, identifier))
    return (0, tuple(parts))


def semver_sort_key(
    version: str,
) -> tuple[int, int, int, tuple[int, tuple[tuple[int, int | str], ...]]]:
    match = SEMVER_TAG.fullmatch(version)
    if match is None:
        raise ValueError(f"Not a SemVer tag: {version}")

    return (
        int(match.group("major")),
        int(match.group("minor")),
        int(match.group("patch")),
        prerelease_key(match.group("prerelease")),
    )


def copy_docs(docs_dir: Path, target_dir: Path) -> None:
    if not docs_dir.is_dir():
        raise SystemExit(f"Built documentation directory not found: {docs_dir}")

    temporary_dir = target_dir.with_name(f".{target_dir.name}.tmp")
    if temporary_dir.exists():
        shutil.rmtree(temporary_dir)

    shutil.copytree(docs_dir, temporary_dir)
    if target_dir.exists():
        shutil.rmtree(target_dir)
    temporary_dir.rename(target_dir)


def clean_root(site_dir: Path) -> None:
    """Remove stale root-level Sphinx output while preserving version directories."""

    preserve_names = {".git", ".nojekyll", "CNAME", "index.html", "versions.json"}
    for path in site_dir.iterdir():
        if path.name in preserve_names:
            continue
        if path.is_dir() and (path.name == "latest" or SEMVER_TAG.fullmatch(path.name)):
            continue
        if path.is_dir():
            shutil.rmtree(path)
        else:
            path.unlink()


def version_label(version: str) -> str:
    if version == "latest":
        return "latest (main)"
    return version


def version_entries(site_dir: Path, base_path: str) -> list[dict[str, str]]:
    entries: list[dict[str, str]] = []
    if (site_dir / "latest").is_dir():
        entries.append(
            {
                "name": "latest",
                "label": version_label("latest"),
                "path": f"{base_path}latest/",
            }
        )

    release_versions = sorted(
        (
            path.name
            for path in site_dir.iterdir()
            if path.is_dir() and SEMVER_TAG.fullmatch(path.name)
        ),
        key=semver_sort_key,
        reverse=True,
    )
    for release_version in release_versions:
        entries.append(
            {
                "name": release_version,
                "label": version_label(release_version),
                "path": f"{base_path}{release_version}/",
            }
        )
    return entries


def write_root_redirect(site_dir: Path, base_path: str) -> None:
    latest_url = f"{base_path}latest/"
    (site_dir / "index.html").write_text(
        f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>HELIX documentation</title>
  <link rel="canonical" href="{latest_url}">
  <meta http-equiv="refresh" content="0; url={latest_url}">
  <script>
    window.location.replace("{latest_url}" + window.location.search + window.location.hash);
  </script>
</head>
<body>
  <p><a href="{latest_url}">HELIX documentation</a></p>
</body>
</html>
""",
        encoding="utf-8",
    )


def write_versions_json(site_dir: Path, entries: list[dict[str, str]]) -> None:
    versions = {
        "default": "latest",
        "versions": entries,
    }
    (site_dir / "versions.json").write_text(
        json.dumps(versions, indent=2) + "\n",
        encoding="utf-8",
    )


def main() -> None:
    args = parse_args()
    version = args.version.strip()
    validate_version(version)

    site_dir = args.site_dir.resolve()
    docs_dir = args.docs_dir.resolve()
    base_path = normalized_base_path(args.base_path.strip() or "/")

    site_dir.mkdir(parents=True, exist_ok=True)
    copy_docs(docs_dir, site_dir / version)
    clean_root(site_dir)

    (site_dir / ".nojekyll").write_text("", encoding="utf-8")
    write_root_redirect(site_dir, base_path)
    entries = version_entries(site_dir, base_path)
    write_versions_json(site_dir, entries)

    print(f"Staged HELIX documentation: {version} -> {site_dir / version}")
    print(f"Wrote {site_dir / 'versions.json'} with {len(entries)} version entries")


if __name__ == "__main__":
    main()
