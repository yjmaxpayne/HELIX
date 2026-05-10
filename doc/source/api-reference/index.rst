.. _api-reference:

=============
API Reference
=============

This section documents the current HELIX C++ library foundation and selected
source-level implementation interfaces. It also reserves a Python API structure
for future bindings.

.. toctree::
   :maxdepth: 2
   :caption: Modules

   cpp
   python
   generated

Module Overview
---------------

.. list-table::
   :widths: 25 75
   :header-rows: 1

   * - Module
     - Description
   * - :doc:`cpp`
     - Current C++ public headers under ``include/helix`` plus selected CUDA
       implementation headers under ``src/``.
   * - :doc:`python`
     - Reserved documentation structure for future Python bindings.
   * - :doc:`generated`
     - Generated Doxygen/Breathe pages for selected C++/CUDA headers.

API Status
----------

The executable is stable enough for baseline verification. The
``include/helix`` headers describe the v0.1 library foundation; selected
``src`` headers remain implementation references rather than ABI promises.
