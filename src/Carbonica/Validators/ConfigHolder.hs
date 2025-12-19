{- |
Module      : Carbonica.Validators.ConfigHolder
Description : Spending validator that protects the platform configuration
License     : Apache-2.0

The Config Holder validator locks the ConfigDatum along with the Identification NFT.
It can only be spent when a DAO proposal is being executed.

This ensures that platform settings (fees, validators, categories) can only
be changed through the official DAO governance process.

VALIDATION LOGIC:
  - Finds DAO input/output by proposal NFT
  - Verifies proposal state transition: InProgress → Executed
  - Ensures Identification NFT continues in output

PHASE 4 OPTIMIZATIONS:
  - Uses shared validation helpers from Carbonica.Validators.Common
  - Removed 35+ lines of duplicate helper functions
  - All validation now uses battle-tested Common module
-}

{- ══════════════════════════════════════════════════════════════════════════
   ERROR CODE REGISTRY - ConfigHolder Validator
   ══════════════════════════════════════════════════════════════════════════

   CHE000 - Invalid script context
            Cause: Not a spending script OR missing inline datum
            Fix: Ensure UTxO has inline datum and is being spent

   CHE001 - ConfigDatum parse failed
            Cause: Datum bytes don't deserialize to ConfigDatum
            Fix: Verify datum structure matches ConfigDatum schema

   CHE002 - ConfigHolderRedeemer parse failed
            Cause: Redeemer bytes don't deserialize to ConfigHolderRedeemer
            Fix: Verify redeemer structure (should be ConfigUpdate with proposal_id)

   CHE003 - DAO proposal state transition invalid
            Cause: Either DAO input not found, input state != InProgress,
                   DAO output not found, or output state != Executed
            Fix: Verify proposal NFT present in inputs/outputs with correct states
            Details: Input must be ProposalInProgress, output must be ProposalExecuted

   CHE005 - Identification NFT not in outputs
            Cause: Config UTxO being consumed but ID NFT not continuing
            Fix: Ensure continuing output contains the Identification NFT

   ══════════════════════════════════════════════════════════════════════════
-}

module Carbonica.Validators.ConfigHolder where

import           GHC.Generics                   (Generic)
import           PlutusLedgerApi.V3             (BuiltinByteString,
                                                 CurrencySymbol, Datum (..),
                                                 ScriptContext (..),
                                                 ScriptInfo (..), TokenName (..),
                                                 TxInInfo (..),
                                                 TxInfo (..),
                                                 getRedeemer)
import           PlutusTx
import           PlutusTx.Blueprint
import qualified PlutusTx.Prelude               as P

import           Carbonica.Types.Config         (ConfigDatum,
                                                 identificationTokenName)
import           Carbonica.Types.Governance     (gdState,
                                                 ProposalState (..))
import           Carbonica.Validators.Common    (extractDatum,
                                                 findInputByNft,
                                                 findOutputByNft,
                                                 hasTokenInOutputs)

--------------------------------------------------------------------------------
-- REDEEMER
--------------------------------------------------------------------------------

-- | Actions for the Config Holder validator
data ConfigHolderRedeemer
  = ConfigUpdate BuiltinByteString
  -- ^ Update config by executing a DAO proposal (proposal_id as token name)
  deriving stock (Generic)
  deriving anyclass (HasBlueprintDefinition)

