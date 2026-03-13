# Roadmap: Carbonica Security Hardening

## Overview

This roadmap transforms the Carbonica smart contract platform from a state with 14 known vulnerabilities into a hardened, tested system where no single malicious actor can manipulate platform state. The journey starts by consolidating shared code and establishing a test framework (so fixes build on clean foundations), then systematically patches vulnerabilities from critical to medium severity, and finishes with comprehensive attack scenario and property-based tests that prove each fix holds.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Code Quality Foundation** - Consolidate shared helpers, standardize error handling, set up test framework (completed 2026-03-11)
- [x] **Phase 2: Critical Vulnerability Fixes** - Patch the 4 critical vulns: datum verification, auth bypass, config integrity, mint validation (completed 2026-03-11)
- [ ] **Phase 3: High Vulnerability Fixes** - Fix NFT destination, trivial signer checks, governance auth gaps; add critical attack tests
- [x] **Phase 4: Medium and Low Fixes** - Harden marketplace validation, governance vote integrity, document disabled features (completed 2026-03-13)
- [ ] **Phase 5: Comprehensive Testing and Documentation** - Attack tests for high/medium fixes, property-based tests, Haddock documentation

## Phase Details

### Phase 1: Code Quality Foundation
**Goal**: All validators build on a single, deduplicated set of shared helpers with consistent error handling, and a Tasty test framework is ready for attack scenario tests
**Depends on**: Nothing (first phase)
**Requirements**: QUAL-01, QUAL-02, QUAL-04, LOW-01, TEST-01
**Success Criteria** (what must be TRUE):
  1. Common.hs is the single source of truth for all shared validation helpers -- no duplicated functions exist in Utils.hs or individual validators
  2. Every validator uses error codes (not string messages) following the established prefix convention (CHE, DGE, PVE, PPE, CPE, plus new prefixes for CetPolicy, UserVault, Marketplace)
  3. All exported helper functions have consistent INLINEABLE pragmas and follow PlutusTx patterns used by the existing codebase
  4. Running `cabal test` executes a Tasty test suite with tasty-hunit and tasty-quickcheck, and all existing tests still pass
**Plans:** 3/3 plans complete

Plans:
- [x] 01-01-PLAN.md -- Consolidate helpers: migrate Utils.hs into Common.hs, remove all local duplicates, delete Utils.hs
- [x] 01-02-PLAN.md -- Error code standardization: add error registries and codes to CetPolicy, UserVault, Marketplace, IdentificationNft
- [x] 01-03-PLAN.md -- Test framework: create Common.hs tests, replace all stub tests with real helper isolation tests

### Phase 2: Critical Vulnerability Fixes
**Goal**: The 4 critical attack vectors are closed -- no single multisig member can manipulate vote outcomes, bypass governance auth, silently change config fields, or mint unauthorized tokens
**Depends on**: Phase 1
**Requirements**: CRIT-01, CRIT-02, CRIT-03, CRIT-04
**Success Criteria** (what must be TRUE):
  1. ProjectVault validateVote verifies the continuing output datum: vote count incremented by exactly 1, voter added to voter list, all other ProjectDatum fields (developer address, COT amount, project name, status) unchanged
  2. DaoGovernance mint verifies the submitter's PubKeyHash is present in the ConfigDatum multisig signers list using txSignedBy -- not just checking that any signer exists
  3. DaoGovernance verifyConfigUpdate checks that ALL non-target ConfigDatum fields remain identical between input and output for every ProposalAction case
  4. CotPolicy mint extracts the referenced ProjectDatum, verifies pdStatus is ProjectApproved, and verifies minted COT amount equals pdCotAmount from the datum (not from the redeemer)
**Plans:** 2/2 plans complete

Plans:
- [x] 02-01-PLAN.md -- Patch ProjectVault vote output datum verification (CRIT-01) and CotPolicy project status/amount validation (CRIT-04)
- [x] 02-02-PLAN.md -- Patch DaoGovernance mint auth (CRIT-02) and verifyConfigUpdate field integrity (CRIT-03), delete hasSigner/hasAnySigner, add Multisig equality tests

