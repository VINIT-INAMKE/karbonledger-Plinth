# Carbonica Ledger — Smart Contracts

> Plutus V3 smart contracts for a decentralized carbon credit platform built with Plinth.

---

## Honest Verdict: Will These Contracts Work?

### ✅ **YES, with caveats**

After thorough code review, these contracts demonstrate **solid Plutus V3 patterns** and should work on-chain. However, there are important considerations:

#### Strengths

| Aspect | Assessment |
|--------|------------|
| **Type Safety** | Excellent. Smart constructors prevent invalid states at construction time |
| **Code Quality** | Well-structured with proper `INLINEABLE` pragmas and shared utilities |
| **Error Handling** | Clear error codes (e.g., `PPE001`, `CHE003`) for debugging |
| **Optimization** | Phase-based validation pattern reduces script execution costs |
| **Modularity** | Shared `Common.hs` module eliminates code duplication |

#### Potential Issues & Risks

| Risk Level | Issue | Details |
|------------|-------|---------|
| 🟡 **Medium** | **No on-chain tests** | Unit tests exist in `test/` but no integration or on-chain tests found |
| 🟡 **Medium** | **Circular dependencies** | Contracts reference each other via ConfigDatum policy IDs (requires careful deployment order) |
| 🟡 **Medium** | **Vote datum continuation** | `ProjectVault.VaultVote` validates but doesn't verify the continuing output datum update |
| 🟢 **Low** | **UserVault incomplete** | `VaultWithdraw` action just `traceError`s — not implemented yet |
| 🟢 **Low** | **Marketplace standalone** | Doesn't integrate with ConfigDatum for dynamic royalty configuration |

#### Pre-Deployment Checklist

Before deploying to mainnet:

1. **Write integration tests** using Plutip or similar emulator
2. **Calculate script sizes** — Plutus V3 scripts have size limits
3. **Test deployment order** — ID NFT must be minted first, then ConfigDatum initialized
4. **Audit multisig logic** — Verify quorum calculations for edge cases
5. **Verify token name derivation** — `tokenNameFromOref` used correctly across contracts

---

## Contract Overview

This repository contains **10 smart contracts** implementing a complete carbon credit lifecycle:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           CARBONICA LEDGER SYSTEM                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────┐                                                        │
│  │  ID NFT Policy   │ ─── One-shot NFT identifying the platform             │
│  └────────┬─────────┘                                                        │
│           │ locked in                                                        │
│           ▼                                                                  │
│  ┌──────────────────┐                                                        │
│  │  Config Holder   │ ─── Stores ConfigDatum (fees, categories, multisig)   │
│  └────────┬─────────┘                                                        │
│           │ read by                                                          │
│  ┌────────┴────────────────────────────────────────────────────────┐        │
│  │                                                                  │        │
│  │  ┌────────────────┐    ┌────────────────┐    ┌───────────────┐  │        │
│  │  │ Project Policy │───▶│ Project Vault  │───▶│  COT Policy   │  │        │
│  │  │  (mint NFT)    │    │  (voting)      │    │  (mint COT)   │  │        │
│  │  └────────────────┘    └────────────────┘    └───────────────┘  │        │
│  │                                                                  │        │
│  │  ┌────────────────┐    ┌────────────────┐                       │        │
│  │  │  CET Policy    │───▶│  User Vault    │ ◀── Emissions tracking│        │
│  │  │  (mint CET)    │    │  (offset)      │                       │        │
│  │  └────────────────┘    └────────────────┘                       │        │
│  │                                                                  │        │
│  │  ┌────────────────┐    ┌────────────────┐                       │        │
│  │  │DAO Governance  │───▶│ Config Holder  │ ◀── Platform updates  │        │
│  │  │ (proposals)    │    │  (execute)     │                       │        │
│  │  └────────────────┘    └────────────────┘                       │        │
│  │                                                                  │        │
│  │  ┌────────────────┐                                              │        │
│  │  │  Marketplace   │ ─── COT trading with royalties               │        │
│  │  └────────────────┘                                              │        │
│  │                                                                  │        │
│  └──────────────────────────────────────────────────────────────────┘        │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Contract Details

### 1. Identification NFT (`IdentificationNft.hs`)

**Purpose:** One-shot NFT that identifies the canonical ConfigDatum holder.

| Action | Validation Rules |
|--------|------------------|
| `IdMint` | Must consume specific TxOutRef (one-shot), mint exactly 1 token |
| `IdBurn` | Must burn exactly 1 token |

**Why it matters:** All other contracts find platform configuration by looking for this NFT.

---

### 2. Config Holder (`ConfigHolder.hs`)

**Purpose:** Spending validator protecting the platform configuration.

| Action | Validation Rules |
|--------|------------------|
| `ConfigUpdate` | DAO proposal must transition from `InProgress` → `Executed`, ID NFT must continue to output |

