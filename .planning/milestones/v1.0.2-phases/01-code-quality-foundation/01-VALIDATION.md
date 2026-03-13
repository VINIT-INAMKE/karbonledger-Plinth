---
phase: 1
slug: code-quality-foundation
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-11
validated: 2026-03-13
---

# Phase 1 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | tasty + tasty-hunit + tasty-quickcheck (already configured) |
| **Config file** | smartcontracts.cabal `test-suite carbonica-tests` stanza |
| **Quick run command** | `cabal build` |
| **Full suite command** | `cabal test carbonica-tests --test-show-details=always` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `cabal build`
- **After every plan wave:** Run `cabal test carbonica-tests --test-show-details=always`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 01-01-T1 | 01 | 1 | QUAL-01, QUAL-02, QUAL-04 | build | `cabal build` | ✅ | ✅ green |
| 01-01-T2 | 01 | 1 | QUAL-01, QUAL-02 | build+grep | `cabal build` + zero `import Carbonica.Utils` | ✅ | ✅ green |
| 01-02-T1 | 02 | 2 | LOW-01 | grep | `grep traceError/traceIfFalse` vs error codes | ✅ | ✅ green (manual) |
| 01-02-T2 | 02 | 2 | LOW-01 | grep | `grep traceError/traceIfFalse` vs error codes | ✅ | ✅ green (manual) |
| 01-03-T1 | 03 | 2 | TEST-01, QUAL-01 | unit | `cabal test carbonica-tests` | ✅ | ✅ green |
| 01-03-T2 | 03 | 2 | TEST-01 | unit | `cabal test carbonica-tests` | ✅ | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] `test/Test/Carbonica/Common.hs` — 24 helper isolation tests (20 HUnit + 4 QuickCheck)
- [x] Add `Test.Carbonica.Common` to `other-modules` in smartcontracts.cabal (line 111 area)
- [x] Replace all `assertBool "..." True` stubs in `test/Test/Carbonica/Validators.hs` — 28 real test cases, zero stubs

*All Wave 0 items completed during Plan 03 execution.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions | Status |
|----------|-------------|------------|-------------------|--------|
| No string error messages remain | LOW-01 | Code convention — error code format verified by grep, not unit tests | Grep all validator files for `traceError`/`traceIfFalse` with string literals; verify all use error codes (CEE/CHE/CPE/DGE/INE/MKE/PPE/PVE/UVE) | ✅ verified |

*LOW-01 verified in 01-VERIFICATION.md with grep evidence: zero string error messages across all 9 validators.*

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved

---

## Validation Audit 2026-03-13

| Metric | Count |
|--------|-------|
| Gaps found | 0 |
| Resolved | 0 |
| Escalated | 0 |
| Manual-only | 1 (LOW-01) |
| Requirements covered | 5/5 (QUAL-01, QUAL-02, QUAL-04, LOW-01, TEST-01) |

All requirements have automated or manual verification. Phase is Nyquist-compliant.
