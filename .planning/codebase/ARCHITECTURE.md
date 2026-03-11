# Architecture

**Analysis Date:** 2026-03-11

## Pattern Overview

**Overall:** Multi-validator Plutus V3 smart contract system using a distributed architecture pattern

**Key Characteristics:**
- Each contract responsibility (token minting, vault management, governance) separated into independent validators
- Layered validation: Core types with smart constructors → Common validation helpers → Specific validators
- Configuration centralization: All validators read settings from ConfigDatum at Config Holder
- Type-driven safety: Domain-specific newtypes (Lovelace, CotAmount, CetAmount) prevent categorical errors at compile time
- Scott encoding optimization: Enums use `unstableMakeIsData` for 20-30% smaller on-chain representation

## Layers

**Type Layer:**
- Purpose: Define domain types with invariant enforcement through smart constructors
- Location: `src/Carbonica/Types/`
- Contains: Core types (Core.hs), Configuration (Config.hs), Project data (Project.hs), Governance proposals (Governance.hs), Emission tracking (Emission.hs)
- Pattern: All types export constructor-hidden data types with `mkXxx` smart constructors that validate invariants
- Used by: All validators and utilities

**Validation Helpers Layer:**
- Purpose: Shared, battle-tested validation logic to reduce duplication across validators
- Location: `src/Carbonica/Validators/Common.hs`
- Contains: NFT finding (findInputByNft, findOutputByNft), datum extraction (extractDatum, findConfigDatum), multisig verification (validateMultisig), token counting and verification
- Pattern: All functions marked `{-# INLINEABLE #-}` for cross-module GHC optimization
- Used by: All individual validators

**Utility Layer:**
- Purpose: Reusable helper functions for token naming, payment verification
- Location: `src/Carbonica/Utils.hs`
- Contains: tokenNameFromOref (one-shot pattern), payment verification (payoutExact, payoutAtLeast), token burning verification
- Pattern: Generic utility functions applicable across multiple validators
- Used by: Validators needing token operations or payment validation

**Validator Layer:**
- Purpose: Implement specific validation rules for each smart contract function
- Location: `src/Carbonica/Validators/`
- Contains: 10 individual validators (IdentificationNft, ConfigHolder, DaoGovernance, ProjectPolicy, ProjectVault, CotPolicy, CetPolicy, UserVault, Marketplace)
- Pattern: Each validator is self-contained with detailed error registries and validation logic
- Examples:
  - Minting policies: IdentificationNft, ProjectPolicy, CotPolicy, CetPolicy
  - Spending validators: ConfigHolder, ProjectVault, UserVault, Marketplace
  - Governance: DaoGovernance (both minting and spending)

## Data Flow

**Project Lifecycle:**

1. **Submit Phase**
   - Developer submits project via ProjectPolicy minting
   - Project NFT minted, ProjectDatum created with status=ProjectSubmitted
   - ProjectVault receives NFT, stores ProjectDatum

2. **Voting Phase**
   - Multisig validators vote via ProjectVault spending (VaultVote action)
   - Each vote updates yes/no counts, prevents duplicate votes
   - ProjectDatum continues to ProjectVault with updated vote state

3. **Finalization Phase**
   - When quorum reached, ProjectVault spends with VaultApprove or VaultReject
   - If approved: CotPolicy mints COT tokens, sends to developer, burns project NFT
   - If rejected: Project NFT burned, no COT minted
   - ProjectDatum removed from chain (NFT burned)

**Emission & Offsetting:**

1. **Emission Recording**
   - Company records emissions via CetPolicy minting
   - CET tokens locked in UserVault with user's stake credential
   - Datum stores emission details (company, quantity, category)

2. **Offset Purchase**
   - User purchases COT tokens from Marketplace
   - Spends MarketplaceDatum output, receives COT tokens
   - Platform takes 5% royalty fee

3. **Offset Execution**
   - User spends UserVault with VaultOffset redeemer
   - Provides COT tokens to match CET quantity
   - Both tokens burned in 1:1 ratio
   - Remaining tokens returned to vault with same stake credential

**DAO Governance:**

1. **Proposal Submission**
   - Multisig member submits proposal via DaoGovernance minting
   - Proposal NFT minted, GovernanceDatum created with state=InProgress
   - Contains action to execute (e.g., UpdateFees)

2. **Voting**
   - Multisig members vote via DaoGovernance spending
   - Each voter can vote Yes/No/Abstain
   - Prevents duplicate voting, enforces deadline

3. **Execution**
   - After deadline, proposal can be executed or rejected
   - If yes > no: Execute action (e.g., update ConfigDatum)
   - If no >= yes: Reject proposal
   - Proposal NFT burned

**State Management:**

- **ConfigDatum**: Centralized configuration stored at Config Holder address
  - Contains: fee amounts, project categories, multisig settings, policy IDs
  - Read via reference inputs by all validators
  - Updated only via DAO governance execution
  - Identified by Identification NFT (one-shot minting pattern)

- **ProjectDatum**: Tracks project voting state in ProjectVault
  - Fields: name, developer, COT amount, vote counts, status
  - Continues through voting phase
  - Destroyed when project finalized

- **UserVault Datum**: Tracks user emissions and offsets
  - Fields: user address, emission details
  - Persists as long as user has CET tokens
  - Used to verify offset ratio (1 CET = 1 COT)

- **GovernanceDatum**: Tracks proposal votes and state
  - Fields: proposal ID, action, vote records, deadline, state
  - Continues through voting phase
  - Destroyed when proposal finalized

## Key Abstractions