PlutusTx.makeIsDataSchemaIndexed ''ConfigHolderRedeemer [('ConfigUpdate, 0)]

--------------------------------------------------------------------------------
-- VALIDATOR LOGIC
--------------------------------------------------------------------------------

{-# INLINEABLE typedValidator #-}
-- | Config Holder spending validator (OPTIMIZED - Phase 2)
--
--   Parameters:
--     idNftPolicy - The Identification NFT policy ID (to verify ownership)
--     daoPolicyId - The DAO Governance policy ID (to find proposal)
--
--   Spending Rules:
--     1. Find DAO input by proposal NFT (daoPolicyId, proposal_id)
--     2. Find DAO output by proposal NFT (daoPolicyId, proposal_id)
--     3. Verify input.proposal_state == InProgress
--     4. Verify output.proposal_state == Executed
--     5. ID NFT must remain in continuing output
--
--   Phase 2 Optimizations:
--     - Error codes (CHE000-CHE005) for minimal on-chain footprint
--     - Hoisted common extractions (inputs, outputs extracted once)
--     - Combined DAO input/output validation (single check, parse datums once)
--     - INLINE pragmas for constants
typedValidator :: CurrencySymbol -> CurrencySymbol -> ScriptContext -> Bool
typedValidator idNftPolicy daoPolicyId ctx =
  let ScriptContext txInfo rawRedeemer scriptInfo = ctx

      -- ═══════════════════════════════════════════════════════════════
      -- PHASE 1: Extract common values ONCE (hoisted to top level)
      -- ═══════════════════════════════════════════════════════════════

      {-# INLINE outputs #-}
      outputs = txInfoOutputs txInfo
      {-# INLINE inputs #-}
      inputs = txInfoInputs txInfo

      -- ID NFT token name (constant)
      {-# INLINE idTokenName #-}
      idTokenName = TokenName identificationTokenName

      -- ═══════════════════════════════════════════════════════════════
      -- PHASE 2: Parse redeemer ONCE
      -- ═══════════════════════════════════════════════════════════════

      {-# INLINE redeemer #-}
      redeemer = case PlutusTx.fromBuiltinData (getRedeemer rawRedeemer) of
        P.Nothing -> P.traceError "CHE002"
        P.Just r  -> r

      -- ═══════════════════════════════════════════════════════════════
      -- PHASE 3: Main validation dispatch
      -- ═══════════════════════════════════════════════════════════════

      {-# INLINEABLE validateSpend #-}
      validateSpend :: ConfigDatum -> ConfigHolderRedeemer -> Bool
      validateSpend _configDatum (ConfigUpdate proposalId) =
        let {-# INLINE proposalTkn #-}
            proposalTkn = TokenName proposalId

            -- ═══════════════════════════════════════════════════════════
            -- OPTIMIZATION: Combined DAO state transition validation
            -- Find input + output, extract datums, validate states - all in one
            -- ═══════════════════════════════════════════════════════════

            {-# INLINE validDaoTransition #-}
            validDaoTransition =
              case (findDaoInput, findDaoOutput) of
                (P.Just inputDatum, P.Just outputDatum) ->
                  gdState inputDatum P.== ProposalInProgress
                  P.&& gdState outputDatum P.== ProposalExecuted
                _ -> False
              where
                {-# INLINE findDaoInput #-}
                findDaoInput = findInputByNft inputs daoPolicyId proposalTkn
                               P.>>= extractDatum P.. txInInfoResolved

                {-# INLINE findDaoOutput #-}
                findDaoOutput = findOutputByNft outputs daoPolicyId proposalTkn
                                P.>>= extractDatum

            -- ═══════════════════════════════════════════════════════════
            -- ID NFT must continue to an output
            -- ═══════════════════════════════════════════════════════════

            {-# INLINE idNftInOutput #-}
            idNftInOutput = hasTokenInOutputs outputs idNftPolicy idTokenName

        in P.traceIfFalse "CHE003" validDaoTransition
           P.&& P.traceIfFalse "CHE005" idNftInOutput

  -- ═══════════════════════════════════════════════════════════════
  -- PHASE 4: Main entry point (parse datum and delegate)
  -- ═══════════════════════════════════════════════════════════════

  in case scriptInfo of
    SpendingScript _oref (Just (Datum datumData)) ->
      case PlutusTx.fromBuiltinData datumData of
        P.Nothing -> P.traceError "CHE001"
        P.Just datum -> validateSpend datum redeemer
    _ -> P.traceError "CHE000"

--------------------------------------------------------------------------------
-- COMPILED VALIDATOR
--------------------------------------------------------------------------------

{-# INLINEABLE untypedValidator #-}
-- | Untyped wrapper for the validator
untypedValidator :: BuiltinData -> BuiltinData -> BuiltinData -> P.BuiltinUnit
untypedValidator idNftPolicyData daoPolicyData ctxData =
  P.check
    ( typedValidator
        (PlutusTx.unsafeFromBuiltinData idNftPolicyData)
        (PlutusTx.unsafeFromBuiltinData daoPolicyData)
        (PlutusTx.unsafeFromBuiltinData ctxData)
    )

-- | Compile the validator to Plutus Core
compiledValidator :: CompiledCode (BuiltinData -> BuiltinData -> BuiltinData -> P.BuiltinUnit)
compiledValidator = $$(PlutusTx.compile [||untypedValidator||])
