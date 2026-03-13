# Phase 4: Medium and Low Fixes - Research

**Researched:** 2026-03-13
**Domain:** PlutusTx V3 Marketplace/DaoGovernance validator hardening, Haddock documentation
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
None — all implementation decisions are at Claude's discretion.

### Claude's Discretion

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
- DaoGovernance: DGE019+ (continuing from DGE018)
- Update error registry comment blocks at top of each patched validator

**Testing approach:**
- Extend existing TestHelpers and AttackScenarios modules from Phase 3
- Attack tests for MED-01 through MED-04 exploit scenarios
- Reuse mkTxInfo, mkSpendingCtx builders for Marketplace and DaoGovernance attack contexts

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| MED-01 | Marketplace must verify UTxO actually contains the listed COT tokens | `valueOf` already imported; `SpendingScript oref` carries the TxOutRef; must find the input by oref and compare value against datum fields |
| MED-02 | Marketplace must enforce minimum price > 0 | Simple integer guard `mdAmount > 0` added to `validateBuy`; new error code MKE007 |
| MED-03 | Marketplace royalty calculation must handle rounding (minimum 1 lovelace) | Replace `royaltyAmount` expression with `max 1 (calculated)` using `P.max`; no additional imports needed |
| MED-04 | DaoGovernance vote must verify all non-vote fields unchanged in output datum | Add field-by-field equality checks inside `validateVote`; pattern follows existing `preservesAllExcept` / `preservesNonMultisigFields` in `verifyConfigUpdate` |
| LOW-02 | Document VaultWithdraw as intentionally disabled with proper error code | UVE003 already exists; add Haddock comment on `VaultWithdraw` branch and update module-level description |
</phase_requirements>

---

## Summary

Phase 4 is a targeted hardening pass touching three validator files (Marketplace.hs, DaoGovernance.hs, UserVault.hs) with no new modules or cabal changes required. Every fix is a small, well-isolated addition using patterns and helpers that already exist in the codebase.

The Marketplace fixes (MED-01 through MED-03) are all within `validateBuy`. MED-01 adds a UTxO value lookup using `valueOf` (already imported via `PlutusLedgerApi.V1.Value`) against the self-input found from the `SpendingScript oref` in the script info. MED-02 adds a pre-check `mdAmount > 0` before computing payouts. MED-03 wraps the royalty calculation in `P.max 1 (...)`. Each check follows the `P.traceIfFalse "MKEn" condition` chain pattern established in Phases 1-3. The error registry comment block at the top of Marketplace.hs must also be extended.

The DaoGovernance fix (MED-04) adds non-vote field integrity to `validateVote`. The three unguarded fields are `gdSubmittedBy`, `gdAction`, and `gdDeadline`; `gdProposalId` and `gdState` are already checked, and vote counts/records are already checked. The fix adds explicit equality assertions `gdSubmittedBy outDatum == gdSubmittedBy inputDatum`, `gdAction outDatum == gdAction inputDatum`, and `gdDeadline outDatum == gdDeadline inputDatum` — three separate `P.traceIfFalse "DGEnnn"` checks with distinct codes. This is preferable to a combined check because individual error codes aid debugging. DGE019 is the next available code.

UserVault LOW-02 is the smallest change: add a Haddock annotation on the `VaultWithdraw` branch in `validateSpend` explaining that the action is intentionally disabled pending V2-02 authorization implementation. UVE003 already carries the correct error code and message; only documentation is missing. The error registry comment block should note the intentional nature of the disabled feature.

**Primary recommendation:** Apply fixes one validator at a time (Marketplace first, then DaoGovernance, then UserVault), then write attack tests for all four medium requirements as a single test plan wave.

---

## Standard Stack

### Core (already in use — no new dependencies)

