{- |
Module      : Carbonica.Validators.ProjectVault
Description : Spending validator that holds Project NFTs during voting
License     : Apache-2.0

The Project Vault locks Project NFTs while validators vote on them.
Projects can only exit the vault when:
  - Approved: COT tokens minted, NFT burned, developer gets COT
  - Rejected: NFT burned, no COT minted

VALIDATION LOGIC:

  Approve Action (Action 0):
    - Developer receives minted COT tokens (payout.exact)
    - Project NFT burned
    - Multisig verification
    - Token name derived from oref

  Reject Action (Action 1):
    - Project NFT burned
    - Multisig verification

Vote rules:
  - Voter must be in multisig group (from ConfigDatum)
  - Voter has not already voted
  - Project is in Submitted status

PHASE 4 OPTIMIZATIONS:
  - Uses shared validation helpers from Carbonica.Validators.Common
  - Removed findConfigFromRefs (now uses findConfigDatum)
  - All validation now uses battle-tested Common module
-}

{- ══════════════════════════════════════════════════════════════════════════
   ERROR CODE REGISTRY - ProjectVault Validator
   ══════════════════════════════════════════════════════════════════════════

   PVE000 - Invalid script context
            Cause: Not a spending script OR missing inline datum
            Fix: Ensure UTxO has inline datum and is being spent

   PVE001 - ProjectDatum parse failed
            Cause: Datum bytes don't deserialize to ProjectDatum
            Fix: Verify datum structure matches ProjectDatum schema

   PVE002 - Redeemer parse failed
            Cause: Redeemer bytes don't deserialize to ProjectVaultRedeemer
            Fix: Verify redeemer is Vote/ApproveProject/RejectProject

   PVE003 - ConfigDatum not found
            Cause: No reference input contains ID NFT with ConfigDatum
            Fix: Include config holder as reference input

   PVE004 - Voter did not sign transaction
            Cause: The voter's PubKeyHash is not verified via txSignedBy
            Fix: Ensure the specific voter signs the transaction

   PVE005 - Voter not in multisig
            Cause: Signer not in ConfigDatum.cdMultisig.msSigners
            Fix: Only multisig members can vote

   PVE006 - Voter already voted
            Cause: Signer's PKH found in ProjectDatum.pdVoters
            Fix: Each voter can only vote once

   PVE007 - Project not submitted
            Cause: Project status != Submitted
            Fix: Can only vote on projects in Submitted status

   PVE008 - Continuing output invalid
            Cause: No output back to script OR datum mismatch
            Fix: Ensure project continues to vault with updated datum

   PVE009 - Insufficient quorum
            Cause: Total votes < required votes
            Fix: Gather enough votes before approve/reject

   PVE010 - Project NFT not burned
            Cause: NFT not being burned (qty >= 0)
            Fix: Ensure project NFT has negative mint quantity

   PVE011 - Developer payment missing
            Cause: Developer not receiving COT tokens
            Fix: Pay COT amount to developer address

   PVE012 - Multisig not satisfied
            Cause: Not enough multisig signatures
            Fix: Provide required number of multisig signatures

   PVE013 - Vote count not incremented correctly
            Cause: Neither (yesVotes+1, noVotes same) nor (noVotes+1, yesVotes same)
            Fix: Exactly one counter must increment by 1, the other must stay unchanged

   PVE014 - Voter not added to voters list
            Cause: output pdVoters length != input pdVoters length + 1
            Fix: Ensure voter PKH is added to pdVoters

   PVE015 - Project name mutated
            Cause: output pdProjectName != input pdProjectName
            Fix: Non-vote fields must be preserved

   PVE016 - Developer address mutated
            Cause: output pdDeveloper != input pdDeveloper
            Fix: Non-vote fields must be preserved

   PVE017 - COT amount mutated
            Cause: output pdCotAmount != input pdCotAmount
            Fix: Non-vote fields must be preserved

   PVE018 - Project status mutated
            Cause: output pdStatus != input pdStatus
            Fix: Status must remain unchanged during voting

   PVE019 - Category mutated
            Cause: output pdCategory != input pdCategory
            Fix: Non-vote fields must be preserved

   PVE020 - Description mutated
            Cause: output pdDescription != input pdDescription
            Fix: Non-vote fields must be preserved

   PVE021 - Submission time mutated
            Cause: output pdSubmittedAt != input pdSubmittedAt
            Fix: Non-vote fields must be preserved

   PVE022 - No valid continuing output
            Cause: zero or multiple continuing outputs, or datum extraction failed
            Fix: Exactly one output must continue to script with valid ProjectDatum

   ══════════════════════════════════════════════════════════════════════════
-}

