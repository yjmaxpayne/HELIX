============
Installation
============

HELIX is currently distributed as source. The active build path is CMake with
the CUDA toolkit.

System requirements
-------------------

Compiler and build tools:

* CMake 3.24+
* GCC or another C++17-capable host compiler compatible with the installed CUDA
  toolkit
* CUDA Toolkit 13.0+

GPU runtime:

* CUDA-capable NVIDIA GPU
* cuBLAS
* cuSPARSE

Documentation environment:

* Python 3.11+
* Doxygen for C++/CUDA API extraction
* Sphinx dependencies from the ``docs`` extra in ``pyproject.toml``

Build from source
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

C++ library consumers
---------------------

The v0.1 library target is exported as ``HELIX::helix``. Build-tree and
install-tree consumers use the same target. In a separate consumer project, the
CMake entry point is:

.. code-block:: cmake

   cmake_minimum_required(VERSION 3.24)
   project(HELIXConsumer LANGUAGES CXX CUDA)

   find_package(HELIX CONFIG REQUIRED)

   add_executable(consumer main.cpp)
   target_link_libraries(consumer PRIVATE HELIX::helix)

For an install-tree smoke, assuming that consumer project lives in
``consumer/``:

.. code-block:: bash

   cmake --install build/cmake --prefix build/install
   cmake -S consumer -B build/consumer \
     -DCMAKE_PREFIX_PATH="$PWD/build/install" \
     -DCMAKE_CUDA_ARCHITECTURES=89
   cmake --build build/consumer

The repository gate for this contract is:

.. code-block:: bash

   ctest --test-dir build/cmake -R v01_external_consumer_cmake_gate --output-on-failure

Use only public headers under ``include/helix`` in consumer code. The repository
example ``examples/cpp/legacy_spin_glass.cpp`` includes ``<helix/helix.h>`` and
is compiled by ``v01_cpp_library_example_gate``.

Experimental Python binding
---------------------------

The Python binding is disabled by default and is experimental in v0.1. It is a
build-tree pybind11 smoke path, not a wheel or conda packaging contract.

.. code-block:: bash

   uv venv --python 3.13 .venv
   uv pip install -e ".[dev]"
   cmake -S . -B build/cmake-python-313 \
     -DCMAKE_BUILD_TYPE=Release \
     -DHELIX_BUILD_PYTHON=ON \
     -DPython3_EXECUTABLE="$PWD/.venv/bin/python"
   cmake --build build/cmake-python-313 --parallel "$(nproc)"
   ctest --test-dir build/cmake-python-313 -R v01_python_smoke_gate --output-on-failure

Use a fresh CMake build directory, or clear the cache, when switching
``Python3_EXECUTABLE``.

Documentation environment
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

The Sphinx configuration enables Python autodoc and keeps these import search
paths available for binding documentation:

* ``python/``
* ``src/python/``
* repository root

The first two paths are reserved for future pure-Python sources. The current
pybind11 extension is generated in the CMake build tree when
``HELIX_BUILD_PYTHON=ON``.
