=============
Core concepts
=============

These pages define the concepts used throughout the HELIX documentation.

.. toctree::
   :maxdepth: 2
   :caption: Contents:

   heom
   runtime-model
   gpu-execution
   baselines

Concept map
-----------

.. list-table::
   :widths: 30 70
   :header-rows: 1

   * - Concept
     - Description
   * - HEOM
     - Hierarchical Equations of Motion for open quantum system dynamics.
   * - Hierarchy state
     - Reduced density matrix plus auxiliary density operators.
   * - Sparse runtime
     - Default CUDA 13 path using host-orchestrated cuBLAS/cuSPARSE work.
   * - Energy baseline
     - Reference ``outputEnergy.txt`` trace used to detect numerical drift.
   * - Lifecycle boundary
     - Current global state cleanup contract and eventual explicit context.
