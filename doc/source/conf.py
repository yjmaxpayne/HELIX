"""Sphinx configuration for the HELIX documentation."""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT_ROOT = ROOT.parent
DOXYGEN_XML = PROJECT_ROOT / "doc" / "_doxygen" / "xml"
DOXYGEN_CONFIG = PROJECT_ROOT / "doc" / "_doxygen" / "Doxyfile.generated"
DOXYGEN_TEMPLATE = PROJECT_ROOT / "doc" / "Doxyfile.in"
SKIP_DOXYGEN = os.environ.get("HELIX_DOCS_SKIP_DOXYGEN") == "1"

sys.path.insert(0, str(PROJECT_ROOT / "python"))
sys.path.insert(0, str(PROJECT_ROOT / "src" / "python"))
sys.path.insert(0, str(PROJECT_ROOT))


def _get_doc_version() -> str:
    env_version = os.environ.get("HELIX_DOCS_VERSION", "").strip()
    if env_version:
        return env_version.removeprefix("v")

    try:
        from dunamai import Style, Version

        return Version.from_git().serialize(style=Style.Pep440)
    except Exception:
        return "0.0.1"


version = _get_doc_version()
project = "HELIX"
author = "Ye Jun"
copyright = "2026, Ye Jun"
release = version
master_doc = "index"

extensions = [
    "sphinx.ext.autodoc",
    "sphinx.ext.autosummary",
    "sphinx.ext.doctest",
    "sphinx.ext.coverage",
    "sphinx.ext.napoleon",
    "sphinx.ext.mathjax",
    "sphinx.ext.viewcode",
    "sphinx.ext.autosectionlabel",
    "breathe",
    "myst_parser",
    "sphinx_copybutton",
    "sphinxcontrib.mermaid",
]

templates_path = ["_templates"]
source_suffix = {".rst": "restructuredtext", ".md": "markdown"}
exclude_patterns = [
    "_build",
    "Thumbs.db",
    ".DS_Store",
    "CLAUDE.md*",
    "**/CLAUDE.md*",
]

html_theme = "furo"
html_title = f"HELIX · v{version}"
html_logo = "_static/logo.png"
html_static_path = ["_static"]
html_extra_path = [".nojekyll"]
html_show_sourcelink = False

autosectionlabel_prefix_document = True
copybutton_prompt_text = r"^\$ "
copybutton_prompt_is_regexp = True
enable_eval_rst = True

myst_enable_extensions = [
    "colon_fence",
    "deflist",
    "fieldlist",
    "tasklist",
    "attrs_block",
    "linkify",
]

autodoc_member_order = "bysource"
autodoc_default_options = {
    "members": True,
    "undoc-members": True,
    "show-inheritance": True,
}
autosummary_generate = True
napoleon_google_docstring = True
napoleon_numpy_docstring = True
doctest_path = [str(PROJECT_ROOT / "examples")]

breathe_projects = {"HELIX": str(DOXYGEN_XML)}
breathe_default_project = "HELIX"
breathe_show_include = True


def write_doxygen_config() -> None:
    """Materialize the tracked Doxyfile template for the local checkout."""

    text = DOXYGEN_TEMPLATE.read_text(encoding="utf-8")
    text = text.replace("@PROJECT_ROOT@", str(PROJECT_ROOT))
    text = text.replace("@DOXYGEN_OUTPUT_DIR@", str(PROJECT_ROOT / "doc" / "_doxygen"))
    DOXYGEN_CONFIG.parent.mkdir(parents=True, exist_ok=True)
    DOXYGEN_CONFIG.write_text(text, encoding="utf-8")


def run_doxygen(_: object) -> None:
    """Generate Doxygen XML before Breathe resolves C++/CUDA API directives."""

    if SKIP_DOXYGEN:
        return

    doxygen = shutil.which("doxygen")
    if doxygen is None:
        raise RuntimeError(
            "doxygen is required to build HELIX C++/CUDA API documentation. "
            "Install doxygen, or set HELIX_DOCS_SKIP_DOXYGEN=1 only for "
            "non-API authoring checks."
        )

    write_doxygen_config()
    subprocess.run([doxygen, str(DOXYGEN_CONFIG)], cwd=PROJECT_ROOT, check=True)


def write_empty_doxygen_index() -> None:
    """Create a placeholder XML index for non-API authoring builds."""

    DOXYGEN_XML.mkdir(parents=True, exist_ok=True)
    (DOXYGEN_XML / "index.xml").write_text(
        """<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<doxygenindex version="1.9.0">
</doxygenindex>
""",
        encoding="utf-8",
    )


def setup(app: object) -> None:
    app.add_css_file("css/style.css")
    if SKIP_DOXYGEN:
        write_empty_doxygen_index()
        app.tags.add("no_doxygen")
    else:
        app.connect("builder-inited", run_doxygen)
