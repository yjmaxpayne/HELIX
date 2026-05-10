Release process
===============

``scripts/package_release.sh`` and the ``Release`` GitHub Actions workflow drive
HELIX release packaging. Release builds run on a CUDA-capable self-hosted
runner.

Version source
--------------

HELIX follows Semantic Versioning and uses Git tags as the product-version
authority. Release tags must use ``vMAJOR.MINOR.PATCH`` with an optional
pre-release suffix such as ``v1.2.0-rc.1``. The first HELIX release version is
``v0.0.1``.

At configure time, CMake resolves the version in this order:

* explicit ``-DHELIX_RELEASE_VERSION=vX.Y.Z`` or ``HELIX_RELEASE_VERSION`` from
  the environment;
* the nearest matching Git tag from ``git describe --tags --match 'v[0-9]*'``;
* ``0.0.1`` as a fallback for source snapshots before the first tag exists.

CMake exposes the configured version through ``helix --version`` and records it
in the release package manifest. The Python ``pyproject.toml`` in this
repository only describes the documentation environment; it is not the HELIX
product version.

Changelog and draft notes
-------------------------

``CHANGELOG.md`` is the canonical human-readable release history. Generate
formal release entries from Conventional Commit history:

.. code-block:: bash

   python -m pip install -e ".[release]"
   cz changelog --incremental

Release Drafter keeps a GitHub Release draft updated from merged pull requests.
PR labels drive the release-note categories and version resolver:

* ``major`` for incompatible public behavior or delivery changes;
* ``minor`` for backward-compatible features;
* ``patch`` for backward-compatible fixes.

Release gate
------------

The release workflow performs the full baseline verification before packaging:

.. code-block:: bash

   HELIX_STEPS=1000 scripts/verify_examples.sh

The run must compare ``outputEnergy.txt`` against ``examples/outputEnergy.txt``
successfully before an artifact is published.

Package contents
----------------

The release package contains:

* ``bin/helix``
* ``README.md``
* ``LICENSE``
* ``examples/outputEnergy.txt``
* ``manifest.txt``

The package name encodes the release tag, platform, CUDA major version, and
CUDA architecture label.

Publishing
----------

Pushing a tag matching ``v*.*.*`` or manually dispatching the release workflow
builds, verifies, packages, uploads artifacts, and publishes or updates the
GitHub Release. The workflow rejects non-SemVer release tags and passes the tag
through ``HELIX_RELEASE_VERSION`` so the binary, manifest, and release title
remain synchronized.

For a local release-candidate build:

.. code-block:: bash

   HELIX_RELEASE_VERSION=v0.0.1 HELIX_STEPS=1000 scripts/verify_examples.sh
   scripts/package_release.sh v0.0.1

The separate ``Documentation`` workflow builds the docs. On pushes to ``main``,
the workflow uploads the Sphinx HTML site as a GitHub Pages artifact and deploys
it through the repository's GitHub Actions Pages source.
