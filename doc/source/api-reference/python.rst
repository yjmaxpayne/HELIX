Python API Preparation
======================

HELIX does not yet expose a Python package. The documentation environment is
already configured for future Python API pages so bindings can be added without
replacing the Sphinx stack.

Enabled Sphinx Features
-----------------------

* ``sphinx.ext.autodoc``
* ``sphinx.ext.autosummary``
* ``sphinx.ext.napoleon``
* ``sphinx.ext.doctest``
* ``sphinx.ext.viewcode``
* MyST Markdown support

Planned Source Locations
------------------------

``doc/source/conf.py`` currently prepends these paths to ``sys.path``:

* ``python/``
* ``src/python/``
* repository root

When Python bindings are introduced, add module pages here with
``.. automodule::`` or ``.. autosummary::`` directives and keep examples
doctestable where practical.

Proposed Binding Boundary
-------------------------

The natural first Python API should wrap a future explicit HEOM context rather
than the current global executable state. That keeps Python resource ownership,
CUDA handle cleanup, and output policy explicit.
