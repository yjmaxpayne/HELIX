## Summary

-

## Validation

- [ ] `cmake -S . -B build/cmake -DCMAKE_BUILD_TYPE=Release`
- [ ] `cmake --build build/cmake --parallel "$(nproc)"`
- [ ] `HELIX_STEPS=2 scripts/verify_examples.sh`
- [ ] Full baseline run, if numerics changed: `HELIX_STEPS=1980 scripts/verify_examples.sh`

## Numerical Impact

- [ ] No intended numerical change
- [ ] Numerical change is intended and documented below

Notes:

## Dependencies / Generated Files

- [ ] No new dependency
- [ ] No generated run outputs committed

## Release Notes

- [ ] Conventional Commit subject used, or release note impact is documented here
- [ ] No release note needed
