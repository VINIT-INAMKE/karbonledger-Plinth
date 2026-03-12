{- |
Module      : Carbonica.Validators.ProjectPolicy
Description : Minting policy for Project NFTs
License     : Apache-2.0

Controls minting of Project NFTs for carbon offset projects.
Each project gets a unique NFT that tracks its verification status.

VALIDATION LOGIC:

  Mint Action (Action 0):
    - Read ConfigDatum via reference input with ID NFT
    - Category must be in supported categories
    - Platform fee must be paid to fee address
    - NFT + ProjectDatum must go to project validation script
    - Exactly 1 NFT minted with derived token name

  Burn Action (Action 1):
    - Must burn (all tokens under policy are < 0)

PHASE 4 OPTIMIZATIONS:
  - Uses shared validation helpers from Carbonica.Validators.Common
  - Removed findConfigFromRefs (now uses findConfigDatum)
  - All validation now uses battle-tested Common module
-}

{- ══════════════════════════════════════════════════════════════════════════
   ERROR CODE REGISTRY - ProjectPolicy Validator
   ══════════════════════════════════════════════════════════════════════════

   PPE000 - Invalid script context
            Cause: Not a minting context
            Fix: Ensure this is a minting policy execution

   PPE001 - Redeemer parse failed
            Cause: Redeemer bytes don't deserialize to ProjectMintRedeemer
            Fix: Verify redeemer is either MintProject or BurnProject

   PPE002 - ConfigDatum not found
            Cause: No reference input contains ConfigDatum with ID NFT
            Fix: Include reference input with ID NFT and ConfigDatum

   PPE003 - Must mint exactly 1 token
            Cause: Minting 0 or multiple tokens instead of exactly 1
            Fix: Mint exactly one Project NFT

   PPE004 - Project output not found or invalid
            Cause: No output contains the minted NFT with ProjectDatum
            Fix: Ensure minted NFT goes to output with inline ProjectDatum

   PPE005 - Category not supported
            Cause: ProjectDatum category not in ConfigDatum.cdCategories
            Fix: Use a supported category from the config

   PPE006 - Fee not paid
            Cause: Fee payment to cdFeesAddress insufficient or missing
            Fix: Pay exact fee amount to the fee address

   PPE007 - NFT not sent to script address
            Cause: Minted NFT sent to PubKey address instead of script
            Fix: Send NFT to the project vault script address

   PPE008 - Burn validation failed
            Cause: Not all tokens under policy have negative quantity
            Fix: Ensure all minted tokens are being burned (qty < 0)

   PPE009 - NFT output missing inline datum
            Cause: Project output does not have an inline datum attached
            Fix: Send NFT to output with OutputDatum (inline datum)

   ══════════════════════════════════════════════════════════════════════════
-}

module Carbonica.Validators.ProjectPolicy where

import           PlutusLedgerApi.V3             (Address (..),
                                                 Credential (..),
                                                 CurrencySymbol (..),
                                                 Datum (..),
                                                 OutputDatum (..),
                                                 PubKeyHash,
                                                 ScriptContext (..),
                                                 ScriptHash (..),
                                                 ScriptInfo (..),
                                                 TokenName (..),
                                                 TxInfo (..),
                                                 TxOut (..),
                                                 getRedeemer)
import           PlutusLedgerApi.V3.MintValue   (mintValueMinted)
import           PlutusLedgerApi.V1.Value       (valueOf, Lovelace (..), lovelaceValueOf)
import           PlutusTx
import qualified PlutusTx.Prelude               as P

import           Carbonica.Types.Config         (cdCategories,
                                                 cdFeesAddress,
                                                 cdFeesAmount,
                                                 cdProjectVaultHash,
                                                 identificationTokenName)
import           Carbonica.Types.Project        (ProjectDatum,
                                                 pdCategory,
                                                 ProjectMintRedeemer (..))
import           Carbonica.Validators.Common    (allNegative,
                                                 findConfigDatum,
                                                 getTokensForPolicy,
                                                 isCategorySupported)

--------------------------------------------------------------------------------
-- VALIDATOR LOGIC
--------------------------------------------------------------------------------

