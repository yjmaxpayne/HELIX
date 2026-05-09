=============
Core Concepts
=============

This section defines the concepts used throughout the HELIX documentation.

.. toctree::
   :maxdepth: 2
   :caption: Contents:

   heom
   runtime-model
   gpu-execution
   baselines

Concept Map
-----------

.. list-table::
   :widths: 30 70
   :header-rows: 1

   * - Concept
     - Description
   * - **HEOM**
     - Hierarchical Equations of Motion for open quantum system dynamics.
   * - **Hierarchy State**
     - Reduced density matrix plus auxiliary density operators.
   * - **Sparse Runtime**
     - Default CUDA 13 path using host-orchestrated cuBLAS/cuSPARSE work.
   * - **Energy Baseline**
     - Reference ``outputEnergy.txt`` trace used to detect numerical drift.
   * - **Lifecycle Boundary**
     - Current global state cleanup contract and future explicit context.
