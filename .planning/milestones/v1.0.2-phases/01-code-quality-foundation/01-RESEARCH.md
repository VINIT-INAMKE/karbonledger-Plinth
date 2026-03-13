# Phase 1: Code Quality Foundation - Research

**Researched:** 2026-03-11
**Domain:** Haskell/PlutusTx on-chain validator consolidation, error code standardization, Tasty test suite
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Error registry format: Match existing block comment pattern at top of file (code/cause/fix) as used by ConfigHolder and ProjectPolicy
- All 3 missing validators (CetPolicy, UserVault, Marketplace) must get error code prefixes and registries
- Replace all string-message traceError/traceIfFalse calls with error codes
- Fix ALL duplicate helper functions -- not just Utils.hs/Common.hs overlap, but also local duplicates inside individual validators (e.g., local isInList in DaoGovernance)
- Complete deduplication in this phase across the entire codebase
- Replace ALL existing placeholder validator tests (assertBool "..." True) with real tests
- Not just Common.hs helper tests -- all stub tests across Types.hs, Validators.hs, and Properties/ must become real

### Claude's Discretion
- Choose 3-letter prefixes for CetPolicy, UserVault, Marketplace (must not conflict with CPE; follow abbreviation + E pattern)
- Decide whether to delete Utils.hs entirely (merging everything into Common.hs) or keep it for non-validator-specific utilities
- Decide whether to update all imports immediately or lazily as validators are touched
- Organize Common.hs sections based on function relationships and usage patterns
- Decide test approach: helper isolation tests vs ScriptContext builders (considering STATE.md blocker about ScriptContext construction difficulty)
- Decide test module layout (dedicated Common test module vs expanding existing Validators.hs)
- Decide on additional test dependencies beyond current tasty + tasty-hunit + tasty-quickcheck

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| QUAL-01 | Apply best Haskell practices: remove duplicate helper functions, consolidate into Common.hs | Full duplicate inventory below; consolidation strategy documented |
| QUAL-02 | Remove Utils.hs duplication — single source of truth in Validators.Common | Utils.hs unique functions catalogued; merge-and-delete strategy documented |
| QUAL-04 | Ensure consistent use of INLINEABLE pragmas and PlutusTx patterns | INLINEABLE audit below; pattern rules documented |
| LOW-01 | Standardize error handling to error codes across all validators | All string messages catalogued per file; prefix choices recommended |
| TEST-01 | Set up Tasty test suite with tasty-hunit and tasty-quickcheck | Framework already configured; stub replacement strategy documented |
</phase_requirements>

---

## Summary

The Carbonica codebase has a mature, well-structured Common.hs module but has not fully applied it across all validators. Three validators (CetPolicy, UserVault, Marketplace) still use string error messages instead of error codes and contain local helper functions that duplicate Common.hs or Utils.hs logic. Utils.hs contains 8 functions, of which 3 are direct duplicates of Common.hs (under different names) and 5 are unique; these unique functions should migrate into Common.hs. Additionally, several individual validators define local copies of helpers that already exist in Common.hs or Utils.hs.

The test suite has a working Tasty + HUnit + QuickCheck infrastructure. The Properties/SmartConstructors.hs module demonstrates the right pattern for real QuickCheck tests. The Types.hs test module already has real assertions. The problem is Validators.hs: every test case is `assertBool "..." True` — a stub that always passes. These must be replaced with tests that actually invoke the pure helper functions with concrete arguments. Since constructing valid `ScriptContext` values is a known blocker (STATE.md), the Phase 1 test strategy must focus on helper function isolation tests, not full validator integration tests.

**Primary recommendation:** Merge Utils.hs into Common.hs, add new sections for payout helpers, burn helpers, and category helpers; replace all local validator duplicates with Common.hs imports; add error registries and codes to CetPolicy (CEE), UserVault (UVE), and Marketplace (MKE); replace all stub tests with real helper isolation tests.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| tasty | (in cabal) | Test runner and tree | Already configured, main test framework |
| tasty-hunit | (in cabal) | HUnit-style unit assertions | Already configured, used in Types.hs |
| tasty-quickcheck | (in cabal) | QuickCheck property tests | Already configured, used in SmartConstructors.hs |
| QuickCheck | (in cabal) | Generators, properties | Already configured, provides `Positive`, `NonNegative`, `testProperty` |
| plutus-tx | ^>=1.56.0.0 | PlutusTx.Prelude, on-chain primitives | Project standard |
| plutus-ledger-api | ^>=1.56.0.0 | Cardano ledger types | Project standard |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| bytestring | (in cabal) | BuiltinByteString test helpers | Already in test build-depends |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Helper isolation tests | ScriptContext builder tests | ScriptContext construction is non-trivial (confirmed blocker in STATE.md); isolation tests are faster and sufficient for Phase 1 |
| Merge Utils into Common | Keep Utils as separate module | Merging eliminates the split-brain problem; Utils is only 170 lines and all its unique content fits naturally into Common.hs sections |

