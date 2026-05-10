=============
Documentation
=============

HELIX uses Sphinx with Furo, MyST, Doxygen, Breathe, and Python autodoc. This
matches the documentation stack used by the companion emulator-platform project
while keeping C++/CUDA API extraction active for HELIX.

Local Environment
-----------------

Create an ignored virtual environment under ``build/``:

.. code-block:: bash

   python3 -m venv build/docs-venv
   build/docs-venv/bin/python -m pip install --upgrade pip
   build/docs-venv/bin/python -m pip install -e ".[docs]"

Build with warnings promoted to errors:

.. code-block:: bash

   SPHINXBUILD="$PWD/build/docs-venv/bin/sphinx-build" \
     make -C doc html SPHINXOPTS="-W --keep-going"

API Documentation
-----------------

* C++/CUDA API pages are generated from ``include/`` and selected ``src/``
  headers with Doxygen and Breathe.
* ``doc/Doxyfile.in`` is the tracked Doxygen template. The concrete Doxyfile is
  generated under ``doc/_doxygen/`` during the Sphinx build.
* Python API pages are reserved for future bindings and will use autodoc,
  autosummary, napoleon, doctest, and viewcode.
* Keep implementation details in generated API pages and design rationale in
  architecture or core-concepts pages.

CI/CD
-----

The ``Documentation`` GitHub Actions workflow installs Doxygen and Python docs
dependencies, builds Sphinx with warnings as errors, uploads the HTML artifact,
and deploys to GitHub Pages on pushes to ``main``. The canonical HELIX
repository uses the GitHub Actions Pages source and publishes to
``https://yjmaxpayne.github.io/HELIX/`` after a successful ``main`` deployment.

Dependency Boundary
-------------------

``pyproject.toml`` manages Python documentation dependencies. Doxygen is a
native executable and remains a system dependency, declared under
``[tool.helix.docs]`` and installed by CI before Sphinx runs.
