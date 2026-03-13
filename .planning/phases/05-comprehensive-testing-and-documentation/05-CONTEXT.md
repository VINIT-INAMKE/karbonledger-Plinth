# Phase 5: Comprehensive Testing and Documentation - Context

**Gathered:** 2026-03-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Add attack scenario tests for medium-severity fixes (MED-01 through MED-04), property-based tests for all smart constructors (TEST-04) and datum integrity invariants (TEST-05), and Haddock documentation for all exported functions across all source modules (QUAL-03). No new validator logic, no new features.

</domain>

<decisions>
## Implementation Decisions

### Attack test scope (TEST-03)
- Trust Phase 3 output for HIGH-01 through HIGH-04 attack tests -- they are already verified and complete
- Add NEW attack tests for MED-01 through MED-04 in AttackScenarios.hs (extend existing module, don't create new file)
- 2-3 exploit variants per medium vulnerability plus a positive test per fix
- Test BOTH Marketplace Buy and Withdraw paths for MED-01/02/03 (Buy for exploit rejection, Withdraw for regression safety)
- MED-04 attack tests cover gdSubmittedBy, gdAction, gdDeadline mutation variants

### Property test depth (TEST-04)
- Boundary + roundtrip properties for all 6 remaining smart constructors: mkCetAmount, mkPercentage, mkMultisig, mkConfigDatum, mkProjectDatum, mkGovernanceDatum
- Pattern: valid inputs accepted, boundary values handled correctly, invalid inputs rejected, toBuiltinData/fromBuiltinData roundtrip preserves equality
- Matches existing Lovelace/CotAmount property test pattern in SmartConstructors.hs

### Datum integrity properties (TEST-05)
- Random mutations via QuickCheck -- generate random field changes and verify validators reject them
- Minimal Arbitrary instances using existing smart constructors where possible (mkConfigDatum, mkProjectDatum, etc.)
- All three invariants covered:
  1. ProjectVault vote preserves non-vote fields
  2. DaoGovernance vote preserves non-vote fields (gdSubmittedBy, gdAction, gdDeadline)
  3. verifyConfigUpdate preserves non-target fields for each ProposalAction case

### Haddock documentation (QUAL-03)
- Scope: ALL source modules (Types/ + Validators/Common.hs + all 9 validator modules)
- Detail level: purpose + params for each exported function (skip usage examples)
- Module-level Haddock headers on every .hs file in src/Carbonica/
- Error registry comment blocks stay as plain comments (don't convert to Haddock)

### Test module organization
- MED attack tests: extend existing AttackScenarios.hs with med01Tests through med04Tests groups
- Smart constructor properties: extend existing SmartConstructors.hs with 6 new constructor test groups
- Datum integrity properties: NEW module Test.Carbonica.Properties.DatumIntegrity
- Arbitrary instances: add to TestHelpers.hs alongside existing builders
- Test Main.hs grouping: Claude's discretion on by-type vs by-validator organization

### Claude's Discretion
- Test Main.hs organization (by type or by validator)
- Exact Arbitrary instance implementations for complex datum types
- Which specific mutation strategies for datum integrity properties
- Internal structure of DatumIntegrity.hs test groups

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- TestHelpers.hs: mkTxInfo, mkSpendingCtx, mkMintingCtx, mkTxInfoWithRange -- reuse for MED attack context building
- AttackScenarios.hs: testAttackRejected3 / testAttackAccepted3 patterns for 3-arg validators (Marketplace)
- SmartConstructors.hs: Lovelace and CotAmount property test patterns -- template for remaining 6 constructors
- All smart constructors in Types/ modules -- use as Arbitrary instance foundations

### Established Patterns
- Attack tests call full untyped entry points with BuiltinData for realistic testing
- Enumerated HUnit cases with explicit exploit variant naming for traceability
- Positive tests in each vulnerability group verifying patched validators accept legitimate transactions
- QuickCheck properties using testProperty with forAll for controlled generation

### Integration Points
- smartcontracts.cabal: register new DatumIntegrity module in test-suite other-modules
- test Main.hs: import and wire DatumIntegrity tests into test tree
- TestHelpers.hs: add Arbitrary instances and any new Marketplace builder helpers
- AttackScenarios.hs: add Marketplace validator imports for MED attack tests

</code_context>

<specifics>
## Specific Ideas

No specific requirements -- standard testing patterns and Haddock conventions. Key constraint: attack tests must call full untyped entry points (established in Phase 3) and property tests should use minimal Arbitrary instances built on existing smart constructors.

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope.

</deferred>

---

*Phase: 05-comprehensive-testing-and-documentation*
*Context gathered: 2026-03-13*
