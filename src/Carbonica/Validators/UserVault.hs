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

  VaultWithdraw action:
    - DISABLED: Intentionally fails with UVE003 pending V2-02
    - Will require owner signature and proper authorization when implemented
-}

{- ══════════════════════════════════════════════════════════════════════════
   ERROR CODE REGISTRY - UserVault Validator
   ══════════════════════════════════════════════════════════════════════════

   UVE000 - Invalid script context
            Cause: Not a spending context with inline datum
            Fix: Ensure UTxO has inline datum and is being spent

   UVE001 - Datum parse failed
            Cause: Datum bytes don't deserialize to EmissionDatum
            Fix: Verify datum structure matches EmissionDatum schema

   UVE002 - Redeemer parse failed
            Cause: Redeemer bytes don't deserialize to UserVaultRedeemer
            Fix: Verify redeemer is VaultOffset or VaultWithdraw

   UVE003 - CET withdrawal not allowed (intentionally disabled)
            Cause: VaultWithdraw action is disabled pending V2-02 implementation
            Fix: Use VaultOffset to burn CET with COT. Withdrawal will be enabled in V2-02.

   UVE004 - Owner must sign
            Cause: EmissionDatum owner PKH not in transaction signatories
            Fix: Owner must sign the offset transaction

   UVE005 - CET qty not negative
            Cause: CET minted quantity is not negative (not burning)
            Fix: CET quantity must be < 0 for burn action

   UVE006 - CET qty /= COT qty
            Cause: CET and COT quantities differ (1:1 ratio violated)
            Fix: Burn equal amounts of CET and COT

   UVE007 - Remaining tokens not returned
            Cause: Remaining CET/COT not sent back to user script address
            Fix: Return remaining tokens to the user vault address

   UVE008 - Expected exactly one CET token
            Cause: Zero or multiple CET token types in mint
            Fix: Ensure exactly one CET token type is being burned

   UVE009 - Expected exactly one COT token
            Cause: Zero or multiple COT token types in mint
            Fix: Ensure exactly one COT token type is being burned

   UVE010 - Self input not found
            Cause: Cannot locate own script input by TxOutRef
            Fix: Ensure the spending UTXO reference is correct

   ══════════════════════════════════════════════════════════════════════════
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
import           PlutusLedgerApi.V1.Value       (Value, valueOf)
import           PlutusTx
import qualified PlutusTx.Prelude               as P

import           Carbonica.Types.Emission       (EmissionDatum (..),
                                                 UserVaultRedeemer (..))
import           Carbonica.Validators.Common    (findInputByOutRef,
                                                 getTokensForPolicy,
                                                 isInList)

--------------------------------------------------------------------------------
-- VALIDATOR LOGIC
--------------------------------------------------------------------------------

-- | User Vault spending validator.
--
--   Parameters:
--     cetPolicy - CET policy ID (to verify burning)
--     cotPolicy - COT policy ID (to verify offsetting)
--
--   VaultOffset: owner signs, CET/COT burned 1:1, remainder returned.
--   VaultWithdraw: intentionally disabled pending V2-02.
{-# INLINEABLE typedValidator #-}
typedValidator :: CurrencySymbol -> CurrencySymbol -> ScriptContext -> Bool
typedValidator cetPolicy cotPolicy ctx = case scriptInfo of
  SpendingScript oref (Just (Datum datumData)) ->
    case PlutusTx.fromBuiltinData datumData of
      P.Nothing -> P.traceError "UVE001"
      P.Just emissionDatum -> validateSpend oref emissionDatum
  _ -> P.traceError "UVE000"
  where
    ScriptContext txInfo rawRedeemer scriptInfo = ctx

    -- Parse redeemer
    redeemer :: UserVaultRedeemer
    redeemer = case PlutusTx.fromBuiltinData (getRedeemer rawRedeemer) of
      P.Nothing -> P.traceError "UVE002"
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
      -- | VaultWithdraw is intentionally disabled pending V2-02 authorization
      -- implementation. Currently fails immediately with UVE003. The withdrawal
      -- feature requires proper authorization checks (owner signature verification,
      -- partial withdrawal accounting) before it can be safely enabled.
      -- See: V2-02 in REQUIREMENTS.md
      VaultWithdraw       -> P.traceError "UVE003"
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
      P.traceIfFalse "UVE004" ownerSigned
      P.&& P.traceIfFalse "UVE005" cetNegative
      P.&& P.traceIfFalse "UVE006" cetEqualsCot
      P.&& P.traceIfFalse "UVE007" remainingTokensReturned
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
          _            -> P.traceError "UVE008"

        -- Extract exactly one COT token and quantity
        cotTokenData :: (TokenName, Integer)
        cotTokenData = case cotMintTokens of
          [(tkn, qty)] -> (tkn, qty)
          _            -> P.traceError "UVE009"

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

    -- Get user script address from inputs (input's script address with stake credential)
    getUserScriptAddress :: TxOutRef -> [TxInInfo] -> Address
    getUserScriptAddress oref inps =
      case findInputByOutRef inps oref of
        P.Nothing -> P.traceError "UVE010"
        P.Just selfIn -> txOutAddress (txInInfoResolved selfIn)
    {-# INLINEABLE getUserScriptAddress #-}

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

-- | Untyped entry point for the User Vault spending validator.
--
-- First arg: cetPolicy. Second arg: cotPolicy. Third arg: ScriptContext.
{-# INLINEABLE untypedValidator #-}
untypedValidator :: BuiltinData -> BuiltinData -> BuiltinData -> P.BuiltinUnit
untypedValidator cetPolicyData cotPolicyData ctxData =
  P.check
    ( typedValidator
        (PlutusTx.unsafeFromBuiltinData cetPolicyData)
        (PlutusTx.unsafeFromBuiltinData cotPolicyData)
        (PlutusTx.unsafeFromBuiltinData ctxData)
    )

-- | Compiled UPLC code for on-chain deployment of the User Vault validator.
compiledValidator :: CompiledCode (BuiltinData -> BuiltinData -> BuiltinData -> P.BuiltinUnit)
compiledValidator = $$(PlutusTx.compile [||untypedValidator||])
