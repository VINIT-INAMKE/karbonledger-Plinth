---
phase: 1
slug: code-quality-foundation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-11
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
| 01-01-01 | 01 | 1 | QUAL-01 | unit | `cabal test carbonica-tests` | ❌ W0 | ⬜ pending |
| 01-01-02 | 01 | 1 | QUAL-01 | unit | `cabal test carbonica-tests` | ❌ W0 | ⬜ pending |
| 01-01-03 | 01 | 1 | QUAL-01 | unit | `cabal test carbonica-tests` | ❌ W0 | ⬜ pending |
| 01-01-04 | 01 | 1 | QUAL-01 | unit | `cabal test carbonica-tests` | ❌ W0 | ⬜ pending |
| 01-01-05 | 01 | 1 | QUAL-01 | unit | `cabal test carbonica-tests` | ❌ W0 | ⬜ pending |
| 01-02-01 | 02 | 1 | QUAL-02 | unit | `cabal test carbonica-tests` | ❌ W0 | ⬜ pending |
| 01-02-02 | 02 | 1 | QUAL-02 | unit | `cabal test carbonica-tests` | ❌ W0 | ⬜ pending |
| 01-03-01 | 03 | 1 | QUAL-04 | build | `cabal build` | ✅ | ⬜ pending |
| 01-04-01 | 04 | 2 | LOW-01 | manual-only | N/A | N/A | ⬜ pending |
| 01-05-01 | 05 | 2 | TEST-01 | integration | `cabal test carbonica-tests` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/Test/Carbonica/Common.hs` — stubs for QUAL-01, QUAL-02 helper isolation tests
- [ ] Add `Test.Carbonica.Common` to `other-modules` in smartcontracts.cabal
- [ ] Replace all `assertBool "..." True` stubs in `test/Test/Carbonica/Validators.hs` with real helper isolation tests

*Existing infrastructure: Main.hs, Types.hs, SmartConstructors.hs are real and should remain unchanged.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| No string error messages remain | LOW-01 | Code review — cannot test error message format programmatically without ScriptContext | Grep all validator files for `traceError` with string literals; verify all use error codes |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
