====
HEOM
====

Hierarchical Equations of Motion (HEOM) model open quantum system dynamics by
coupling the reduced density matrix to a hierarchy of auxiliary density
operators. HELIX keeps the original GPU-HEOM numerical workflow usable while
making the implementation testable and portable.

Default Profile
---------------

The default build profile uses:

* ``Param::N=1024``
* ``Param::KMax=2``
* ``Param::JMax=3``
* hierarchy size 10
* single precision via ``SINGLE``
* counter term via ``USE_COUNTER``

Bath Expansion
--------------

``src/Psd/`` computes Pade spectrum decomposition poles and residues. These
values feed ``setTemperatureDependence()``, which initializes bath frequencies
and HEOM coefficients used by the Liouville propagation path.

Implementation Status
---------------------

The numerical semantics are protected by reference tests and the executable
baseline. The immediate modernization goal is not to change the HEOM equations;
it is to expose lifecycle, configuration, and API boundaries around the current
verified behavior.
