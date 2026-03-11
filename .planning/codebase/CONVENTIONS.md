# Coding Conventions

**Analysis Date:** 2026-03-11

## Naming Patterns

**Files:**
- `Carbonica.Types.*` for type definitions and domain models
- `Carbonica.Validators.*` for validator/minting policy implementations
- `Carbonica.Utils` for shared utility functions
- Test files mirror source structure: `Test.Carbonica.*`
- PascalCase for module names (standard Haskell)

**Functions:**
- camelCase for all functions: `mkLovelace`, `findInputByNft`, `extractDatum`
- Smart constructors: `mk<TypeName>` prefix (e.g., `mkLovelace`, `mkCotAmount`, `mkConfigDatum`)
- Getter functions: no prefix, simple name (e.g., `cdFeesAmount`, `gdProposalId`, `pdCategory`)
- Validation helpers: `validate<Subject>` or `verify<Subject>` (e.g., `validateMultisig`, `verifyMultisig`)
- Searchers: `find<Subject>` or `get<Subject>` (e.g., `findInputByNft`, `findConfigDatum`, `getTokensForPolicy`)
- Checkers: `has<Subject>` or `is<Subject>` (e.g., `hasTokenInOutputs`, `isCategorySupported`, `isInList`)
- Recursive helpers: `go` for inner recursive functions within a where clause

**Variables:**
- Abbreviated for context clarity: `pkh` (PubKeyHash), `qty` (quantity), `oref` (output reference), `tkn` (token)
- Full names for domain concepts: `lovelaceAmount`, `cotAmount`, `developer`, `signer`
- Pattern-matched values retain their origin names: `Lovelace n`, `CotAmount n` (lowercase binding of newtype value)
- Constructor bindings in case statements: `(cs, tkn, qty)` for flattened value tuples

**Types:**
- PascalCase for all types: `ConfigDatum`, `GovernanceDatum`, `ProjectDatum`
- Newtype wrappers: `Lovelace`, `CotAmount`, `CetAmount`, `Percentage`, `DeveloperAddress`, `FeeAddress`, `ValidatorAddress`
- Sum types for state/actions: `Vote`, `ProposalState`, `ProjectStatus`, `IdNftRedeemer`, `ProjectMintRedeemer`
- Record fields with `cd` prefix for ConfigDatum: `cdFeesAmount`, `cdCategories`, `cdMultisig`
- Record fields with `gd` prefix for GovernanceDatum: `gdProposalId`, `gdYesCount`, `gdDeadline`
- Record fields with `pd` prefix for ProjectDatum: `pdCategory`, `pdDeveloper`

## Code Style

**Formatting:**
- Tool: `stylish-haskell` (configured via `.stylish-haskell.yaml`)
- Make target: `make format` runs `stylish-haskell -i` on all source files
- Column width: Standard (no explicit limit in `.stylish-haskell.yaml`)
- Indentation: 2 spaces (standard Haskell practice)

**Linting:**
- Tool: `hlint` (`.hlint.yaml` present but empty - uses defaults)
- Make target: `make lint` runs `hlint src app`
- Configuration: `.hlint.yaml` is empty, uses HLint default rules

**Language Extensions:**
- Common across all files (defined in `smartcontracts.cabal`):
  - `DataKinds` - Type-level data
  - `DeriveAnyClass` - Derive via any typeclass
  - `DeriveGeneric` - Derive Generic
  - `DerivingStrategies` - Explicit derive strategy
  - `FlexibleContexts` - Allow flexible constraint contexts
  - `FlexibleInstances` - Allow flexible instance declarations
  - `GeneralizedNewtypeDeriving` - Auto-derive for newtypes
  - `ImportQualifiedPost` - Import X qualified (postfix style)
  - `LambdaCase` - `\case` syntax
  - `MultiParamTypeClasses` - Multiple parameter typeclasses
  - `NumericUnderscores` - `1_000_000` numeric literals
  - `OverloadedStrings` - String literals as `BuiltinByteString`
  - `PatternSynonyms` - Custom pattern matching
  - `RecordWildCards` - `{..}` record syntax
  - `ScopedTypeVariables` - Explicit type variables in scope
  - `StandaloneDeriving` - Standalone deriving declarations
  - `Strict` - Strict evaluation by default
  - `TemplateHaskell` - Compile-time metaprogramming (TH)
  - `TypeApplications` - `@TypeName` explicit application
  - `UndecidableInstances` - Allow undecidable instances
  - `ViewPatterns` - `(view -> pat)` syntax
- GHC-specific (not in Plinth builds):
  - `GADTs` - Generalized algebraic data types

**GHC Compiler Options:**
- `-Wall` - All warnings enabled
- Plinth-specific options (in `cabal.project`):
  - `-fobject-code` - Generate object code
  - `-fno-full-laziness` - Disable laziness optimizations
  - `-fno-specialise` - Disable specialization
  - `-fplugin-opt PlutusTx.Plugin:target-version=1.1.0` - Plutus 1.1.0 compatibility

## Import Organization

**Order:**
1. **GHC/stdlib imports**: `import GHC.Generics (Generic)`
2. **PlutusLedgerApi imports**: `import PlutusLedgerApi.V3 (...)`
3. **PlutusTx imports**: `import PlutusTx` and `import qualified PlutusTx.Prelude as P`
4. **Local project imports**: `import Carbonica.Types.*` and `import Carbonica.Validators.*`

**Path Aliases:**
- `import qualified PlutusTx.Prelude as P` - Always qualified to avoid clashes with stdlib Prelude
- `import qualified PlutusTx.Builtins as Builtins` - Used for low-level operations
- `import PlutusLedgerApi.V3` - Unqualified for on-chain ledger types
- `import PlutusLedgerApi.V1.Value` - Unqualified for Value operations

