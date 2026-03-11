# Codebase Structure

## Directory Layout

```
smartcontracts/
├── app/
│   └── GenBlueprint.hs          # Blueprint JSON generation entry point
├── blueprints/
│   └── .gitkeep                  # Output directory for compiled validator blueprints
├── src/
│   ├── Validator.hs              # Template/example validator (Plutus V3)
│   └── Carbonica/
│       ├── Utils.hs              # Shared utility functions (payout, burn, multisig)
│       ├── Types/
│       │   ├── Core.hs           # Newtypes: Lovelace, CotAmount, CetAmount, Percentage, addresses
│       │   ├── Config.hs         # ConfigDatum, Multisig, smart constructors
│       │   ├── Project.hs        # ProjectDatum, ProjectStatus, redeemers
│       │   ├── Emission.hs       # EmissionDatum, CetDatum, CetMintRedeemer, UserVaultRedeemer
│       │   └── Governance.hs     # GovernanceDatum, ProposalAction, Vote, redeemers
│       └── Validators/
│           ├── Common.hs         # Shared validator helpers (NFT find, datum extract, multisig)
│           ├── IdentificationNft.hs  # One-shot NFT minting policy (platform identity)
│           ├── ConfigHolder.hs       # Spending validator protecting ConfigDatum
│           ├── DaoGovernance.hs      # DAO proposal lifecycle (mint + spend validators)
│           ├── ProjectPolicy.hs      # Project NFT minting policy
│           ├── ProjectVault.hs       # Spending validator for project voting
│           ├── CotPolicy.hs         # Carbon Offset Token minting policy
│           ├── CetPolicy.hs         # Carbon Emission Token minting policy
│           ├── UserVault.hs         # Spending validator for user CET holdings
│           └── Marketplace.hs       # COT trading marketplace validator
├── test/
│   ├── Main.hs                   # Test entry point
│   └── Test/Carbonica/
│       ├── Types.hs              # Type-level tests
│       ├── Validators.hs         # Validator unit tests
│       └── Properties/
│           └── SmartConstructors.hs  # Property-based tests for smart constructors
├── dist-newstyle/                # Cabal build artifacts (gitignored)
├── .hlint.yaml                   # HLint linter configuration
└── .stylish-haskell.yaml         # Haskell code formatter configuration
```

## Key Locations

| Purpose | Path |
|---------|------|
| Domain types | `src/Carbonica/Types/` |
| Validator logic | `src/Carbonica/Validators/` |
| Shared helpers | `src/Carbonica/Validators/Common.hs`, `src/Carbonica/Utils.hs` |
| Blueprint generation | `app/GenBlueprint.hs` |
| Tests | `test/Test/Carbonica/` |
| Build output | `blueprints/`, `dist-newstyle/` |
| Linting config | `.hlint.yaml`, `.stylish-haskell.yaml` |

## Module Dependency Graph

```
Types/Core.hs          (no internal deps - base types)
    ↑
Types/Config.hs        (imports Core)
Types/Project.hs       (imports Core)
Types/Emission.hs      (no internal deps)
Types/Governance.hs    (no internal deps)
    ↑
Validators/Common.hs   (imports nothing from Types - generic helpers)
Utils.hs               (imports nothing from Types - raw PubKeyHash utils)
    ↑
Validators/IdentificationNft.hs  (imports Config for token name)
Validators/ConfigHolder.hs       (imports Config, Governance, Common)
Validators/DaoGovernance.hs      (imports Config, Governance, Common)
Validators/ProjectPolicy.hs      (imports Config, Project, Common)
Validators/ProjectVault.hs       (imports Config, Project, Common)
Validators/CotPolicy.hs          (imports Config, Project, Common)
Validators/CetPolicy.hs          (imports Emission)
Validators/UserVault.hs          (imports Emission, Common)
Validators/Marketplace.hs        (standalone - no internal imports)
```

## Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Modules | PascalCase, hierarchical | `Carbonica.Validators.ProjectVault` |
| Types | PascalCase | `ConfigDatum`, `ProjectStatus` |
| Functions | camelCase | `typedValidator`, `findInputByNft` |
| Private fields | camelCase with trailing `'` | `cdFeesAddress'`, `pdStatus'` |
| Public getters | camelCase (no `'`) | `cdFeesAddress`, `pdStatus` |
| Error codes | UPPER_PREFIX + 3-digit number | `CHE001`, `DGE007`, `PVE003` |
| Constants | camelCase | `identificationTokenName`, `royaltyNumerator` |
| Redeemer constructors | PascalCase with domain prefix | `VaultVote`, `DaoExecute`, `MktBuy` |

## Error Code Prefixes

| Prefix | Validator |
|--------|-----------|
| `CHE` | ConfigHolder |
| `DGE` | DaoGovernance |
| `PVE` | ProjectVault |
| `PPE` | ProjectPolicy |
| `CPE` | CotPolicy |
| (none) | CetPolicy, UserVault, Marketplace (use string messages) |

## File Organization Pattern

Each validator file follows a consistent structure:
1. Module header with Haddock documentation
2. Error code registry (block comment)
3. Module exports
4. Imports (PlutusLedgerApi, PlutusTx, internal types, Common)
5. Redeemer type definition (if any)
6. `typedValidator` - main validation logic
7. Helper functions (INLINEABLE)
8. `untypedValidator` - BuiltinData wrapper
9. `compiledValidator` - PlutusTx compilation