**Smart Constructor Pattern:**
- Purpose: Enforce data invariants at construction time, preventing invalid states on-chain
- Examples: `mkLovelace`, `mkCotAmount`, `mkPercentage`, `mkProjectDatum`, `mkConfigDatum`
- Pattern: Return `Either error value` - validators must pattern match to proceed
- Benefits: Compile-time guarantee that only valid data reaches chain; reduces runtime validation

**NFT One-Shot Pattern:**
- Purpose: Identify unique entities (config, projects, proposals) without using hashes
- Implementation: Token name derived from OutputReference via `blake2b_224(serialise(oref))`
- Used for: Identification NFT (config), Project NFTs, Proposal NFTs
- Benefit: Prevents re-minting, ensures singletons

**Multisig Abstraction:**
- Purpose: Centralized authorization mechanism across all validators
- Implementation: Data structure in ConfigDatum with signer list and threshold
- Usage: `validateMultisig(signatories, authorized, required)` in Common module
- Benefit: Single source of truth for validator authorization, updatable via governance

**Datum Continuation Pattern:**
- Purpose: Persist state across multiple validation steps (voting, updates)
- Implementation: Spending validators verify exact datum changes, return updated UTxO to same address
- Used in: ProjectVault voting loop, DaoGovernance voting loop, UserVault offset tracking
- Benefit: Multi-step transactions without side channels

**Value Verification Helpers:**
- Purpose: Generic token checking functions (findByNft, findByOutRef, extractDatum)
- Pattern: Tail-recursive list traversal with early return on match
- Inlining: All marked `{-# INLINEABLE #-}` for GHC cross-module optimization
- Benefit: Reduced code duplication, consistent validation across validators

## Entry Points

**Minting Policies** (triggered by policy scripts):

- `Carbonica.Validators.IdentificationNft`: Mints one-shot config identifier
  - Triggering: DaoGovernance initial setup
  - Responsibility: Ensure single token exists, prevents config hijacking

- `Carbonica.Validators.ProjectPolicy`: Mints Project NFTs
  - Triggering: Developer submits carbon offset project
  - Responsibility: Validate ProjectDatum format, send to ProjectVault

- `Carbonica.Validators.CotPolicy`: Mints/burns Carbon Offset Tokens (fungible)
  - Triggering: Projects approved OR offset transactions
  - Responsibility: Validate project approval, prevent double-minting, handle burning

- `Carbonica.Validators.CetPolicy`: Mints/burns Carbon Emission Tokens (fungible)
  - Triggering: Companies report emissions OR users offset
  - Responsibility: Validate emission data, enforce 1:1 offset ratio with COT

- `Carbonica.Validators.DaoGovernance`: Mints/burns Proposal NFTs
  - Triggering: Multisig members submit governance proposals
  - Responsibility: Validate proposal action format, verify quorum for execution

**Spending Validators** (triggered when spending UTxOs at script addresses):

- `Carbonica.Validators.ConfigHolder`: Controls ConfigDatum updates
  - Triggering: DAO executes governance proposal to change fees/categories
  - Responsibility: Only DAO can update, prevent config downgrade

- `Carbonica.Validators.ProjectVault`: Controls Project NFT voting and finalization
  - Triggering: Multisig votes OR project finalization
  - Responsibility: Validate voting rules, ensure quorum, manage vote counts

- `Carbonica.Validators.UserVault`: Controls user's CET token offsetting
  - Triggering: User burns CET by purchasing COT
  - Responsibility: Enforce 1:1 offset ratio, prevent partial offsets

- `Carbonica.Validators.Marketplace`: Controls COT trading
  - Triggering: User purchases COT from seller
  - Responsibility: Verify price payment, collect royalty fee

## Error Handling

**Strategy:** Explicit error codes with detailed registry in each validator

**Patterns:**

Each validator includes comprehensive error registry at top of file documenting:
- Error code (e.g., PVE000, DGE001)
- Root cause description
- Fix recommendation

Examples from codebase:
- ProjectVault registers PVE000-PVE012 (13 error conditions)
- DaoGovernance registers DGE000-DGE012 (13 error conditions)
- Each error has cause and fix guidance

**On-Chain Error Reporting:**

- Primary: `P.traceError "message"` for validation failures
- Usage: Applied to datum/redeemer parsing failures, multisig failures, state violations
- Not exportable: Error codes are documentation only; on-chain only reports fatal failures

**Type-Based Error Prevention:**

Smart constructors return `Either error value`, catching errors before validators run:
- `mkLovelace: Integer -> Either QuantityError Lovelace`
- `mkProjectDatum: ... -> Either ProjectError ProjectDatum`
- Validators only work with validated types

## Cross-Cutting Concerns

**Logging:** Not used on-chain (Plutus V3 doesn't support). Error codes documented in source registries.

**Validation:** Multi-layered approach:
1. Smart constructor validation (off-chain preparation, on-chain verification)
2. Common module validation helpers (findInputByNft, extractDatum, validateMultisig)
3. Individual validator-specific rules (state transitions, vote counting)
4. Inlineable helpers reduce code size through GHC optimization

**Authentication:** Multisig verification pattern:
- Authorized signers list stored in ConfigDatum
- Validators call `validateMultisig(txSignatories, configMultisig.signers, configMultisig.required)`
- Applies to: governance, project approval, config updates
- Configuration updatable via DAO without contract redeploy

**Authorization:** Role-based via multisig:
- DAO Members: Can submit proposals, vote on governance
- Validators: Can vote on projects, approve/reject projects
- Config: Specifies all authorized roles in single datum

---

*Architecture analysis: 2026-03-11*
