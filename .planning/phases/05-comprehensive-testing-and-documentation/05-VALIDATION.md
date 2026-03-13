---
phase: 5
slug: comprehensive-testing-and-documentation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-13
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

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 05-01-01 | 01 | 1 | TEST-03 | HUnit attack | `cabal test carbonica-tests` | ❌ W0 | ⬜ pending |
| 05-01-02 | 01 | 1 | TEST-03 | HUnit attack | `cabal test carbonica-tests` | ❌ W0 | ⬜ pending |
| 05-01-03 | 01 | 1 | TEST-03 | HUnit attack | `cabal test carbonica-tests` | ❌ W0 | ⬜ pending |
| 05-01-04 | 01 | 1 | TEST-03 | HUnit attack | `cabal test carbonica-tests` | ❌ W0 | ⬜ pending |
| 05-02-01 | 02 | 1 | TEST-04 | QuickCheck | `cabal test carbonica-tests` | ❌ W0 | ⬜ pending |
| 05-02-02 | 02 | 1 | TEST-04 | QuickCheck | `cabal test carbonica-tests` | ❌ W0 | ⬜ pending |
| 05-02-03 | 02 | 1 | TEST-04 | QuickCheck | `cabal test carbonica-tests` | ❌ W0 | ⬜ pending |
| 05-02-04 | 02 | 1 | TEST-04 | QuickCheck | `cabal test carbonica-tests` | ❌ W0 | ⬜ pending |
| 05-02-05 | 02 | 1 | TEST-04 | QuickCheck | `cabal test carbonica-tests` | ❌ W0 | ⬜ pending |
| 05-02-06 | 02 | 1 | TEST-04 | QuickCheck | `cabal test carbonica-tests` | ❌ W0 | ⬜ pending |
| 05-03-01 | 03 | 1 | TEST-05 | QuickCheck property | `cabal test carbonica-tests` | ❌ W0 | ⬜ pending |
| 05-03-02 | 03 | 1 | TEST-05 | QuickCheck property | `cabal test carbonica-tests` | ❌ W0 | ⬜ pending |
| 05-03-03 | 03 | 1 | TEST-05 | QuickCheck property | `cabal test carbonica-tests` | ❌ W0 | ⬜ pending |
| 05-04-01 | 04 | 2 | QUAL-03 | Manual review | N/A | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/Test/Carbonica/Properties/DatumIntegrity.hs` — new module for TEST-05
- [ ] Arbitrary instances in `test/Test/Carbonica/TestHelpers.hs` — needed by DatumIntegrity.hs
- [ ] `smartcontracts.cabal` other-modules entry for `Test.Carbonica.Properties.DatumIntegrity`
- [ ] `test/Main.hs` updated import + wiring for `datumIntegrityTests`

*Existing files `AttackScenarios.hs` and `Properties/SmartConstructors.hs` need extension, not creation.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Haddock on all exported functions | QUAL-03 | Documentation quality is subjective; requires visual review of generated docs | Run `cabal haddock` and inspect generated HTML for completeness |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
