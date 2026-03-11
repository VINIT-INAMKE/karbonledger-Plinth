{- |
Module      : Carbonica.Validators.CotPolicy
Description : Carbon Offset Token (COT) minting policy
License     : Apache-2.0

This policy controls the minting and burning of Carbon Offset Tokens (COT).
COTs represent verified carbon offset credits that can be minted when projects
are approved and burned when emissions are offset.

PHASE 4 OPTIMIZATIONS:
  - Uses shared validation helpers from Carbonica.Validators.Common
  - All helper functions use descriptive names (no compressed abbreviations)
  - INLINEABLE pragmas for cross-module optimization
  - Eliminated code duplication (findCfg, msOk, sumP, exactN)
-}

{- ══════════════════════════════════════════════════════════════════════════
   ERROR CODE REGISTRY - CotPolicy Validator
   ══════════════════════════════════════════════════════════════════════════

   CPE000 - Invalid script context
            Cause: Not a minting script context
            Fix: Ensure script is being used as minting policy

   CPE001 - Invalid action
            Cause: cotAction is not 0 or 1
            Fix: Use action 0 (mint COT with project) or 1 (burn COT)

   CPE002 - ConfigDatum not found
            Cause: No reference input contains ID NFT with ConfigDatum
            Fix: Include config holder as reference input

   CPE003 - Project input not found
            Cause: Referenced UTXO doesn't exist or lacks ProjectDatum
            Fix: Ensure cotOref points to valid project UTXO

   CPE004 - Vault tokens not burned
            Cause: No vault tokens being burned (sumP < 0 check failed)
            Fix: Ensure vault policy tokens are being burned

   CPE005 - Project NFT mismatch
            Cause: Not exactly 1 project NFT with specified token name
            Fix: Ensure exactly one project NFT is being burned

   CPE006 - Multisig verification failed
            Cause: Insufficient multisig signatures
            Fix: Provide required number of signatures from multisig group

   CPE007 - Invalid CET token count
            Cause: Expected exactly 1 CET token type being burned
            Fix: Ensure single CET token is present in mint

   CPE008 - Invalid COT token count or mismatch
            Cause: Expected exactly 1 COT token OR CET != COT quantities
            Fix: Ensure single COT token and quantities match CET

   CPE009 - Project not approved
            Cause: pdStatus != ProjectApproved
            Fix: Only approved projects can have COT minted

   CPE010 - COT amount mismatch with project datum
            Cause: minted COT amount != pdCotAmount from ProjectDatum
            Fix: Minted amount must exactly match the datum-specified COT amount

   CPE011 - COT quantity not positive
            Cause: expectedCotAmount (from datum) <= 0
            Fix: Project must specify a positive COT amount

   ══════════════════════════════════════════════════════════════════════════
-}

module Carbonica.Validators.CotPolicy where

import           GHC.Generics                   (Generic)
import           PlutusLedgerApi.V3             (CurrencySymbol (..),
                                                 ScriptContext (..),
                                                 ScriptInfo (..),
                                                 TokenName (..),
                                                 TxInInfo (..),
                                                 TxInfo (..),
                                                 TxOutRef (..),
                                                 getRedeemer)
import           PlutusLedgerApi.V3.MintValue   (mintValueMinted)
import           PlutusLedgerApi.V1.Value       (flattenValue)
import           PlutusTx
import           PlutusTx.Blueprint
import qualified PlutusTx.Prelude               as P

import           Carbonica.Types.Config         (ConfigDatum,
                                                 Multisig (..),
                                                 cdCetPolicyId,
                                                 cdMultisig,
                                                 identificationTokenName)
import           Carbonica.Types.Project        (ProjectDatum,
                                                 ProjectStatus (..),
                                                 pdCotAmount,
                                                 pdStatus)
import           Carbonica.Validators.Common    (extractDatum,
                                                 findConfigDatum,
                                                 findInputByOutRef,
                                                 getMintedAmountForToken,
                                                 sumTokensByPolicy,
                                                 validateMultisig)

--------------------------------------------------------------------------------
-- REDEEMER
--------------------------------------------------------------------------------

data CotRedeemer = CotRedeemer
  { cotAction :: Integer
  , cotOref   :: TxOutRef
  , cotAmount :: Integer
  , cotTkn    :: TokenName
  }
  deriving stock (Generic)
  deriving anyclass (HasBlueprintDefinition)