**Datum:** `ConfigDatum` containing:
- Fee address and amount
- Allowed project categories  
- Multisig configuration (signers + required count)
- Script hashes for other contracts (set via DAO)

---

### 3. Project Policy (`ProjectPolicy.hs`)

**Purpose:** Minting policy for Project NFTs.

| Action | Validation Rules |
|--------|------------------|
| `MintProject` | Category in ConfigDatum, fee paid, NFT to script address with ProjectDatum |
| `BurnProject` | All tokens have negative quantity |

**Flow:**
```
Developer → Pay Fee → Mint Project NFT → Locked in Project Vault
```

---

### 4. Project Vault (`ProjectVault.hs`)

**Purpose:** Holds Project NFTs during the voting process.

| Action | Validation Rules |
|--------|------------------|
| `VaultVote` | Voter in multisig, hasn't voted, project is Submitted |
| `VaultApprove` | Quorum reached (yes votes ≥ required), NFT burned, COT minted to developer |
| `VaultReject` | Quorum reached (no votes ≥ required), NFT burned, no COT minted |

**Flow:**
```
Validators Vote → Quorum Reached → Approve (mint COT) or Reject (burn NFT)
```

---

### 5. COT Policy (`CotPolicy.hs`)

**Purpose:** Carbon Offset Token minting policy (fungible tokens).

**Parameters:**
- `cfgNft` - ID NFT policy for finding ConfigDatum
- `valMint` - Vault minting policy

| Action | Validation Rules |
|--------|------------------|
| `MintWithProject` (0) | Project input valid, vault tokens burned, COT amount matches redeemer, amount > 0, multisig verified |
| `Burn` (1) | Either multisig burn OR 1:1 CET offset burn |

**Token:** Represents verified carbon credits (fungible).

---

### 6. CET Policy (`CetPolicy.hs`)

**Purpose:** Carbon Emission Token minting policy.

**Parameters:**
- `userVaultHash` - ScriptHash of UserVault (ensures CET is locked in correct vault)

| Action | Validation Rules |
|--------|------------------|
| `CetMintWithDatum` | Single token, quantity matches datum, sent to UserVault (verified by script hash) |
| `CetBurnWithCot` | CET negative, CET quantity == COT quantity (1:1 offset) |

**Token:** Represents reported carbon emissions (non-transferable, locked in User Vault).

---

### 7. User Vault (`UserVault.hs`)

**Purpose:** Holds user's CET tokens, enabling offset operations.

| Action | Validation Rules |
|--------|------------------|
| `VaultOffset` | CET burned < 0, CET qty == COT qty, remaining tokens returned |
| `VaultWithdraw` | **Not implemented** (traceError) |

**Flow:**
```
User has CET → Burns COT 1:1 → CET offset recorded
```

---

### 8. DAO Governance (`DaoGovernance.hs`)

**Purpose:** Two validators for DAO proposal lifecycle.

**Minting Policy:**

| Action | Validation Rules |
|--------|------------------|
| `DaoSubmitProposal` | Submitter signs, output has NFT, state = InProgress |
| `DaoBurnProposal` | Authorized signer signs |

**Spending Validator:**

| Action | Validation Rules |
|--------|------------------|
| `DaoVote` | Before deadline, voter in multisig, was Pending, vote count updated |
| `DaoExecute` | After deadline, yes > no, state → Executed, ConfigDatum update verified |
| `DaoReject` | After deadline, no ≥ yes, state → Rejected |

**Proposal Actions:**
- Add/Remove signers
- Update fees
- Add/Remove categories
- Update script hashes

---

### 9. Marketplace (`Marketplace.hs`)

**Purpose:** COT trading with platform royalties and complete trade verification.

**Datum:**
```haskell
MarketplaceDatum
  { mdOwner     :: Wallet         -- Seller's wallet
  , mdAmount    :: Integer        -- Price in lovelace
  , mdCotPolicy :: CurrencySymbol -- COT policy ID
  , mdCotToken  :: TokenName      -- COT token name
  , mdCotQty    :: Integer        -- Quantity being sold
  }
```

| Action | Validation Rules |
|--------|------------------|
| `MktBuy` | Seller receives (price - 5% royalty), platform receives royalty, buyer receives COT tokens |
| `MktWithdraw` | Owner signature required |

**Royalty:** Fixed 5% (could be made configurable via ConfigDatum).

---

## System Workflow

