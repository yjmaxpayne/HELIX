===================
Baselines and drift
===================

HELIX uses a checked-in energy trace to protect numerical behavior during
modernization.

Energy trace
------------

``examples/outputEnergy.txt`` is the reference trace for the current default
compiled profile. It contains 1981 rows for ``HELIX_STEPS=1980`` plus the final
output row. The default full baseline gate runs ``HELIX_STEPS=1000`` and
compares the 1001-row prefix against that longer reference.

Verification commands
---------------------

Quick smoke:

.. code-block:: bash

   HELIX_STEPS=2 scripts/verify_examples.sh

Full baseline:

.. code-block:: bash

   HELIX_STEPS=1000 scripts/verify_examples.sh

Tolerance
---------

The default baseline comparison uses absolute tolerance ``1e-5`` for
``outputEnergy.txt``. Numerical tests should print reference inputs, maximum
absolute difference, maximum relative difference, tolerances, and the reference
source.
