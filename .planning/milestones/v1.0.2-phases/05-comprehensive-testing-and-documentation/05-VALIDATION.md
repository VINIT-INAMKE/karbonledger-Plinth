---
phase: 5
slug: comprehensive-testing-and-documentation
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-13
validated: 2026-03-13
---

# Phase 5 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | tasty 1.x + tasty-hunit + tasty-quickcheck + QuickCheck |
| **Config file** | none (exitcode-stdio-1.0 via cabal test-suite) |
| **Quick run command** | `cabal test carbonica-tests --test-show-details=direct` |
| **Full suite command** | `cabal test carbonica-tests --test-show-details=direct` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cabal test carbonica-tests --test-show-details=direct`
- **After every plan wave:** Run `cabal test carbonica-tests --test-show-details=direct`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

**CRITICAL CONSTRAINT:** User runs all builds and tests manually. Never invoke cabal, nix, or WSL commands in executor tasks.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | Test File | Status |
|---------|------|------|-------------|-----------|-------------------|-----------|--------|
| 05-01-01 | 01 | 1 | TEST-03 | HUnit attack | `cabal test carbonica-tests` | AttackScenarios.hs: med01Tests (4 cases) | green |
| 05-01-02 | 01 | 1 | TEST-03 | HUnit attack | `cabal test carbonica-tests` | AttackScenarios.hs: med02Tests (4 cases) | green |
| 05-01-03 | 01 | 1 | TEST-03 | HUnit attack | `cabal test carbonica-tests` | AttackScenarios.hs: med03Tests (3 cases) | green |
| 05-01-04 | 01 | 1 | TEST-03 | HUnit attack | `cabal test carbonica-tests` | AttackScenarios.hs: med04Tests (4 cases) | green |
| 05-02-01 | 01 | 1 | TEST-04 | QuickCheck | `cabal test carbonica-tests` | SmartConstructors.hs: cetAmountProperties | green |
| 05-02-02 | 01 | 1 | TEST-04 | QuickCheck | `cabal test carbonica-tests` | SmartConstructors.hs: percentageProperties | green |
| 05-02-03 | 01 | 1 | TEST-04 | QuickCheck | `cabal test carbonica-tests` | SmartConstructors.hs: multisigProperties | green |
| 05-02-04 | 01 | 1 | TEST-04 | QuickCheck | `cabal test carbonica-tests` | SmartConstructors.hs: configDatumProperties | green |
| 05-02-05 | 01 | 1 | TEST-04 | QuickCheck | `cabal test carbonica-tests` | SmartConstructors.hs: projectDatumProperties | green |
| 05-02-06 | 01 | 1 | TEST-04 | QuickCheck | `cabal test carbonica-tests` | SmartConstructors.hs: governanceDatumProperties | green |
| 05-03-01 | 02 | 2 | TEST-05 | QuickCheck property | `cabal test carbonica-tests` | DatumIntegrity.hs: projectVaultVoteIntegrity (2 props) | green |
| 05-03-02 | 02 | 2 | TEST-05 | QuickCheck property | `cabal test carbonica-tests` | DatumIntegrity.hs: daoGovernanceVoteIntegrity (3 props) | green |
| 05-03-03 | 02 | 2 | TEST-05 | QuickCheck property | `cabal test carbonica-tests` | DatumIntegrity.hs: configUpdateIntegrity (1 prop) | green |
| 05-04-01 | 03 | 1 | QUAL-03 | Manual review | `cabal haddock` | 13 source files with Haddock | green |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [x] `test/Test/Carbonica/Properties/DatumIntegrity.hs` — 355 lines, 6 properties across 3 invariant groups
- [x] Arbitrary instances in `test/Test/Carbonica/TestHelpers.hs` — ArbPubKeyHash, ArbPOSIXTime exported
- [x] `smartcontracts.cabal` other-modules entry for `Test.Carbonica.Properties.DatumIntegrity` (line 115)
- [x] `test/Main.hs` updated import + wiring for `datumIntegrityTests` (lines 13, 22)

*All Wave 0 requirements delivered across Plans 01-02 (commits 1160f55, 37493ae, e440212, fbb361b).*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Haddock on all exported functions | QUAL-03 | Documentation quality is subjective; requires visual review of generated docs | Run `cabal haddock` and inspect generated HTML for completeness |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved

## Validation Audit 2026-03-13

| Metric | Count |
|--------|-------|
| Gaps found | 0 |
| Resolved | 0 |
| Escalated | 0 |

All 4 requirements (TEST-03, TEST-04, TEST-05, QUAL-03) have automated or manual verification coverage:
- TEST-03: 15 MED attack tests (med01-04Tests) including 3 Withdraw regression tests
- TEST-04: 38 QuickCheck properties across 8 smart constructor groups
- TEST-05: 6 datum integrity properties across 3 invariant groups (ProjectVault vote, DaoGovernance vote, ConfigUpdate)
- QUAL-03: Haddock on all exported functions across 13 source files (manual-only)

Verification report (05-VERIFICATION.md) confirms 4/4 truths verified.
