{- |
Module      : Carbonica.Validators.IdentificationNft
Description : One-shot minting policy for Carbonica platform identification
License     : Apache-2.0

This minting policy creates a unique, one-time NFT used to identify
the Config Holder UTxO. Other contracts find the configuration by
looking for this NFT.

One-shot pattern: The policy is parameterized by a specific TxOutRef.
Once that UTxO is spent to mint the NFT, it can never be minted again.
-}
module Carbonica.Validators.IdentificationNft where

import           GHC.Generics                (Generic)
import           PlutusLedgerApi.V3          (CurrencySymbol,
                                              ScriptContext (..),
                                              ScriptInfo (..), TokenName (..),
                                              TxInInfo (..), TxInfo (..),
                                              TxOutRef (..),
                                              getRedeemer)
import           PlutusLedgerApi.V3.MintValue (mintValueMinted)
import           PlutusLedgerApi.V1.Value    (valueOf)
import           PlutusTx
import           PlutusTx.Blueprint
import qualified PlutusTx.Prelude            as P

import           Carbonica.Types.Config      (identificationTokenName)

--------------------------------------------------------------------------------
-- REDEEMER
--------------------------------------------------------------------------------

-- | Actions for the Identification NFT policy
data IdNftRedeemer
  = IdMint
  -- ^ Mint the identification NFT (one-time only)
  | IdBurn
  -- ^ Burn the identification NFT (destroy platform)
  deriving stock (Generic)
  deriving anyclass (HasBlueprintDefinition)

PlutusTx.makeIsDataSchemaIndexed ''IdNftRedeemer [('IdMint, 0), ('IdBurn, 1)]

--------------------------------------------------------------------------------
-- VALIDATOR LOGIC
--------------------------------------------------------------------------------

{-# INLINEABLE typedValidator #-}
-- | Identification NFT minting policy
--
--   Parameters:
--     oref - The specific UTxO that must be consumed to mint (one-shot)
--
--   Mint rules:
--     - Must consume the specified UTxO
--     - Must mint exactly 1 token
--
--   Burn rules:
--     - Must burn exactly 1 token
typedValidator :: TxOutRef -> ScriptContext -> Bool
typedValidator oref ctx = case scriptInfo of
  MintingScript ownPolicy -> case redeemer of
    IdMint -> mintCheck ownPolicy
    IdBurn -> burnCheck ownPolicy
  _ -> P.traceError "Expected minting context"
  where
    ScriptContext txInfo rawRedeemer scriptInfo = ctx

    -- Parse redeemer
    redeemer :: IdNftRedeemer
    redeemer = case PlutusTx.fromBuiltinData (getRedeemer rawRedeemer) of
      P.Nothing -> P.traceError "Failed to parse redeemer"
      P.Just r  -> r

    -- Token name as proper TokenName type
    tokenName :: TokenName
    tokenName = TokenName identificationTokenName
    {-# INLINEABLE tokenName #-}

    -- Check: consuming the specific UTxO (one-shot guarantee)
    consumingOref :: Bool
    consumingOref = hasInput oref (txInfoInputs txInfo)
    {-# INLINEABLE consumingOref #-}

    -- Helper to check if oref is in inputs
    hasInput :: TxOutRef -> [TxInInfo] -> Bool
    hasInput _ []       = False
    hasInput ref (i:is) = txInInfoOutRef i P.== ref P.|| hasInput ref is
    {-# INLINEABLE hasInput #-}

    -- Check: minting exactly 1 token with correct name
    mintCheck :: CurrencySymbol -> Bool
    mintCheck ownPolicy =
      let mintedValue = mintValueMinted (txInfoMint txInfo)  -- Convert MintValue to Value
          amount = valueOf mintedValue ownPolicy tokenName
      in P.traceIfFalse "Must consume oref" consumingOref
         P.&& P.traceIfFalse "Must mint exactly 1 token" (amount P.== 1)
    {-# INLINEABLE mintCheck #-}

    -- Check: burning exactly 1 token
    burnCheck :: CurrencySymbol -> Bool
    burnCheck ownPolicy =
      let mintedValue = mintValueMinted (txInfoMint txInfo)
          amount = valueOf mintedValue ownPolicy tokenName
      in P.traceIfFalse "Must burn exactly 1 token" (amount P.== (-1))
    {-# INLINEABLE burnCheck #-}

--------------------------------------------------------------------------------
-- COMPILED VALIDATOR
--------------------------------------------------------------------------------

{-# INLINEABLE untypedValidator #-}
-- | Untyped wrapper for the validator
--   Takes serialized oref parameter
untypedValidator :: BuiltinData -> BuiltinData -> P.BuiltinUnit
untypedValidator orefData ctxData =
  P.check
    ( typedValidator
        (PlutusTx.unsafeFromBuiltinData orefData)
        (PlutusTx.unsafeFromBuiltinData ctxData)
    )

-- | Compile the validator to Plutus Core
compiledValidator :: CompiledCode (BuiltinData -> BuiltinData -> P.BuiltinUnit)
compiledValidator = $$(PlutusTx.compile [||untypedValidator||])
