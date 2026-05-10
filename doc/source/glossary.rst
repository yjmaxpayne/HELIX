========
Glossary
========

Terms used throughout the HELIX documentation.

.. glossary::
   :sorted:

   Auxiliary Density Operator
      A hierarchy element coupled to the reduced density matrix in HEOM.

   Baseline Trace
      The checked-in ``examples/outputEnergy.txt`` reference used to detect
      numerical drift.

   Breathe
      Sphinx extension that renders Doxygen XML into Sphinx pages.

   Doxygen
      Documentation generator used to extract C++/CUDA declarations from
      ``src/``.

   HEOM
      Hierarchical Equations of Motion. A method for open quantum system
      dynamics that expands environment memory effects into auxiliary
      hierarchy terms.

   Hierarchy Size
      Number of hierarchy rows generated from ``KMax`` and ``JMax``. The
      current default profile has hierarchy size 10.

   Liouville Path
      HELIX propagation code that computes density-matrix derivatives and
      advances ``dRho``.

   Pade Spectrum Decomposition
      Pole and residue expansion used by HELIX to initialize bath coefficients.

   Sparse Runtime
      The active default execution path that uses host-orchestrated cuBLAS and
      cuSPARSE operations.

   ``HELIX_STEPS``
      Runtime environment variable controlling propagation step count.
