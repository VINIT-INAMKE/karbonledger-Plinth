---
phase: 04-medium-and-low-fixes
plan: 01
subsystem: validators
tags: [plutus, marketplace, uservault, security, validation, royalty]

# Dependency graph
requires:
  - phase: 01-code-quality-foundation
    provides: findInputByOutRef helper in Common.hs, error code registry pattern
  - phase: 02-critical-vulnerability-fixes
    provides: datum integrity checks that Marketplace builds on
provides:
  - MKE008 zero-price rejection guard in Marketplace validateBuy
  - MKE007 UTxO COT token verification via findInputByOutRef in Marketplace validateBuy
  - Royalty floor (P.max 1) preventing royalty evasion via rounding in Marketplace
  - VaultWithdraw V2-02 documentation in UserVault
affects: [04-medium-and-low-fixes, testing]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "UTxO content verification via findInputByOutRef + valueOf for spend validators"
    - "Validation ordering: price guard before token verification for clear error messages"
    - "P.max 1 royalty floor pattern for integer division rounding protection"

key-files:
  created: []
  modified:
    - src/Carbonica/Validators/Marketplace.hs
    - src/Carbonica/Validators/UserVault.hs

key-decisions:
  - "MKE008 precedes MKE007 in validation chain so zero-price listings fail with clear error before reaching token check"
  - "UTxO COT check uses P.>= (not P.==) so over-funded UTxOs remain valid"
  - "Royalty floor is 1 lovelace via P.max 1 -- prevents rounding to 0 for small prices"

patterns-established:
  - "UTxO content verification: findInputByOutRef + valueOf for checking spent UTxO contains claimed tokens"
  - "Royalty floor: P.max 1 wrapping integer division to prevent rounding evasion"

requirements-completed: [MED-01, MED-02, MED-03, LOW-02]

# Metrics
duration: 2min
completed: 2026-03-13
---

# Phase 4 Plan 1: Medium and Low Fixes Summary

**Marketplace hardened with UTxO token verification (MKE007), price positivity guard (MKE008), royalty floor (P.max 1); VaultWithdraw documented as intentionally disabled pending V2-02**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-13T08:56:06Z
- **Completed:** 2026-03-13T08:58:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Marketplace validateBuy rejects zero/negative price listings (MKE008) before any other checks
- Marketplace validateBuy verifies spent UTxO actually contains claimed COT tokens (MKE007) via findInputByOutRef
- Royalty calculation has a floor of 1 lovelace preventing royalty evasion through tiny sale prices
- VaultWithdraw branch has comprehensive Haddock documentation explaining V2-02 deferral

## Task Commits

Each task was committed atomically:

1. **Task 1: Add UTxO token verification, price floor, and royalty floor to Marketplace validateBuy** - `4e28b1b` (fix)
2. **Task 2: Document VaultWithdraw as intentionally disabled (LOW-02)** - `22712b4` (docs)

## Files Created/Modified
- `src/Carbonica/Validators/Marketplace.hs` - Added MKE007/MKE008 checks, royalty floor, oref threading, TxOutRef/TxInInfo/findInputByOutRef imports
- `src/Carbonica/Validators/UserVault.hs` - VaultWithdraw Haddock comment, UVE003 registry update, module-level VALIDATION LOGIC note

## Decisions Made
- MKE008 (price positivity) precedes MKE007 (COT verification) in the validation chain so zero-price listings fail with a clear error before the token lookup
- UTxO COT quantity check uses P.>= (not P.==) so over-funded UTxOs are valid
- Royalty floor of 1 lovelace via P.max 1 wrapping integer division

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Marketplace now has 3 new validation guards (MKE007, MKE008, royalty floor) ready for testing
- VaultWithdraw documentation is complete, no code changes needed until V2-02
- All existing MKE003-MKE006 checks remain unchanged

## Self-Check: PASSED

- FOUND: src/Carbonica/Validators/Marketplace.hs
- FOUND: src/Carbonica/Validators/UserVault.hs
- FOUND: .planning/phases/04-medium-and-low-fixes/04-01-SUMMARY.md
- FOUND: commit 4e28b1b (Task 1)
- FOUND: commit 22712b4 (Task 2)

---
*Phase: 04-medium-and-low-fixes*
*Completed: 2026-03-13*