| Library | Version | Purpose | Already Used |
|---------|---------|---------|--------------|
| `PlutusLedgerApi.V3` | 1.56.x | ScriptContext, TxInfo, TxInInfo, TxOut | Yes |
| `PlutusLedgerApi.V1.Value` | 1.56.x | `valueOf` for token lookup | Yes, in Marketplace |
| `PlutusTx.Prelude` | 1.56.x | `P.traceIfFalse`, `P.max`, arithmetic | Yes |
| `tasty-hunit` | in cabal | HUnit test cases | Yes, in AttackScenarios |

No new dependencies are needed. All required functions (`valueOf`, `P.max`, `P.traceIfFalse`) are already imported or accessible via existing imports.

---

## Architecture Patterns

### Recommended File Structure (no changes)
```
src/Carbonica/Validators/
├── Marketplace.hs      # MED-01, MED-02, MED-03 — validateBuy + registry update
├── DaoGovernance.hs    # MED-04 — validateVote + registry update
└── UserVault.hs        # LOW-02 — Haddock on VaultWithdraw branch only

test/Test/Carbonica/
└── AttackScenarios.hs  # Extend with med01-04 test groups
```

### Pattern 1: UTxO Value Verification (MED-01)

The `SpendingScript oref` carries the TxOutRef of the UTxO being spent. The validator already has access to `txInfo` (and therefore `txInfoInputs`). The existing `findInputByOutRef` helper in Common.hs resolves the TxInInfo from the oref. The resolved output's value is then checked with `valueOf`.

**Scope decision:** Buy path only. The economic exploit is exclusive to Buy: a seller could list with a fake datum referencing COT they do not actually hold, then sell a worthless UTxO while collecting payment. Withdraw only requires owner signature and returns the UTxO to the owner — no counterparty can be cheated.

**Implementation location:** Inside `validateBuy`, after extracting `mktDatum`, before computing `royaltyAmount`.

```haskell
-- Source: existing Common.hs findInputByOutRef + PlutusLedgerApi.V1.Value.valueOf
-- In Marketplace.hs, within validateBuy:

-- Get the self input to verify its value matches the datum claims
cotVerified :: Bool
cotVerified =
  let selfInput = case findInputByOutRef (txInfoInputs txInfo) selfOref of
        P.Nothing -> P.traceError "MKE007"   -- self input missing
        P.Just i  -> txInInfoResolved i
      actualQty = valueOf (txOutValue selfInput) (mdCotPolicy mktDatum) (mdCotToken mktDatum)
  in actualQty P.>= mdCotQty mktDatum
```

Note: `selfOref` must be threaded from the outer `validateSpend` call where it is already bound via `SpendingScript oref (Just datum)` pattern match. The refactoring is: change `validateSpend :: MarketplaceDatum -> Bool` to `validateSpend :: TxOutRef -> MarketplaceDatum -> Bool` and pass `oref` through `validateBuy`.

`findInputByOutRef` is already exported from `Carbonica.Validators.Common` and must be added to the Marketplace import list.

### Pattern 2: Positive-Floor Arithmetic (MED-02 + MED-03)

**MED-02 (price floor):** Add `P.traceIfFalse "MKE008" pricePositive` where `pricePositive = salePrice P.> 0`. This goes at the top of `validateBuy`'s checks, before computing royalty (avoids divide-by-zero risk and makes the error clear).

**MED-03 (royalty floor):** Replace the royalty calculation:
```haskell
-- Before:
royaltyAmount = (salePrice P.* royaltyNumerator) `P.divide` royaltyDenominator

-- After:
royaltyAmount = P.max 1 ((salePrice P.* royaltyNumerator) `P.divide` royaltyDenominator)
```

`P.max` is available in `PlutusTx.Prelude` — no new import needed. The minimum of `1` lovelace is a straightforward floor. No minUTxO-aware enforcement is needed; `> 0` is the audit requirement and `max 1` satisfies it while preserving the intent.

### Pattern 3: Field-by-Field Datum Integrity (MED-04)

