# Requirements: Carbonica Security Hardening

**Defined:** 2026-03-11
**Core Value:** Every validator enforces complete authorization and datum integrity

## v1 Requirements

### Critical Fixes

- [x] **CRIT-01**: ProjectVault vote must verify continuing output datum (vote count +1, voter added, all other fields unchanged)
- [x] **CRIT-02**: DaoGovernance mint must verify submitter is in multisig group (replace trivial hasSigner)
- [x] **CRIT-03**: DaoGovernance verifyConfigUpdate must verify all non-target ConfigDatum fields remain unchanged
- [x] **CRIT-04**: CotPolicy mint must verify project status is Approved and minted COT matches pdCotAmount

### High Fixes

- [x] **HIGH-01**: ProjectPolicy mint must verify NFT sent to specific ProjectVault script hash (from ConfigDatum)
- [x] **HIGH-02**: Replace all trivial signer checks (hasSigners/hasAnySigner) with real txSignedBy verification
- [x] **HIGH-03**: DaoGovernance execute/reject must require at least one multisig signer
- [x] **HIGH-04**: DaoGovernance vote must verify voter PKH specifically signed (not just any signer)

### Medium Fixes

- [x] **MED-01**: Marketplace must verify UTxO actually contains the listed COT tokens
- [x] **MED-02**: Marketplace must enforce minimum price > 0
- [x] **MED-03**: Marketplace royalty calculation must handle rounding (minimum 1 lovelace royalty)
- [x] **MED-04**: DaoGovernance vote must verify all non-vote fields unchanged in output datum

### Low Fixes

- [x] **LOW-01**: Standardize error handling to error codes across all validators (CetPolicy, UserVault, Marketplace)
- [x] **LOW-02**: Document VaultWithdraw as intentionally disabled with proper error code

### Code Quality

- [x] **QUAL-01**: Apply best Haskell practices: remove duplicate helper functions, consolidate into Common.hs
- [x] **QUAL-02**: Remove Utils.hs duplication — single source of truth in Validators.Common
- [x] **QUAL-03**: Add proper Haddock documentation to all exported functions
- [x] **QUAL-04**: Ensure consistent use of INLINEABLE pragmas and PlutusTx patterns

### Testing

- [x] **TEST-01**: Set up Tasty test suite with tasty-hunit and tasty-quickcheck
- [x] **TEST-02**: Add attack scenario tests for each critical vulnerability fix
- [x] **TEST-03**: Add attack scenario tests for each high vulnerability fix
- [x] **TEST-04**: Add property-based tests for all smart constructors
- [x] **TEST-05**: Add datum integrity property tests for vote/config update validators

## v2 Requirements

- **V2-01**: Set-based multisig lookup for >20 signers
- **V2-02**: Implement UserVault VaultWithdraw with proper authorization
- **V2-03**: On-chain emulator integration tests with cardano-node-emulator

## Out of Scope

| Feature | Reason |
|---------|--------|
| New protocol features | Security hardening only |
| Off-chain / frontend code | Validators scope only |
| Datum schema migration | Maintain backward compatibility |
| Performance optimization | Only where needed for fixes |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| CRIT-01 | Phase 2 | Complete |
| CRIT-02 | Phase 2 | Complete |
| CRIT-03 | Phase 2 | Complete |
| CRIT-04 | Phase 2 | Complete |
| HIGH-01 | Phase 3 | Complete |
| HIGH-02 | Phase 3 | Complete |
| HIGH-03 | Phase 3 | Complete |
| HIGH-04 | Phase 3 | Complete |
| MED-01 | Phase 4 | Complete |
| MED-02 | Phase 4 | Complete |
| MED-03 | Phase 4 | Complete |
| MED-04 | Phase 4 | Complete |
| LOW-01 | Phase 1 | Complete |
| LOW-02 | Phase 4 | Complete |
| QUAL-01 | Phase 1 | Complete |
| QUAL-02 | Phase 1 | Complete |
| QUAL-03 | Phase 5 | Complete |
| QUAL-04 | Phase 1 | Complete |
| TEST-01 | Phase 1 | Complete |
| TEST-02 | Phase 3 | Complete |
| TEST-03 | Phase 5 | Complete |
| TEST-04 | Phase 5 | Complete |
| TEST-05 | Phase 5 | Complete |

**Coverage:**
- v1 requirements: 23 total
- Mapped to phases: 23
- Unmapped: 0

---
*Requirements defined: 2026-03-11*
*Traceability updated: 2026-03-11*
