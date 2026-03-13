---
phase: 4
slug: medium-and-low-fixes
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-13
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | tasty 1.x + tasty-hunit 0.10.x + tasty-quickcheck 0.11.x |
| **Config file** | smartcontracts.cabal (test-suite carbonica-tests) |
| **Quick run command** | `cabal test carbonica-tests` |
| **Full suite command** | `cabal test carbonica-tests --test-show-details=always` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cabal test carbonica-tests`
- **After every plan wave:** Run `cabal test carbonica-tests --test-show-details=always`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 04-01-01 | 01 | 1 | MED-01 | attack (HUnit) | `cabal test carbonica-tests` | TBD | ⬜ pending |
| 04-01-02 | 01 | 1 | MED-02 | attack (HUnit) | `cabal test carbonica-tests` | TBD | ⬜ pending |
| 04-01-03 | 01 | 1 | MED-03 | attack (HUnit) | `cabal test carbonica-tests` | TBD | ⬜ pending |
| 04-02-01 | 02 | 1 | MED-04 | attack (HUnit) | `cabal test carbonica-tests` | TBD | ⬜ pending |
| 04-02-02 | 02 | 1 | LOW-02 | documentation | N/A (manual review) | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

*Existing infrastructure covers all phase requirements.*

No new test files, framework installs, or fixture modules needed. AttackScenarios.hs and TestHelpers.hs already provide all required builders (`mkTxInfo`, `mkSpendingCtx`, `testAttackRejected3`).

The only prerequisite is: the `ProposalAction P.Eq` instance must be added to `Carbonica.Types.Governance` before the DaoGovernance validator change can compile. This is a validator source dependency, not a test infrastructure gap.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| VaultWithdraw Haddock comment present | LOW-02 | Documentation-only change; no runtime behavior change | Read `UserVault.hs` VaultWithdraw branch and verify Haddock comment explains intentional disable pending V2-02 |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