Follow the Phase 2 `preservesNonMultisigFields` pattern: explicit named equality per field, distinct error codes per logical group.

**Fields already verified in validateVote:**
- `gdProposalId` — checked via `proposalIdMatches`
- `gdState` — checked via `outputStillInProgress`
- `gdYesCount`, `gdNoCount`, `gdAbstainCount` — checked via `voteCountIncremented`
- `gdVotes` (the voted record) — checked via `voterStatusUpdated`

**Fields NOT yet verified (MED-04 scope):**
- `gdSubmittedBy` — could be changed silently to redirect governance authority
- `gdAction` — could be changed to swap what gets executed
- `gdDeadline` — could be extended to keep voting open indefinitely

**Depth decision:** Verify structural immutable fields only (`gdSubmittedBy`, `gdAction`, `gdDeadline`). The vote records list as a whole is protected indirectly: `voterStatusUpdated` verifies the voter's own record changed correctly, and `voterWasPending` verifies the pre-state. A complete list-equality check would be more robust but is not required by MED-04.

```haskell
-- In validateVote, add to the P.&& chain:
P.&& P.traceIfFalse "DGE019" submitterUnchanged
P.&& P.traceIfFalse "DGE020" actionUnchanged
P.&& P.traceIfFalse "DGE021" deadlineUnchanged
where
  submitterUnchanged = gdSubmittedBy outDatum P.== gdSubmittedBy inputDatum
  actionUnchanged    = gdAction outDatum P.== gdAction inputDatum
  deadlineUnchanged  = gdDeadline outDatum P.== gdDeadline inputDatum
```

**Eq instances required:** `ProposalAction` and `POSIXTime` (alias for `Integer`) must support `P.==`. Looking at the codebase: `ProposalAction` uses `makeIsDataSchemaIndexed` and derives no explicit `P.Eq` instance. This is a critical gap — see Anti-Patterns below.

### Pattern 4: Haddock Documentation (LOW-02)

Standard GHC Haddock comment on the `VaultWithdraw` branch. The existing code at line 148 of UserVault.hs:
```haskell
VaultWithdraw -> P.traceError "UVE003"
```
Add a comment above the match arm explaining the intentional disability. Also update the module-level `VALIDATION LOGIC` section comment and the error registry entry for UVE003 to note "intentionally disabled pending V2-02".

### Anti-Patterns to Avoid

- **Using `P.Eq` on `ProposalAction` without verifying the instance exists:** `ProposalAction` in `Carbonica.Types.Governance` uses `makeIsDataSchemaIndexed` but does NOT derive `P.Eq`. The `DaoGovernance.hs` file never compares two `ProposalAction` values — it pattern-matches on `gdAction`. Adding `actionUnchanged = gdAction outDatum P.== gdAction inputDatum` requires either (a) adding a `P.Eq ProposalAction` instance to Types/Governance.hs, or (b) comparing via `BuiltinData` serialization. **Option (a) is cleaner** — add an explicit `P.Eq ProposalAction` instance following the same pattern as `Vote`, `ProposalState`, and `VoterStatus` in the same file. This requires a case-by-case expansion since `ProposalAction` has 9 constructors.

- **Comparing `POSIXTime` with `P.==` without checking the type alias:** `POSIXTime` is a newtype around `Integer` in `PlutusLedgerApi.V3`. `Integer` has `P.Eq` so `gdDeadline outDatum P.== gdDeadline inputDatum` is valid with no additional instance needed.

- **Zero-price royalty with `max 1`:** When `salePrice = 0` and MED-02's `pricePositive` check is the FIRST check (as recommended), the royalty floor never fires on a zero-price transaction. The ordering of checks matters: MED-02 check must precede MED-03 in the validation chain.

