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

===================
HELIX documentation
===================

**HELIX** is a C++17/CUDA modernization of a legacy GPU-accelerated
Hierarchical Equations of Motion (HEOM) codebase. The supported v0.1
user-facing artifacts are the ``helix`` compatibility executable and the
``HELIX::helix`` C++ library foundation target. The source tree is being
refactored toward a reusable HEOM runtime while preserving the validated legacy
CUDA baseline.

The docs come from the source where possible. Doxygen and Breathe generate
C++/CUDA API pages from ``include/`` and selected ``src/`` headers. Python
autodoc, MyST, doctest, and viewcode are enabled for the experimental binding
docs and future Python sources.

What HELIX does
===============

HELIX preserves a CUDA HEOM implementation while making its build, test,
verification, and runtime contracts explicit:

* GPU HEOM propagation using CUDA, cuBLAS, and cuSPARSE.
* Sparse default numerical path for the active CUDA 13 migration.
* Reference baseline workflow based on ``examples/outputEnergy.txt``.
* Layered CTest contract for unit, CUDA, numerical, integration, baseline,
  sanitizer, and benchmark labels.
* Public ``include/helix`` headers for the v0.1 C++ library foundation.
* Experimental build-tree Python binding over the public C++ API.

Documentation overview
----------------------

.. toctree::
   :maxdepth: 2
   :caption: Getting started

   getting-started/index

.. toctree::
   :maxdepth: 2
   :caption: Core concepts

   core-concepts/index

.. toctree::
   :maxdepth: 2
   :caption: Architecture

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
   :caption: API reference

   api-reference/index

.. toctree::
   :maxdepth: 1
   :caption: Reference

   glossary

Main features
-------------

.. list-table::
   :widths: 30 70
   :header-rows: 1

   * - Feature
     - Description
   * - CUDA runtime
     - C++17/CUDA executable with cuBLAS and cuSPARSE execution paths.
   * - HEOM baseline
     - Checked-in energy trace for ``HELIX_STEPS=1980`` plus 1000-step prefix validation.
   * - CUDA 13 compatibility
     - Compatibility wrappers for removed legacy cuSPARSE CSRMM entry points.
   * - CTest contract
     - Shared labels and GPU resource locking through ``helix_add_test()``.
   * - C++ library foundation
     - Public ``<helix/helix.h>`` API and exported ``HELIX::helix`` CMake target.
   * - Experimental Python binding
     - Optional pybind11 smoke path enabled with ``HELIX_BUILD_PYTHON=ON``.

Example usage
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

Current status
--------------

The executable is still the regression harness and owns legacy generated files.
The ``include/helix`` headers expose the v0.1 C++ library starting point; core
library calls return ``RunResult`` and do not write legacy output files.
Selected ``src`` headers document the legacy CUDA runtime that both paths still
use internally.
