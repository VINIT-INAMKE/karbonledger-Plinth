---
phase: 4
slug: medium-and-low-fixes
status: validated
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-13
validated: 2026-03-13
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
| 04-01-01 | 01 | 1 | MED-01 | attack (HUnit) | `cabal test carbonica-tests` | `test/Test/Carbonica/AttackScenarios.hs` (med01Tests: 4 cases) | ✅ green |
| 04-01-02 | 01 | 1 | MED-02 | attack (HUnit) | `cabal test carbonica-tests` | `test/Test/Carbonica/AttackScenarios.hs` (med02Tests: 4 cases) | ✅ green |
| 04-01-03 | 01 | 1 | MED-03 | attack (HUnit) | `cabal test carbonica-tests` | `test/Test/Carbonica/AttackScenarios.hs` (med03Tests: 3 cases) | ✅ green |
| 04-02-01 | 02 | 1 | MED-04 | attack (HUnit) + property (QC) | `cabal test carbonica-tests` | `AttackScenarios.hs` (med04Tests: 4 cases) + `DatumIntegrity.hs` (3 props) | ✅ green |
| 04-02-02 | 02 | 1 | LOW-02 | documentation | N/A (manual review) | N/A | ✅ green |

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

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** validated 2026-03-13

---

## Validation Audit 2026-03-13

| Metric | Count |
|--------|-------|
| Gaps found | 0 |
| Resolved | 0 |
| Escalated | 0 |

### Test Coverage Detail

| Requirement | Test File | Test Function | Cases |
|-------------|-----------|---------------|-------|
| MED-01 | `test/Test/Carbonica/AttackScenarios.hs` | `med01Tests` | empty UTxO (MKE007), wrong token (MKE007), positive, withdraw regression |
| MED-02 | `test/Test/Carbonica/AttackScenarios.hs` | `med02Tests` | zero price (MKE008), negative price (MKE008), positive, withdraw regression |
| MED-03 | `test/Test/Carbonica/AttackScenarios.hs` | `med03Tests` | rounding evasion (MKE004), royalty floor paid, withdraw regression |
| MED-04 | `test/Test/Carbonica/AttackScenarios.hs` | `med04Tests` | submitter mutated (DGE019), action mutated (DGE020), deadline mutated (DGE021), positive |
| MED-04 | `test/Test/Carbonica/Properties/DatumIntegrity.hs` | `daoVoteDatumIntegrityTests` | prop_dgVoteRejectsMutatedSubmitter, prop_dgVoteRejectsMutatedAction, prop_dgVoteRejectsMutatedDeadline |
| LOW-02 | `src/Carbonica/Validators/UserVault.hs` | N/A (manual) | V2-02 documentation verified in 5 locations |
