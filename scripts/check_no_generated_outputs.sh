#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -eq 0 ]]; then
	exit 0
fi

cat >&2 <<'MESSAGE'
Generated HELIX run outputs and profiler captures must not be committed.
Keep local outputs under build/ or another scratch directory.
Nsight reports may embed environment variables, credentials, and local paths.
MESSAGE

printf '  %s\n' "$@" >&2
exit 1
