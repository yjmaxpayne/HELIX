============
Installation
============

HELIX is currently distributed as source. The active build path is CMake with
the CUDA toolkit.

System Requirements
-------------------

**Compiler and Build Tools**

* CMake 3.24+
* GCC or another C++17-capable host compiler compatible with the installed CUDA
  toolkit
* CUDA Toolkit 13.0+

**GPU Runtime**

* CUDA-capable NVIDIA GPU
* cuBLAS
* cuSPARSE

**Documentation Environment**

* Python 3.11+
* Doxygen for C++/CUDA API extraction
* Sphinx dependencies from the ``docs`` extra in ``pyproject.toml``

Build From Source
-----------------

From the repository root:

.. code-block:: bash

   cmake -S . -B build/cmake -DCMAKE_BUILD_TYPE=Release
   cmake --build build/cmake --parallel "$(nproc)"

If GPU architecture detection fails, pass the architecture explicitly:

.. code-block:: bash

   cmake -S . -B build/cmake -DCMAKE_BUILD_TYPE=Release \
     -DHELIX_CUDA_ARCHITECTURES=89

The executable is written to ``build/cmake/helix``.

Documentation Environment
-------------------------

Use an ignored virtual environment under ``build/`` for local documentation
work:

.. code-block:: bash

   python3 -m venv build/docs-venv
   build/docs-venv/bin/python -m pip install --upgrade pip
   build/docs-venv/bin/python -m pip install -e ".[docs]"

Build the documentation with the virtual environment:

.. code-block:: bash

   SPHINXBUILD="$PWD/build/docs-venv/bin/sphinx-build" \
     make -C doc html SPHINXOPTS="-W --keep-going"

The Sphinx configuration already enables Python autodoc and inserts these
future binding paths:

* ``python/``
* ``src/python/``
* repository root

When Python bindings are added, put importable modules under one of those paths
or update ``doc/source/conf.py`` with the final package location.
