=============
Runtime model
=============

The current runtime still uses legacy global CUDA state internally. v0.1 wraps
that path with a sequential ``Context`` and ``HEOMSolver`` library surface while
keeping the ``helix`` executable as the compatibility workflow.

Execution sequence
------------------

.. code-block:: text

   initialize()
     initialize PSD data
     build temperature-dependent bath coefficients
     create dense and sparse system operators
     create cuBLAS handle
     build hierarchy rows and edges
     allocate rho and buffers
     initialize device constants

   loop over HELIX_STEPS
     output rho and energy at configured intervals
     develop()

   final output and cleanup

Cleanup contract
----------------

Code that calls runtime functions in-process must release global resources:

.. code-block:: c++

   clearLiouvilleStorage();
   clearMatrixStorage();
   cublasDestroy(cublasHandle);
   cublasHandle = nullptr;

Library boundary
----------------

The public v0.1 library boundary is:

* ``Context`` for one-active-context lifecycle ownership.
* ``HEOMSolver`` for the current legacy spin-glass compatibility run path.
* ``RunResult`` for final reduced density shape, time, and diagnostics.
* ``Diagnostics`` for unsupported runtime options and validation errors.

Core library calls return structured results and do not write legacy output
files. File output remains executable-only behavior.

Known limits
------------

* Only sequential create/run/destroy/recreate is supported.
* Only the legacy CUDA sparse backend and single precision runtime path are
  accepted.
* Arbitrary sparse system schema validation exists, but runtime execution is
  limited to the legacy spin-glass compatibility adapter.