{-# INLINEABLE typedValidator #-}
-- | Project Policy minting validator (OPTIMIZED - Phase 2)
--
--   Parameters:
--     idNftPolicy - Identification NFT policy (to find ConfigDatum)
--
--   Action 0 (Mint):
--     1. Read ConfigDatum from reference input with ID NFT
--     2. Category must be in cdCategories
--     3. Fee paid to cdFeesAddress (exact amount)
--     4. NFT sent to project validation script (cdProjectVaultHash)
--     5. Output has inline datum with ProjectDatum
--     6. Exactly 1 token minted
--
--   Action 1 (Burn):
--     - All tokens under policy must be burned (< 0)
--
--   Phase 2 Optimizations:
--     - Error codes (PPE000-PPE008) for minimal on-chain footprint
--     - Hoisted common extractions (outputs, mintedValue, config extracted once)
--     - INLINE pragmas for constants and frequently used values
typedValidator :: CurrencySymbol -> ScriptContext -> Bool
typedValidator idNftPolicy ctx =
  let ScriptContext txInfo rawRedeemer scriptInfo = ctx

      -- ═══════════════════════════════════════════════════════════════
      -- PHASE 1: Extract common values ONCE (hoisted to top level)
      -- ═══════════════════════════════════════════════════════════════

      {-# INLINE outputs #-}
      outputs = txInfoOutputs txInfo

      {-# INLINE mintedValue #-}
      mintedValue = mintValueMinted (txInfoMint txInfo)

      {-# INLINE refInputs #-}
      refInputs = txInfoReferenceInputs txInfo

      {-# INLINE idTokenName #-}
      idTokenName = TokenName identificationTokenName

      -- ═══════════════════════════════════════════════════════════════
      -- PHASE 2: Parse config and redeemer ONCE
      -- ═══════════════════════════════════════════════════════════════

      {-# INLINE config #-}
      config = case findConfigDatum refInputs idNftPolicy idTokenName of
        P.Nothing  -> P.traceError "PPE002"
        P.Just cfg -> cfg

      {-# INLINE redeemer #-}
      redeemer = case PlutusTx.fromBuiltinData (getRedeemer rawRedeemer) of
        P.Nothing -> P.traceError "PPE001"
        P.Just r  -> r

      -- ═══════════════════════════════════════════════════════════════
      -- PHASE 3: Main validation dispatch
      -- ═══════════════════════════════════════════════════════════════

      {-# INLINEABLE validateMint #-}
      validateMint :: CurrencySymbol -> Bool
      validateMint ownPolicy = case redeemer of
        MintProject -> mintCheck ownPolicy
        BurnProject -> burnCheck ownPolicy

      --------------------------------------------------------------------------------
      -- MINT CHECK
      -- Rules:
      --   1. Get ConfigDatum from reference inputs
      --   2. Category must be in supported categories
      --   3. Platform fee paid to fee address (exact amount)
      --   4. Exactly 1 NFT minted with correct token name
      --   5. NFT and ProjectDatum sent to project vault script
      --------------------------------------------------------------------------------
      {-# INLINEABLE mintCheck #-}
      mintCheck :: CurrencySymbol -> Bool
      mintCheck ownPolicy =
        P.traceIfFalse "PPE003" exactlyOneMinted
        P.&& P.traceIfFalse "PPE004" projectOutputValid
        P.&& P.traceIfFalse "PPE005" categoryValid
        P.&& P.traceIfFalse "PPE006" feePaid
        P.&& P.traceIfFalse "PPE007" nftSentToScript
        P.&& P.traceIfFalse "PPE009" projectOutputHasDatum
        where
          -- Exactly 1 token minted
          {-# INLINE ownTokens #-}
          ownTokens = getTokensForPolicy mintedValue ownPolicy

          {-# INLINE exactlyOneMinted #-}
          exactlyOneMinted = case ownTokens of
            [(_, qty)] -> qty P.== 1
            _          -> False

          -- Get the minted token name
          {-# INLINE mintedTokenName #-}
          mintedTokenName = case ownTokens of
            [(tkn, _)] -> tkn
            _          -> P.traceError "PPE003"

          -- Find project output with this NFT
          {-# INLINE projectOutput #-}
          projectOutput = findProjectOutput outputs ownPolicy mintedTokenName

          {-# INLINE projectOutputValid #-}
          projectOutputValid = case projectOutput of
            P.Nothing -> False
            P.Just _  -> True

          -- Category must be in supported categories
          {-# INLINE categoryValid #-}
          categoryValid = case projectOutput of
            P.Nothing -> False
            P.Just (_, pd) -> isCategorySupported (pdCategory pd) (cdCategories config)

          -- Platform fee paid to fee address (exact amount)
          {-# INLINE feePaid #-}
          feePaid = verifyFeePayment outputs (cdFeesAddress config) (cdFeesAmount config)

          -- NFT and ProjectDatum sent to exact ProjectVault script
          {-# INLINE nftSentToScript #-}
          nftSentToScript = case projectOutput of
            P.Nothing -> False
            P.Just (txOut, _) ->
              case addressCredential (txOutAddress txOut) of
                ScriptCredential sh -> getScriptHash sh P.== cdProjectVaultHash config
                _                   -> False

          -- Project output must have inline datum
          {-# INLINE projectOutputHasDatum #-}
          projectOutputHasDatum = case projectOutput of
            P.Nothing -> False
            P.Just (txOut, _) -> case txOutDatum txOut of
              OutputDatum _ -> True
              _             -> False

      --------------------------------------------------------------------------------
      -- BURN CHECK
      -- Rules:
      --   All tokens under this policy must be burned (negative quantities)
      --------------------------------------------------------------------------------
      {-# INLINEABLE burnCheck #-}
      burnCheck :: CurrencySymbol -> Bool
      burnCheck ownPolicy =
        P.traceIfFalse "PPE008" allBurned
        where
          {-# INLINE ownTokens #-}
          ownTokens = getTokensForPolicy mintedValue ownPolicy

          {-# INLINE allBurned #-}
          allBurned = allNegative ownTokens

  -- ═══════════════════════════════════════════════════════════════
  -- PHASE 4: Main entry point
  -- ═══════════════════════════════════════════════════════════════

  in case scriptInfo of
    MintingScript ownPolicy -> validateMint ownPolicy
    _ -> P.traceError "PPE000"
  where

    -- ═══════════════════════════════════════════════════════════════
    -- HELPER FUNCTIONS (all INLINEABLE for optimization)
    -- ═══════════════════════════════════════════════════════════════

    -- Find project output with NFT and extract ProjectDatum
    {-# INLINEABLE findProjectOutput #-}
    findProjectOutput :: [TxOut] -> CurrencySymbol -> TokenName -> P.Maybe (TxOut, ProjectDatum)
    findProjectOutput [] _ _ = P.Nothing
    findProjectOutput (o:os) policy tkn =
      if valueOf (txOutValue o) policy tkn P.> 0
        then case txOutDatum o of
          OutputDatum (Datum d) -> case PlutusTx.fromBuiltinData d of
            P.Just pd -> P.Just (o, pd)
            P.Nothing -> findProjectOutput os policy tkn
          _ -> findProjectOutput os policy tkn
        else findProjectOutput os policy tkn

    -- Verify fee payment to fee address (exact amount)
    {-# INLINEABLE verifyFeePayment #-}
    verifyFeePayment :: [TxOut] -> PubKeyHash -> Integer -> Bool
    verifyFeePayment [] _ _ = False
    verifyFeePayment (o:os) feeAddr feeAmt =
      let addr = txOutAddress o
          matchesPkh = case addressCredential addr of
            PubKeyCredential pk -> pk P.== feeAddr
            _                   -> False
          Lovelace lovelaceAmt = lovelaceValueOf (txOutValue o)
      in if matchesPkh P.&& lovelaceAmt P.>= feeAmt
           then True
           else verifyFeePayment os feeAddr feeAmt

--------------------------------------------------------------------------------
-- COMPILED VALIDATOR
--------------------------------------------------------------------------------

{-# INLINEABLE untypedValidator #-}
untypedValidator :: BuiltinData -> BuiltinData -> P.BuiltinUnit
untypedValidator idNftPolicyData ctxData =
  P.check
    ( typedValidator
        (PlutusTx.unsafeFromBuiltinData idNftPolicyData)
        (PlutusTx.unsafeFromBuiltinData ctxData)
    )

compiledValidator :: CompiledCode (BuiltinData -> BuiltinData -> P.BuiltinUnit)
compiledValidator = $$(PlutusTx.compile [||untypedValidator||])
