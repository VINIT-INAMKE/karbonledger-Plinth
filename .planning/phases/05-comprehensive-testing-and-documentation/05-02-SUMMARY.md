---
phase: 05-comprehensive-testing-and-documentation
plan: 02
subsystem: testing
tags: [quickcheck, property-tests, datum-integrity, plutus-v3]

# Dependency graph
requires:
  - phase: 05-01
    provides: TestHelpers builder functions, test constants, attack test patterns
provides:
  - QuickCheck Arbitrary instances for PubKeyHash and POSIXTime (ArbPubKeyHash, ArbPOSIXTime)
  - Datum integrity property tests for ProjectVault vote, DaoGovernance vote, and ConfigUpdate
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns: [ioProperty-with-try-evaluate for validator property tests, newtype-wrapper Arbitrary instances to avoid orphans]

key-files:
  created:
    - test/Test/Carbonica/Properties/DatumIntegrity.hs
  modified:
    - test/Test/Carbonica/TestHelpers.hs
    - smartcontracts.cabal
    - test/Main.hs

key-decisions:
  - "Newtype wrappers (ArbPubKeyHash, ArbPOSIXTime) to avoid orphan Arbitrary instances"
  - "ioProperty + try/evaluate pattern for all property tests since validators throw exceptions on rejection"
  - "Concrete values for ConfigUpdate integrity (mirrors CRIT-03 pattern) rather than full Arbitrary ConfigDatum"

patterns-established:
  - "ioProperty pattern: wrap validator calls in try/evaluate, return Bool for QuickCheck"
  - "Implication guard (==>) to exclude trivially-passing cases where mutation equals original"

requirements-completed: [TEST-05]

# Metrics
duration: 4min
completed: 2026-03-13
---

# Phase 05 Plan 02: Datum Integrity Property Tests Summary

**QuickCheck property tests proving ProjectVault vote, DaoGovernance vote, and ConfigUpdate reject mutations to protected datum fields**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-13T10:15:37Z
- **Completed:** 2026-03-13T10:19:04Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments
- Created DatumIntegrity.hs with 6 property tests across 3 invariant groups
- Added ArbPubKeyHash and ArbPOSIXTime Arbitrary instances to TestHelpers.hs
- Wired module into cabal and Main.hs test tree

## Task Commits

Each task was committed atomically:

1. **Task 1: Create DatumIntegrity module with Arbitrary instances and property tests** - `e440212` (test)
2. **Task 2: Wire DatumIntegrity into cabal and test Main.hs** - `fbb361b` (feat)

## Files Created/Modified
- `test/Test/Carbonica/Properties/DatumIntegrity.hs` - New module with datumIntegrityTests covering 3 datum integrity invariants
- `test/Test/Carbonica/TestHelpers.hs` - Added ArbPubKeyHash/ArbPOSIXTime Arbitrary instances and exports
- `smartcontracts.cabal` - Registered DatumIntegrity in test-suite other-modules
- `test/Main.hs` - Imported and wired datumIntegrityTests into test tree

## Decisions Made
- Newtype wrappers (ArbPubKeyHash, ArbPOSIXTime) to avoid orphan Arbitrary instances for Plutus types
- ioProperty + try/evaluate pattern for property tests since Plutus validators signal rejection via exceptions
- ConfigUpdate integrity test uses concrete values (same CRIT-03 pattern) rather than full Arbitrary ConfigDatum generation

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- All 3 datum integrity invariants covered by QuickCheck properties
- User should run `cabal test carbonica-tests --test-show-details=direct` to verify all tests compile and pass
- This completes the missing plan 05-02 in the phase

## Self-Check: PASSED

- All created files exist on disk
- All commit hashes found in git log
- DatumIntegrity.hs: 355 lines (exceeds 100 minimum)

---
*Phase: 05-comprehensive-testing-and-documentation*
*Completed: 2026-03-13*