- **Not threading `oref` into `validateBuy`:** The `oref` is bound in the outer pattern match `SpendingScript oref (Just datum)` in `typedValidator`. It must be passed down through `validateSpend` to `validateBuy`. Alternatively it can be captured via a closure — but since `validateBuy` is a local function in `where` it already captures from `typedValidator`'s scope. Careful: `typedValidator` already destructures `ctx` to get `txInfo`, so `oref` just needs to be included in scope. The cleanest approach is to add `oref` as a parameter to `validateSpend` and `validateBuy`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Find spending UTxO input | Custom oref lookup | `findInputByOutRef` in Common.hs | Already exported, tested, INLINEABLE |
| Token amount in a value | Custom traversal | `valueOf` from `PlutusLedgerApi.V1.Value` | Standard Plutus API, already imported in Marketplace |
| Maximum of two integers | Custom comparison | `P.max` from `PlutusTx.Prelude` | Builtin, no overhead |
| ProposalAction equality | BuiltinData comparison hack | Explicit `P.Eq ProposalAction` instance | Same pattern as Vote/VoterStatus in same module |

---

## Common Pitfalls

### Pitfall 1: ProposalAction has no P.Eq instance
**What goes wrong:** `gdAction outDatum P.== gdAction inputDatum` fails to compile.
**Why it happens:** `ProposalAction` uses `makeIsDataSchemaIndexed` but the `P.Eq` instance was never defined. The existing code never compared two `ProposalAction` values directly — it only pattern-matched.
**How to avoid:** Add `instance P.Eq ProposalAction` to `Carbonica.Types.Governance`, enumerating all 9 constructors. Follow the `Vote` instance pattern in the same file.
**Warning signs:** GHC compile error "No instance for (P.Eq ProposalAction)".

### Pitfall 2: Stale error code numbering
**What goes wrong:** Duplicate or out-of-sequence error codes after patch.
**Current state:**
- Marketplace: MKE000–MKE006 in use. Next available: **MKE007**.
- DaoGovernance: DGE000–DGE018 in use (DGE018 = reject without multisig, added Phase 3). Next available: **DGE019**.
- UserVault: UVE000–UVE010 in use. No new codes needed for LOW-02.
**How to avoid:** Check the error registry comment block at the top of each validator before assigning codes. Update registry after adding.

### Pitfall 3: Import missing for findInputByOutRef in Marketplace
**What goes wrong:** `findInputByOutRef` is used in Marketplace but not currently imported. The current import list only has `isInList` and `payoutAtLeast` from Common.
**How to avoid:** Add `findInputByOutRef` to the `Carbonica.Validators.Common` import in Marketplace.hs. Also need `TxInInfo (..)` which is not currently imported — check import list. Looking at the file: `TxInInfo` is not imported in Marketplace.hs. Need to add `TxInInfo (..)` to the `PlutusLedgerApi.V3` import.

### Pitfall 4: valueOf comparison for token verification
**What goes wrong:** Using `>= mdCotQty` instead of `>= mdCotQty` would be semantically wrong if we use `== mdCotQty`. The correct semantics is `>=` (the UTxO must contain *at least* the claimed quantity — it could have more, e.g. partial fill scenarios). However, looking at the Marketplace design: `mdCotQty` is the *listed* quantity and `hasTokenPayment` already uses `>=` for buyer receipt. For the input UTxO verification, `>=` is correct — the UTxO must hold at least what is claimed in the datum.
**How to avoid:** Use `P.>=` not `P.==` for the input UTxO check.

### Pitfall 5: Checking both Buy and Withdraw for MED-01
**What goes wrong:** Adding UTxO token verification to Withdraw as well as Buy. This is unnecessary work and could cause legitimate Withdraw transactions to fail (e.g., if the owner previously withdrew some tokens and the UTxO was partially consumed).
**How to avoid:** Scope MED-01 fix to `validateBuy` only per the CONTEXT.md guidance. The economic exploit is exclusive to Buy.

