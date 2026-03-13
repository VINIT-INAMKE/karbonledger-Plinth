# Phase 4: Medium and Low Fixes - Context

**Gathered:** 2026-03-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Harden Marketplace validation against fake listings, zero-price trades, and royalty evasion (MED-01, MED-02, MED-03). Enforce DaoGovernance vote datum integrity so non-vote fields cannot be silently mutated (MED-04). Document VaultWithdraw as intentionally disabled with proper error code and Haddock annotation (LOW-02). No new features, no test infrastructure changes.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion

All implementation decisions are at Claude's discretion. The audit findings and success criteria from ROADMAP.md define WHAT to fix; Claude determines HOW.

**Marketplace token verification (MED-01):**
- Verify the spent UTxO actually contains the claimed COT tokens (policy, name, quantity matching MarketplaceDatum fields)
- Decide scope: Buy path only (where economic exploit exists) vs both Buy and Withdraw
- Add new error code(s) in MKE sequence

**Marketplace price and royalty floors (MED-02 + MED-03):**
- Enforce mdAmount > 0 to prevent zero-price listings
- Handle royalty rounding with minimum 1 lovelace floor (e.g., `max 1 (calculated)`)
- Decide whether to enforce a higher meaningful minimum (minUTxO-aware) or just > 0
- Add new error code(s) in MKE sequence

**DaoGovernance vote datum integrity (MED-04):**
- Verify all non-vote GovernanceDatum fields unchanged between input and output during vote
- Fields to protect: gdSubmittedBy, gdAction, gdDeadline (gdProposalId and gdState already checked)
- Decide depth: structural fields only vs also verifying untouched vote records
- Follow Phase 2 pattern: explicit field-by-field comparison preferred over generic Eq
- Add new error code(s) in DGE sequence

**VaultWithdraw documentation (LOW-02):**
- UVE003 error code already exists with "CET withdrawal not allowed" message
- Add Haddock documentation on VaultWithdraw indicating intentionally disabled pending V2-02
- Update error registry comment if needed

**Error codes:**
- Continue one-error-code-per-check pattern from Phases 1-3
- Marketplace: MKE007+ (continuing from MKE006)
- DaoGovernance: DGE018+ or next available (continuing from existing sequence)
- Update error registry comment blocks at top of each patched validator

**Testing approach:**
- Extend existing TestHelpers and AttackScenarios modules from Phase 3
- Attack tests for MED-01 through MED-04 exploit scenarios
- Reuse mkTxInfo, mkSpendingCtx builders for Marketplace and DaoGovernance attack contexts

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `payoutAtLeast` (Common.hs): Already used by Marketplace for seller/platform payout checks
- `isInList` (Common.hs): Already used by Marketplace for owner signature check
- `valueOf` (PlutusLedgerApi.V1.Value): Already imported in Marketplace — use for UTxO token verification
- `TestHelpers` module: ScriptContext builders (mkTxInfo, mkSpendingCtx) for attack tests
- `AttackScenarios` module: Existing attack test structure to extend
- Phase 2 `preservesAllExcept` pattern: Field-by-field comparison approach for datum integrity

### Established Patterns
- Error code format: 3-letter prefix + 3-digit number (MKE006, DGE017, UVE003)
- Validation chain: `P.traceIfFalse "CODE" condition P.&& ...`
- Royalty calculation: `(salePrice * royaltyNumerator) / royaltyDenominator` with integer division
- Marketplace already has `mdCotPolicy`, `mdCotToken`, `mdCotQty` fields in datum — verification compares these against actual UTxO value
- DaoGovernance validateVote already checks proposalId, state, deadline, vote counts — MED-04 adds submittedBy, action, and vote record integrity

### Integration Points
- Marketplace.hs `validateBuy` (line 201): Add UTxO token verification and price floor checks
- Marketplace.hs `royaltyAmount` calculation (line 213): Add minimum royalty floor
- DaoGovernance.hs `validateVote` (line 407): Add non-vote field integrity checks
- UserVault.hs `VaultWithdraw` (line 148): Add Haddock documentation
- smartcontracts.cabal: No new modules needed — extending existing test modules

</code_context>

<specifics>
## Specific Ideas

No specific requirements — user deferred all implementation decisions to Claude. Follow established patterns from Phases 1-3 and the audit recommendations in CONCERNS.md.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 04-medium-and-low-fixes*
*Context gathered: 2026-03-13*
