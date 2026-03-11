# Carbonica Security Hardening

## What This Is

A comprehensive security audit remediation for the Carbonica smart contract platform — a Cardano/Plutus V3 carbon credit system with validators for project submission, DAO governance, COT/CET token minting, marketplace trading, and user vaults. The codebase has 14 identified vulnerabilities (4 critical, 4 high, 4 medium, 2 low) that need to be fixed, plus attack scenario tests added to verify each fix.

## Core Value

Every validator must enforce complete authorization and datum integrity checks so that no single malicious actor (including a multisig member) can manipulate platform state, mint unauthorized tokens, or steal funds.

## Requirements

### Validated

- IdentificationNft one-shot minting policy — existing
- ConfigDatum smart constructors with invariant enforcement — existing
- ProjectDatum smart constructors with validation — existing
- GovernanceDatum smart constructors with validation — existing
- Type-safe newtypes (Lovelace, CotAmount, CetAmount) — existing
- Shared validation helpers in Common.hs — existing
- Token name derivation from TxOutRef — existing
- CET/COT 1:1 offset burn mechanism — existing

### Active

- [ ] Fix all 14 identified vulnerabilities across all severity levels
- [ ] Add on-chain emulator tests for attack scenarios
- [ ] Ensure no single multisig member can unilaterally manipulate platform state

### Out of Scope

- New features or protocol changes — this is purely security hardening
- Off-chain code / frontend changes — validators only
- Performance optimization beyond what's needed for fixes
- UserVault VaultWithdraw implementation — separate feature work

## Context

### Existing Codebase
- 9 validators: IdentificationNft, ConfigHolder, DaoGovernance (mint+spend), ProjectPolicy, ProjectVault, CotPolicy, CetPolicy, UserVault, Marketplace
- 4 type modules: Core, Config, Project, Emission, Governance
- 2 shared helper modules: Common.hs, Utils.hs
- Built with PlutusTx, Plutus V3, Cabal
- Codebase map at `.planning/codebase/`

### Vulnerability Summary
**Critical (4):** ProjectVault vote has no output datum verification, DaoGovernance mint has trivial auth bypass, DaoGovernance verifyConfigUpdate only checks target field, CotPolicy mint has no project status/amount verification

**High (4):** ProjectPolicy sends NFT to any script address, DaoGovernance/ProjectVault have trivial signer checks, DaoGovernance execute/reject have no auth check

**Medium (4):** Marketplace tokens not verified in UTxO, no minimum price, royalty rounding, DaoGovernance empty votes list and incomplete output integrity

**Low (2):** UserVault withdraw always fails (stub), inconsistent error handling

### Full Audit
See `.planning/codebase/CONCERNS.md` for detailed vulnerability descriptions with file locations and fix recommendations.

## Constraints

- **Tech stack**: Haskell/PlutusTx/Plutus V3 — must stay on existing stack
- **Backward compatibility**: Datum schemas should remain compatible where possible to avoid migration complexity
- **On-chain size**: Fixes must not blow up script sizes beyond Cardano's limits
- **Testing**: Must use Plutus emulator or equivalent for attack scenario tests

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Fix all 14 vulnerabilities | Complete security posture, not partial | -- Pending |
| Add emulator tests | Verify fixes prevent actual attack scenarios | -- Pending |
| Validators-only scope | Minimize blast radius, focused remediation | -- Pending |

---
*Last updated: 2026-03-11 after initialization*
