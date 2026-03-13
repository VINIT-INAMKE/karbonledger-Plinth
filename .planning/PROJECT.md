# Carbonica Security Hardening

## What This Is

A Cardano/Plutus V3 carbon credit platform with 9 validators (IdentificationNft, ConfigHolder, DaoGovernance, ProjectPolicy, ProjectVault, CotPolicy, CetPolicy, UserVault, Marketplace) that has been comprehensively security-hardened — all 14 identified vulnerabilities patched, attack scenario tests added, and full Haddock documentation applied.

## Core Value

Every validator must enforce complete authorization and datum integrity checks so that no single malicious actor (including a multisig member) can manipulate platform state, mint unauthorized tokens, or steal funds.

## Requirements

### Validated

- ✓ Fix all 14 identified vulnerabilities across all severity levels — v1.0.2
- ✓ Add comprehensive Tasty test suite with attack scenario tests — v1.0.2
- ✓ Apply best Haskell practices throughout entire codebase — v1.0.2
- ✓ Ensure no single multisig member can unilaterally manipulate platform state — v1.0.2
- ✓ IdentificationNft one-shot minting policy — existing
- ✓ ConfigDatum smart constructors with invariant enforcement — existing
- ✓ ProjectDatum smart constructors with validation — existing
- ✓ GovernanceDatum smart constructors with validation — existing
- ✓ Type-safe newtypes (Lovelace, CotAmount, CetAmount) — existing
- ✓ Shared validation helpers in Common.hs — existing
- ✓ Token name derivation from TxOutRef — existing
- ✓ CET/COT 1:1 offset burn mechanism — existing

### Active

(None — define with next milestone)

### Out of Scope

- New features or protocol changes — this is security hardening + code quality
- Off-chain code / frontend changes — validators only
- UserVault VaultWithdraw implementation — separate feature work (V2-02)
- Datum schema migration — maintain backward compatibility

## Context

Shipped v1.0.2 with 8,363 LOC Haskell.
Tech stack: Haskell, PlutusTx, Plutus V3, Cabal, Tasty (tasty-hunit + tasty-quickcheck).
9 validators, 5 type modules, 1 shared helper module (Common.hs), 6 test modules.
All 14 vulnerabilities (4 critical, 4 high, 4 medium, 2 low) fixed with attack tests.
5 non-blocking tech debt items documented in milestone audit.

## Constraints

- **Tech stack**: Haskell/PlutusTx/Plutus V3 — must stay on existing stack
- **Backward compatibility**: Datum schemas remain compatible — no migration needed
- **On-chain size**: Fixes stayed within Cardano script size limits
- **Testing**: Tasty with concrete ScriptContext builder functions (no emulator dependency)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Fix all 14 vulnerabilities | Complete security posture, not partial | ✓ Good — all closed |
| Attack scenario tests over emulator | Emulator adds complexity; concrete ScriptContext builders sufficient | ✓ Good — full coverage without emulator dependency |
| Validators-only scope | Minimize blast radius, focused remediation | ✓ Good — clean boundary |
| Delete Utils.hs, consolidate to Common.hs | Single source of truth for shared helpers | ✓ Good — eliminated split-brain |
| Error code registries per validator | Consistent 3-letter prefix + 3-digit codes | ✓ Good — 9 prefixes, machine-parseable |
| Total-count vote enforcement | Direction-agnostic since VaultVote carries no payload | ✓ Good — simpler invariant |
| MintValue via BuiltinData round-trip | No direct constructor available in PlutusTx | ✓ Good — same encoding, works reliably |
| Enumerated HUnit over QuickCheck for attacks | Explicit exploit variant naming and traceability | ✓ Good — each test maps to specific CVE |
| P.Eq instances for Multisig/ProposalAction | Needed for field preservation checks | ✓ Good — clean datum integrity |
| Newtype wrappers for Arbitrary instances | Avoid orphan instances for Plutus types | ✓ Good — no orphan warnings |

---
*Last updated: 2026-03-13 after v1.0.2 milestone*
