---
phase: 05-comprehensive-testing-and-documentation
plan: 01
subsystem: testing
tags: [tasty, hunit, quickcheck, attack-tests, property-tests, marketplace, governance]

# Dependency graph
requires:
  - phase: 04-medium-and-low-fixes
    provides: MED-01 through MED-04 validator patches (MKE007/MKE008/MKE004/DGE019-021)
  - phase: 03-high-vulnerability-fixes
    provides: TestHelpers module, AttackScenarios framework, SmartConstructors property test skeleton
provides:
  - MED-01 through MED-04 attack scenario tests with Withdraw regression coverage
  - Property-based tests for all 8 smart constructors (was 2, now 8)
  - mkMarketplaceCtx helper, testRoyaltyAddr constant, lovelaceSingleton utility
affects: [05-02, 05-03]

# Tech tracking
tech-stack:
  added: []
  patterns: [marketplace-ctx-builder, withdraw-regression-pattern, med-attack-test-pattern]

key-files:
  created: []
  modified:
    - test/Test/Carbonica/TestHelpers.hs
    - test/Test/Carbonica/AttackScenarios.hs
    - test/Test/Carbonica/Properties/SmartConstructors.hs

key-decisions:
  - "Withdraw regression tests verify Buy-path hardening is properly scoped to MktBuy redeemer"
  - "MED-04 uses local mkDaoVoteSpendCtx helper for compact vote-specific context building"
  - "Property tests for composite types (ConfigDatum, ProjectDatum, GovernanceDatum) use concrete known-good values rather than full Arbitrary instances"

patterns-established:
  - "Withdraw regression pattern: each MED-01/02/03 includes a test using MktWithdraw on Buy-failing conditions to prove hardening does not leak"
  - "MED attack test pattern: 2-3 exploit variants + 1 positive + 1 Withdraw regression per Marketplace fix"

requirements-completed: [TEST-03, TEST-04]

# Metrics
duration: 5min
completed: 2026-03-13
---

# Phase 5 Plan 01: MED Attack Scenarios and Smart Constructor Properties Summary

**15 MED-01 through MED-04 attack scenario tests (including 3 Withdraw regression tests) plus 29 new property-based tests covering all 8 smart constructors**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-13T10:05:00Z
- **Completed:** 2026-03-13T10:10:40Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- MED-01/02/03 Marketplace attack tests with Withdraw regression proving Buy-path hardening does not break owner withdrawals
- MED-04 DaoGovernance vote non-vote field mutation tests (DGE019/DGE020/DGE021)
- 6 new smart constructor property test groups: cetAmount, percentage, multisig, configDatum, projectDatum, governanceDatum
- TestHelpers extended with mkMarketplaceCtx builder, testRoyaltyAddr, and lovelaceSingleton

## Task Commits

Each task was committed atomically:

1. **Task 1: Add MED-01 through MED-04 attack scenario tests with Withdraw regression** - `1160f55` (feat)
2. **Task 2: Add property-based tests for 6 remaining smart constructors** - `37493ae` (feat)

## Files Created/Modified
- `test/Test/Carbonica/TestHelpers.hs` - Added mkMarketplaceCtx, testRoyaltyAddr, lovelaceSingleton, Marketplace type imports
- `test/Test/Carbonica/AttackScenarios.hs` - Added med01Tests through med04Tests (15 test cases) with Marketplace and DaoGovernance imports
- `test/Test/Carbonica/Properties/SmartConstructors.hs` - Extended from 2 to 8 property test groups (38 total properties)

## Decisions Made
- Withdraw regression tests verify Buy-path hardening is properly scoped to MktBuy redeemer -- each MED-01/02/03 test passes MktWithdraw with owner signing on conditions that would fail Buy validation
- MED-04 uses a local mkDaoVoteSpendCtx helper rather than the existing mkDaoVoteCtx from HIGH-04 tests because MED-04 needs explicit control over input/output governance datums
- Property tests for composite types use concrete known-good values rather than full Arbitrary instances -- simpler and sufficient for invariant verification

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All MED attack tests and smart constructor properties are in place
- User should run `cabal test carbonica-tests --test-show-details=direct` to verify all tests compile and pass
- Ready for plan 05-02 (datum integrity property tests) and 05-03 (Haddock documentation)

## Self-Check: PASSED

All 4 files verified present. Both task commits (1160f55, 37493ae) verified in git log.

---
*Phase: 05-comprehensive-testing-and-documentation*
*Completed: 2026-03-13*
