# Milestones

## v1.0.2 Security Hardening (Shipped: 2026-03-13)

**Phases completed:** 5 phases, 12 plans
**Timeline:** 3 days (2026-03-11 → 2026-03-13)
**Commits:** 67 | **LOC:** 8,363 Haskell
**Git range:** d968522..5c02486

**Delivered:** Comprehensive security audit remediation closing all 14 identified vulnerabilities across 9 Cardano/Plutus V3 validators, with full attack scenario test coverage and Haddock documentation.

**Key accomplishments:**
1. Consolidated all shared helpers into Common.hs (deleted Utils.hs), standardized error codes across 9 validators with 9 unique prefixes
2. Fixed 4 critical vulnerabilities: ProjectVault vote datum verification, DaoGovernance mint auth bypass, config update field integrity, CotPolicy mint validation
3. Fixed 4 high vulnerabilities: ProjectPolicy NFT destination pinning, txSignedBy enforcement replacing trivial signer checks, multisig authorization for execute/reject
4. Hardened Marketplace against fake listings, zero-price trades, and royalty evasion; enforced DaoGovernance vote datum integrity
5. Added attack scenario tests for all 14 vulnerabilities plus property-based tests for all 8 smart constructors and datum integrity invariants
6. Added Haddock documentation to all exported functions across Types/ and Validators/ modules

**Audit:** Passed — 23/23 requirements, 5/5 phases, 6/6 E2E flows, Nyquist compliant
**Tech debt:** 5 non-blocking items (see milestones/v1.0.2-MILESTONE-AUDIT.md)

---

