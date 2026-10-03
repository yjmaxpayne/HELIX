#!/usr/bin/env bash
# Smoke test for research bootstrap mechanism.
# Asserts: manifest exists, READ_ORDER files exist, shell fallback handles
# missing-plan and present-plan correctly.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

plan_name="regression-recovery-and-opt"
manifest=".plan/research/${plan_name}/00-CONTEXT-MANIFEST.md"

fail=0
report() { printf '[%s] %s\n' "$1" "$2"; }

# 1. manifest must exist
if [[ -f "$manifest" ]]; then
    report PASS "manifest exists: $manifest"
else
    report FAIL "missing manifest: $manifest"; fail=1
fi

# 2. every READ_ORDER entry referenced in manifest must exist on disk
if [[ -f "$manifest" ]]; then
    while IFS= read -r path; do
        if [[ -e "$path" ]]; then
            report PASS "READ_ORDER target exists: $path"
        else
            report FAIL "READ_ORDER target missing: $path"; fail=1
        fi
    done < <(awk '/^<!-- READ_ORDER_BEGIN -->/{flag=1;next} /^<!-- READ_ORDER_END -->/{flag=0} flag && /^- /{sub(/^- /,""); sub(/ +—.*$/,""); print}' "$manifest")
fi

# 3. shell fallback exists and is executable
if [[ -x scripts/research_resume.sh ]]; then
    report PASS "scripts/research_resume.sh executable"
else
    report FAIL "scripts/research_resume.sh missing or not executable"; fail=1
fi

# 4. shell fallback exits non-zero on missing plan
if scripts/research_resume.sh __definitely_missing__ >/dev/null 2>&1; then
    report FAIL "shell fallback should error on missing plan"; fail=1
else
    report PASS "shell fallback errors on missing plan"
fi

# 5. shell fallback prints manifest path on present plan
if scripts/research_resume.sh "$plan_name" 2>/dev/null | grep -Fq "$manifest"; then
    report PASS "shell fallback prints manifest path"
else
    report FAIL "shell fallback did not print manifest path"; fail=1
fi

# 6. slash command file exists (L1, local-only, .claude/ gitignored)
if [[ -f .claude/commands/research-resume.md ]]; then
    report PASS "slash command exists"
else
    report FAIL "slash command missing"; fail=1
fi

exit "$fail"