module Carbonica.Validators.ProjectVault where

import           PlutusLedgerApi.V3             (CurrencySymbol (..),
                                                 Datum (..),
                                                 PubKeyHash,
                                                 ScriptContext (..),
                                                 ScriptInfo (..),
                                                 TokenName (..),
                                                 TxInfo (..),
                                                 TxOutRef,
                                                 getRedeemer)
import           PlutusLedgerApi.V3.Contexts   (getContinuingOutputs, txSignedBy)
import           PlutusLedgerApi.V3.MintValue   (mintValueMinted)
import           PlutusLedgerApi.V1.Value       (valueOf)
import           PlutusTx
import qualified PlutusTx.Prelude               as P

import           Carbonica.Types.Config         (Multisig (..),
                                                 cdCotPolicyId,
                                                 cdMultisig,
                                                 identificationTokenName)
import           Carbonica.Types.Project        (ProjectDatum,
                                                 ProjectStatus (..),
                                                 ProjectVaultRedeemer (..),
                                                 pdCategory,
                                                 pdCotAmount,
                                                 pdDescription,
                                                 pdDeveloper,
                                                 pdNoVotes,
                                                 pdProjectName,
                                                 pdStatus,
                                                 pdSubmittedAt,
                                                 pdVoters,
                                                 pdYesVotes)
import           Carbonica.Validators.Common    (anySignerInList,
                                                 countMatching,
                                                 extractDatum,
                                                 findConfigDatum,
                                                 isInList,
                                                 payoutTokenExact)

--------------------------------------------------------------------------------
-- VALIDATOR LOGIC
--------------------------------------------------------------------------------