**No additional installation needed** — all required libraries are already in cabal:
```bash
# Already in smartcontracts.cabal test-suite build-depends:
# tasty, tasty-hunit, tasty-quickcheck, QuickCheck, bytestring, smartcontracts
```

---

## Architecture Patterns

### Recommended Project Structure After Phase 1
```
src/Carbonica/
├── Validators/
│   ├── Common.hs          # Single source of truth (expanded with Utils content)
│   ├── ConfigHolder.hs    # Already correct (CHE codes, Common imports)
│   ├── CotPolicy.hs       # Already correct (CPE codes, Common imports)
│   ├── DaoGovernance.hs   # Already correct (DGE codes, Common imports)
│   ├── ProjectPolicy.hs   # Already correct (PPE codes, Common imports)
│   ├── ProjectVault.hs    # Already correct (PVE codes, Common imports)
│   ├── CetPolicy.hs       # Needs: CEE codes, remove local helpers
│   ├── UserVault.hs       # Needs: UVE codes, remove local helpers
│   ├── Marketplace.hs     # Needs: MKE codes, remove local helpers
│   └── IdentificationNft.hs  # Needs: error codes (minor)
# Utils.hs DELETED after migration
test/
├── Main.hs
└── Test/Carbonica/
    ├── Types.hs               # Already real tests -- keep, possibly extend
    ├── Validators.hs          # Replace all stubs with real helper isolation tests
    ├── Common.hs              # NEW: dedicated Common.hs helper tests
    └── Properties/
        └── SmartConstructors.hs  # Already real -- keep
```

### Pattern 1: Error Code Registry (Established)
**What:** Block comment at the top of each validator file, before `module` declaration, listing all error codes with code/cause/fix structure.
**When to use:** Every validator. ConfigHolder and ProjectPolicy are canonical examples.
**Example:**
```haskell
{- ══════════════════════════════════════════════════════════════════════════
   ERROR CODE REGISTRY - CetPolicy Validator
   ══════════════════════════════════════════════════════════════════════════

   CEE000 - Invalid script context
            Cause: Not a minting context
            Fix: Ensure script is used as minting policy

   CEE001 - Redeemer parse failed
            Cause: Redeemer bytes do not deserialize to CetMintRedeemer
            Fix: Verify redeemer structure matches CetMintRedeemer schema

   CEE002 - Must mint single token type
            Cause: Zero or multiple token names minted under policy
            Fix: Mint exactly one token type per transaction

   CEE003 - Minted quantity does not match redeemer quantity
            Cause: flattenValue qty differs from cet_qty in redeemer
            Fix: Ensure redeemer qty equals actual minted amount

   CEE004 - CET must go to UserVault with matching quantity
            Cause: No output to UserVault script hash with correct qty
            Fix: Route CET output to correct UserVault script address

   CEE005 - Output datum does not match redeemer datum
            Cause: Output datum BuiltinData differs from toBuiltinData cetDatum
            Fix: Ensure output datum is exactly the CetDatum from redeemer

   CEE006 - Must burn (negative quantity)
            Cause: CET burn quantity is not negative
            Fix: CET qty must be < 0 for burn action

   CEE007 - CET quantity does not equal COT quantity
            Cause: cetQtyBurned /= cotQtyBurned (1:1 offset ratio violated)
            Fix: Burn equal amounts of CET and COT

   ══════════════════════════════════════════════════════════════════════════
-}
```

### Pattern 2: INLINEABLE Usage (Established)
**What:** `{-# INLINEABLE #-}` on every function exported from Common.hs and on every top-level validator function. `{-# INLINE #-}` (no `ABLE`) on local `let`-bound definitions within validator bodies.
**When to use:** All on-chain code. Plinth requires cross-module inlining; without INLINEABLE the function cannot be referenced in the TH splice.
**Critical rule:** Functions in the `where` clause of a validator use `{-# INLINEABLE #-}`. Local `let` bindings inside the validator body use `{-# INLINE #-}`. Both patterns are present in the existing codebase and must be maintained consistently.

