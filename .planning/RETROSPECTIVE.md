# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.0.2 — Security Hardening

**Shipped:** 2026-03-13
**Phases:** 5 | **Plans:** 12 | **Sessions:** ~5

### What Was Built
- Patched all 14 identified vulnerabilities (4 critical, 4 high, 4 medium, 2 low) across 9 Plutus V3 validators
- Attack scenario test suite covering every vulnerability with concrete ScriptContext builders
- Property-based tests for all 8 smart constructors and datum integrity invariants
- Haddock documentation for all exported functions across Types/ and Validators/
- Consolidated Common.hs as single source of truth with standardized error codes (9 prefixes)

### What Worked
- Foundation-first approach (Phase 1): consolidating helpers and error codes before patching made all subsequent phases clean
- Critical-first ordering: most dangerous vulns fixed in Phase 2, tested in Phase 3 — fast risk reduction
- YOLO mode with verification/Nyquist validation: fast execution without sacrificing quality checks
- Concrete ScriptContext builders: avoided emulator dependency while getting full attack test coverage
- Enumerated HUnit cases: each test maps to a specific vulnerability ID, excellent traceability

### What Was Inefficient
- SUMMARY.md frontmatter `requirements_completed` never populated across all 12 plans — process gap
- testAttackRejected wrappers initially caught SomeException without verifying error codes — had to revert that tech debt fix due to PlutusTx evaluation semantics
- Phase 3 took longest (~22min, 2 plans) due to MintValue coercion discovery — BuiltinData round-trip was not obvious

### Patterns Established
- Error code registry: block comment at top of each validator file, 3-letter prefix + 3-digit number
- TestHelpers module with builder functions (mkTxInfo, mkMintingCtx, mkSpendingCtx) for all future test work
- ioProperty + try/evaluate pattern for property-testing Plutus validators that signal rejection via exceptions
- Newtype wrappers (ArbPubKeyHash, ArbPOSIXTime) to avoid orphan Arbitrary instances
- Haddock placement: BEFORE INLINEABLE pragma, not after

### Key Lessons
1. Consolidate shared code before fixing vulnerabilities — deduplicated helpers prevent fix-on-fix conflicts
2. MintValue has no direct constructor in PlutusTx; Value->BuiltinData->MintValue round-trip coercion works because they share the same Data encoding
3. PlutusTx validators signal rejection via exceptions, not return values — test harnesses must use try/evaluate, not assertEqual
4. Attack tests are more readable as enumerated HUnit cases than QuickCheck generators — each exploit variant gets a descriptive name

### Cost Observations
- Model mix: ~70% opus (execution, planning), ~30% sonnet (research)
- Sessions: ~5 over 3 days
- Notable: 12 plans in ~72 min total execution (~6 min/plan average) — security hardening at high velocity

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Sessions | Phases | Key Change |
|-----------|----------|--------|------------|
| v1.0.2 | ~5 | 5 | First milestone — established all patterns |

### Cumulative Quality

| Milestone | Tests | Coverage | Zero-Dep Additions |
|-----------|-------|----------|-------------------|
| v1.0.2 | ~80+ (HUnit + QuickCheck) | All 14 vulns covered | 6 test modules |

### Top Lessons (Verified Across Milestones)

1. Foundation-first: consolidate shared code before building on it
2. Concrete test builders beat emulator dependencies for Plutus validators
