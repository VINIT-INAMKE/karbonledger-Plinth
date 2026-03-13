# Phase 5: Comprehensive Testing and Documentation - Research

**Researched:** 2026-03-13
**Domain:** Haskell/PlutusTx testing (tasty-hunit, tasty-quickcheck) + Haddock documentation
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Attack test scope (TEST-03)**
- Trust Phase 3 output for HIGH-01 through HIGH-04 attack tests -- they are already verified and complete
- Add NEW attack tests for MED-01 through MED-04 in AttackScenarios.hs (extend existing module, don't create new file)
- 2-3 exploit variants per medium vulnerability plus a positive test per fix
- Test BOTH Marketplace Buy and Withdraw paths for MED-01/02/03 (Buy for exploit rejection, Withdraw for regression safety)
- MED-04 attack tests cover gdSubmittedBy, gdAction, gdDeadline mutation variants

**Property test depth (TEST-04)**
- Boundary + roundtrip properties for all 6 remaining smart constructors: mkCetAmount, mkPercentage, mkMultisig, mkConfigDatum, mkProjectDatum, mkGovernanceDatum
- Pattern: valid inputs accepted, boundary values handled correctly, invalid inputs rejected, toBuiltinData/fromBuiltinData roundtrip preserves equality
- Matches existing Lovelace/CotAmount property test pattern in SmartConstructors.hs

**Datum integrity properties (TEST-05)**
- Random mutations via QuickCheck -- generate random field changes and verify validators reject them
- Minimal Arbitrary instances using existing smart constructors where possible (mkConfigDatum, mkProjectDatum, etc.)
- All three invariants covered:
  1. ProjectVault vote preserves non-vote fields
  2. DaoGovernance vote preserves non-vote fields (gdSubmittedBy, gdAction, gdDeadline)
  3. verifyConfigUpdate preserves non-target fields for each ProposalAction case

**Haddock documentation (QUAL-03)**
- Scope: ALL source modules (Types/ + Validators/Common.hs + all 9 validator modules)
- Detail level: purpose + params for each exported function (skip usage examples)
- Module-level Haddock headers on every .hs file in src/Carbonica/
- Error registry comment blocks stay as plain comments (don't convert to Haddock)

**Test module organization**
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

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| TEST-03 | Add attack scenario tests for each medium vulnerability fix (MED-01 through MED-04) | AttackScenarios.hs patterns fully understood; Marketplace.untypedValidator signature confirmed as 3-arg; DaoGovernance vote non-field errors DGE019/020/021 confirmed |
| TEST-04 | Add property-based tests for all smart constructors | All 6 remaining constructors read: mkCetAmount, mkPercentage, mkMultisig, mkConfigDatum, mkProjectDatum, mkGovernanceDatum; invariants documented below |
| TEST-05 | Add datum integrity property tests for vote/config update validators | GovernanceDatum and ProjectDatum field structure confirmed; Arbitrary instance strategy documented; mutation approach mapped |
| QUAL-03 | Add Haddock documentation to all exported functions | Scope confirmed: Types/ (4 files) + Validators/Common.hs + 9 validator modules; existing patterns in Common.hs and Core.hs show the Haddock style already established |
</phase_requirements>

---

## Summary

Phase 5 is a pure test-and-docs phase with no validator logic changes. All four requirements are additive: extending existing test modules (AttackScenarios.hs, SmartConstructors.hs), creating one new test module (DatumIntegrity), registering it in the cabal file, and adding Haddock to source files.

The codebase is mature and well-structured. The test infrastructure (TestHelpers.hs, attack test wrappers, QuickCheck scaffolding) is fully established from Phases 3-4. The primary research challenge was mapping each requirement to the exact code signatures and invariants already in place.

The most complex piece is TEST-05 (datum integrity properties): it requires Arbitrary instances for PlutusTx-native types (BuiltinByteString, POSIXTime, PubKeyHash) plus the composite datum types, and the mutation tests must call the full untyped validator entry points to be realistic. The strategy for this is documented in detail below.

**Primary recommendation:** Follow the "extend existing modules, one new module" structure from CONTEXT.md exactly. The test infrastructure is production-ready and no scaffolding changes are needed except cabal registration.

---

## Standard Stack

### Core (already in cabal, no new deps)
| Library | Version | Purpose | Status |
|---------|---------|---------|--------|
| tasty | in use | Test runner + tree | Active |
| tasty-hunit | in use | HUnit assertions | Active |
| tasty-quickcheck | in use | QuickCheck integration | Active |
| QuickCheck | in use | Property-based testing | Active |

### No new dependencies required
All libraries needed for Phase 5 are already in `smartcontracts.cabal` test-suite `build-depends`. No cabal additions for libraries.

### New cabal other-modules entry required
```
Test.Carbonica.Properties.DatumIntegrity
```
This must be added to `test-suite carbonica-tests` `other-modules` in `smartcontracts.cabal`.

---

## Architecture Patterns

### Recommended Project Structure (Phase 5 additions)

```
test/
├── Main.hs                                         -- add datumIntegrityTests import
├── Test/Carbonica/
│   ├── AttackScenarios.hs                          -- extend: add med01-med04 groups
│   ├── TestHelpers.hs                              -- extend: add Arbitrary instances + Marketplace builders
│   ├── Properties/
│   │   ├── SmartConstructors.hs                    -- extend: add 6 constructor groups
│   │   └── DatumIntegrity.hs                       -- NEW
src/Carbonica/
│   ├── Types/
│   │   ├── Core.hs                                 -- add Haddock (some already present)
│   │   ├── Config.hs                               -- add Haddock (some already present)
│   │   ├── Project.hs                              -- add Haddock
│   │   ├── Governance.hs                           -- add Haddock
│   │   └── Emission.hs                             -- add Haddock
│   └── Validators/
│       ├── Common.hs                               -- add Haddock (module header present, functions need it)
│       ├── IdentificationNft.hs                    -- add Haddock
│       ├── ConfigHolder.hs                         -- add Haddock
│       ├── DaoGovernance.hs                        -- add Haddock
│       ├── ProjectPolicy.hs                        -- add Haddock
│       ├── ProjectVault.hs                         -- add Haddock
│       ├── CotPolicy.hs                            -- add Haddock
│       ├── CetPolicy.hs                            -- add Haddock
│       ├── UserVault.hs                            -- add Haddock
│       └── Marketplace.hs                          -- add Haddock
```

### Pattern 1: MED Attack Test (Marketplace 3-arg validator)

Marketplace's `untypedValidator` is a 3-arg function (idNftPolicy -> royaltyAddr -> ctx), so all MED attack tests use `testAttackRejected3` / `testAttackAccepted3`.

```haskell
-- Source: test/Test/Carbonica/AttackScenarios.hs (existing pattern)
import qualified Carbonica.Validators.Marketplace as Marketplace
import Carbonica.Validators.Marketplace (MarketplaceDatum(..), MarketplaceRedeemer(..), Wallet(..))

-- Helper: build marketplace spending context
mkMarketplaceCtx
  :: [PubKeyHash]     -- signers
  -> MarketplaceDatum -- datum
  -> MarketplaceRedeemer
  -> Value            -- UTxO value (what the listing UTxO holds)
  -> [TxOut]          -- outputs
  -> ScriptContext
mkMarketplaceCtx signers datum redeemer utxoValue outputs =
  let oref = TxOutRef (TxId "market_utxo_id_0000000000000000") 0
      datumData = Datum (toBuiltinData datum)
      mktInput = mkTxInInfo oref
        (TxOut
          (Address (ScriptCredential (ScriptHash "marketplace_hash_00000000000")) Nothing)
          utxoValue
          (OutputDatum datumData)
          Nothing)
      txInfo' = mkTxInfo signers [mktInput] outputs [] emptyValue
  in mkSpendingCtx txInfo' (Redeemer (toBuiltinData redeemer)) oref datumData

-- Rejection test pattern
testCase "MED-01a: buy with zero COT in UTxO (MKE007)" $
  let datum = MarketplaceDatum (Wallet alice Nothing) 10_000_000 testCotPolicy (TokenName "COT") 100
      -- UTxO holds NO COT tokens (attack: listing without backing)
      utxoValue = singleton (CurrencySymbol "") (TokenName "") 2_000_000
      outputs = [ mkPkhTxOut alice 9_500_000_lovelace  -- seller
                , mkPkhTxOut royaltyAddr 500_000_lovelace  -- platform
                , mkPkhTxOut bob (singleton testCotPolicy (TokenName "COT") 100) ]
      ctx = mkMarketplaceCtx [alice, bob] datum MktBuy utxoValue outputs
  in testAttackRejected3 "MED-01a: ..."
       Marketplace.untypedValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData (walletPkh (Wallet alice Nothing)))  -- royaltyAddr
       (toBuiltinData ctx)
```

**Key insight:** Marketplace's second parameter to `untypedValidator` is `royaltyAddr :: PubKeyHash` (not a CurrencySymbol). This is distinct from the idNftPolicy pattern used in ProjectVault/CotPolicy.

### Pattern 2: QuickCheck Property Test (SmartConstructors extension)

```haskell
-- Source: test/Test/Carbonica/Properties/SmartConstructors.hs (existing pattern)

-- For mkCetAmount (mirrors mkCotAmount pattern exactly):
cetAmountProperties :: TestTree
cetAmountProperties = testGroup "CetAmount Smart Constructor Properties"
  [ testProperty "Positive CET amount accepted" prop_cetAcceptsPositive
  , testProperty "Zero CET accepted"             prop_cetAcceptsZero
  , testProperty "Negative CET rejected"         prop_cetRejectsNegative
  , testProperty "CetAmount preserves value"     prop_cetPreservesValue
  ]

prop_cetAcceptsPositive :: Positive Integer -> Bool
prop_cetAcceptsPositive (Positive amt) =
  case mkCetAmount amt of
    P.Right cetAmt -> cetValue cetAmt P.== amt
    P.Left _ -> False

-- For mkPercentage (boundary: 0 valid, 100 valid, -1 invalid, 101 invalid):
prop_percentageAcceptsZero :: Bool
prop_percentageAcceptsZero = case mkPercentage 0 of
  P.Right _ -> True
  P.Left _  -> False

prop_percentageAcceptsHundred :: Bool
prop_percentageAcceptsHundred = case mkPercentage 100 of
  P.Right _ -> True
  P.Left _  -> False

prop_percentageRejectsAbove100 :: Positive Integer -> Bool
prop_percentageRejectsAbove100 (Positive n) =
  case mkPercentage (100 + n) of
    P.Left _ -> True
    P.Right _ -> False

prop_percentageRejectsNegative :: Positive Integer -> Bool
prop_percentageRejectsNegative (Positive n) =
  case mkPercentage (negate n) of
    P.Left _ -> True
    P.Right _ -> False
```

### Pattern 3: Datum Integrity Properties (DatumIntegrity.hs)

The key challenge is that `ProjectDatum` and `GovernanceDatum` constructors are NOT exported (opaque types with smart constructors). Arbitrary instances must generate via smart constructors and then feed validator entry points.

**Strategy for Arbitrary instances:**

```haskell
-- In TestHelpers.hs, add:
import Test.QuickCheck (Arbitrary(..), Gen, choose, elements, listOf1, vectorOf)
import Data.String (fromString)

-- Arbitrary for BuiltinByteString: generate via fromString over printable chars
newtype ArbBBS = ArbBBS { unArbBBS :: BuiltinByteString }
instance Arbitrary ArbBBS where
  arbitrary = ArbBBS . fromString <$> listOf1 (elements ['a'..'z'])

-- Arbitrary for PubKeyHash: 28-byte bytestring
instance Arbitrary PubKeyHash where
  arbitrary = PubKeyHash . fromString <$> vectorOf 28 (elements ['a'..'f'])

-- Arbitrary for POSIXTime: positive integer
instance Arbitrary POSIXTime where
  arbitrary = fromIntegral . getPositive <$> (arbitrary :: Gen (Positive Integer))

-- Arbitrary for GovernanceDatum via mkGovernanceDatum:
instance Arbitrary GovernanceDatum where
  arbitrary = do
    pid <- (fromString <$> listOf1 (elements ['a'..'z']))
    sub <- arbitrary
    yc  <- getNonNegative <$> arbitrary
    nc  <- getNonNegative <$> arbitrary
    ac  <- getNonNegative <$> arbitrary
    dl  <- arbitrary
    case mkGovernanceDatum pid sub (ActionUpdateFeeAmount 100) [] yc nc ac dl ProposalInProgress of
      P.Right gd -> return gd
      P.Left _   -> return (mkTestGovernanceDatum "prop" sub (ActionUpdateFeeAmount 100) [] 0 0 0 oneWeekMs ProposalInProgress)
```

**Datum integrity property pattern (using full validator entry point):**

```haskell
-- Property: vote transaction with mutated gdSubmittedBy is rejected
prop_votePreservesSubmitter :: GovernanceDatum -> PubKeyHash -> Bool
prop_votePreservesSubmitter inputGov badSubmitter =
  -- Build a vote ctx where output has mutated submitter
  let outputGov = buildVoteOutput inputGov badSubmitter  -- mutate submittedBy
      ctx = buildDaoVoteCtx inputGov outputGov [alice] alice
  in case try (evaluate (DaoGovernance.untypedSpendValidator
                          (toBuiltinData testIdNftPolicy)
                          (toBuiltinData ctx))) of
       -- Exception means validator rejected (PASS when submitter mutated)
       Left (_ :: SomeException) -> True
       Right _ -> gdSubmittedBy inputGov P.== badSubmitter  -- only pass if unchanged
```

Note: The `try/evaluate` approach from `testAttackRejected2` can be adapted into property-returning Bool functions by using `unsafePerformIO` OR by structuring as HUnit tests with `testProperty` wrapping. The cleanest approach for properties is to use `ioProperty` from QuickCheck:

```haskell
import Test.QuickCheck (ioProperty, Property)

prop_votePreservesSubmitter :: GovernanceDatum -> PubKeyHash -> Property
prop_votePreservesSubmitter inputGov badSubmitter = ioProperty $ do
  result <- try (evaluate (DaoGovernance.untypedSpendValidator ...))
  return $ case result of
    Left (_ :: SomeException) -> True   -- rejected as expected
    Right _ -> False                     -- should have been rejected
```

### Pattern 4: Haddock Documentation Style

Existing style established in `Core.hs` and `Common.hs`:

```haskell
-- Module header (already present in all files, just needs expansion):
{- |
Module      : Carbonica.Validators.Marketplace
Description : Marketplace validator for trading COT tokens
License     : Apache-2.0
-}

-- Function Haddock (purpose + params, no usage examples per decision):
-- | Find an input UTxO by its output reference.
--
-- Returns 'P.Nothing' if no input matches the given reference.
{-# INLINEABLE findInputByOutRef #-}
findInputByOutRef :: [TxInInfo] -> TxOutRef -> P.Maybe TxInInfo

-- Exported type field documentation (record syntax):
-- | Marketplace listing datum
data MarketplaceDatum = MarketplaceDatum
  { mdOwner    :: Wallet    -- ^ Seller's wallet
  , mdAmount   :: Integer   -- ^ Sale price in lovelace
  , mdCotPolicy :: CurrencySymbol  -- ^ COT token policy ID
  , mdCotToken  :: TokenName       -- ^ COT token name
  , mdCotQty    :: Integer         -- ^ Quantity offered
  }
```

### Anti-Patterns to Avoid

- **Converting error registry comment blocks to Haddock:** The `{- ══ ERROR CODE REGISTRY ... ══ -}` blocks must stay as plain comments per the decision. Converting them to Haddock would create confusing double-documentation.
- **Using `unsafePerformIO` in property tests:** Use `ioProperty` instead to stay in the IO monad safely.
- **Building ProjectDatum with raw constructor:** The constructor is unexported. Always use `mkProjectDatum` or `mkTestProjectDatum`. Arbitrary instances must go through smart constructors.
- **Assuming Marketplace has 2-arg untyped validator:** It has 3 args (`idNftPolicy -> royaltyAddr -> ctx`), confirmed from source. Use `testAttackRejected3`.
- **Roundtrip testing for opaque datums:** `toBuiltinData`/`fromBuiltinData` roundtrip tests require importing the internal constructor or comparing via getters. Since constructors are unexported, compare using getter functions, not structural equality.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Random BuiltinByteString | Custom encoder | `fromString` over `['a'..'z']` list | Already works via OverloadedStrings in test environment |
| Random PubKeyHash | Fixed-set enum | QuickCheck Arbitrary with vectorOf 28 chars | More thorough coverage |
| Property that needs IO (try/evaluate) | unsafePerformIO | `ioProperty :: IO Property -> Property` from QuickCheck | Safe, composable |
| New builder for Marketplace context | Separate helper module | Add `mkMarketplaceCtx` to TestHelpers.hs | Keeps all builders co-located |
| Haddock for internal/unexported functions | Skip undocumented functions | Document only exported functions per module's export list | Per QUAL-03 decision scope |

**Key insight:** The `ioProperty` function from `Test.QuickCheck` is the bridge between the IO-based `try/evaluate` exception-catching pattern (used in HUnit attack tests) and QuickCheck's pure property model. Without it, datum integrity properties would require either `unsafePerformIO` or a structural redesign.

---

## Common Pitfalls

### Pitfall 1: Marketplace royaltyAddr parameter confusion
**What goes wrong:** Passing `testIdNftPolicy` as the second argument to `Marketplace.untypedValidator` (pattern-matching the 3-arg ProjectVault/CotPolicy style) instead of a `PubKeyHash`.
**Why it happens:** Marketplace's second param is `royaltyAddr :: PubKeyHash`, not a policy. Its signature is `idNftPolicy -> royaltyAddr -> ctx`.
**How to avoid:** Always serialize with `toBuiltinData (royaltyAddr :: PubKeyHash)` as the second argument. Use a `testRoyaltyAddr :: PubKeyHash` test constant.
**Warning signs:** Tests that pass compilation but the validator always returns `MKE004` (platform not paid), because royaltyAddr decoded wrongly.

### Pitfall 2: MED-04 DaoGovernance vote context requires valid range
**What goes wrong:** Forgetting that `validateVote` checks `before deadline validRange` -- the TxInfo valid range must start before the deadline. Using `mkTxInfo` (which uses `always`) is safe, but the vote must be before deadline.
**Why it happens:** The HIGH-04 tests already use `mkTxInfoWithRange (from (oneWeekMs + 1000001))` for post-deadline contexts. MED-04 vote tests need pre-deadline range (use `always` or an interval starting before `oneWeekMs`).
**How to avoid:** Use `mkTxInfo` (defaults to `always`) for vote tests. Reserve `mkTxInfoWithRange` for execute/reject tests.

### Pitfall 3: GovernanceDatum Arbitrary instance hitting mkGovernanceDatum validation
**What goes wrong:** Generating `yesCount < 0` or empty `proposalId` causes `P.Left` from `mkGovernanceDatum`, and the fallback test datum masks the generation failure.
**Why it happens:** `mkGovernanceDatum` validates: non-empty proposalId, non-negative yesCount/noCount/abstainCount.
**How to avoid:** Use `NonNegative Integer` from QuickCheck for all count fields. Use `listOf1` (non-empty list) for proposalId bytes, then convert to `BuiltinByteString`.

### Pitfall 4: mkProjectDatum rejects zero cotAmount
**What goes wrong:** `mkProjectDatum` returns `Left (InvalidCotAmount 0)` if `cotAmt = CotAmount 0` because it checks `cotValue cotAmt <= 0`.
**Why it happens:** `CotAmount` allows zero (via `mkCotAmount`), but `mkProjectDatum` requires strictly positive COT.
**How to avoid:** Use `Positive Integer` for cotAmount in ProjectDatum Arbitrary instances. The COT amount field in ProjectDatum is independently constrained from CotAmount itself.

### Pitfall 5: ioProperty test with exception catching requires SomeException import
**What goes wrong:** Ambiguous type for `try` without explicit type annotation on the exception.
**Why it happens:** `try` is polymorphic; GHC needs the exception type.
**How to avoid:** Always annotate: `result <- try (evaluate ...) :: IO (Either SomeException P.BuiltinUnit)`.

### Pitfall 6: Haddock on INLINEABLE functions requires pragma AFTER the Haddock comment
**What goes wrong:** Placing `{-# INLINEABLE f #-}` before the Haddock comment means the doc comment doesn't attach to the function.
**Why it happens:** Haddock attaches the `-- |` comment to the immediately following declaration. A pragma between the comment and the function breaks attachment in some GHC versions.
**How to avoid:** Place Haddock comment, then pragma, then type signature:
```haskell
-- | Find an input by output reference.
{-# INLINEABLE findInputByOutRef #-}
findInputByOutRef :: [TxInInfo] -> TxOutRef -> P.Maybe TxInInfo
```
This matches the existing pattern in `Core.hs` (e.g., `mkLovelace`).

---

## Code Examples

Verified from source reading:

### MED-01 exploit: buy with empty UTxO (MKE007)
```haskell
-- Source: Marketplace.hs validateBuy, cotVerified check
-- Attack: create a MarketplaceDatum claiming 100 COT but spend a UTxO with 0 COT
med01a_buyWithEmptyUtxo :: TestTree
med01a_buyWithEmptyUtxo =
  let cotPolicy = CurrencySymbol "test_cot_policy_0000000000000000"
      cotToken  = TokenName "CARBON_COT"
      datum     = MarketplaceDatum (Wallet alice Nothing) 10_000_000 cotPolicy cotToken 100
      -- UTxO holds only ADA, no COT
      utxoVal   = singleton (CurrencySymbol "") (TokenName "") 2_000_000
      royalty   = (10_000_000 * 5) `div` 100     -- 500_000, but P.max 1 applies
      payout    = 10_000_000 - royalty
      outputs   = [ mkPkhTxOut alice (lovelaceSingleton payout)
                  , mkPkhTxOut testRoyaltyAddr (lovelaceSingleton royalty)
                  , mkPkhTxOut bob (singleton cotPolicy cotToken 100) ]
      ctx       = mkMarketplaceCtx [bob, alice] datum MktBuy utxoVal outputs
  in testAttackRejected3
       "MED-01a: buy with UTxO missing COT (MKE007)"
       Marketplace.untypedValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData testRoyaltyAddr)
       (toBuiltinData ctx)
```

### MED-02 exploit: zero price listing (MKE008)
```haskell
-- Source: Marketplace.hs validateBuy, pricePositive check (MKE008 checked first)
med02a_zeroPriceBuy :: TestTree
med02a_zeroPriceBuy =
  let cotPolicy = CurrencySymbol "test_cot_policy_0000000000000000"
      cotToken  = TokenName "CARBON_COT"
      -- Zero price datum
      datum     = MarketplaceDatum (Wallet alice Nothing) 0 cotPolicy cotToken 100
      utxoVal   = singleton cotPolicy cotToken 100
      ctx       = mkMarketplaceCtx [bob, alice] datum MktBuy utxoVal []
  in testAttackRejected3
       "MED-02a: zero price buy rejected (MKE008)"
       Marketplace.untypedValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData testRoyaltyAddr)
       (toBuiltinData ctx)
```

### MED-03 exploit: royalty rounding evasion (MKE003/MKE004)
```haskell
-- Source: Marketplace.hs royaltyAmount = P.max 1 ((salePrice * 5) `P.divide` 100)
-- Attack: price = 1 lovelace; integer division gives 0 royalty; P.max 1 forces 1 lovelace minimum
-- Attacker tries to pay 0 royalty (old behavior before fix)
med03a_royaltyRoundingFloor :: TestTree
med03a_royaltyRoundingFloor =
  let cotPolicy = CurrencySymbol "test_cot_policy_0000000000000000"
      cotToken  = TokenName "CARBON_COT"
      datum     = MarketplaceDatum (Wallet alice Nothing) 1 cotPolicy cotToken 1
      utxoVal   = singleton cotPolicy cotToken 1
      -- Try to pay 0 royalty (attacker omits platform payment entirely)
      outputs   = [ mkPkhTxOut alice (lovelaceSingleton 1)
                  , mkPkhTxOut bob (singleton cotPolicy cotToken 1) ]
      ctx       = mkMarketplaceCtx [bob, alice] datum MktBuy utxoVal outputs
  in testAttackRejected3
       "MED-03a: royalty rounding evasion (MKE004, P.max 1 enforced)"
       Marketplace.untypedValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData testRoyaltyAddr)
       (toBuiltinData ctx)
```

### MED-04 exploit: vote with mutated gdSubmittedBy (DGE019)
```haskell
-- Source: DaoGovernance.hs validateVote, checks DGE019/020/021
-- MED-04: output datum has gdSubmittedBy changed to eve
med04a_submitterMutated :: TestTree
med04a_submitterMutated =
  let inputGov = mkTestGovernanceDatum
        "test_proposal_001" alice (ActionUpdateFeeAmount 200_000_000)
        [VoteRecord alice VoterPending, VoteRecord bob VoterPending, VoteRecord charlie VoterPending]
        0 0 0 (oneWeekMs P.+ 1_000_000) ProposalInProgress
      -- Output: alice votes yes BUT gdSubmittedBy changed to eve (attack)
      badOutputGov = mkTestGovernanceDatum
        "test_proposal_001" eve (ActionUpdateFeeAmount 200_000_000)  -- mutated submitter
        [VoteRecord alice (VoterVoted VoteYes), VoteRecord bob VoterPending, VoteRecord charlie VoterPending]
        1 0 0 (oneWeekMs P.+ 1_000_000) ProposalInProgress
      ctx = buildDaoVoteSpendCtx [alice] inputGov badOutputGov
  in testAttackRejected2
       "MED-04a: gdSubmittedBy mutated during vote (DGE019)"
       DaoGovernance.untypedSpendValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData ctx)
```

### Smart constructor properties for mkMultisig
```haskell
-- Source: Config.hs mkMultisig invariants
-- Required > 0, Required <= length signers, signers non-empty
multisigProperties :: TestTree
multisigProperties = testGroup "Multisig Smart Constructor Properties"
  [ testProperty "Valid multisig accepted"           prop_multisigAcceptsValid
  , testProperty "Empty signers rejected"            prop_multisigRejectsEmpty
  , testProperty "Zero required rejected"            prop_multisigRejectsZeroRequired
  , testProperty "Required > signers rejected"       prop_multisigRejectsExcessRequired
  , testProperty "Required = signers accepted"       prop_multisigAcceptsEqualRequired
  ]

prop_multisigAcceptsValid :: NonEmptyList PubKeyHash -> Positive Integer -> Bool
prop_multisigAcceptsValid (NonEmpty signers) (Positive r) =
  let required = (r `mod` fromIntegral (length signers)) + 1
  in case mkMultisig required signers of
       P.Right ms -> msRequired ms P.== required
       P.Left _   -> False
```

### Datum integrity property using ioProperty
```haskell
-- Source: Test.QuickCheck (ioProperty), Control.Exception (try, evaluate)
prop_votePreservesDeadline :: GovernanceDatum -> POSIXTime -> Property
prop_votePreservesDeadline inputGov badDeadline = ioProperty $ do
  -- Build vote ctx where output mutates gdDeadline
  let badOutputGov = buildVoteOutputWithBadDeadline inputGov badDeadline
      ctx = buildValidVoteCtx inputGov badOutputGov [alice]
  result <- try (evaluate
    (DaoGovernance.untypedSpendValidator
      (toBuiltinData testIdNftPolicy)
      (toBuiltinData ctx)))
    :: IO (Either SomeException P.BuiltinUnit)
  return $ case result of
    Left _  -> True   -- rejected as expected
    Right _ -> gdDeadline inputGov P.== badDeadline
```

---

## Smart Constructor Invariants Reference

Complete mapping for TEST-04 — what properties to test per constructor:

### mkCetAmount (mirrors mkCotAmount exactly)
- Positive amounts: accepted, value preserved (`cetValue`)
- Zero: accepted
- Negative: rejected (`NegativeQuantity`)
- Roundtrip: `mkCetAmount n >>= \c -> Right (cetValue c) == Right n` for n >= 0

### mkPercentage
- Range `[0, 100]` accepted
- Boundary: 0 and 100 both accepted
- `101`, negative: rejected (`InvalidPercentage`)
- Roundtrip: `mkPercentage n >>= \p -> Right (getPercentage p) == Right n` for n in [0,100]
  - Note: `Percentage` unwrapped via `Percentage n -> n` or newtype accessor (no exported getter — use pattern match in test)

### mkMultisig
- Non-empty signers, `1 <= required <= length signers`: accepted
- Empty signers list: rejected (`NoSigners`)
- `required <= 0`: rejected (`InvalidRequired`)
- `required > length signers`: rejected (`InvalidRequired`)
- Roundtrip: `msRequired` and `msSigners` getters preserve input values

### mkConfigDatum
- Valid inputs: accepted
- `feeAmt <= 0`: rejected (`InvalidFeeAmount`)
- Empty categories list: rejected (`NoCategoriesProvided`)
- Invalid multisig: rejected (`InvalidMultisigConfig`)
- Roundtrip: `cdFeesAmount`, `cdCategories`, `cdMultisig`, etc. preserve input values

### mkProjectDatum
- Valid inputs: accepted
- Empty name: rejected (`EmptyProjectName`)
- `cotAmt <= 0` (using `CotAmount 0`): rejected (`InvalidCotAmount`)
- `yesVotes < 0` or `noVotes < 0`: rejected (`NegativeVoteCount`)
- Roundtrip: all getters preserve input values

### mkGovernanceDatum
- Valid inputs: accepted
- Empty proposalId: rejected (`EmptyProposalId`)
- `yesCount < 0`, `noCount < 0`, `abstainCount < 0`: rejected (`NegativeVoteCount`)
- Roundtrip: all getters (`gdProposalId`, `gdSubmittedBy`, `gdAction`, etc.) preserve input values

---

## Datum Integrity Invariants Reference

Complete mapping for TEST-05:

### Invariant 1: ProjectVault vote preserves non-vote fields
**Validator:** `ProjectVault.untypedValidator` (3-arg: idNftPolicy -> projectPolicy -> ctx)
**Checked fields (vote must preserve):** `pdProjectName`, `pdCategory`, `pdDeveloper`, `pdCotAmount`, `pdDescription`, `pdStatus`, `pdSubmittedAt`
**Fields that DO change:** `pdYesVotes` (+1), `pdNoVotes`, `pdVoters` (voter appended)
**Error codes:** PVE016 (developer), PVE017 (COT amount) -- individual field checks in Phase 2 patch
**Property strategy:** Generate valid ProjectDatum via Arbitrary, build a vote output that mutates one non-vote field, confirm rejection.

### Invariant 2: DaoGovernance vote preserves non-vote fields
**Validator:** `DaoGovernance.untypedSpendValidator` (2-arg: idNftPolicy -> ctx)
**Checked fields (must be preserved):** `gdSubmittedBy` (DGE019), `gdAction` (DGE020), `gdDeadline` (DGE021)
**Fields that DO change:** `gdVotes` (one VoteRecord updated), `gdYesCount`/`gdNoCount`/`gdAbstainCount` (+1), `gdState` stays InProgress
**Property strategy:** 3 separate property groups, one per invariant field. Mutate one field at a time, verify rejection.

### Invariant 3: verifyConfigUpdate preserves non-target fields
**Validator:** `DaoGovernance.untypedSpendValidator` (Execute redeemer)
**Logic:** `verifyConfigUpdate` in DaoGovernance checks that only the ProposalAction's target field changes.
**Error code:** DGE015
**Property strategy:** For each ProposalAction case (ActionUpdateFeeAmount, ActionAddSigner, etc.), generate a random ConfigDatum mutation in a non-target field and verify Execute is rejected. The CRIT-03 attack tests already show `mkDaoExecuteCtx` as the builder.

---

## Module Integration Points

### smartcontracts.cabal change required
```cabal
-- In test-suite carbonica-tests, other-modules, add:
Test.Carbonica.Properties.DatumIntegrity
```

### test/Main.hs change required
```haskell
import Test.Carbonica.Properties.DatumIntegrity (datumIntegrityTests)

main = defaultMain $ testGroup "Carbonica Tests"
  [ typeTests
  , validatorTests
  , commonTests
  , propertyTests           -- includes 6 new constructor groups
  , attackScenarioTests     -- includes med01Tests through med04Tests
  , datumIntegrityTests     -- NEW
  ]
```
(By-type grouping preferred per discretion: types tests, then validators tests, then properties, then attack scenarios, then datum integrity. This keeps property tests together rather than mixing with attack scenarios.)

### test/Test/Carbonica/AttackScenarios.hs changes
- Add `import qualified Carbonica.Validators.Marketplace as Marketplace`
- Add `import Carbonica.Validators.Marketplace (MarketplaceDatum(..), MarketplaceRedeemer(..), Wallet(..))`
- Add `testRoyaltyAddr :: PubKeyHash` constant
- Add `mkMarketplaceCtx` helper
- Add `med01Tests` through `med04Tests` groups
- Update `attackScenarioTests` to include new groups

### test/Test/Carbonica/Properties/SmartConstructors.hs changes
- Add imports for: `mkCetAmount`, `cetValue`, `mkPercentage`, `mkMultisig`, `msRequired`, `msSigners`, `mkConfigDatum`, `cdFeesAmount`, `cdCategories`, `cdMultisig`, `mkProjectDatum`, `pdProjectName`, `pdCotAmount`, `mkGovernanceDatum`, `gdProposalId`
- Update `propertyTests` to include 6 new groups

### test/Test/Carbonica/TestHelpers.hs changes
- Add Arbitrary instances for: `PubKeyHash`, `POSIXTime`, `GovernanceDatum`, `ProjectDatum` (or newtype wrappers)
- Add `mkMarketplaceCtx` or let AttackScenarios.hs define it locally (local is cleaner given it's attack-test-specific)
- Export `testRoyaltyAddr` constant

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| HUnit tests only | HUnit + QuickCheck via tasty-quickcheck | Phase 1 | QuickCheck available for all new property tests |
| ScriptContext manual construction | TestHelpers.hs builder functions | Phase 3 | All attack tests use builders, not raw records |
| No attack tests | Full untyped entry point attack tests | Phase 3 (CRIT), Phase 4 (HIGH) | MED tests follow same proven pattern |

---

## Open Questions

1. **Percentage accessor in SmartConstructors.hs**
   - What we know: `Percentage` is a newtype with `deriving newtype (Ord)` but no exported getter function in `Core.hs`
   - What's unclear: Test code will need to unwrap `Percentage n -> n`. Pattern matching on the constructor should work since `Percentage(..)` is exported from Core.hs (it's in the `Lovelace(..)` style export list)
   - Recommendation: Pattern match directly: `case mkPercentage n of P.Right (Percentage v) -> v P.== n`

2. **Arbitrary for ProposalAction in GovernanceDatum**
   - What we know: ProposalAction has 9 constructors, some with PubKeyHash args, some with Integer, some with BuiltinByteString
   - What's unclear: Full Arbitrary instance is verbose; minimal version using fixed action is sufficient per CONTEXT.md ("minimal Arbitrary instances")
   - Recommendation: Use `ActionUpdateFeeAmount 100_000_000` as the fixed action in GovernanceDatum Arbitrary instances. This keeps the Arbitrary instances minimal per the decision while still exercising the datum integrity checks.

3. **mkProjectDatum Arbitrary: COT amount constraint**
   - What we know: `mkProjectDatum` requires `cotValue cotAmt > 0`, but takes a `CotAmount` wrapper
   - What's unclear: Whether to unwrap and re-wrap or use `Positive Integer` for the raw amount
   - Recommendation: Use `Positive Integer` for the raw cotAmt, then wrap with `CotAmount`: `CotAmount (getPositive cotAmt)`. Skip the `mkCotAmount` layer since `mkProjectDatum` takes `CotAmount` directly.

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | tasty 1.x + tasty-hunit + tasty-quickcheck + QuickCheck |
| Config file | none (exitcode-stdio-1.0 via cabal test-suite) |
| Quick run command | `cabal test carbonica-tests --test-show-details=direct` |
| Full suite command | `cabal test carbonica-tests --test-show-details=direct` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | File | Exists? |
|--------|----------|-----------|------|---------|
| TEST-03 | MED-01: buy with no COT in UTxO rejected | HUnit attack | AttackScenarios.hs | Wave 0 |
| TEST-03 | MED-01: buy with COT in UTxO accepted | HUnit attack | AttackScenarios.hs | Wave 0 |
| TEST-03 | MED-01: withdraw with no COT accepted (regression) | HUnit attack | AttackScenarios.hs | Wave 0 |
| TEST-03 | MED-02: zero price buy rejected | HUnit attack | AttackScenarios.hs | Wave 0 |
| TEST-03 | MED-02: negative price buy rejected | HUnit attack | AttackScenarios.hs | Wave 0 |
| TEST-03 | MED-02: positive price buy accepted | HUnit attack | AttackScenarios.hs | Wave 0 |
| TEST-03 | MED-03: royalty rounding (price=1) zero royalty attempt rejected | HUnit attack | AttackScenarios.hs | Wave 0 |
| TEST-03 | MED-03: legitimate buy with royalty floor accepted | HUnit attack | AttackScenarios.hs | Wave 0 |
| TEST-03 | MED-04: gdSubmittedBy mutated during vote rejected (DGE019) | HUnit attack | AttackScenarios.hs | Wave 0 |
| TEST-03 | MED-04: gdAction mutated during vote rejected (DGE020) | HUnit attack | AttackScenarios.hs | Wave 0 |
| TEST-03 | MED-04: gdDeadline mutated during vote rejected (DGE021) | HUnit attack | AttackScenarios.hs | Wave 0 |
| TEST-03 | MED-04: valid vote with unchanged non-vote fields accepted | HUnit attack | AttackScenarios.hs | Wave 0 |
| TEST-04 | mkCetAmount: positive/zero/negative/preserve | QuickCheck | SmartConstructors.hs | Wave 0 |
| TEST-04 | mkPercentage: 0/100 boundary, >100/negative rejected | QuickCheck | SmartConstructors.hs | Wave 0 |
| TEST-04 | mkMultisig: valid/empty/zero-required/excess-required | QuickCheck | SmartConstructors.hs | Wave 0 |
| TEST-04 | mkConfigDatum: valid/zero-fee/empty-cats/bad-multisig | QuickCheck | SmartConstructors.hs | Wave 0 |
| TEST-04 | mkProjectDatum: valid/empty-name/zero-cot/neg-votes | QuickCheck | SmartConstructors.hs | Wave 0 |
| TEST-04 | mkGovernanceDatum: valid/empty-id/neg-counts | QuickCheck | SmartConstructors.hs | Wave 0 |
| TEST-05 | ProjectVault vote: non-vote field mutation rejected | QuickCheck property | DatumIntegrity.hs | Wave 0 |
| TEST-05 | DaoGovernance vote: gdSubmittedBy mutation rejected | QuickCheck property | DatumIntegrity.hs | Wave 0 |
| TEST-05 | DaoGovernance vote: gdAction mutation rejected | QuickCheck property | DatumIntegrity.hs | Wave 0 |
| TEST-05 | DaoGovernance vote: gdDeadline mutation rejected | QuickCheck property | DatumIntegrity.hs | Wave 0 |
| TEST-05 | DaoGovernance execute: non-target config field rejected | QuickCheck property | DatumIntegrity.hs | Wave 0 |
| QUAL-03 | All exported functions have Haddock | Manual review | All src/ modules | Wave 0 |

### Sampling Rate
- **Per task commit:** `cabal test carbonica-tests --test-show-details=direct`
- **Per wave merge:** `cabal test carbonica-tests --test-show-details=direct`
- **Phase gate:** Full suite green before `/gsd:verify-work`

**CRITICAL CONSTRAINT:** User runs all builds and tests manually. Never invoke cabal, nix, or WSL commands in executor tasks.

### Wave 0 Gaps
- [ ] `test/Test/Carbonica/Properties/DatumIntegrity.hs` -- covers TEST-05 (NEW file)
- [ ] Arbitrary instances in `test/Test/Carbonica/TestHelpers.hs` -- needed by DatumIntegrity.hs
- [ ] `smartcontracts.cabal` other-modules entry for `Test.Carbonica.Properties.DatumIntegrity`
- [ ] `test/Main.hs` updated import + wiring for `datumIntegrityTests`

*(Existing files `AttackScenarios.hs` and `Properties/SmartConstructors.hs` need extension, not creation)*

---

## Sources

### Primary (HIGH confidence)
- Direct source reading: `src/Carbonica/Validators/Marketplace.hs` -- confirmed 3-arg signature, MED-01/02/03 error codes
- Direct source reading: `src/Carbonica/Validators/DaoGovernance.hs` -- confirmed DGE019/020/021 error codes
- Direct source reading: `src/Carbonica/Types/Core.hs` -- confirmed all smart constructor invariants
- Direct source reading: `src/Carbonica/Types/Config.hs` -- confirmed mkMultisig, mkConfigDatum invariants
- Direct source reading: `src/Carbonica/Types/Project.hs` -- confirmed mkProjectDatum invariants
- Direct source reading: `src/Carbonica/Types/Governance.hs` -- confirmed mkGovernanceDatum invariants
- Direct source reading: `test/Test/Carbonica/AttackScenarios.hs` -- confirmed all attack test patterns
- Direct source reading: `test/Test/Carbonica/TestHelpers.hs` -- confirmed all builder functions and constants
- Direct source reading: `test/Test/Carbonica/Properties/SmartConstructors.hs` -- confirmed property test patterns
- Direct source reading: `smartcontracts.cabal` -- confirmed test-suite structure, no new deps needed
- `.planning/phases/05-comprehensive-testing-and-documentation/05-CONTEXT.md` -- locked decisions

### Secondary (MEDIUM confidence)
- QuickCheck `ioProperty` pattern: standard Haskell idiom for IO-based properties, well-established in ecosystem

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- confirmed from cabal file, all deps already present
- Architecture: HIGH -- confirmed from reading all relevant source files directly
- Pitfalls: HIGH -- derived from actual code invariants and existing test patterns
- Smart constructor invariants: HIGH -- read directly from source implementations
- Datum integrity strategy: MEDIUM -- `ioProperty` approach is idiomatic but Arbitrary instances for PlutusTx types (BuiltinByteString) need careful implementation

**Research date:** 2026-03-13
**Valid until:** 2026-04-13 (stable codebase, no external dependencies changing)