### Pattern 3: Common.hs Import (Established)
**What:** Validators import only the specific helpers they need from `Carbonica.Validators.Common`.
**When to use:** All validators. Local definitions that duplicate Common.hs content must be removed.
**Example:**
```haskell
import Carbonica.Validators.Common
  ( findInputByNft
  , findOutputByNft
  , findInputByOutRef    -- replaces local findSelfInput in UserVault
  , validateMultisig
  , isInList
  , countMatching
  , extractDatum
  , payoutAtLeast        -- after migration from Utils.hs
  , payoutTokenExact     -- after migration from Utils.hs
  , getTokensForPolicy   -- after migration from Utils.hs
  , sumTokensForPolicy   -- after migration from Utils.hs
  )
```

### Pattern 4: Test Isolation (Phase 1 Approach)
**What:** Test pure helper functions directly with concrete Haskell values, not ScriptContext. Import the function under test, construct inputs using normal Haskell constructors, assert on outputs.
**When to use:** All Phase 1 tests. ScriptContext tests require Phase 3 infrastructure.
**Example:**
```haskell
-- Source: existing SmartConstructors.hs pattern
import Carbonica.Validators.Common (validateMultisig, isInList, countMatching)

testValidateMultisig :: TestTree
testValidateMultisig = testGroup "validateMultisig"
  [ testCase "3 of 5 required: 3 signers pass" $
      let authorized = ["pkh1", "pkh2", "pkh3", "pkh4", "pkh5"]
          signers    = ["pkh1", "pkh2", "pkh3"]
      in assertBool "Should pass with 3/5" (validateMultisig signers authorized 3)

  , testCase "3 of 5 required: 2 signers fail" $
      let authorized = ["pkh1", "pkh2", "pkh3", "pkh4", "pkh5"]
          signers    = ["pkh1", "pkh2"]
      in assertBool "Should fail with 2/5" (not (validateMultisig signers authorized 3))
  ]
```

### Anti-Patterns to Avoid
- **Stub tests (`assertBool "..." True`):** These always pass and test nothing. Every test in Validators.hs is currently this pattern and must be replaced.
- **Monomorphic local isInList:** Utils.hs has `isInList :: PubKeyHash -> [PubKeyHash] -> Bool` (non-generic). Common.hs has the superior generic `isInList :: Eq a => a -> [a] -> Bool`. When removing the Utils version, use the Common.hs generic version.
- **Missing INLINEABLE on where-clause helpers:** Several new helpers added to Common.hs must have `{-# INLINEABLE #-}` or the PlutusTx plugin will reject them at compile time.
- **Keeping `module Carbonica.Utils` in cabal after deletion:** If Utils.hs is deleted, `exposed-modules` in smartcontracts.cabal must remove `Carbonica.Utils` or the build will fail.
- **Using string messages for traceError in new code:** Always use error codes. The pattern is `P.traceError "CEE000"` not `P.traceError "CET: Expected minting context"`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Multisig verification | Local countMatchingSigners | `validateMultisig` from Common.hs | ProjectVault, Utils.hs both have it -- already solved |
| Input searching by outref | Local findSelfInput | `findInputByOutRef` from Common.hs | Already exists in Common.hs |
| Datum extraction | Local case-on-txOutDatum | `extractDatum` from Common.hs | Generic, handles all OutputDatum cases |
| Token filtering by policy | Local list comprehension getTokensForPolicy | Migrate from Utils.hs to Common.hs | Identical logic in 4 validators |
| Payout verification | Local payoutAtLeast | Migrate from Utils.hs to Common.hs | Utils.hs already has the right implementation |
| isInList check | Local type-specific version | `isInList` from Common.hs | Generic version covers all cases |
| QuickCheck generators for PubKeyHash | Custom Arbitrary instances | Wrap Integer in `newtype` or use `BS.pack` with word8 list | PubKeyHash is BuiltinByteString-backed; simple wrapping works |

**Key insight:** The duplication problem exists because validators were written before Common.hs was fully populated. The pattern of "copy-paste helper locally" is endemic but all copies are identical to their Common.hs counterparts. The solution is mechanical import substitution, not redesign.