### Phase 3: High Vulnerability Fixes
**Goal**: All high-severity authorization and destination checks are real -- NFTs go to the correct vault, signer checks use txSignedBy, and governance actions require actual multisig authorization; critical fixes are verified by attack tests
**Depends on**: Phase 2
**Requirements**: HIGH-01, HIGH-02, HIGH-03, HIGH-04, TEST-02
**Success Criteria** (what must be TRUE):
  1. ProjectPolicy mint verifies the project NFT is sent to the specific ProjectVault script hash obtained from cdProjectVaultHash in ConfigDatum -- not just any ScriptCredential
  2. Every instance of hasSigners/hasAnySigner across all validators is replaced with actual txSignedBy verification against specific authorized PubKeyHashes from ConfigDatum
  3. DaoGovernance validateExecute and validateReject both require at least one multisig signer (verified via txSignedBy) before allowing proposal finalization
  4. DaoGovernance vote verifies the specific voter PubKeyHash signed the transaction (not just that any signer exists)
  5. Attack scenario tests exist for all 4 critical vulnerabilities: each test constructs a malicious transaction exploiting the old vulnerability and confirms the patched validator rejects it
**Plans:** 2 plans

Plans:
- [ ] 03-01-PLAN.md -- Patch HIGH-01 (ProjectPolicy NFT destination), HIGH-02/HIGH-04 (txSignedBy in DaoGovernance + ProjectVault), HIGH-03 (multisig in execute/reject)
- [ ] 03-02-PLAN.md -- Create TestHelpers + AttackScenarios modules with attack tests for CRIT-01 through CRIT-04 and HIGH-01 through HIGH-04

### Phase 4: Medium and Low Fixes
**Goal**: Marketplace cannot be exploited via fake listings, zero-price trades, or royalty evasion; governance vote datum integrity is fully enforced; disabled features are properly documented
**Depends on**: Phase 3
**Requirements**: MED-01, MED-02, MED-03, MED-04, LOW-02
**Success Criteria** (what must be TRUE):
  1. Marketplace validator verifies the locked UTxO actually contains the tokens claimed in MarketplaceDatum (policy ID, token name, quantity all match)
  2. Marketplace enforces mdAmount > 0 and calculates royalty with a minimum of 1 lovelace (no zero-royalty transactions possible)
  3. DaoGovernance vote validator verifies all non-vote GovernanceDatum fields (proposal ID, action, deadline, state) remain unchanged in the output datum, and no other vote records are modified
  4. VaultWithdraw redeemer in UserVault has a proper error code and documentation indicating it is intentionally disabled pending V2-02
**Plans**: 2 plans

Plans:
- [x] 04-01-PLAN.md -- Harden Marketplace validateBuy (UTxO token verification, price floor, royalty floor) and document VaultWithdraw
- [ ] 04-02-PLAN.md -- Add P.Eq ProposalAction instance and DaoGovernance vote non-vote field integrity checks

### Phase 5: Comprehensive Testing and Documentation
**Goal**: Every fix category has attack scenario tests proving exploits are blocked, all smart constructors have property-based tests, datum integrity invariants are verified by properties, and all exported functions have Haddock documentation
**Depends on**: Phase 4
**Requirements**: TEST-03, TEST-04, TEST-05, QUAL-03
**Success Criteria** (what must be TRUE):
  1. Attack scenario tests exist for all 4 high-severity vulnerabilities: each constructs a malicious transaction exploiting the old vulnerability and confirms the patched validator rejects it
  2. Every smart constructor (mkLovelace, mkCotAmount, mkCetAmount, mkPercentage, mkMultisig, mkConfigDatum, mkProjectDatum, mkGovernanceDatum) has QuickCheck property tests covering valid inputs, boundary values, and invalid input rejection
  3. Property-based tests verify datum integrity invariants: ProjectVault vote preserves non-vote fields, DaoGovernance vote preserves non-vote fields, verifyConfigUpdate preserves non-target fields
  4. All exported functions in Types/, Validators/Common.hs, and Utils.hs have Haddock documentation with purpose, parameters, and usage examples
**Plans**: TBD

Plans:
- [ ] 05-01: TBD
- [ ] 05-02: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Code Quality Foundation | 3/3 | Complete    | 2026-03-11 |
| 2. Critical Vulnerability Fixes | 2/2 | Complete | 2026-03-11 |
| 3. High Vulnerability Fixes | 2/2 | Complete | 2026-03-12 |
| 4. Medium and Low Fixes | 2/2 | Complete   | 2026-03-13 |
| 5. Comprehensive Testing and Documentation | 0/0 | Not started | - |
