.. _api-reference:

=============
API Reference
=============

This section documents the current HELIX source-level interfaces and reserves a
Python API structure for future bindings.

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
     - Current C++/CUDA implementation surface under ``src/``.
   * - :doc:`python`
     - Reserved documentation structure for future Python bindings.
   * - :doc:`generated`
     - Generated Doxygen/Breathe pages for selected C++/CUDA headers.

API Status
----------

The executable is stable enough for baseline verification. The C++/CUDA headers
are internal implementation interfaces until an explicit HEOM context and
installable library boundary are introduced.