---

## Common Pitfalls

### Pitfall 1: Removing INLINEABLE from Migrated Functions
**What goes wrong:** A function migrated from Utils.hs or a validator's `where` clause to Common.hs loses its `{-# INLINEABLE #-}` pragma. At compile time `cabal build` fails with a PlutusTx plugin error: "GHC.Core.Opt.ConstantFold: can't inline...".
**Why it happens:** INLINEABLE must be present on the definition site in Common.hs. The pragma on the call site does not propagate.
**How to avoid:** Every function added to Common.hs must have `{-# INLINEABLE functionName #-}` immediately above it.
**Warning signs:** Build error mentioning `-fno-ignore-interface-pragmas` or PlutusTx plugin.

### Pitfall 2: Duplicate Name Collision After Import Substitution
**What goes wrong:** A validator imports `isInList` from Common.hs but also has a local `isInList` in its `where` clause. GHC reports an ambiguous name error.
**Why it happens:** Both definitions are in scope with the same name.
**How to avoid:** When adding a Common.hs import for a function, remove the local definition simultaneously in the same commit. The UserVault, Marketplace, and ProjectVault validators all have this risk.
**Warning signs:** `Ambiguous occurrence 'isInList'` GHC error.

### Pitfall 3: Utils.hs Import Breakage After Deletion
**What goes wrong:** Utils.hs is deleted but `CotPolicy.hs`, `Marketplace.hs`, or `IdentificationNft.hs` still has `import Carbonica.Utils`. Build fails.
**Why it happens:** Three validators import from Utils.hs: `tokenNameFromOref` (CotPolicy, IdentificationNft) and `payoutAtLeast`/`payoutExact` (Marketplace).
**How to avoid:** Before deleting Utils.hs, update every `import Carbonica.Utils` to point to `Carbonica.Validators.Common` (after migrating the functions). Also remove `Carbonica.Utils` from cabal `exposed-modules`.
**Warning signs:** `Could not find module 'Carbonica.Utils'` build error.

### Pitfall 4: Utils.isInList Type Mismatch
**What goes wrong:** Utils.hs `isInList` is typed `PubKeyHash -> [PubKeyHash] -> Bool`. Common.hs `isInList` is typed `Eq a => a -> [a] -> Bool`. After switching, call sites that relied on the monomorphic version continue to work (the generic version is strictly more general), but the `where` clause local copies in validators are also typed specifically for PubKeyHash. Removing a local copy and using the Common.hs import is safe but the import must be added explicitly.
**Why it happens:** Different type signatures for the same logical function.
**How to avoid:** Use Common.hs `isInList` everywhere. It is a strict superset.

### Pitfall 5: Test Module Not Registered in cabal
**What goes wrong:** A new test module `Test.Carbonica.Common` is created and imported in Main.hs but not listed in `other-modules` in `smartcontracts.cabal`. Build fails with `Could not find module`.
**Why it happens:** Cabal requires explicit module registration.
**How to avoid:** When adding new test modules, update `other-modules` in the `test-suite carbonica-tests` stanza.
**Warning signs:** Module not found error only in test compilation.

### Pitfall 6: Error Code Prefix Conflicts
**What goes wrong:** Two validators end up with the same 3-letter prefix, making error codes ambiguous in logs.
**Why it happens:** Not checking existing prefixes before choosing new ones.
**How to avoid:** Existing prefixes: CHE (ConfigHolder), DGE (DaoGovernance), PVE (ProjectVault), PPE (ProjectPolicy), CPE (CotPolicy). New ones must not conflict. Recommended new prefixes: CEE (CetPolicy), UVE (UserVault), MKE (Marketplace), INE (IdentificationNft).

---

## Code Examples