-- | Project Vault spending validator.
--
--   Parameters:
--     idNftPolicy   - Identification NFT policy (to find config)
--     projectPolicy - Project NFT policy (to verify burning)
--
--   VaultVote:    voter signs, is in multisig, has not voted, project Submitted.
--   VaultApprove: quorum met, project NFT burned, developer gets COT, multisig.
--   VaultReject:  quorum met, project NFT burned, multisig.
{-# INLINEABLE typedValidator #-}
typedValidator :: CurrencySymbol -> CurrencySymbol -> ScriptContext -> Bool
typedValidator idNftPolicy projectPolicy ctx =
  let ScriptContext txInfo rawRedeemer scriptInfo = ctx

      -- ═══════════════════════════════════════════════════════════════
      -- PHASE 1: Extract common values ONCE (hoisted to top level)
      -- ═══════════════════════════════════════════════════════════════

      {-# INLINE outputs #-}
      outputs = txInfoOutputs txInfo

      {-# INLINE signatories #-}
      signatories = txInfoSignatories txInfo

      {-# INLINE mintedValue #-}
      mintedValue = mintValueMinted (txInfoMint txInfo)

      {-# INLINE refInputs #-}
      refInputs = txInfoReferenceInputs txInfo

      {-# INLINE idTokenName #-}
      idTokenName = TokenName identificationTokenName

      -- ═══════════════════════════════════════════════════════════════
      -- PHASE 2: Parse config and redeemer ONCE
      -- ═══════════════════════════════════════════════════════════════

      {-# INLINE configDatum #-}
      configDatum = case findConfigDatum refInputs idNftPolicy idTokenName of
        P.Nothing -> P.traceError "PVE003"
        P.Just cfg -> cfg

      {-# INLINE redeemer #-}
      redeemer = case PlutusTx.fromBuiltinData (getRedeemer rawRedeemer) of
        P.Nothing -> P.traceError "PVE002"
        P.Just r  -> r

      {-# INLINEABLE listLength #-}
      listLength :: [a] -> Integer
      listLength []     = 0
      listLength (_:xs) = 1 P.+ listLength xs

      -- ═══════════════════════════════════════════════════════════════
      -- PHASE 3: Main validation dispatch
      -- ═══════════════════════════════════════════════════════════════

      {-# INLINEABLE validateSpend #-}
      validateSpend :: TxOutRef -> ProjectDatum -> Bool
      validateSpend oref projectDatum = case redeemer of
        VaultVote    -> validateVote projectDatum
        VaultApprove -> validateApprove oref projectDatum
        VaultReject  -> validateReject oref projectDatum


      --------------------------------------------------------------------------------
      -- VOTE VALIDATION
      -- Voter must be in multisig group, not already voted, project is Submitted
      --------------------------------------------------------------------------------
      {-# INLINEABLE validateVote #-}
      validateVote :: ProjectDatum -> Bool
      validateVote projectDatum =
        P.traceIfFalse "PVE004" voterSigned
        P.&& P.traceIfFalse "PVE005" voterInMultisig
        P.&& P.traceIfFalse "PVE006" notAlreadyVoted
        P.&& P.traceIfFalse "PVE007" isSubmitted
        P.&& P.traceIfFalse "PVE022" outputDatumValid
        where
          {-# INLINE multisigSigners #-}
          multisigSigners = msSigners (cdMultisig configDatum)

          {-# INLINE existingVoters #-}
          existingVoters = pdVoters projectDatum

          -- Voter specifically signed (verified via txSignedBy)
          {-# INLINE voter #-}
          voter :: PubKeyHash
          voter = case signatories of
            (s:_) -> s
            []    -> P.traceError "PVE004"

          {-# INLINE voterSigned #-}
          voterSigned = txSignedBy txInfo voter

          {-# INLINE voterInMultisig #-}
          voterInMultisig = anySignerInList signatories multisigSigners

          {-# INLINE notAlreadyVoted #-}
          notAlreadyVoted = P.not (anySignerInList signatories existingVoters)

          {-# INLINE isSubmitted #-}
          isSubmitted = pdStatus projectDatum P.== ProjectSubmitted

          -- CRIT-01 FIX: Verify the continuing output datum matches expected state transition.
          -- Enforces exactly one counter incremented by 1, the other unchanged.
          -- Prevents vote manipulation (e.g., +2 yes / -1 no netting to +1 total).
          {-# INLINE continuingOutputDatum #-}
          continuingOutputDatum :: P.Maybe ProjectDatum
          continuingOutputDatum = case getContinuingOutputs ctx of
            [o] -> extractDatum o
            _   -> P.Nothing

          {-# NOINLINE outputDatumValid #-}
          outputDatumValid :: Bool
          outputDatumValid = case continuingOutputDatum of
            P.Nothing -> False
            P.Just outDatum ->
              -- Vote count: exactly one counter +1, other unchanged
              P.traceIfFalse "PVE013"
                ((pdYesVotes outDatum P.== pdYesVotes projectDatum P.+ 1
                  P.&& pdNoVotes outDatum P.== pdNoVotes projectDatum)
                 P.||
                 (pdNoVotes outDatum P.== pdNoVotes projectDatum P.+ 1
                  P.&& pdYesVotes outDatum P.== pdYesVotes projectDatum))
              -- Voter added to voters list: must be prepended, must be a multisig signer who signed
              P.&& P.traceIfFalse "PVE014" (case pdVoters outDatum of
                (newVoter:restVoters) ->
                  isInList newVoter multisigSigners
                  P.&& isInList newVoter signatories
                  P.&& restVoters P.== pdVoters projectDatum
                [] -> False)
              -- Immutable fields unchanged
              P.&& P.traceIfFalse "PVE015" (pdProjectName outDatum P.== pdProjectName projectDatum)
              P.&& P.traceIfFalse "PVE016" (pdDeveloper outDatum P.== pdDeveloper projectDatum)
              P.&& P.traceIfFalse "PVE017" (pdCotAmount outDatum P.== pdCotAmount projectDatum)
              P.&& P.traceIfFalse "PVE018" (pdStatus outDatum P.== pdStatus projectDatum)
              P.&& P.traceIfFalse "PVE019" (pdCategory outDatum P.== pdCategory projectDatum)
              P.&& P.traceIfFalse "PVE020" (pdDescription outDatum P.== pdDescription projectDatum)
              P.&& P.traceIfFalse "PVE021" (pdSubmittedAt outDatum P.== pdSubmittedAt projectDatum)

      --------------------------------------------------------------------------------
      -- APPROVE VALIDATION
      -- Rules:
      --   1. Developer receives COT (payout.exact)
      --   2. Project NFT burned
      --   3. Token name derived from oref
      --------------------------------------------------------------------------------
      {-# INLINEABLE validateApprove #-}
      validateApprove :: TxOutRef -> ProjectDatum -> Bool
      validateApprove _oref projectDatum =
        P.traceIfFalse "PVE009" hasQuorum
        P.&& P.traceIfFalse "PVE010" projectBurned
        P.&& P.traceIfFalse "PVE011" developerPaid
        P.&& P.traceIfFalse "PVE012" multisigSatisfied
        where
          {-# INLINE requiredVotes #-}
          requiredVotes = msRequired (cdMultisig configDatum)

          {-# INLINE yesVotes #-}
          yesVotes = pdYesVotes projectDatum

          {-# INLINE hasQuorum #-}
          hasQuorum = yesVotes P.>= requiredVotes

          {-# INLINE projectTokenName #-}
          projectTokenName = TokenName (pdProjectName projectDatum)

          {-# INLINE projectBurned #-}
          projectBurned = valueOf mintedValue projectPolicy projectTokenName P.< 0

          {-# INLINE developerPaid #-}
          developerPaid =
            payoutTokenExact (pdDeveloper projectDatum)
              (CurrencySymbol (cdCotPolicyId configDatum))
              projectTokenName
              (pdCotAmount projectDatum)
              outputs

          {-# INLINE multisigSatisfied #-}
          multisigSatisfied =
            countMatching signatories (msSigners (cdMultisig configDatum))
              P.>= msRequired (cdMultisig configDatum)

      --------------------------------------------------------------------------------
      -- REJECT VALIDATION
      -- Rules:
      --   1. Project NFT burned
      --   2. Multisig verification
      --------------------------------------------------------------------------------
      {-# INLINEABLE validateReject #-}
      validateReject :: TxOutRef -> ProjectDatum -> Bool
      validateReject _oref projectDatum =
        P.traceIfFalse "PVE009" hasRejectionQuorum
        P.&& P.traceIfFalse "PVE010" projectBurned
        P.&& P.traceIfFalse "PVE012" multisigSatisfied
        where
          {-# INLINE requiredVotes #-}
          requiredVotes = msRequired (cdMultisig configDatum)

          {-# INLINE noVotes #-}
          noVotes = pdNoVotes projectDatum

          {-# INLINE hasRejectionQuorum #-}
          hasRejectionQuorum = noVotes P.>= requiredVotes

          {-# INLINE projectTokenName #-}
          projectTokenName = TokenName (pdProjectName projectDatum)

          {-# INLINE projectBurned #-}
          projectBurned = valueOf mintedValue projectPolicy projectTokenName P.< 0

          {-# INLINE multisigSatisfied #-}
          multisigSatisfied =
            countMatching signatories (msSigners (cdMultisig configDatum))
              P.>= msRequired (cdMultisig configDatum)

  -- ═══════════════════════════════════════════════════════════════
  -- PHASE 4: Main entry point (parse datum and delegate)
  -- ═══════════════════════════════════════════════════════════════

  in case scriptInfo of
    SpendingScript oref (Just (Datum datumData)) ->
      case PlutusTx.fromBuiltinData datumData of
        P.Nothing -> P.traceError "PVE001"
        P.Just projectDatum -> validateSpend oref projectDatum
    _ -> P.traceError "PVE000"

--------------------------------------------------------------------------------
-- COMPILED VALIDATOR
--------------------------------------------------------------------------------

-- | Untyped entry point for the Project Vault spending validator.
--
-- First arg: idNftPolicy. Second arg: projectPolicy. Third arg: ScriptContext.
{-# INLINEABLE untypedValidator #-}
untypedValidator :: BuiltinData -> BuiltinData -> BuiltinData -> P.BuiltinUnit
untypedValidator idNftPolicyData projectPolicyData ctxData =
  P.check
    ( typedValidator
        (PlutusTx.unsafeFromBuiltinData idNftPolicyData)
        (PlutusTx.unsafeFromBuiltinData projectPolicyData)
        (PlutusTx.unsafeFromBuiltinData ctxData)
    )

-- | Compiled UPLC code for on-chain deployment of the Project Vault validator.
compiledValidator :: CompiledCode (BuiltinData -> BuiltinData -> BuiltinData -> P.BuiltinUnit)
compiledValidator = $$(PlutusTx.compile [||untypedValidator||])