### Pitfall 6: GovernanceDatum field comparison via BuiltinData
**What goes wrong:** Attempting `PlutusTx.toBuiltinData inputDatum P.== PlutusTx.toBuiltinData outDatum` as a shortcut for comparing all fields — this would over-constrain the check and reject valid votes (where vote counts and voter status legitimately change).
**How to avoid:** Compare only the three specific fields (`gdSubmittedBy`, `gdAction`, `gdDeadline`) individually, not the whole datum.

---

## Code Examples

### MED-01: UTxO token verification in validateBuy

```haskell
-- Source: existing Common.hs findInputByOutRef pattern + PlutusLedgerApi.V1.Value.valueOf
-- Require oref to be threaded into validateBuy (or captured via closure)

validateBuy :: TxOutRef -> MarketplaceDatum -> Bool
validateBuy selfOref mktDatum =
  P.traceIfFalse "MKE008" pricePositive       -- MED-02: price > 0 (first check)
  P.&& P.traceIfFalse "MKE007" cotVerified    -- MED-01: UTxO has claimed COT
  P.&& P.traceIfFalse "MKE003" sellerPaid
  P.&& P.traceIfFalse "MKE004" platformPaid
  P.&& P.traceIfFalse "MKE005" buyerReceivesCot
  where
    salePrice = mdAmount mktDatum

    pricePositive :: Bool                      -- MED-02
    pricePositive = salePrice P.> 0

    cotVerified :: Bool                        -- MED-01
    cotVerified =
      case findInputByOutRef (txInfoInputs txInfo) selfOref of
        P.Nothing -> False
        P.Just i  ->
          let actualQty = valueOf (txOutValue (txInInfoResolved i))
                            (mdCotPolicy mktDatum) (mdCotToken mktDatum)
          in actualQty P.>= mdCotQty mktDatum

    royaltyAmount :: Integer                   -- MED-03: royalty floor
    royaltyAmount = P.max 1 ((salePrice P.* royaltyNumerator) `P.divide` royaltyDenominator)
    ...
```

### MED-04: P.Eq instance for ProposalAction

```haskell
-- Source: existing Vote/VoterStatus P.Eq instances in Carbonica.Types.Governance
-- Add to Carbonica.Types.Governance after the existing VoterStatus instance

instance P.Eq ProposalAction where
  {-# INLINEABLE (==) #-}
  ActionAddSigner pkh1          == ActionAddSigner pkh2          = pkh1 P.== pkh2
  ActionRemoveSigner pkh1       == ActionRemoveSigner pkh2       = pkh1 P.== pkh2
  ActionUpdateFeeAmount n1      == ActionUpdateFeeAmount n2      = n1 P.== n2
  ActionUpdateFeeAddress pkh1   == ActionUpdateFeeAddress pkh2   = pkh1 P.== pkh2
  ActionAddCategory cat1        == ActionAddCategory cat2        = cat1 P.== cat2
  ActionRemoveCategory cat1     == ActionRemoveCategory cat2     = cat1 P.== cat2
  ActionUpdateRequired n1       == ActionUpdateRequired n2       = n1 P.== n2
  ActionUpdateProposalDuration d1 == ActionUpdateProposalDuration d2 = d1 P.== d2
  ActionUpdateScriptHash f1 h1  == ActionUpdateScriptHash f2 h2  = f1 P.== f2 P.&& h1 P.== h2
  _                             == _                             = False
```

### MED-04: Non-vote field integrity checks in validateVote

```haskell
-- Source: Phase 2 preservesNonMultisigFields pattern in DaoGovernance.hs
-- Add to validateVote's where clause and P.&& chain

-- Add to the validation chain:
P.&& P.traceIfFalse "DGE019" submitterUnchanged
P.&& P.traceIfFalse "DGE020" actionUnchanged
P.&& P.traceIfFalse "DGE021" deadlineUnchanged

-- Add to where clause:
submitterUnchanged :: Bool
submitterUnchanged = gdSubmittedBy outDatum P.== gdSubmittedBy inputDatum

actionUnchanged :: Bool
actionUnchanged = gdAction outDatum P.== gdAction inputDatum

deadlineUnchanged :: Bool
deadlineUnchanged = gdDeadline outDatum P.== gdDeadline inputDatum
```