### Complete Project Lifecycle

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         PROJECT LIFECYCLE                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. PLATFORM SETUP                                                       │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Admin mints ID NFT → Creates ConfigDatum with initial settings   │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                          ↓                                               │
│  2. PROJECT SUBMISSION                                                   │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Developer pays fee → Mints Project NFT → NFT locked in Vault     │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                          ↓                                               │
│  3. VALIDATOR VOTING                                                     │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Multisig validators review → Cast votes → Quorum reached         │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                          ↓                                               │
│  4. OUTCOME                                                              │
│  ┌───────────────────────────┐    ┌────────────────────────────────┐   │
│  │ APPROVED                  │    │ REJECTED                        │   │
│  │ • Burn Project NFT        │    │ • Burn Project NFT              │   │
│  │ • Mint COT to developer   │    │ • No COT minted                 │   │
│  │ • Developer can trade COT │    │ • Project ends                  │   │
│  └───────────────────────────┘    └────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### Carbon Offset Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         CARBON OFFSET FLOW                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. REPORT EMISSION                                                      │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ User mints CET tokens → Locked in User Vault (non-transferable)  │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                          ↓                                               │
│  2. ACQUIRE COT                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ User buys COT from Marketplace (5% royalty to platform)          │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                          ↓                                               │
│  3. OFFSET                                                               │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ User burns COT 1:1 with CET → Emission offset recorded           │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### DAO Governance Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         DAO GOVERNANCE FLOW                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  1. SUBMIT PROPOSAL                                                      │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Signer mints proposal NFT → GovernanceDatum with action & deadline│   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                          ↓                                               │
│  2. VOTING PERIOD                                                        │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │ Multisig members vote (Yes/No/Abstain) → Vote counts updated      │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                          ↓                                               │
│  3. FINALIZATION (after deadline)                                        │
│  ┌───────────────────────────┐    ┌────────────────────────────────┐   │
│  │ YES > NO: Execute         │    │ NO ≥ YES: Reject               │   │
│  │ • Update ConfigDatum      │    │ • Burn proposal NFT            │   │
│  │ • Burn proposal NFT       │    │ • No config change             │   │
│  └───────────────────────────┘    └────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Project Structure

```
src/
├── Carbonica/
│   ├── Types/
│   │   ├── Core.hs          # Domain newtypes (Lovelace, CotAmount, etc.)
│   │   ├── Config.hs        # ConfigDatum, Multisig
│   │   ├── Project.hs       # ProjectDatum, ProjectStatus
│   │   ├── Emission.hs      # CET types, EmissionDatum
│   │   └── Governance.hs    # DAO types, ProposalAction, Vote
│   │
│   ├── Validators/
│   │   ├── Common.hs        # Shared validation helpers
│   │   ├── IdentificationNft.hs
│   │   ├── ConfigHolder.hs
│   │   ├── ProjectPolicy.hs
│   │   ├── ProjectVault.hs
│   │   ├── CotPolicy.hs
│   │   ├── CetPolicy.hs
│   │   ├── UserVault.hs
│   │   ├── DaoGovernance.hs
│   │   └── Marketplace.hs
│   │
│   └── Utils.hs             # Utility functions
│
└── Validator.hs             # Template validator (unused)

app/
└── GenBlueprint.hs          # Blueprint generator

blueprints/                  # Generated CIP-57 blueprints
test/                        # Unit tests
```

---

## Building & Testing

```bash
# Enter development shell
nix develop

# Build all contracts
make build

# Generate blueprint
make blueprint

# Run tests
cabal test
```

---

## Token Summary

| Token | Full Name | Purpose | Transferable |
|-------|-----------|---------|--------------|
| **ID NFT** | Identification NFT | Identifies platform config | No (locked) |
| **Project NFT** | Project Token | Represents submitted project | No (locked, burned after voting) |
| **COT** | Carbon Offset Token | Tradeable carbon credits | Yes |
| **CET** | Carbon Emission Token | Logged emissions | No (locked in User Vault) |
| **Proposal NFT** | DAO Proposal | Represents governance proposal | No (locked, burned after execution) |

---

## Deployment Order

Contracts must be deployed in this order due to cross-references:

1. **IdentificationNft** — Mint ID NFT with initial ConfigDatum
2. **ConfigHolder** — Lock ID NFT with ConfigDatum
3. **DaoGovernance** — Reference ID NFT policy
4. **ProjectPolicy** — Reference ID NFT policy
5. **ProjectVault** — Reference ID NFT + Project policies
6. **CotPolicy** — Reference ID NFT + Vault policy
7. **UserVault** — Reference CET + COT policies
8. **CetPolicy** — Requires UserVault script hash as parameter
9. **Marketplace** — Reference ID NFT policy

After deployment, use DAO governance to update script hashes in ConfigDatum.

---

## Version 1.1 Enhancements

| Contract | Enhancement |
|----------|-------------|
| **CotPolicy** | Full fungible token support with exact amount validation |
| **CetPolicy** | Secure destination routing via UserVault script hash parameter |
| **Marketplace** | Complete trade verification — validates buyer receives tokens |
| **UserVault** | Precise token accounting for offset operations |
| **Common** | New `getMintedAmountForToken` helper for fungible tokens |

---

## License

Apache-2.0
