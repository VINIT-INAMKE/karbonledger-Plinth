{- |
Module      : Validator
Description : Template for Cardano Plutus V3 Validators
License     : Apache-2.0

This is a starting point for your Plutus V3 smart contract.
Replace the example logic with your own validator rules.

== How Validators Work ==

A validator is a function that decides whether a transaction is allowed
to spend a UTxO locked at a script address. It receives:

  1. ScriptContext - Contains all transaction information
     - txInfo: inputs, outputs, signatures, validity range, etc.
     - scriptInfo: the datum attached to the UTxO being spent
     - redeemer: the "password" or action provided by the spender

The validator must return True for the transaction to be valid.

== Compiling to Blueprint ==

After writing your validator:
  1. Run: make build
  2. Run: make blueprint NAME=Validator
  3. Use blueprints/Validator.json in your frontend with MeshJS

-}
module Validator where

import           GHC.Generics                (Generic)

import           PlutusLedgerApi.V3          (Datum (..), PubKeyHash,
                                              Redeemer (..), ScriptContext (..),
                                              ScriptInfo (..), getRedeemer)
import           PlutusLedgerApi.V3.Contexts (txSignedBy)
import           PlutusTx
import           PlutusTx.Blueprint
import qualified PlutusTx.Prelude            as PlutusTx

--------------------------------------------------------------------------------
-- DATUM
-- The datum is data stored with the locked UTxO.
-- Think of it as the "state" or "configuration" of this particular UTxO.
--------------------------------------------------------------------------------

-- | Example datum: stores an owner's public key hash.
--   The owner is the only one who can unlock this UTxO.
--
--   Customize this for your use case:
--   - Auction: { seller, highestBid, endTime }
--   - Escrow: { buyer, seller, amount, deadline }
--   - NFT: { owner, metadata }
data MyDatum = MyDatum
  { owner :: PubKeyHash
  -- ^ The public key hash of the owner who can unlock this UTxO
  }
  deriving stock (Generic)
  deriving anyclass (HasBlueprintDefinition)

-- Generate Plutus data encoding (required for on-chain use)
PlutusTx.makeLift ''MyDatum
PlutusTx.makeIsDataSchemaIndexed ''MyDatum [('MyDatum, 0)]

--------------------------------------------------------------------------------
-- REDEEMER
-- The redeemer is provided when spending the UTxO.
-- Think of it as the "action" or "instruction" for what to do.
--------------------------------------------------------------------------------

-- | Example redeemer: simple actions that can be performed.
--
--   Customize this for your use case:
--   - Auction: NewBid { bidder, amount } | CloseBid
--   - Escrow: Release | Refund | Dispute
--   - Vesting: Claim { amount }
data MyRedeemer
  = Unlock    -- ^ Standard unlock by owner
  | Cancel    -- ^ Cancel/refund operation
  deriving stock (Generic)
  deriving anyclass (HasBlueprintDefinition)

-- Generate Plutus data encoding
PlutusTx.makeIsDataSchemaIndexed ''MyRedeemer [('Unlock, 0), ('Cancel, 1)]

--------------------------------------------------------------------------------
-- VALIDATOR LOGIC
-- This is where your smart contract rules live.
--------------------------------------------------------------------------------

{-# INLINEABLE typedValidator #-}
-- | The main validator function.
--
--   @param ctx - The script context containing all transaction data
--   @returns True if the transaction is valid, False otherwise
--
--   This example validates that:
--   - For 'Unlock': The transaction must be signed by the owner
--   - For 'Cancel': The transaction must be signed by the owner
typedValidator :: ScriptContext -> Bool
typedValidator (ScriptContext txInfo scriptRedeemer scriptInfo) =
  case redeemer of
    Unlock -> ownerSigned
    Cancel -> ownerSigned
  where
    -- Extract the redeemer from context and parse it
    redeemer :: MyRedeemer
    redeemer = case PlutusTx.fromBuiltinData (getRedeemer scriptRedeemer) of
      Nothing -> PlutusTx.traceError "Failed to parse redeemer"
      Just r  -> r

    -- Extract the datum from the UTxO being spent
    datum :: MyDatum
    datum = case scriptInfo of
      SpendingScript _ (Just (Datum d)) ->
        case PlutusTx.fromBuiltinData d of
          Just parsed -> parsed
          Nothing     -> PlutusTx.traceError "Failed to parse datum"
      _ -> PlutusTx.traceError "Expected SpendingScript with datum"

    -- Check if the owner signed this transaction
    ownerSigned :: Bool
    ownerSigned = txSignedBy txInfo (owner datum)

--------------------------------------------------------------------------------
-- COMPILED VALIDATOR
-- This section compiles the validator for on-chain use.
-- You typically don't need to modify this.
--------------------------------------------------------------------------------

{-# INLINEABLE untypedValidator #-}
-- | Wrapper that converts typed validator to untyped (required by Cardano)
untypedValidator :: BuiltinData -> PlutusTx.BuiltinUnit
untypedValidator ctx =
  PlutusTx.check
    ( typedValidator
        (PlutusTx.unsafeFromBuiltinData ctx)
    )

-- | Compile the validator to Plutus Core
--   This is what gets serialized to the blueprint JSON
compiledValidator :: CompiledCode (BuiltinData -> PlutusTx.BuiltinUnit)
compiledValidator = $$(PlutusTx.compile [||untypedValidator||])
