Python API preparation
======================

HELIX does not yet expose a Python package. The documentation environment is
configured for later Python API pages, so bindings can be added without
replacing the Sphinx stack.

Enabled Sphinx features
-----------------------

* ``sphinx.ext.autodoc``
* ``sphinx.ext.autosummary``
* ``sphinx.ext.napoleon``
* ``sphinx.ext.doctest``
* ``sphinx.ext.viewcode``
* MyST Markdown support

Planned source locations
------------------------

``doc/source/conf.py`` currently prepends these paths to ``sys.path``:

* ``python/``
* ``src/python/``
* repository root

When Python bindings are introduced, add module pages here with
``.. automodule::`` or ``.. autosummary::`` directives and keep examples
doctestable where practical.

Proposed binding boundary
-------------------------

The first Python API should wrap the explicit HEOM context once it exists,
rather than the current global executable state. That keeps Python resource
ownership, CUDA handle cleanup, and output policy explicit.
