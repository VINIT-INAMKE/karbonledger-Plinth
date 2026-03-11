# Testing

## Framework

- **Test runner:** Cabal test suite (standard Haskell)
- **Entry point:** `test/Main.hs`
- **Test modules:**
  - `test/Test/Carbonica/Types.hs` - Type-level tests
  - `test/Test/Carbonica/Validators.hs` - Validator unit tests
  - `test/Test/Carbonica/Properties/SmartConstructors.hs` - Property-based tests

## Test Structure

```
test/
├── Main.hs                          # Test entry point (runs all test groups)
└── Test/Carbonica/
    ├── Types.hs                     # Type construction and validation tests
    ├── Validators.hs                # Validator logic tests
    └── Properties/
        └── SmartConstructors.hs     # QuickCheck property tests for smart constructors
```

## What's Tested

### Smart Constructor Properties (`Properties/SmartConstructors.hs`)
- `mkLovelace` rejects negative values
- `mkCotAmount` rejects negative values
- `mkCetAmount` rejects negative values
- `mkPercentage` rejects values outside 0-100
- `mkMultisig` validates required <= signers count
- `mkConfigDatum` validates fee > 0, non-empty categories
- `mkProjectDatum` validates non-empty name, positive COT

### Type Tests (`Types.hs`)
- Newtype construction and unwrapping
- PlutusTx serialization roundtrips
- Eq instance correctness

### Validator Tests (`Validators.hs`)
- Basic validator logic paths

## What's NOT Tested (Gaps)

### Critical Missing Coverage
- **No on-chain emulation tests** - Validators are not tested with actual `ScriptContext` simulation
- **No transaction-level tests** - No Plutus emulator or cardano-testnet tests
- **No negative test cases for validators** - Attack scenarios not tested
- **ProjectVault vote output datum** - The critical vulnerability (no output verification) has no test
- **DaoGovernance authorization** - The trivial `hasSigner` check has no test proving it's insufficient
- **CotPolicy project status** - No test verifying COT can be minted without project approval
- **Marketplace edge cases** - Zero price, royalty rounding, missing tokens not tested
- **ConfigHolder update integrity** - No test that other config fields can be changed during update

### Recommended Testing Additions
1. **Plutus emulator tests** using `plutus-contract` or `cardano-node-emulator`
2. **Attack scenario tests** for each vulnerability identified in CONCERNS.md
3. **Property tests** for validator invariants (e.g., "vote should not change developer address")
4. **Integration tests** for multi-validator flows (submit project -> vote -> approve -> mint COT)
5. **Boundary tests** for integer arithmetic (royalty rounding, zero amounts)

## Test Commands

```bash
cabal test           # Run all tests
cabal test --test-show-details=direct  # Verbose output
```

## Testing Patterns

### Smart Constructor Testing
```haskell
-- Property: mkLovelace rejects negative
prop_mkLovelace_negative :: Integer -> Property
prop_mkLovelace_negative n = n < 0 ==> mkLovelace n == Left (NegativeQuantity n)
```

### No Mocking Framework
The codebase does not use a mocking framework. Plutus validators are pure functions, so testing is done by constructing inputs directly. However, constructing valid `ScriptContext` values is non-trivial and appears to be largely untested.