### Attack test structure for MED-01 (extending AttackScenarios.hs)

```haskell
-- Pattern: follows existing test group structure
-- Needs new Marketplace validator import + MarketplaceDatum/MarketplaceRedeemer types

med01Tests :: TestTree
med01Tests = testGroup "MED-01: Marketplace fake listing"
  [ med01a_datumClaimsMoreThanHeld
  , med01b_datumClaimsWrongPolicy
  , med01_positive_validListing
  ]
```

The Marketplace validator is a 3-arg untyped validator (idNftPolicy, royaltyAddr, ctx), so it uses `testAttackRejected3` / `testAttackAccepted3`.

---

## State of the Art

| Area | Current State | Phase 4 Change |
|------|--------------|----------------|
| MKE error registry | MKE000–MKE006 | Add MKE007 (cotVerified), MKE008 (pricePositive) |
| DGE error registry | DGE000–DGE018 | Add DGE019 (submitterUnchanged), DGE020 (actionUnchanged), DGE021 (deadlineUnchanged) |
| UVE error registry | UVE000–UVE010 | No new codes; UVE003 gets Haddock clarification |
| validateBuy | Checks seller paid, platform paid, buyer gets COT | Add price > 0, UTxO COT verification, royalty floor |
| validateVote | Checks ID, state, deadline, voter signed, count, status | Add submitter, action, deadline field preservation |
| ProposalAction | No P.Eq instance | Add P.Eq instance (required for field comparison) |
| TestHelpers | Has mkTxInfo, mkSpendingCtx, mkTxInfoWithRange | No changes needed; attack tests use existing builders |
| AttackScenarios | Covers CRIT-01 through HIGH-04 | Add med01-04 test groups |

---

## Open Questions

1. **Marketplace MED-01: `>=` vs `==` for UTxO quantity check**
   - What we know: `hasTokenPayment` (buyer receives COT) uses `>=` semantics. The listed quantity in `mdCotQty` is exactly what the seller is offering.
   - What's unclear: Should we enforce `== mdCotQty` (exact match) or `>= mdCotQty` (at least that much)?
   - Recommendation: Use `>=`. An over-funded UTxO is fine; the datum-claimed quantity is the *minimum* the UTxO should hold. Using `==` would reject listings where the UTxO accidentally received extra tokens.

2. **MED-04: Should gdVotes list (untouched records) be equality-checked?**
   - What we know: `voterStatusUpdated` verifies the voting voter's record changed. `voterWasPending` verifies the pre-state. Other voters' records are not explicitly checked.
   - What's unclear: An attacker could change other voters' pending status or add/remove vote records.
   - Recommendation: For Phase 4 scope, the CONTEXT.md explicitly limits to "structural fields" (`gdSubmittedBy`, `gdAction`, `gdDeadline`). Full vote-record list integrity is not in scope for this phase.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | tasty 1.x + tasty-hunit 0.10.x + tasty-quickcheck 0.11.x |
