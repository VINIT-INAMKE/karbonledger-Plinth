# External Integrations

**Analysis Date:** 2026-03-11

## APIs & External Services

**Cardano Blockchain:**
- Cardano Node - Blockchain network interaction (not bundled, external deployment dependency)
- Purpose: Execute validators on-chain, manage UTxOs, track token minting/burning

## Data Storage

**Blockchain Ledger (UTxO Model):**
- Cardano UTxO storage via PlutusLedgerApi.V3
- Datum types:
  - `ConfigDatum` - Platform configuration (stored at Config Holder address)
  - `ProjectDatum` - Project metadata (name, category, description)
  - `GovernanceDatum` - DAO proposals and voting state
  - `EmissionDatum` - Carbon emission records
  - `MarketplaceDatum` - Token trading listings (seller, price)
  - `UserVaultDatum` - User stake credentials for CET token locking

**No External Database:**
- All state stored on-chain via Cardano UTxO ledger
- No off-chain database required for validation
- Blueprint artifacts exported to JSON (`blueprints/contract.json`) for frontend integration

**File Storage:**
- Local filesystem only for build artifacts
- Generated blueprints: `blueprints/contract.json`
- Build cache: `dist-newstyle/` (Cabal build directory)

**Caching:**
- None - Cardano UTxO cache managed by node infrastructure

## Blockchain Tokens & Policies

**Minting Policies (No external API, on-chain rules):**
- `CetPolicy` - Carbon Emission Token minting/burning policy
  - Mint action: Requires emission data, validates script address and datum
  - Burn action: Requires 1:1 COT burning ratio (offset semantics)
  - No external validation

- `CotPolicy` - Carbon Offset Token minting/burning policy
  - Mint action: Requires valid ProjectDatum, vault token burning, multisig approval
  - Burn action: Requires CET/COT 1:1 burning or multisig override
  - On-chain multisig validation (no external service)

**Identification NFT:**
- Single unique token: "CARBONICA_ID"
- Used as capability token to access ConfigDatum
- Ensures only authorized scripts can read platform configuration

## Authentication & Authorization

**Auth Provider:**
- Custom on-chain multisig (no external provider)

**Implementation:**
- Multisig configuration stored in ConfigDatum: `Multisig { msRequired, msSigners }`
- Validation: `verifyMultisig :: [PubKeyHash] -> [PubKeyHash] -> Integer -> Bool`
- Located in: `src/Carbonica/Utils.hs` (lines 159-163)
- Example: 3-of-5 multisig for DAO governance updates

**Transaction Signing:**
- Cardano native signing (standard tx signatures)
- Validated via `txSignedBy :: TxInfo -> PubKeyHash -> Bool`
- Source: `PlutusLedgerApi.V3.Contexts`

## Monitoring & Observability

**Error Tracking:**
- Error codes embedded in validator logic
- Error reporting via validator failure traces
- Examples from `src/Carbonica/Validators/ConfigHolder.hs`:
  - CHE000 - Invalid script context
  - CHE001 - ConfigDatum parse failure
  - CHE002 - ConfigHolderRedeemer parse failure
  - CHE003 - DAO state transition invalid
  - CHE005 - Identification NFT missing in outputs

**Logs:**
- On-chain logging via PlutusTx trace functions: `traceError`, `traceInfo`
- Off-chain logging: Standard Haskell IO (not implemented in current codebase)

## CI/CD & Deployment

**Hosting:**
- Cardano blockchain (mainnet or testnet)
- No traditional server hosting required
- Validators compiled to Plutus Core and registered on-chain

**CI Pipeline:**
- Nix Flakes hydra jobs configured for:
  - x86_64-linux
  - x86_64-darwin
  - aarch64-linux
  - aarch64-darwin
- Pre-commit hooks: Haskell linting via HLint, formatting via stylish-haskell
- Build verification: `cabal build all`

**Build/Release Artifacts:**
- Compiled Plutus Core validators (serialized bytecode)
- CIP-57 blueprint JSON (`blueprints/contract.json`)
- Blueprint consumed by frontend: MeshJS or Cardano dApp libraries

## Environment Configuration

**No External Environment Variables Required:**

The codebase is self-contained and does not depend on:
- API keys or secrets
- External service credentials
- Network configuration (Cardano node connection handled by dApp frontend)

**Build-Time Configuration:**
- Cabal project configuration: `cabal.project`
- Plutus target version: `1.1.0` (set in ghc-options)
- Flake inputs: Automatically managed via `flake.nix`

**Secrets Location:**
- Not applicable - Smart contracts operate in trusted execution environment (blockchain)
- Wallet/signing keys managed by Cardano wallet (off-chain responsibility)

## Webhooks & Callbacks

**Incoming:**
- None - Validators are passive (respond to transactions spending locked UTxOs)
- Triggers: Transaction submission to Cardano network

**Outgoing:**
- None - No external service calls from validators
- All state updates recorded on-chain

## Integration Points

**Frontend/dApp Integration:**
- Blueprint export: `blueprints/contract.json`
- Format: CIP-57 compliant JSON
- Consumer: MeshJS, Cardano dApp libraries, wallet applications
- Contains: Validator schema, redeemer definitions, datum types

**Off-Chain Components (Not Implemented in This Repo):**
- Blockfrost API (for reading blockchain state)
- Lucid/Meshjs (for transaction building)
- Cardano wallet (for signing)
- These are client-side responsibilities

## Data Flow

**Emission Reporting Flow:**
1. User submits emission data (via dApp)
2. CetPolicy validates and mints CET tokens
3. CET locked in UserVault (associated with stake credential)
4. Tokens tracked on-chain via UTxO ledger

**Project Approval Flow:**
1. Developer submits project (via dApp)
2. ProjectPolicy creates ProjectDatum UTxO
3. DAO proposes approval (via DaoGovernance validator)
4. Multisig votes and executes (via ConfigHolder)
5. CotPolicy mints COT tokens upon approval

**Carbon Offsetting Flow:**
1. User purchases COT from marketplace
2. User spends UserVault with VaultOffset redeemer
3. CET and COT burned in 1:1 ratio
4. Remaining tokens returned to vault address

---

*Integration audit: 2026-03-11*
