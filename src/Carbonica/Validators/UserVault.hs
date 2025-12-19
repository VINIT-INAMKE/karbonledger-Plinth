{- |
Module      : Carbonica.Validators.UserVault
Description : Spending validator that holds user's CET tokens
License     : Apache-2.0

The User Vault locks CET tokens making them non-transferable.
Users can only "spend" from vault to offset emissions with COT.

VALIDATION LOGIC:

  Action 0 (Offset emissions):
    - CET qty < 0 (burning)
    - CET qty == COT qty (1:1 offset)
    - Remaining tokens sent back to user's script address

  Action 1 (Withdraw COT): Not yet implemented
-}
module Carbonica.Validators.UserVault where

import           PlutusLedgerApi.V3             (Address (..),
                                                 CurrencySymbol (..),
                                                 Datum (..),
                                                 PubKeyHash,
                                                 ScriptContext (..),
                                                 ScriptInfo (..),
                                                 TokenName (..),
                                                 TxInInfo (..),
                                                 TxInfo (..),
                                                 TxOut (..),
                                                 TxOutRef,
                                                 getRedeemer)
import           PlutusLedgerApi.V3.MintValue   (mintValueMinted)
import           PlutusLedgerApi.V1.Value       (Value, valueOf, flattenValue)
import           PlutusTx
import qualified PlutusTx.Prelude               as P

import           Carbonica.Types.Emission       (EmissionDatum (..),
                                                 UserVaultRedeemer (..))
import           Carbonica.Validators.Common    (isInList)

--------------------------------------------------------------------------------
-- VALIDATOR LOGIC
--------------------------------------------------------------------------------