| Config file | smartcontracts.cabal (test-suite carbonica-tests) |
| Quick run command | `cabal test carbonica-tests` |
| Full suite command | `cabal test carbonica-tests --test-show-details=always` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | File | Notes |
|--------|----------|-----------|------|-------|
| MED-01 | Buy rejected when UTxO lacks claimed COT | attack (HUnit) | AttackScenarios.hs | New group `med01Tests` |
| MED-01 | Buy rejected when UTxO has wrong policy | attack (HUnit) | AttackScenarios.hs | Variant in med01Tests |
| MED-01 | Buy accepted when UTxO contains claimed tokens | positive (HUnit) | AttackScenarios.hs | Variant in med01Tests |
| MED-02 | Buy rejected when mdAmount == 0 | attack (HUnit) | AttackScenarios.hs | New group `med02Tests` |
| MED-02 | Buy accepted when mdAmount > 0 | positive (HUnit) | AttackScenarios.hs | Variant in med02Tests |
| MED-03 | Platform receives at least 1 lovelace even for tiny sale | attack (HUnit) | AttackScenarios.hs | New group `med03Tests` |
| MED-04 | Vote rejected when gdSubmittedBy mutated in output | attack (HUnit) | AttackScenarios.hs | New group `med04Tests` |
| MED-04 | Vote rejected when gdAction mutated in output | attack (HUnit) | AttackScenarios.hs | Variant in med04Tests |
| MED-04 | Vote rejected when gdDeadline mutated in output | attack (HUnit) | AttackScenarios.hs | Variant in med04Tests |
| MED-04 | Vote accepted with all non-vote fields unchanged | positive (HUnit) | AttackScenarios.hs | Variant in med04Tests |
| LOW-02 | VaultWithdraw redeemer returns UVE003 error | existing test coverage | N/A | No new test needed; error behavior unchanged |

### Sampling Rate
- **Per task commit:** `cabal test carbonica-tests`
- **Per wave merge:** `cabal test carbonica-tests --test-show-details=always`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps

None — existing test infrastructure (tasty, HUnit, TestHelpers module with all required builders) covers all phase requirements. No new test files or framework config needed. The attack test cases are added to the existing `AttackScenarios.hs` module.

The only prerequisite is: the `ProposalAction P.Eq` instance must be added to `Carbonica.Types.Governance` before the DaoGovernance validator change can compile. This is a validator source dependency, not a test infrastructure gap.

**New import required in AttackScenarios.hs** when adding Marketplace attack tests:
- `import qualified Carbonica.Validators.Marketplace as Marketplace`
- `import Carbonica.Validators.Marketplace (MarketplaceDatum (..), MarketplaceRedeemer (..), MktBuy, MktWithdraw, Wallet (..))`

These are already exposed by the `smartcontracts` library in the cabal file.

---

## Sources

### Primary (HIGH confidence)
- Direct code reading of `Marketplace.hs` (lines 1–297) — current state of validateBuy, error registry, imports
- Direct code reading of `DaoGovernance.hs` (lines 1–725) — current state of validateVote, DGE registry, ProposalAction definition
- Direct code reading of `UserVault.hs` (lines 1–262) — current state of VaultWithdraw, UVE003
- Direct code reading of `Common.hs` (lines 1–476) — available helpers, export list
- Direct code reading of `Carbonica.Types.Governance` (lines 1–407) — ProposalAction constructors, absence of P.Eq instance, getter exports
- Direct code reading of `TestHelpers.hs` + `AttackScenarios.hs` — established attack test patterns
- Direct code reading of `smartcontracts.cabal` — test module list, build-depends

### Secondary (MEDIUM confidence)
- PlutusTx.Prelude `P.max` availability: inferred from project-wide `qualified PlutusTx.Prelude as P` usage and standard Prelude content (HIGH — `max` is a fundamental Haskell Prelude function, present in PlutusTx.Prelude)
- `POSIXTime` as `Integer` newtype with `P.Eq`: inferred from how deadlines are compared elsewhere in the codebase (`before deadline validRange` in DaoGovernance uses `PlutusLedgerApi.V1.Interval.before`)

### Tertiary (LOW confidence)
- None

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependencies; all required functions verified present in existing imports
- Architecture: HIGH — all patterns sourced directly from existing codebase (Phase 2 preserves pattern, Phase 3 attack test structure)
- Pitfalls: HIGH — ProposalAction P.Eq gap verified by direct inspection of Types/Governance.hs; import gaps verified by inspecting Marketplace.hs import list

**Research date:** 2026-03-13
**Valid until:** Stable — no fast-moving ecosystem concerns; pure PlutusTx validator code