**Post-Import Style:**
- `ImportQualifiedPost` enabled: imports read as `import X qualified` (postfix)
- Used throughout: `import qualified PlutusTx.Prelude as P`

## Error Handling

**Patterns:**
- Plutus on-chain errors use `P.traceError "string"` for fatal failures
- Validator invariant checks use `P.traceIfFalse "message" condition`
- Error codes embedded in trace messages: e.g., `P.traceError "CHE002"`
- Error registry documented at top of validator modules (see `ProjectPolicy.hs` for pattern)
- Smart constructors return `Either error value` (e.g., `Either QuantityError Lovelace`)
- Off-chain code returns `Either ConfigError ConfigDatum`

**Error Code Format:**
- 4-character codes: `<prefix><number>` where prefix is module abbreviation
- Examples: `CHE002` (ConfigHolder Error 2), `PPE001` (ProjectPolicy Error 1)
- Full error registry documented as comment block with cause/fix
- Used in trace messages: `P.traceError "PPE001"`

**Validation Chain Pattern:**
```haskell
P.traceIfFalse "Check 1" condition1
  P.&& P.traceIfFalse "Check 2" condition2
  P.&& P.traceIfFalse "Check 3" condition3
```

## Comments

**When to Comment:**
- Module-level Haddock comments required for all exports (see every file)
- Section separators for logical groupings (see `-------------------- SECTION NAME ----` pattern)
- Complex validation logic explained inline (see `ProjectPolicy.hs` error registry)
- Non-obvious algorithmic choices documented
- One-liner for simple straightforward code preferred over multi-line comments

**Haddock/JSDoc Style:**
- Module header: `{- | Module : ... Description : ... License : ... -}`
- Export documentation above type signature or data declaration
- `-- |` for documentation comments on functions/types
- `-- ^` for documentation of record fields (below field declaration)
- Examples use `==== Examples` header with `>>>` syntax
- Implementation notes use `==== Implementation` header
- Properties/safety notes use `==== Properties` and `==== Security Considerations` headers

**Example from `Core.hs`:**
```haskell
{- |
Module      : Carbonica.Types.Core
Description : Core domain types with compile-time safety guarantees
License     : Apache-2.0

This module provides domain-specific newtypes that prevent common errors...
-}
```

## Function Design

**Size:**
- Small focused functions preferred (most are <20 lines)
- Recursive helpers extracted to where clauses (see `findInputByNft`)
- Validator main functions separated from helper logic

**Parameters:**
- Smart constructors use single parameter functions: `mkLovelace :: Integer -> Either QuantityError Lovelace`
- Validators use record pattern matching in where clauses for ScriptContext
- Helper functions use multiple parameters: `payoutExact :: PubKeyHash -> Integer -> [TxOut] -> Bool`
- Type applications used for clarity: `@<Type>` notation in comments

**Return Values:**
- Smart constructors return `Either error value` for off-chain code
- Validators return `Bool` (True = allow, False = fail with trace)
- Searchers return `Maybe value` (Nothing if not found)
- Checkers return `Bool` for binary conditions

**Inlining Pragmas:**
- `{-# INLINEABLE function #-}` - Applied to ALL on-chain code meant for cross-module optimization
- Enables PlutusTx plugin to inline across module boundaries
- Reduces script size and execution costs
- Located immediately before function definition
- Standard practice throughout: utilities, smart constructors, validators all marked INLINEABLE

## Module Design

**Exports:**
- Explicit export lists in all module headers
- Type constructors sometimes hidden (export type but not constructor)
  - Example: `ConfigDatum` exported, but users must use `mkConfigDatum` smart constructor
  - Pattern: `Carbonica.Types.Config exports `ConfigDatum` (type) but not constructor`
- Smart constructors and getters always exported

**Barrel Files:**
- No barrel files used (no `Carbonica/Types.hs` that re-exports)
- Each module is independently imported: `import Carbonica.Types.Core`

**Record Access:**
- Getter functions used instead of raw field access: `cdFeesAmount config` not `config.cdFeesAmount`
- Prevents direct construction and maintains invariants through smart constructors
- All record types have accessor functions (see `Core.hs`, `Config.hs`, `Governance.hs`)

## PlutusTx Code Generation

**Data Instances:**
- `PlutusTx.makeIsDataSchemaIndexed ''TypeName [('Constructor, index)]` for on-chain serialization
- Or `PlutusTx.unstableMakeIsData ''TypeName` for Scott encoding (more efficient)
- `PlutusTx.makeLift ''TypeName` for Template Haskell lifting to type level

**Deriving Strategies:**
- `deriving stock (Generic, Show, Eq)` - Standard derivations
- `deriving newtype (Ord)` - Newtype derivation for wrapped types
- `deriving anyclass (HasBlueprintDefinition)` - Blueprint generation for documentation
- Never use plain `deriving` without explicit strategy

## Type Safety Patterns

**Newtypes for Domain Concepts:**
- Used extensively to prevent mixing incompatible types
- Examples: `Lovelace`, `CotAmount`, `CetAmount`, `DeveloperAddress`, `FeeAddress`
- Derive `Eq`, `Ord`, `Show` for debugging
- Use newtype in PlutusTx instances for custom behavior (see `Eq` instances in `Core.hs`)

**Smart Constructors:**
- All types that can be invalid must use smart constructors
- Never export raw constructors (export type but not constructor)
- Pattern: `mkLovelace :: Integer -> Either QuantityError Lovelace`
- Invariants checked at construction time

---

*Convention analysis: 2026-03-11*
