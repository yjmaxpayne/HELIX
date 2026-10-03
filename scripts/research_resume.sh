#!/usr/bin/env bash
# Usage: scripts/research_resume.sh <plan-name>
# L3 of the three-layer bootstrap. Prints the canonical resume prompt for
# non-Claude environments (or for re-priming a Claude session from shell).
# See .plan/research/<plan-name>/00-CONTEXT-MANIFEST.md for the truth source.
set -euo pipefail

plan_name="${1:-}"
if [[ -z "$plan_name" ]]; then
    echo "usage: $0 <plan-name>" >&2
    exit 2
fi

manifest=".plan/research/${plan_name}/00-CONTEXT-MANIFEST.md"
if [[ ! -f "$manifest" ]]; then
    echo "manifest not found: $manifest" >&2
    echo "available plans under .plan/research/:" >&2
    if [[ -d .plan/research ]]; then
        find .plan/research -maxdepth 2 -name 00-CONTEXT-MANIFEST.md -printf '  %h\n' >&2 || true
    fi
    exit 1
fi

cat <<PROMPT
You are resuming research plan: ${plan_name}

The single source of truth for what to do next is:
  ${manifest}

Read it in full, then follow its READ_ORDER, STATE_DISCOVERY, and
NEXT_ACTION_TEMPLATE sections. Do not reconstruct state from memory; do not
skip READ_ORDER. Update hypothesis-log.md status fields as you progress; that
table is the only authoritative state.
PROMPT
