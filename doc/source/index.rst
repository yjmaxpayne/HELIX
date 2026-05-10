.. title::
   HELIX: GPU-Accelerated HEOM

.. image:: _static/logo.png
   :alt: HELIX logo
   :align: center
   :width: 220px

.. image:: https://img.shields.io/badge/C%2B%2B-17-00599C.svg?logo=cplusplus&logoColor=white
   :alt: C++17

.. image:: https://img.shields.io/badge/CUDA-13.0%2B-76B900.svg?logo=nvidia&logoColor=white
   :alt: CUDA 13.0+

.. image:: https://img.shields.io/badge/CMake-3.24%2B-064F8C.svg?logo=cmake&logoColor=white
   :alt: CMake 3.24+

.. image:: https://img.shields.io/badge/status-Modernizing-yellow
   :alt: Project status

.. image:: https://img.shields.io/badge/HEOM-GPU--Accelerated-6A5ACD.svg
   :alt: GPU-accelerated HEOM

==============================
Welcome to HELIX Documentation
==============================

**HELIX** is a C++17/CUDA modernization of a legacy GPU-accelerated
Hierarchical Equations of Motion (HEOM) codebase. The current supported product
is the ``helix`` executable; the source tree is being refactored toward a
reusable HEOM runtime and future Python-facing API.

The documentation is source-driven. C++/CUDA API pages are generated from
``include/`` and selected ``src/`` headers with Doxygen and Breathe. Python
autodoc, MyST, doctest, and viewcode are already enabled so future Python
bindings can be documented without rebuilding the documentation stack.

What is HELIX?
==============

HELIX preserves a CUDA HEOM implementation while making its build, test,
verification, and runtime contracts explicit:

* **GPU HEOM propagation** using CUDA, cuBLAS, and cuSPARSE.
* **Sparse default numerical path** for the active CUDA 13 migration.
* **Reference baseline workflow** based on ``examples/outputEnergy.txt``.
* **Layered CTest contract** for unit, CUDA, numerical, integration, and
  baseline checks.
* **Refactoring-ready source reference** for moving from global runtime state
  toward an explicit HEOM context.

Documentation Overview
----------------------

.. toctree::
   :maxdepth: 2
   :caption: Getting Started

   getting-started/index

.. toctree::
   :maxdepth: 2
   :caption: Core Concepts

   core-concepts/index

.. toctree::
   :maxdepth: 2
   :caption: Architecture Guide

   architecture/index

.. toctree::
   :maxdepth: 2
   :caption: Tutorials

   tutorials/index

.. toctree::
   :maxdepth: 2
   :caption: Development

   development/index

.. toctree::
   :maxdepth: 2
   :caption: Release

   release/index

.. toctree::
   :maxdepth: 2
   :caption: API Reference

   api-reference/index

.. toctree::
   :maxdepth: 1
   :caption: Reference

   glossary

Key Features
------------

.. list-table::
   :widths: 30 70
   :header-rows: 1

   * - Feature
     - Description
   * - **CUDA Runtime**
     - C++17/CUDA executable with cuBLAS and cuSPARSE execution paths.
   * - **HEOM Baseline**
     - Checked-in energy trace for ``HELIX_STEPS=1980`` plus smoke validation.
   * - **CUDA 13 Compatibility**
     - Compatibility wrappers for removed legacy cuSPARSE CSRMM entry points.
   * - **CTest Contract**
     - Shared labels and GPU resource locking through ``helix_add_test()``.
   * - **Future Python API**
     - Sphinx configuration already enables autodoc, autosummary, napoleon,
       doctest, MyST, and viewcode.

Example Usage
-------------

.. code-block:: bash

   cmake -S . -B build/cmake -DCMAKE_BUILD_TYPE=Release
   cmake --build build/cmake --parallel "$(nproc)"

   mkdir -p build/example-run
   cd build/example-run
   HELIX_STEPS=2 ../cmake/helix

For the repository verification wrapper:

.. code-block:: bash

   HELIX_STEPS=2 scripts/verify_examples.sh

Current Status
--------------

The executable remains the authoritative regression harness. The
``include/helix`` headers expose the v0.1 C++ library foundation, while selected
``src`` headers are documented as implementation references for the current
legacy CUDA runtime.