### Example 1: Common.hs New Section — Payout Helpers (migrate from Utils.hs)
```haskell
-- Source: src/Carbonica/Utils.hs lines 49-97 (migrate verbatim, add INLINEABLE)
--------------------------------------------------------------------------------
-- PAYOUT VERIFICATION (shared across validators)
--------------------------------------------------------------------------------

{-# INLINEABLE payoutExact #-}
payoutExact :: PubKeyHash -> Integer -> [TxOut] -> Bool
payoutExact _ _ [] = False
payoutExact pkh expectedAmt (o:os) =
  let addr = txOutAddress o
      matchesPkh = case addressCredential addr of
        PubKeyCredential pk -> pk P.== pkh
        _                   -> False
      Lovelace lovelaceAmt = lovelaceValueOf (txOutValue o)
  in if matchesPkh P.&& lovelaceAmt P.== expectedAmt
       then True
       else payoutExact pkh expectedAmt os

{-# INLINEABLE payoutAtLeast #-}
payoutAtLeast :: PubKeyHash -> Integer -> [TxOut] -> Bool
-- (identical to Utils.hs, migrate verbatim)

{-# INLINEABLE payoutTokenExact #-}
payoutTokenExact :: PubKeyHash -> CurrencySymbol -> TokenName -> Integer -> [TxOut] -> Bool
-- (identical to Utils.hs, migrate verbatim)
```

### Example 2: Common.hs New Section — Token Policy Helpers (migrate from Utils.hs)
```haskell
-- Source: src/Carbonica/Utils.hs lines 99-134 (migrate verbatim)
--------------------------------------------------------------------------------
-- TOKEN POLICY HELPERS (parity with Utils.hs getTokensForPolicy pattern)
--------------------------------------------------------------------------------

{-# INLINEABLE getTokensForPolicy #-}
-- | Get all tokens for a specific policy from a flattened Value
-- Used in CetPolicy, UserVault, ProjectPolicy, CotPolicy (all local copies identical)
getTokensForPolicy :: Value -> CurrencySymbol -> [(TokenName, Integer)]
getTokensForPolicy val policy =
  [(tkn, qty) | (cs, tkn, qty) <- flattenValue val, cs P.== policy]

{-# INLINEABLE mustBurnLessThan0 #-}
mustBurnLessThan0 :: Value -> CurrencySymbol -> Bool
mustBurnLessThan0 val policy =
  let tokens = getTokensForPolicy val policy
  in allNegative tokens
```

### Example 3: CetPolicy Error Code Replacement Pattern
```haskell
-- BEFORE (string messages):
typedValidator userVaultHash cotPolicy ctx = case scriptInfo of
  MintingScript ownPolicy -> case redeemer of
    CetMintWithDatum cetDatum   -> mintCheck userVaultHash ownPolicy cetDatum
    CetBurnWithCot _burnRedeemer -> burnCheck ownPolicy cotPolicy
  _ -> P.traceError "CET: Expected minting context"
  where
    redeemer = case PlutusTx.fromBuiltinData (getRedeemer rawRedeemer) of
      P.Nothing -> P.traceError "CET: Failed to parse redeemer"
      P.Just r  -> r

-- AFTER (error codes):
typedValidator userVaultHash cotPolicy ctx = case scriptInfo of
  MintingScript ownPolicy -> case redeemer of
    CetMintWithDatum cetDatum    -> mintCheck userVaultHash ownPolicy cetDatum
    CetBurnWithCot _burnRedeemer -> burnCheck ownPolicy cotPolicy
  _ -> P.traceError "CEE000"
  where
    redeemer = case PlutusTx.fromBuiltinData (getRedeemer rawRedeemer) of
      P.Nothing -> P.traceError "CEE001"
      P.Just r  -> r
```

### Example 4: Replacing Stub Tests with Real Isolation Tests
```haskell
-- BEFORE (stub, always passes):
testCase "CET burning requires COT burning" $
  assertBool "1:1 offset mechanic" True

-- AFTER (real test of validateMultisig or isInList from Common):
testCase "isInList finds element in list" $
  let xs = ["pkh1", "pkh2", "pkh3"] :: [P.BuiltinByteString]
  in assertBool "pkh1 should be found" (isInList "pkh1" xs)

testCase "isInList returns False for absent element" $
  let xs = ["pkh1", "pkh2", "pkh3"] :: [P.BuiltinByteString]
  in assertBool "pkh9 should not be found" (not (isInList "pkh9" xs))

testCase "validateMultisig passes with sufficient signers" $
  let authorized = ["a", "b", "c", "d", "e"] :: [P.BuiltinByteString]
      signers    = ["a", "b", "c"]           :: [P.BuiltinByteString]
  in assertBool "3/5 should pass" (validateMultisig signers authorized 3)

testCase "validateMultisig fails with insufficient signers" $
  let authorized = ["a", "b", "c", "d", "e"] :: [P.BuiltinByteString]
      signers    = ["a", "b"]                :: [P.BuiltinByteString]
  in assertBool "2/5 should fail" (not (validateMultisig signers authorized 3))
```

