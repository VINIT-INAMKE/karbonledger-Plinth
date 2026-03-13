{- |
Module      : Carbonica.Validators.CetPolicy
Description : Carbon Emission Token (CET) minting policy
License     : Apache-2.0

Controls minting and burning of CET tokens.
CET tokens represent reported carbon emissions.

VALIDATION LOGIC:

  Mint Action (CETDatum redeemer):
    - Exactly one token type minted under policy
    - Minted quantity matches redeemer.cet_qty
    - CET sent to user script address (script with user's stake credential)
    - Output datum matches redeemer datum exactly

  Burn Action (EmissionBurnRedeemer):
    - CET qty < 0 (burning)
    - CET quantity == COT quantity (1:1 offset ratio)
-}

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

module Carbonica.Validators.CetPolicy where

import           PlutusLedgerApi.V3             (Address (..),
                                                 Credential (..),
                                                 CurrencySymbol (..),
                                                 Datum (..),
                                                 OutputDatum (..),
                                                 ScriptContext (..),
                                                 ScriptHash (..),
                                                 ScriptInfo (..),
                                                 TokenName (..),
                                                 TxInfo (..),
                                                 TxOut (..),
                                                 getRedeemer)
import           PlutusLedgerApi.V3.MintValue   (mintValueMinted)
import           PlutusLedgerApi.V1.Value       (Value, valueOf, flattenValue)
import           PlutusTx
import qualified PlutusTx.Prelude               as P

import           Carbonica.Types.Emission       (CetDatum (..),
                                                 CetMintRedeemer (..))
import           Carbonica.Validators.Common    (getTotalForPolicy)

--------------------------------------------------------------------------------
-- VALIDATOR LOGIC
--------------------------------------------------------------------------------

-- | CET minting policy validator.
--
--   Parameters:
--     userVaultHash - Script hash of the UserVault (to verify CET destination)
--     cotPolicy     - COT policy ID (hardcoded parameter to prevent spoofing)
--
--   Mint rules (CETDatum branch):
--     1. Exactly one token name minted under own policy
--     2. Minted quantity == cet_qty from redeemer
--     3. Output to UserVault script address contains same quantity
--     4. Output datum == redeemer datum
--
--   Burn rules (EmissionBurnRedeemer branch):
--     1. CET qty < 0 (burning)
--     2. CET qty == COT qty (both negative, same absolute value)
{-# INLINEABLE typedValidator #-}
typedValidator :: ScriptHash -> CurrencySymbol -> ScriptContext -> Bool
typedValidator userVaultHash cotPolicy ctx = case scriptInfo of
  MintingScript ownPolicy -> case redeemer of
    CetMintWithDatum cetDatum   -> mintCheck userVaultHash ownPolicy cetDatum
    CetBurnWithCot _burnRedeemer -> burnCheck ownPolicy cotPolicy
  _ -> P.traceError "CEE000"
  where
    ScriptContext txInfo rawRedeemer scriptInfo = ctx

    -- Parse redeemer
    redeemer :: CetMintRedeemer
    redeemer = case PlutusTx.fromBuiltinData (getRedeemer rawRedeemer) of
      P.Nothing -> P.traceError "CEE001"
      P.Just r  -> r

    mintedValue :: Value
    mintedValue = mintValueMinted (txInfoMint txInfo)
    {-# INLINEABLE mintedValue #-}

    outputs :: [TxOut]
    outputs = txInfoOutputs txInfo
    {-# INLINEABLE outputs #-}

    --------------------------------------------------------------------------------
    -- MINT CHECK
    -- Rules:
    --   1. Extract exactly one token from mint under own policy
    --   2. Minted qty == cetDatum.cet_qty
    --   3. Find output with CET that goes to UserVault
    --   4. Output datum == CetDatum from redeemer
    --------------------------------------------------------------------------------
    mintCheck :: ScriptHash -> CurrencySymbol -> CetDatum -> Bool
    mintCheck vaultHash ownPolicy cetDatum =
      P.traceIfFalse "CEE002" singleTokenMinted
      P.&& P.traceIfFalse "CEE003" qtyMatches
      P.&& P.traceIfFalse "CEE004" sentToUserVault
      P.&& P.traceIfFalse "CEE005" datumMatches
      where
        expectedQty :: Integer
        expectedQty = cetQty cetDatum

        -- Find tokens minted under our policy using list comprehension
        ownTokens :: [(CurrencySymbol, TokenName, Integer)]
        ownTokens = [(cs, tkn, qty) | (cs, tkn, qty) <- flattenValue mintedValue, cs P.== ownPolicy]

        -- Must be exactly one token type
        singleTokenMinted :: Bool
        singleTokenMinted = case ownTokens of
          [_] -> True
          _   -> False

        -- Get the minted token name and quantity
        mintedTokenData :: (TokenName, Integer)
        mintedTokenData = case ownTokens of
          [(_, tkn, qty)] -> (tkn, qty)
          _               -> P.traceError "CEE002"

        mintedTkn :: TokenName
        mintedQtyVal :: Integer
        (mintedTkn, mintedQtyVal) = mintedTokenData

        -- Qty must match redeemer
        qtyMatches :: Bool
        qtyMatches = mintedQtyVal P.== expectedQty

        -- Find output with CET going to UserVault script address
        cetOutput :: P.Maybe TxOut
        cetOutput = findCetOutputToUserVault outputs vaultHash ownPolicy mintedTkn

        sentToUserVault :: Bool
        sentToUserVault = case cetOutput of
          P.Nothing -> False
          P.Just o  -> valueOf (txOutValue o) ownPolicy mintedTkn P.== expectedQty

        -- Verify output datum matches redeemer datum exactly
        datumMatches :: Bool
        datumMatches = case cetOutput of
          P.Nothing -> False
          P.Just o  -> case txOutDatum o of
            OutputDatum (Datum d) ->
              let redeemerData :: BuiltinData = PlutusTx.toBuiltinData cetDatum
              in d P.== redeemerData
            _ -> False
    {-# INLINEABLE mintCheck #-}

    -- Find output with CET token going to UserVault (verified by script hash)
    findCetOutputToUserVault :: [TxOut] -> ScriptHash -> CurrencySymbol -> TokenName -> P.Maybe TxOut
    findCetOutputToUserVault [] _ _ _ = P.Nothing
    findCetOutputToUserVault (o:os) vaultHash policy tkn =
      let hasCet = valueOf (txOutValue o) policy tkn P.> 0
          isUserVault = case addressCredential (txOutAddress o) of
            ScriptCredential sh -> sh P.== vaultHash  -- verify specific script hash
            _                   -> False
      in if hasCet P.&& isUserVault
           then P.Just o
           else findCetOutputToUserVault os vaultHash policy tkn
    {-# INLINEABLE findCetOutputToUserVault #-}

    --------------------------------------------------------------------------------
    -- BURN CHECK
    -- Rules:
    --   1. CET qty < 0 (burning)
    --   2. CET qty == COT qty (1:1 ratio)
    --------------------------------------------------------------------------------
    -- | Burn check using cotPolicy from validator parameter (not redeemer)
    burnCheck :: CurrencySymbol -> CurrencySymbol -> Bool
    burnCheck ownPolicy cotPolicyParam =
      P.traceIfFalse "CEE006" cetNegative
      P.&& P.traceIfFalse "CEE007" cetEqualsCot
      where
        -- Total CET quantity being burned (negative value)
        cetQtyBurned :: Integer
        cetQtyBurned = getTotalForPolicy mintedValue ownPolicy

        -- Total COT quantity being burned (negative value)
        -- Uses cotPolicyParam from validator parameter, NOT from redeemer
        cotQtyBurned :: Integer
        cotQtyBurned = getTotalForPolicy mintedValue cotPolicyParam

        -- cet_qty < 0 (burning)
        cetNegative :: Bool
        cetNegative = cetQtyBurned P.< 0

        -- cet_qty == cot_qty (both negative, same magnitude)
        cetEqualsCot :: Bool
        cetEqualsCot = cetQtyBurned P.== cotQtyBurned
    {-# INLINEABLE burnCheck #-}

--------------------------------------------------------------------------------
-- COMPILED VALIDATOR
--------------------------------------------------------------------------------

-- | Untyped entry point for the CET minting policy.
--
-- First arg: userVaultHash. Second arg: cotPolicy. Third arg: ScriptContext.
{-# INLINEABLE untypedValidator #-}
untypedValidator :: BuiltinData -> BuiltinData -> BuiltinData -> P.BuiltinUnit
untypedValidator userVaultHashData cotPolicyData ctxData =
  P.check (typedValidator
    (PlutusTx.unsafeFromBuiltinData userVaultHashData)
    (PlutusTx.unsafeFromBuiltinData cotPolicyData)
    (PlutusTx.unsafeFromBuiltinData ctxData))

-- | Compiled UPLC code for on-chain deployment of the CET minting policy.
compiledValidator :: CompiledCode (BuiltinData -> BuiltinData -> BuiltinData -> P.BuiltinUnit)
compiledValidator = $$(PlutusTx.compile [||untypedValidator||])
