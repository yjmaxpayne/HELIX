.. _api-reference:

=============
API reference
=============

These pages document HELIX C++ headers and implementation interfaces used by the
executable. The Python page is a placeholder for later bindings.

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
     - Placeholder documentation structure for later Python bindings.
   * - :doc:`generated`
     - Doxygen/Breathe pages for selected C++/CUDA headers.

API status
----------

The executable can run baseline verification. The ``include/helix`` headers
describe the v0.1 library starting point; selected ``src`` headers remain
implementation references rather than ABI promises.