### Example 5: ProjectVault Local Helpers to Remove
```haskell
-- ProjectVault.hs where clause -- ALL of these must be removed after Common.hs import:
-- hasSigners         -> replaced by: inline check `not (null signatories)` or new Common helper
-- anySignerInList    -> replaced by: `P.any (\s -> isInList s list) signers` using Common.isInList
-- isInList           -> replaced by: Common.isInList
-- countMatchingSigners -> replaced by: Common.countMatching
-- getTokensBurnedForPolicy -> replaced by: Common.getTokensForPolicy + sum
-- sumQty             -> replaced by: inline or Common helper
-- verifyPaymentToAddress -> replaced by: Common.payoutTokenExact (after migration)
```

---

## Complete Duplicate Function Inventory

### Utils.hs Functions — Disposition

| Function | In Common.hs? | Action |
|----------|--------------|--------|
| `tokenNameFromOref` | No | Migrate to Common.hs (new section: Token Name Generation) |
| `payoutExact` | No | Migrate to Common.hs (new section: Payout Verification) |
| `payoutAtLeast` | No | Migrate to Common.hs (payout section) |
| `payoutTokenExact` | No | Migrate to Common.hs (payout section) |
| `mustBurnLessThan0` | No | Migrate to Common.hs (new section: Burn Verification) |
| `getTokensForPolicy` | No (but 4 identical local copies exist) | Migrate to Common.hs |
| `getTotalForPolicy` | Partial (`sumTokensByPolicy` in Common) | Migrate/unify |
| `allNegative` | No (used by mustBurnLessThan0) | Migrate to Common.hs |
| `sumQty` | No (4 local copies) | Migrate to Common.hs |
| `isCategorySupported` | No (1 local copy in ProjectPolicy) | Migrate to Common.hs |
| `countMatchingSigners` | Yes (`countMatching` in Common.hs) | DELETE from Utils.hs |
| `verifyMultisig` | Yes (`validateMultisig` in Common.hs) | DELETE from Utils.hs |
| `isInList` (monomorphic) | Yes (generic in Common.hs) | DELETE from Utils.hs |

### Local Validator Duplicates — Must Remove

| Validator | Local Function | Common.hs Replacement |
|-----------|---------------|----------------------|
| ProjectVault | `isInList` | `Common.isInList` |
| ProjectVault | `countMatchingSigners` | `Common.countMatching` |
| ProjectVault | `sumQty` | migrate `sumQty` from Utils, or inline |
| ProjectVault | `getTokensBurnedForPolicy` | `Common.getTokensForPolicy` |
| ProjectVault | `verifyPaymentToAddress` | `Common.payoutTokenExact` (after migration) |
| ProjectVault | `anySignerInList` | combine `isInList` + `P.any` |
| ProjectVault | `hasSigners` | `not (null signatories)` inline |
| UserVault | `getTokensForPolicy` | `Common.getTokensForPolicy` (after migration) |
| UserVault | `sumQty` (via getTotalTokensInInputs) | inline/Common |
| UserVault | `findSelfInput` | `Common.findInputByOutRef` |
| CetPolicy | `getTotalMintedForPolicy` | `Common.sumTokensByPolicy` or new helper |
| CetPolicy | `sumQty` | Common.sumQty (after migration) |
| Marketplace | `payoutAtLeast` | `Common.payoutAtLeast` (after migration) |
| Marketplace | `isSignedBy` | `Common.isInList` |
| Marketplace | `hasTokenPayment` | `Common.payoutTokenExact` variant |
| ProjectPolicy | `getTokensForPolicy` | `Common.getTokensForPolicy` (after migration) |
| ProjectPolicy | `isCategorySupported` | `Common.isCategorySupported` (after migration) |
| ProjectPolicy | `allQtysNegative` | `Common.allNegative` (after migration) |
| IdentificationNft | `hasInput` | `Common.findInputByOutRef` (returns Maybe, adapt) |

---

## Error Code Audit — All String Messages to Replace

