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

--------------------------------------------------------------------------------
-- VALIDATOR LOGIC
--------------------------------------------------------------------------------

{-# INLINEABLE typedValidator #-}
-- | CET minting policy validator
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
typedValidator :: ScriptHash -> CurrencySymbol -> ScriptContext -> Bool
typedValidator userVaultHash cotPolicy ctx = case scriptInfo of
  MintingScript ownPolicy -> case redeemer of
    CetMintWithDatum cetDatum   -> mintCheck userVaultHash ownPolicy cetDatum
    CetBurnWithCot _burnRedeemer -> burnCheck ownPolicy cotPolicy
  _ -> P.traceError "CET: Expected minting context"
  where
    ScriptContext txInfo rawRedeemer scriptInfo = ctx

    -- Parse redeemer
    redeemer :: CetMintRedeemer
    redeemer = case PlutusTx.fromBuiltinData (getRedeemer rawRedeemer) of
      P.Nothing -> P.traceError "CET: Failed to parse redeemer"
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
      P.traceIfFalse "CET: Must mint single token type" singleTokenMinted
      P.&& P.traceIfFalse "CET: Minted qty /= redeemer qty" qtyMatches
      P.&& P.traceIfFalse "CET: Must go to UserVault with matching qty" sentToUserVault
      P.&& P.traceIfFalse "CET: Output datum /= redeemer" datumMatches
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
          _               -> P.traceError "CET: Expected exactly one token"

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
            ScriptCredential sh -> sh P.== vaultHash  -- FIXED: verify specific script hash
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
      P.traceIfFalse "CET: Must burn (negative qty)" cetNegative
      P.&& P.traceIfFalse "CET: CET qty /= COT qty" cetEqualsCot
      where
        -- Total CET quantity being burned (negative value)
        cetQtyBurned :: Integer
        cetQtyBurned = getTotalMintedForPolicy mintedValue ownPolicy

        -- Total COT quantity being burned (negative value)
        -- Uses cotPolicyParam from validator parameter, NOT from redeemer
        cotQtyBurned :: Integer
        cotQtyBurned = getTotalMintedForPolicy mintedValue cotPolicyParam

        -- cet_qty < 0 (burning)
        cetNegative :: Bool
        cetNegative = cetQtyBurned P.< 0

        -- cet_qty == cot_qty (both negative, same magnitude)
        cetEqualsCot :: Bool
        cetEqualsCot = cetQtyBurned P.== cotQtyBurned
    {-# INLINEABLE burnCheck #-}

    -- Sum all token quantities for a given policy
    getTotalMintedForPolicy :: Value -> CurrencySymbol -> Integer
    getTotalMintedForPolicy val policy =
      sumQty [qty | (cs, _, qty) <- flattenValue val, cs P.== policy]
    {-# INLINEABLE getTotalMintedForPolicy #-}

    sumQty :: [Integer] -> Integer
    sumQty []     = 0
    sumQty (x:xs) = x P.+ sumQty xs
    {-# INLINEABLE sumQty #-}

--------------------------------------------------------------------------------
-- COMPILED VALIDATOR
--------------------------------------------------------------------------------

{-# INLINEABLE untypedValidator #-}
untypedValidator :: BuiltinData -> BuiltinData -> BuiltinData -> P.BuiltinUnit
untypedValidator userVaultHashData cotPolicyData ctxData =
  P.check (typedValidator 
    (PlutusTx.unsafeFromBuiltinData userVaultHashData)
    (PlutusTx.unsafeFromBuiltinData cotPolicyData)
    (PlutusTx.unsafeFromBuiltinData ctxData))

compiledValidator :: CompiledCode (BuiltinData -> BuiltinData -> BuiltinData -> P.BuiltinUnit)
compiledValidator = $$(PlutusTx.compile [||untypedValidator||])