PlutusTx.makeIsDataSchemaIndexed ''CotRedeemer [('CotRedeemer, 0)]

--------------------------------------------------------------------------------
-- VALIDATOR
--------------------------------------------------------------------------------

{-# INLINEABLE typedValidator #-}
-- | COT minting policy (OPTIMIZED - Phase 2)
--
--   Phase 2 Optimizations:
--     - Error codes (CPE000-CPE008) for minimal on-chain footprint
--     - Hoisted common extractions (inputs, refs, mint, sigs extracted once)
--     - INLINE pragmas for constants and frequently used values
typedValidator :: CurrencySymbol -> CurrencySymbol -> ScriptContext -> Bool
typedValidator cfgNft valMint ctx =
  let ScriptContext txInfo rawRed scriptInfo = ctx

      -- ═══════════════════════════════════════════════════════════════
      -- PHASE 1: Extract common values ONCE (hoisted to top level)
      -- ═══════════════════════════════════════════════════════════════

      {-# INLINE red #-}
      red = PlutusTx.unsafeFromBuiltinData (getRedeemer rawRed) :: CotRedeemer

      {-# INLINE inps #-}
      inps = txInfoInputs txInfo

      {-# INLINE refs #-}
      refs = txInfoReferenceInputs txInfo

      {-# INLINE mnt #-}
      mnt = flattenValue (mintValueMinted (txInfoMint txInfo))

      {-# INLINE sgs #-}
      sgs = txInfoSignatories txInfo

      {-# INLINE idTk #-}
      idTk = TokenName identificationTokenName

      -- ═══════════════════════════════════════════════════════════════
      -- PHASE 2: Load ConfigDatum ONCE
      -- ═══════════════════════════════════════════════════════════════

      {-# INLINE config #-}
      config :: ConfigDatum
      config = case findConfigDatum refs cfgNft idTk of
        P.Nothing -> P.traceError "CPE002"
        P.Just c -> c

      {-# INLINE multisig #-}
      multisig = cdMultisig config

      -- ═══════════════════════════════════════════════════════════════
      -- PHASE 3: Action-specific validation
      -- ═══════════════════════════════════════════════════════════════

      {-# INLINEABLE validateMintWithProject #-}
      validateMintWithProject :: CurrencySymbol -> Bool
      validateMintWithProject policy =
        P.traceIfFalse "CPE003" projectInputValid
        P.&& P.traceIfFalse "CPE009" projectApproved
        P.&& P.traceIfFalse "CPE004" (sumTokensByPolicy mnt valMint P.< 0)
        P.&& P.traceIfFalse "CPE010" cotAmountValid
        P.&& P.traceIfFalse "CPE011" cotQuantityPositive
        P.&& P.traceIfFalse "CPE006" (validateMultisig sgs (msSigners multisig) (msRequired multisig))
        where
          -- Extract ProjectDatum from the project input
          maybeProjectDatum :: P.Maybe ProjectDatum
          maybeProjectDatum = case findInputByOutRef inps (cotOref red) of
            P.Nothing -> P.Nothing
            P.Just txIn -> extractDatum (txInInfoResolved txIn)

          projectInputValid :: Bool
          projectInputValid = case maybeProjectDatum of
            P.Nothing -> False
            P.Just _  -> True

          -- CRIT-04 FIX: Verify project is approved before allowing mint
          projectApproved :: Bool
          projectApproved = case maybeProjectDatum of
            P.Nothing -> False
            P.Just pd -> pdStatus pd P.== ProjectApproved

          -- CRIT-04 FIX: Use datum amount, NOT redeemer amount
          expectedCotAmount :: Integer
          expectedCotAmount = case maybeProjectDatum of
            P.Nothing -> 0
            P.Just pd -> pdCotAmount pd

          actualCotAmount = getMintedAmountForToken mnt policy (cotTkn red)
          cotAmountValid = actualCotAmount P.== expectedCotAmount

          -- Ensure positive quantity for minting (renamed from CPE009 to CPE011)
          cotQuantityPositive = expectedCotAmount P.> 0

      {-# INLINEABLE validateBurn #-}
      validateBurn :: CurrencySymbol -> Bool
      validateBurn policy =
        if validateMultisig sgs (msSigners multisig) (msRequired multisig)
          then P.traceIfFalse "CPE004" (sumTokensByPolicy mnt policy P.< 0)
          else
            -- Burn with CET: match CET and COT quantities
            -- Expect exactly one CET token type being burned
            -- Expect exactly one COT token type with matching quantity
            let cetPolicy = CurrencySymbol (cdCetPolicyId config)
            in case extractSingleToken mnt cetPolicy of
                 P.Nothing -> P.traceError "CPE007"
                 P.Just cetQuantity -> case extractSingleToken mnt policy of
                   P.Nothing -> P.traceError "CPE008"
                   P.Just cotQuantity -> P.traceIfFalse "CPE008" (cetQuantity P.< 0 P.&& cetQuantity P.== cotQuantity)

      -- | Extract single token quantity for a policy (should have exactly 1 token name)
      {-# INLINEABLE extractSingleToken #-}
      extractSingleToken :: [(CurrencySymbol, TokenName, Integer)] -> CurrencySymbol -> P.Maybe Integer
      extractSingleToken tokens policy = case filterByPolicy tokens policy of
        [(_, quantity)] -> P.Just quantity
        _ -> P.Nothing

      -- | Filter tokens by policy, returning (TokenName, Quantity) pairs
      {-# INLINEABLE filterByPolicy #-}
      filterByPolicy :: [(CurrencySymbol, TokenName, Integer)] -> CurrencySymbol -> [(TokenName, Integer)]
      filterByPolicy [] _ = []
      filterByPolicy ((cs, tkn, qty):xs) policy =
        if cs P.== policy
          then (tkn, qty) : filterByPolicy xs policy
          else filterByPolicy xs policy

  -- ═══════════════════════════════════════════════════════════════
  -- PHASE 4: Main entry point (dispatch by script context)
  -- ═══════════════════════════════════════════════════════════════

  in case scriptInfo of
    MintingScript policy ->
      let action = cotAction red
      in if action P.== 0
           then validateMintWithProject policy
           else if action P.== 1
             then validateBurn policy
             else P.traceError "CPE001"
    _ -> P.traceError "CPE000"

--------------------------------------------------------------------------------
-- COMPILED VALIDATOR
--------------------------------------------------------------------------------

{-# INLINEABLE untypedValidator #-}
untypedValidator :: BuiltinData -> BuiltinData -> BuiltinData -> P.BuiltinUnit
untypedValidator a b c = 
  P.check (typedValidator 
    (PlutusTx.unsafeFromBuiltinData a) 
    (PlutusTx.unsafeFromBuiltinData b) 
    (PlutusTx.unsafeFromBuiltinData c))

compiledValidator :: CompiledCode (BuiltinData -> BuiltinData -> BuiltinData -> P.BuiltinUnit)
compiledValidator = $$(PlutusTx.compile [||untypedValidator||])
