# Technology Stack

**Analysis Date:** 2026-03-11

## Languages

**Primary:**
- Haskell 2010 - On-chain and off-chain validator development

**Extensions Used:**
- PlutusTx for blockchain-specific type system
- TemplateHaskell for compile-time metaprogramming
- Generics for data serialization
- DataKinds for type-level programming

## Runtime

**Environment:**
- GHC 9.6.6 - Haskell compiler targeting Plutus Core

**Package Manager:**
- Cabal 3.10+ (based on cabal-version 3.0)
- Lockfile: `flake.lock` (Nix-based dependency pinning)

## Frameworks

**Core Blockchain:**
- plutus-core 1.56.0.0 - Plutus Core backend and primitives
- plutus-ledger-api 1.56.0.0 - Cardano ledger API (V3)
- plutus-tx 1.56.0.0 - On-chain Haskell compilation
- plutus-tx-plugin 1.56.0.0 - GHC plugin for PlutusTx compilation

**Testing:**
- tasty - Test suite framework
- tasty-hunit - Unit test helpers
- tasty-quickcheck - Property-based testing with QuickCheck
- QuickCheck - Property generation and randomized testing

**Build/Dev:**
- Nix Flakes - Reproducible development environment
- haskell.nix - Haskell project integration
- iohk-nix - IOHK infrastructure utilities
- pre-commit-hooks.nix - Pre-commit hook management

## Key Dependencies

**Critical:**
- plutus-tx-plugin - Compiles Haskell to Plutus Core for blockchain validators
  - Critical for on-chain code compilation
  - Configured with target version 1.1.0
  - Optimization flags: `-fobject-code`, `-fno-specialise`, `-fno-strictness`

**Infrastructure:**
- base - Haskell standard library
- bytestring - Efficient binary data handling
- containers - Data structure utilities
- directory - File system operations (for blueprint generation)

## Compiler Configuration

**On-Chain Compilation (PlutusTx):**
- Common flags applied: `-Wall` (all warnings)
- Plinth-specific optimizations in `common plinth-options`:
  - `-fobject-code` - Generate object code
  - `-fno-full-laziness` - Reduce code bloat
  - `-fno-specialise` - Prevent specialization
  - `-fno-unbox-strict-fields` - Control boxing behavior
  - Plugin target: `PlutusTx.Plugin:target-version=1.1.0`

**Language Extensions (All validators):**
```haskell
DataKinds
DeriveAnyClass
DeriveGeneric
DerivingStrategies
FlexibleContexts
FlexibleInstances
GeneralizedNewtypeDeriving
ImportQualifiedPost
LambdaCase
MultiParamTypeClasses
NumericUnderscores
OverloadedStrings
PatternSynonyms
RecordWildCards
ScopedTypeVariables
StandaloneDeriving
Strict
TemplateHaskell
TypeApplications
UndecidableInstances
ViewPatterns
```

**GHC-Only Extensions (Off-chain only):**
- GADTs - Used in off-chain code (not supported by Plinth)

## Code Generation

**Blueprint Generation:**
- CIP-57 standard blueprints output to `blueprints/contract.json`
- Generated via `cabal run gen-blueprint`
- Serialized using `PlutusLedgerApi.Common.serialiseCompiledCode`
- Blueprint module: `PlutusTx.Blueprint`

## Development Tools

**Code Quality:**
- HLint (`hlint` command) - Haskell linting in `src/` and `app/`
- Stylish Haskell (`.stylish-haskell.yaml`) - Code formatting
  - Applied to `.hs` files via `make format`

**Build Commands:**
```bash
make build         # Compile all contracts
make buildall      # Full build with tests
make blueprint     # Generate CIP-57 blueprint
make clean         # Remove build artifacts
make lint          # Run HLint
make format        # Apply stylish-haskell
make shell         # Enter nix development environment
```

## Package Sources

**Hackage:**
- Index state: 2025-12-11T11:28:18Z
- Standard Haskell package repository

**CHaP (Cardano Haskell Packages):**
- URL: https://chap.intersectmbo.org/
- Index state: 2025-12-10T11:48:32Z
- Provides Plutus and Cardano-specific packages
- Root keys for signature verification included in `cabal.project`

## Module Organization

**Library Structure:**
- hs-source-dirs: `src/`
- Main library: `smartcontracts` (v0.1.0.0)
- License: Apache-2.0

**Modules (exposing Carbonica namespace):**
- Types: Config, Core, Emission, Governance, Project
- Validators: CetPolicy, ConfigHolder, CotPolicy, DaoGovernance, IdentificationNft, Marketplace, ProjectPolicy, ProjectVault, UserVault
- Utilities: Common, Utils

**Test Suite:**
- test-suite: carbonica-tests
- hs-source-dirs: `test/`
- Entry: `Main.hs`
- Test modules: Test.Carbonica.Types, Test.Carbonica.Validators, Test.Carbonica.Properties.SmartConstructors

## Platform Requirements

**Development:**
- Linux, macOS, or Windows with WSL2
- Nix package manager (for reproducible builds)
- Supported architectures: x86_64-linux, x86_64-darwin, aarch64-linux, aarch64-darwin

**Production:**
- Cardano blockchain (main network or testnet)
- Plutus V3 validator support
- Blueprint compatible with MeshJS or other Cardano dApp libraries

---

*Stack analysis: 2026-03-11*
