.. _api-reference:

=============
API reference
=============

These pages document HELIX C++ headers, the v0.1 public library foundation, and
the optional experimental Python binding.

.. toctree::
   :maxdepth: 2
   :caption: Modules

   cpp
   python
   generated

Module overview
---------------

.. list-table::
   :widths: 25 75
   :header-rows: 1

   * - Module
     - Description
   * - :doc:`cpp`
     - C++ public headers under ``include/helix`` plus selected CUDA
       implementation headers under ``src/``.
   * - :doc:`python`
     - Experimental pybind11 binding smoke path over the public C++ API.
   * - :doc:`generated`
     - Doxygen/Breathe pages for selected C++/CUDA headers.

API status
----------

The executable remains the compatibility and baseline verification path. The
``include/helix`` headers describe the v0.1 library starting point; selected
``src`` headers remain implementation references rather than ABI promises.