### CetPolicy.hs (all strings, needs full error registry)
| Location | Current String | New Code |
|----------|---------------|----------|
| `typedValidator` catch-all | `"CET: Expected minting context"` | `CEE000` |
| `redeemer` parse | `"CET: Failed to parse redeemer"` | `CEE001` |
| `mintCheck` traceIfFalse | `"CET: Must mint single token type"` | `CEE002` |
| `mintCheck` traceIfFalse | `"CET: Minted qty /= redeemer qty"` | `CEE003` |
| `mintCheck` traceIfFalse | `"CET: Must go to UserVault with matching qty"` | `CEE004` |
| `mintCheck` traceIfFalse | `"CET: Output datum /= redeemer"` | `CEE005` |
| `mintCheck` internal traceError | `"CET: Expected exactly one token"` | `CEE002` (same condition) |
| `burnCheck` traceIfFalse | `"CET: Must burn (negative qty)"` | `CEE006` |
| `burnCheck` traceIfFalse | `"CET: CET qty /= COT qty"` | `CEE007` |

### UserVault.hs (all strings, needs full error registry)
| Location | Current String | New Code |
|----------|---------------|----------|
| `typedValidator` catch-all | `"UserVault: Expected spending context with datum"` | `UVE000` |
| datum parse | `"UserVault: Failed to parse datum"` | `UVE001` |
| redeemer parse | `"UserVault: Failed to parse redeemer"` | `UVE002` |
| `validateSpend` VaultWithdraw | `"UserVault: CET withdrawal not allowed"` | `UVE003` |
| `validateOffset` traceIfFalse | `"UserVault: Owner must sign"` | `UVE004` |
| `validateOffset` traceIfFalse | `"UserVault: CET qty not negative"` | `UVE005` |
| `validateOffset` traceIfFalse | `"UserVault: CET qty /= COT qty"` | `UVE006` |
| `validateOffset` traceIfFalse | `"UserVault: Remaining tokens not returned"` | `UVE007` |
| `cetTokenData` case | `"UserVault: Expected exactly one CET token"` | `UVE008` |
| `cotTokenData` case | `"UserVault: Expected exactly one COT token"` | `UVE009` |
| `getUserScriptAddress` | `"UserVault: Self input not found"` | `UVE010` |

### Marketplace.hs (all strings, needs full error registry)
| Location | Current String | New Code |
|----------|---------------|----------|
| `typedValidator` catch-all | `"Marketplace: Expected spending context with datum"` | `MKE000` |
| datum parse | `"Marketplace: Failed to parse MarketplaceDatum"` | `MKE001` |
| redeemer parse | `"Marketplace: Failed to parse redeemer"` | `MKE002` |
| `validateBuy` traceIfFalse | `"Marketplace: Seller not paid"` | `MKE003` |
| `validateBuy` traceIfFalse | `"Marketplace: Platform not paid"` | `MKE004` |
| `validateBuy` traceIfFalse | `"Marketplace: Buyer not receiving COT"` | `MKE005` |
| `validateWithdraw` traceIfFalse | `"Marketplace: Owner must sign"` | `MKE006` |

### IdentificationNft.hs (partial, needs minor cleanup)
| Location | Current String | New Code |
|----------|---------------|----------|
| `typedValidator` catch-all | `"Expected minting context"` | `INE000` |
| redeemer parse | `"Failed to parse redeemer"` | `INE001` |
| `mintCheck` traceIfFalse | `"Must consume oref"` | `INE002` |
| `mintCheck` traceIfFalse | `"Must mint exactly 1 token"` | `INE003` |
| `burnCheck` traceIfFalse | `"Must burn exactly 1 token"` | `INE004` |

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| PlutusTx V2 ScriptContext | PlutusTx V3 ScriptContext (PlutusLedgerApi.V3) | plutus-ledger-api 1.x | V3 has `getRedeemer`, `MintValue`, `ScriptInfo` — all already used |
| `flattenValue` returns Value directly | `mintValueMinted` returns `MintValue` needing conversion | V3 | Already handled in all validators via `mintValueMinted (txInfoMint txInfo)` |
| Datum lookup via txInfoData map | Inline datum via `OutputDatum (Datum d)` | V3 | Already handled in extractDatum; datum hash support not needed |

**No deprecated patterns detected in the existing codebase.** All validators already use V3 patterns correctly.

---

## Open Questions

1. **Utils.hs tokenNameFromOref migration: import path**
   - What we know: `tokenNameFromOref` uses `PlutusTx.Builtins` which is not currently imported in Common.hs
   - What's unclear: Whether to add Builtins import to Common.hs or keep tokenNameFromOref in a separate module
   - Recommendation: Add to Common.hs with the necessary import; Common.hs already imports PlutusTx and PlutusLedgerApi