{-# INLINEABLE typedValidator #-}
-- | User Vault spending validator
--
--   Parameters:
--     cetPolicy - CET policy ID (to verify burning)
--     cotPolicy - COT policy ID (to verify offsetting)
--
--   Action 0 (VaultOffset): Offset emissions by burning CET and COT
--     1. CET qty < 0 (burning)
--     2. CET qty == COT qty (1:1 ratio)
--     3. Remaining tokens sent back to user's script address
--
--   Action 1 (VaultWithdraw): Not yet implemented (fails)
typedValidator :: CurrencySymbol -> CurrencySymbol -> ScriptContext -> Bool
typedValidator cetPolicy cotPolicy ctx = case scriptInfo of
  SpendingScript oref (Just (Datum datumData)) ->
    case PlutusTx.fromBuiltinData datumData of
      P.Nothing -> P.traceError "UserVault: Failed to parse datum"
      P.Just emissionDatum -> validateSpend oref emissionDatum
  _ -> P.traceError "UserVault: Expected spending context with datum"
  where
    ScriptContext txInfo rawRedeemer scriptInfo = ctx

    -- Parse redeemer
    redeemer :: UserVaultRedeemer
    redeemer = case PlutusTx.fromBuiltinData (getRedeemer rawRedeemer) of
      P.Nothing -> P.traceError "UserVault: Failed to parse redeemer"
      P.Just r  -> r

    mintedValue :: Value
    mintedValue = mintValueMinted (txInfoMint txInfo)
    {-# INLINEABLE mintedValue #-}

    inputs :: [TxInInfo]
    inputs = txInfoInputs txInfo
    {-# INLINEABLE inputs #-}

    outputs :: [TxOut]
    outputs = txInfoOutputs txInfo
    {-# INLINEABLE outputs #-}

    signatories :: [PubKeyHash]
    signatories = txInfoSignatories txInfo
    {-# INLINEABLE signatories #-}

    -- Main validation
    validateSpend :: TxOutRef -> EmissionDatum -> Bool
    validateSpend oref emissionDatum = case redeemer of
      VaultOffset _amount -> validateOffset oref emissionDatum
      VaultWithdraw       -> P.traceError "UserVault: CET withdrawal not allowed"
    {-# INLINEABLE validateSpend #-}

    --------------------------------------------------------------------------------
    -- OFFSET VALIDATION
    -- Rules:
    --   1. Owner must sign the transaction
    --   2. Extract CET token and quantity from mint
    --   3. Extract COT token and quantity from mint
    --   4. CET qty < 0 (burning)
    --   5. CET qty == COT qty (1:1 offset)
    --   6. Remaining tokens sent back to user script address
    --------------------------------------------------------------------------------
    validateOffset :: TxOutRef -> EmissionDatum -> Bool
    validateOffset oref emissionDatum =
      P.traceIfFalse "UserVault: Owner must sign" ownerSigned
      P.&& P.traceIfFalse "UserVault: CET qty not negative" cetNegative
      P.&& P.traceIfFalse "UserVault: CET qty /= COT qty" cetEqualsCot
      P.&& P.traceIfFalse "UserVault: Remaining tokens not returned" remainingTokensReturned
      where
        -- Owner signature check
        ownerSigned :: Bool
        ownerSigned = isInList (edOwner emissionDatum) signatories
        -- Get CET token info from mint
        cetMintTokens :: [(TokenName, Integer)]
        cetMintTokens = getTokensForPolicy mintedValue cetPolicy

        -- Get COT token info from mint
        cotMintTokens :: [(TokenName, Integer)]
        cotMintTokens = getTokensForPolicy mintedValue cotPolicy

        -- Extract exactly one CET token and quantity
        cetTokenData :: (TokenName, Integer)
        cetTokenData = case cetMintTokens of
          [(tkn, qty)] -> (tkn, qty)
          _            -> P.traceError "UserVault: Expected exactly one CET token"

        -- Extract exactly one COT token and quantity
        cotTokenData :: (TokenName, Integer)
        cotTokenData = case cotMintTokens of
          [(tkn, qty)] -> (tkn, qty)
          _            -> P.traceError "UserVault: Expected exactly one COT token"

        (cetTkn, cetQtyVal) = cetTokenData
        (cotTkn, cotQtyVal) = cotTokenData

        -- CET quantity must be negative (burning)
        cetNegative :: Bool
        cetNegative = cetQtyVal P.< 0

        -- CET quantity must equal COT quantity (1:1 offset)
        cetEqualsCot :: Bool
        cetEqualsCot = cetQtyVal P.== cotQtyVal

        -- Calculate remaining tokens and verify they go back to user script address
        remainingTokensReturned :: Bool
        remainingTokensReturned =
          let userScriptAddr = getUserScriptAddress oref inputs
              -- Total CET and COT in inputs
              (totalCetIn, totalCotIn) = getTotalTokensInInputs inputs cetPolicy cotPolicy cetTkn cotTkn
              -- Expected remaining after burn (burn qty is negative)
              remainingCet = totalCetIn P.+ cetQtyVal
              remainingCot = totalCotIn P.+ cotQtyVal
          in if remainingCet P.== 0 P.&& remainingCot P.== 0
               then True  -- Nothing remaining, no output required
               else verifyRemainingTokensToAddr outputs userScriptAddr cetPolicy cotPolicy cetTkn cotTkn remainingCet remainingCot
    {-# INLINEABLE validateOffset #-}

    -- Get tokens for a policy from minted value
    getTokensForPolicy :: Value -> CurrencySymbol -> [(TokenName, Integer)]
    getTokensForPolicy val policy =
      [(tkn, qty) | (cs, tkn, qty) <- flattenValue val, cs P.== policy]
    {-# INLINEABLE getTokensForPolicy #-}

    -- Get user script address from inputs (input's script address with stake credential)
    getUserScriptAddress :: TxOutRef -> [TxInInfo] -> Address
    getUserScriptAddress oref inps =
      case findSelfInput oref inps of
        P.Nothing -> P.traceError "UserVault: Self input not found"
        P.Just selfIn -> txOutAddress (txInInfoResolved selfIn)
    {-# INLINEABLE getUserScriptAddress #-}

    findSelfInput :: TxOutRef -> [TxInInfo] -> P.Maybe TxInInfo
    findSelfInput _ [] = P.Nothing
    findSelfInput ref (i:is) =
      if txInInfoOutRef i P.== ref
        then P.Just i
        else findSelfInput ref is
    {-# INLINEABLE findSelfInput #-}

    -- Sum total CET and COT tokens in inputs
    getTotalTokensInInputs :: [TxInInfo] -> CurrencySymbol -> CurrencySymbol -> TokenName -> TokenName -> (Integer, Integer)
    getTotalTokensInInputs [] _ _ _ _ = (0, 0)
    getTotalTokensInInputs (i:is) cetP cotP cetT cotT =
      let val = txOutValue (txInInfoResolved i)
          cetAmt = valueOf val cetP cetT
          cotAmt = valueOf val cotP cotT
          (restCet, restCot) = getTotalTokensInInputs is cetP cotP cetT cotT
      in (cetAmt P.+ restCet, cotAmt P.+ restCot)
    {-# INLINEABLE getTotalTokensInInputs #-}

    -- Verify remaining tokens go to user script address (exact amounts)
    verifyRemainingTokensToAddr :: [TxOut] -> Address -> CurrencySymbol -> CurrencySymbol -> TokenName -> TokenName -> Integer -> Integer -> Bool
    verifyRemainingTokensToAddr [] _ _ _ _ _ _ _ = False
    verifyRemainingTokensToAddr (o:os) addr cetP cotP cetT cotT expCet expCot =
      if txOutAddress o P.== addr
        then let cetInOut = valueOf (txOutValue o) cetP cetT
                 cotInOut = valueOf (txOutValue o) cotP cotT
             in cetInOut P.== expCet P.&& cotInOut P.== expCot 
        else verifyRemainingTokensToAddr os addr cetP cotP cetT cotT expCet expCot
    {-# INLINEABLE verifyRemainingTokensToAddr #-}

--------------------------------------------------------------------------------
-- COMPILED VALIDATOR
--------------------------------------------------------------------------------

{-# INLINEABLE untypedValidator #-}
untypedValidator :: BuiltinData -> BuiltinData -> BuiltinData -> P.BuiltinUnit
untypedValidator cetPolicyData cotPolicyData ctxData =
  P.check
    ( typedValidator
        (PlutusTx.unsafeFromBuiltinData cetPolicyData)
        (PlutusTx.unsafeFromBuiltinData cotPolicyData)
        (PlutusTx.unsafeFromBuiltinData ctxData)
    )

compiledValidator :: CompiledCode (BuiltinData -> BuiltinData -> BuiltinData -> P.BuiltinUnit)
compiledValidator = $$(PlutusTx.compile [||untypedValidator||])