2. **anySignerInList replacement**
   - What we know: ProjectVault uses `anySignerInList signatories list` which is `P.any (\s -> isInList s list) signatories`
   - What's unclear: Whether to add `anySignerInList` to Common.hs or inline it
   - Recommendation: Add `anySignerInList` to Common.hs List Helpers section as it is useful for validators

3. **Test module for Common.hs helpers: add to cabal**
   - What we know: A new `Test.Carbonica.Common` module will need to be added to cabal `other-modules`
   - What's unclear: Whether the planner will choose a separate module or expand existing Validators.hs
   - Recommendation: Separate `Test.Carbonica.Common` module is cleaner; update cabal `other-modules` accordingly

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | tasty + tasty-hunit + tasty-quickcheck (already configured) |
| Config file | smartcontracts.cabal `test-suite carbonica-tests` stanza |
| Quick run command | `cabal test carbonica-tests` |
| Full suite command | `cabal test carbonica-tests --test-show-details=always` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| QUAL-01 | `isInList` from Common.hs finds/misses elements | unit | `cabal test carbonica-tests` | ❌ Wave 0 (Test.Carbonica.Common) |
| QUAL-01 | `validateMultisig` passes with threshold, fails below | unit | `cabal test carbonica-tests` | ❌ Wave 0 |
| QUAL-01 | `countMatching` counts correct intersections | unit | `cabal test carbonica-tests` | ❌ Wave 0 |
| QUAL-01 | `findInputByNft` finds/misses input | unit | `cabal test carbonica-tests` | ❌ Wave 0 |
| QUAL-01 | `extractDatum` parses known datum, returns Nothing for wrong type | unit | `cabal test carbonica-tests` | ❌ Wave 0 |
| QUAL-02 | `payoutAtLeast` / `payoutExact` verify payment correctly | unit | `cabal test carbonica-tests` | ❌ Wave 0 |
| QUAL-02 | `getTokensForPolicy` filters by policy correctly | unit | `cabal test carbonica-tests` | ❌ Wave 0 |
| QUAL-04 | Project compiles with `cabal build` (INLINEABLE check) | build | `cabal build` | ✅ (implicit) |
| LOW-01 | No string error messages remain (code review) | manual-only | N/A | N/A |
| TEST-01 | `cabal test` runs all tests without failure | integration | `cabal test carbonica-tests` | ✅ Main.hs exists |

### Sampling Rate
- **Per task commit:** `cabal build` (fast compilation check)
- **Per wave merge:** `cabal test carbonica-tests`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `test/Test/Carbonica/Common.hs` — covers QUAL-01, QUAL-02 helper isolation tests
- [ ] Add `Test.Carbonica.Common` to `other-modules` in smartcontracts.cabal
- [ ] Replace all `assertBool "..." True` stubs in `test/Test/Carbonica/Validators.hs` with real helper isolation tests

*(Existing test infrastructure: Main.hs, Types.hs, SmartConstructors.hs are real and should remain unchanged.)*

---

## Sources

### Primary (HIGH confidence)
- Direct source code inspection — `src/Carbonica/Validators/Common.hs` (all 326 lines)
- Direct source code inspection — `src/Carbonica/Utils.hs` (all 170 lines)
- Direct source code inspection — all 9 validator files
- Direct source code inspection — `test/` directory (all 4 test files)
- Direct source code inspection — `smartcontracts.cabal`

### Secondary (MEDIUM confidence)
- PlutusTx documentation patterns: INLINEABLE requirement for cross-module TH compilation is established practice across all existing validators

### Tertiary (LOW confidence)
- None required — all findings are from direct codebase inspection

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries already in cabal, no new dependencies needed
- Architecture: HIGH — patterns derived directly from existing well-structured validators (ConfigHolder, ProjectPolicy)
- Duplicate inventory: HIGH — all files read in full, every local helper catalogued
- Error code audit: HIGH — all string messages catalogued per file
- Test approach: HIGH — SmartConstructors.hs provides the exact pattern to follow; ScriptContext blocker confirmed in STATE.md

**Research date:** 2026-03-11
**Valid until:** 2026-06-11 (stable ecosystem; plutus-tx 1.56 API unlikely to change)
