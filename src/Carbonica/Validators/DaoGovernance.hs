{- |
Module      : Carbonica.Validators.DaoGovernance
Description : DAO Governance validator for Carbonica platform
License     : Apache-2.0

This validator handles the DAO proposal lifecycle:
  1. Submit proposal -> Mint proposal NFT
  2. Vote on proposal -> Update GovernanceDatum
  3. Execute proposal -> Update ConfigDatum
  4. Reject proposal -> Burn proposal NFT

5 members, 3 required for any action.

VALIDATION RULES

Vote Action:
    - Proposal ID unchanged
    - State == InProgress
    - Before deadline
    - Voter status was Pending (index into votes list)
    - Voter in multisig group
    - Vote count incremented
    - Voter status updated to Voted

Execute Action:
    - Past deadline
    - Yes > No
    - State -> Executed
    - ConfigDatum update verification for proposal action

Reject Action:
    - Past deadline
    - No >= Yes
    - State -> Rejected
-}

{- ══════════════════════════════════════════════════════════════════════════
   ERROR CODE REGISTRY - DaoGovernance Validator
   ══════════════════════════════════════════════════════════════════════════

   MINTING POLICY ERRORS (DGE000-DGE003):

   DGE000 - Invalid minting context
            Cause: Not a minting script context
            Fix: Ensure script is being used as minting policy

   DGE001 - Redeemer parse failed (mint)
            Cause: Redeemer bytes don't deserialize to DaoMintRedeemer
            Fix: Verify redeemer structure matches DaoMintRedeemer schema

   DGE002 - Submitter must sign
            Cause: No signatures in transaction for proposal submission
            Fix: Include at least one signature

   DGE003 - Output missing proposal NFT
            Cause: No output contains the proposal NFT being minted
            Fix: Ensure output to script includes minted proposal NFT

   DGE004 - Output state invalid
            Cause: Output datum not found OR proposal_id mismatch OR state != InProgress
            Fix: Verify output has correct GovernanceDatum with matching ID and InProgress state

   DGE013 - ConfigDatum not found during mint
            Cause: No reference input contains ID NFT with ConfigDatum
            Fix: Include config holder as reference input when submitting proposals

   DGE014 - Submitter not authorized for mint
            Cause: Transaction signatories do not satisfy multisig requirement from ConfigDatum
            Fix: Required number of authorized multisig members must sign

   SPENDING VALIDATOR ERRORS (DGE005-DGE012, DGE015-DGE016):

   DGE005 - Invalid spending context
            Cause: Not a spending script OR missing inline datum
            Fix: Ensure UTxO has inline datum and is being spent

   DGE006 - GovernanceDatum parse failed
            Cause: Datum bytes don't deserialize to GovernanceDatum
            Fix: Verify datum structure matches GovernanceDatum schema

   DGE007 - Redeemer parse failed (spend)
            Cause: Redeemer bytes don't deserialize to DaoSpendRedeemer
            Fix: Verify redeemer structure (Vote/Execute/Reject)

   DGE008 - ConfigDatum not found
            Cause: No reference input contains ID NFT with ConfigDatum
            Fix: Include config holder as reference input for multisig verification

   DGE009 - No continuing output
            Cause: No output going back to same script address
            Fix: Ensure proposal UTxO continues to script (except for final states)

   DGE010 - Voter not in votes list
            Cause: Signer's PKH not found in GovernanceDatum votes list
            Fix: Ensure voter was included when proposal was created

   DGE011 - Input ConfigDatum not found
            Cause: No reference input with ID NFT during Execute action
            Fix: Include config holder as reference input

   DGE012 - Output ConfigDatum not found
            Cause: No output with ID NFT during Execute action
            Fix: Ensure updated ConfigDatum is sent to config holder

   DGE015 - Non-target ConfigDatum field mutated
            Cause: A field not targeted by the ProposalAction was changed between input and output ConfigDatum
            Fix: Only the field specified by the ProposalAction may change

   DGE016 - Governance deadlock risk
            Cause: ActionRemoveSigner would leave msRequired > remaining signers count,
                   or ActionUpdateRequired sets value outside [1, signers count]
            Fix: Ensure required threshold is achievable after the change

   ══════════════════════════════════════════════════════════════════════════
-}

module Carbonica.Validators.DaoGovernance where

import           PlutusLedgerApi.V3             (CurrencySymbol,
                                                 Datum (..),
                                                 OutputDatum (..),
                                                 PubKeyHash,
                                                 ScriptContext (..),
                                                 ScriptInfo (..),
                                                 TokenName (..),
                                                 TxInInfo (..),
                                                 TxInfo (..),
                                                 TxOut (..),
                                                 getRedeemer,
                                                 txInfoValidRange)
import           PlutusLedgerApi.V3.Contexts    (getContinuingOutputs)
import           PlutusLedgerApi.V1.Interval    (before)
import           PlutusLedgerApi.V1.Value       (valueOf)
import           PlutusTx
import qualified PlutusTx.Prelude               as P

import           Carbonica.Types.Config         (ConfigDatum,
                                                 Multisig (..),
                                                 cdCategories,
                                                 cdCetPolicyId,
                                                 cdCotPolicyId,
                                                 cdFeesAddress,
                                                 cdFeesAmount,
                                                 cdMultisig,
                                                 cdProjectPolicyId,
                                                 cdProjectVaultHash,
                                                 cdProposalDuration,
                                                 cdUserVaultHash,
                                                 cdVotingHash,
                                                 identificationTokenName)
import           Carbonica.Validators.Common    (findConfigDatum,
                                                 findDatumInOutputs,
                                                 isInList,
                                                 validateMultisig)
import           Carbonica.Types.Governance     (GovernanceDatum,
                                                 ProposalState (..),
                                                 Vote (..),
                                                 VoteRecord (..),
                                                 VoterStatus (..),
                                                 ProposalAction (..),
                                                 DaoSpendRedeemer (..),
                                                 DaoMintRedeemer (..),
                                                 gdProposalId,
                                                 gdState,
                                                 gdDeadline,
                                                 gdVotes,
                                                 gdYesCount,
                                                 gdNoCount,
                                                 gdAbstainCount,
                                                 gdAction)

--------------------------------------------------------------------------------
-- MINTING POLICY (Submit/Burn proposals)
--------------------------------------------------------------------------------

{-# INLINEABLE mintValidator #-}
-- | DAO Governance minting policy (OPTIMIZED - Phase 2)
--
--   Phase 2 Optimizations:
--     - Error codes (DGE000-DGE004) for minimal on-chain footprint
--     - Hoisted common extractions (outputs, signatories extracted once)
--     - INLINE pragmas for frequently used values
--
--   Minting Policy Rules:
--     - SubmitProposal: submitter signs, output to script, InProgress state
--     - Other redeemers: fail
mintValidator :: CurrencySymbol -> ScriptContext -> Bool
mintValidator idNftPolicy ctx =
  let ScriptContext txInfo rawRedeemer scriptInfo = ctx

      -- ═══════════════════════════════════════════════════════════════
      -- PHASE 1: Extract common values ONCE (hoisted to top level)
      -- ═══════════════════════════════════════════════════════════════

      {-# INLINE outputs #-}
      outputs = txInfoOutputs txInfo

      {-# INLINE signatories #-}
      signatories = txInfoSignatories txInfo

      {-# INLINE refs #-}
      refs = txInfoReferenceInputs txInfo

      {-# INLINE idTokenName #-}
      idTokenName :: TokenName
      idTokenName = TokenName identificationTokenName

      {-# INLINE mintConfigDatum #-}
      mintConfigDatum :: ConfigDatum
      mintConfigDatum = case findConfigDatum refs idNftPolicy idTokenName of
        P.Nothing  -> P.traceError "DGE013"
        P.Just cfg -> cfg

      -- ═══════════════════════════════════════════════════════════════
      -- PHASE 2: Parse redeemer ONCE
      -- ═══════════════════════════════════════════════════════════════

      {-# INLINE redeemer #-}
      redeemer :: DaoMintRedeemer
      redeemer = case PlutusTx.fromBuiltinData (getRedeemer rawRedeemer) of
        P.Nothing -> P.traceError "DGE001"
        P.Just r  -> r

      -- ═══════════════════════════════════════════════════════════════
      -- PHASE 3: Action-specific validation
      -- ═══════════════════════════════════════════════════════════════

      {-# INLINEABLE submitCheck #-}
      submitCheck :: CurrencySymbol -> P.BuiltinByteString -> Bool
      submitCheck ownPolicy proposalId =
        P.traceIfFalse "DGE014" hasAuthorizedSigner
        P.&& P.traceIfFalse "DGE003" outputHasNft
        P.&& P.traceIfFalse "DGE004" outputStateValid
        where
          proposalTokenName = TokenName proposalId

          -- Find output with this NFT
          maybeOutput :: P.Maybe TxOut
          maybeOutput = findOutputWithNft outputs ownPolicy proposalTokenName

          outputHasNft :: Bool
          outputHasNft = case maybeOutput of
            P.Nothing -> False
            P.Just _  -> True

          outputStateValid :: Bool
          outputStateValid = case maybeOutput of
            P.Nothing -> False
            P.Just txOut -> case extractGovDatum txOut of
              P.Nothing -> False
              P.Just govDatum ->
                gdProposalId govDatum P.== proposalId
                P.&& gdState govDatum P.== ProposalInProgress

      {-# INLINEABLE burnCheck #-}
      burnCheck :: Bool
      burnCheck = P.traceIfFalse "DGE014" hasAuthorizedSigner

      {-# INLINE hasAuthorizedSigner #-}
      hasAuthorizedSigner :: Bool
      hasAuthorizedSigner =
        let ms = cdMultisig mintConfigDatum
        in validateMultisig signatories (msSigners ms) (msRequired ms)

      {-# INLINEABLE findOutputWithNft #-}
      findOutputWithNft :: [TxOut] -> CurrencySymbol -> TokenName -> P.Maybe TxOut
      findOutputWithNft [] _ _ = P.Nothing
      findOutputWithNft (o:os) policy tkn =
        if valueOf (txOutValue o) policy tkn P.> 0
          then P.Just o
          else findOutputWithNft os policy tkn

      {-# INLINEABLE extractGovDatum #-}
      extractGovDatum :: TxOut -> P.Maybe GovernanceDatum
      extractGovDatum txOut = case txOutDatum txOut of
        OutputDatum (Datum d) -> PlutusTx.fromBuiltinData d
        _ -> P.Nothing

  -- ═══════════════════════════════════════════════════════════════
  -- PHASE 4: Main entry point (dispatch by script context)
  -- ═══════════════════════════════════════════════════════════════

  in case scriptInfo of
    MintingScript ownPolicy -> case redeemer of
      DaoSubmitProposal proposalId -> submitCheck ownPolicy proposalId
      DaoBurnProposal              -> burnCheck
    _ -> P.traceError "DGE000"

--------------------------------------------------------------------------------
-- SPENDING VALIDATOR (Vote/Execute/Reject)
--------------------------------------------------------------------------------

{-# INLINEABLE spendValidator #-}
-- | DAO Governance spending validator (OPTIMIZED - Phase 2)
--
--   Phase 2 Optimizations:
--     - Error codes (DGE005-DGE012) for minimal on-chain footprint
--     - Hoisted common extractions (signatories, refs, outputs extracted once)
--     - INLINE pragmas for constants and frequently used values
--
--   Spending Validator Rules:
--     Vote:
--       - proposal_id unchanged
--       - InProgress
--       - before deadline
--       - voter in multisig group
--       - voter status was Pending
--       - vote count +1 in output
--       - voter status updated in output
--
--     Execute:
--       - proposal_id unchanged
--       - InProgress
--       - after deadline
--       - yes > no
--       - output state = Executed
--       - ConfigDatum update matches proposal action
--
--     Reject:
--       - proposal_id unchanged
--       - InProgress
--       - after deadline
--       - no >= yes
--       - output state = Rejected
spendValidator :: CurrencySymbol -> ScriptContext -> Bool
spendValidator idNftPolicy ctx =
  let ScriptContext txInfo rawRedeemer scriptInfo = ctx

      -- ═══════════════════════════════════════════════════════════════
      -- PHASE 1: Extract common values ONCE (hoisted to top level)
      -- ═══════════════════════════════════════════════════════════════

      {-# INLINE signatories #-}
      signatories :: [PubKeyHash]
      signatories = txInfoSignatories txInfo

      {-# INLINE refs #-}
      refs = txInfoReferenceInputs txInfo

      {-# INLINE outputs #-}
      outputs = txInfoOutputs txInfo

      {-# INLINE validRange #-}
      validRange = txInfoValidRange txInfo

      -- ID NFT token name
      {-# INLINE idTokenName #-}
      idTokenName :: TokenName
      idTokenName = TokenName identificationTokenName

      -- ═══════════════════════════════════════════════════════════════
      -- PHASE 2: Parse redeemer ONCE
      -- ═══════════════════════════════════════════════════════════════

      {-# INLINE redeemer #-}
      redeemer :: DaoSpendRedeemer
      redeemer = case PlutusTx.fromBuiltinData (getRedeemer rawRedeemer) of
        P.Nothing -> P.traceError "DGE007"
        P.Just r  -> r

      -- ═══════════════════════════════════════════════════════════════
      -- PHASE 3: Load ConfigDatum ONCE (for multisig verification)
      -- ═══════════════════════════════════════════════════════════════

      {-# INLINE configDatum #-}
      configDatum :: P.Maybe ConfigDatum
      configDatum = findConfigDatum refs idNftPolicy idTokenName

      -- Get continuing output datum (the output going back to same script)
      {-# INLINE outputDatum #-}
      outputDatum :: P.Maybe GovernanceDatum
      outputDatum = case getContinuingOutputs ctx of
        [o] -> case txOutDatum o of
          OutputDatum (Datum d) -> PlutusTx.fromBuiltinData d
          _ -> P.Nothing
        _ -> P.Nothing

      -- ═══════════════════════════════════════════════════════════════
      -- PHASE 4: Main validation dispatch
      -- ═══════════════════════════════════════════════════════════════

      {-# INLINEABLE validateSpend #-}
      validateSpend :: GovernanceDatum -> Bool
      validateSpend inputDatum = case redeemer of
        DaoVote vote    -> validateVote inputDatum vote
        DaoExecute      -> validateExecute inputDatum
        DaoReject       -> validateReject inputDatum

      --------------------------------------------------------------------------------
      -- VOTE VALIDATION
      -- Rules:
      --   1. proposal_id unchanged
      --   2. state == InProgress
      --   3. before deadline
      --   4. get voter index, expect input.votes[idx].status == Pending
      --   5. output.yes_vote == input.yes_vote + 1 (or no_vote +1)
      --   6. output.votes[idx].status == Voted(vote)
      --------------------------------------------------------------------------------
      {-# INLINEABLE validateVote #-}
      validateVote :: GovernanceDatum -> Vote -> Bool
      validateVote inputDatum vote =
        P.traceIfFalse "DGE009" (case outputDatum of { P.Nothing -> False; P.Just _ -> True })
        P.&& P.traceIfFalse "DGE009" proposalIdMatches
        P.&& P.traceIfFalse "DGE009" isInProgress
        P.&& P.traceIfFalse "DGE009" beforeDeadline
        P.&& P.traceIfFalse "DGE002" voterSigned
        P.&& P.traceIfFalse "DGE008" voterInMultisig
        P.&& P.traceIfFalse "DGE010" voterWasPending
        P.&& P.traceIfFalse "DGE009" outputStillInProgress
        P.&& P.traceIfFalse "DGE009" voteCountIncremented
        P.&& P.traceIfFalse "DGE009" voterStatusUpdated
        where
          -- Get output datum (required)
          outDatum :: GovernanceDatum
          outDatum = case outputDatum of
            P.Just d -> d
            P.Nothing -> P.traceError "DGE009"

          proposalIdMatches = gdProposalId inputDatum P.== gdProposalId outDatum
          isInProgress = gdState inputDatum P.== ProposalInProgress

          deadline = gdDeadline inputDatum
          beforeDeadline = before deadline validRange

          -- At least one signer present
          voterSigned = P.not (P.null signatories)

          -- Get voter (first signer)
          voter :: PubKeyHash
          voter = case signatories of
            (s:_) -> s
            []    -> P.traceError "DGE002"

          -- Voter must be in multisig group
          voterInMultisig :: Bool
          voterInMultisig = case configDatum of
            P.Nothing -> P.traceError "DGE008"
            P.Just cfg -> isInList voter (msSigners (cdMultisig cfg))

          -- Expect Pending = input.votes[idx].status
          -- Find voter in input votes list, check status is Pending
          voterWasPending :: Bool
          voterWasPending = case findVoterRecord voter (gdVotes inputDatum) of
            P.Nothing -> P.traceError "DGE010"
            P.Just vr -> vrStatus vr P.== VoterPending

          outputStillInProgress = gdState outDatum P.== ProposalInProgress

          -- Check vote count increment based on vote type
          voteCountIncremented = case vote of
            VoteYes     -> gdYesCount outDatum P.== gdYesCount inputDatum P.+ 1
            VoteNo      -> gdNoCount outDatum P.== gdNoCount inputDatum P.+ 1
            VoteAbstain -> gdAbstainCount outDatum P.== gdAbstainCount inputDatum P.+ 1

          -- Expect Voted(vote) = output.votes[idx].status
          voterStatusUpdated :: Bool
          voterStatusUpdated = case findVoterRecord voter (gdVotes outDatum) of
            P.Nothing -> False
            P.Just vr -> vrStatus vr P.== VoterVoted vote

      --------------------------------------------------------------------------------
      -- EXECUTE VALIDATION
      -- Rules:
      --   1. InProgress
      --   2. past deadline
      --   3. yes > no
      --   4. output state = Executed
      --   5. ConfigDatum update matches proposal action
      --------------------------------------------------------------------------------
      {-# INLINEABLE validateExecute #-}
      validateExecute :: GovernanceDatum -> Bool
      validateExecute inputDatum =
        P.traceIfFalse "DGE009" isInProgress
        P.&& P.traceIfFalse "DGE009" afterDeadline
        P.&& P.traceIfFalse "DGE009" yesWins
        P.&& P.traceIfFalse "DGE009" outputIsExecuted
        P.&& P.traceIfFalse "DGE011" configUpdatedCorrectly
        where
          outDatum :: GovernanceDatum
          outDatum = case outputDatum of
            P.Just d -> d
            P.Nothing -> P.traceError "DGE009"

          isInProgress = gdState inputDatum P.== ProposalInProgress

          deadline = gdDeadline inputDatum
          afterDeadline = P.not (before deadline validRange)

          yesWins = gdYesCount inputDatum P.> gdNoCount inputDatum
          outputIsExecuted = gdState outDatum P.== ProposalExecuted

          -- Verify ConfigDatum update matches proposal action
          -- Find old ConfigDatum in reference inputs, new ConfigDatum in outputs
          configUpdatedCorrectly :: Bool
          configUpdatedCorrectly = case configDatum of
            P.Nothing -> P.traceError "DGE011"
            P.Just inputConfig ->
              case findDatumInOutputs outputs idNftPolicy idTokenName of
                P.Nothing -> P.traceError "DGE012"
                P.Just outputConfig ->
                  verifyConfigUpdate (gdAction inputDatum) inputConfig outputConfig

      --------------------------------------------------------------------------------
      -- REJECT VALIDATION
      --------------------------------------------------------------------------------
      {-# INLINEABLE validateReject #-}
      validateReject :: GovernanceDatum -> Bool
      validateReject inputDatum =
        P.traceIfFalse "DGE009" isInProgress
        P.&& P.traceIfFalse "DGE009" afterDeadline
        P.&& P.traceIfFalse "DGE009" noWins
        P.&& P.traceIfFalse "DGE009" outputIsRejected
        where
          outDatum :: GovernanceDatum
          outDatum = case outputDatum of
            P.Just d -> d
            P.Nothing -> P.traceError "DGE009"

          isInProgress = gdState inputDatum P.== ProposalInProgress

          deadline = gdDeadline inputDatum
          afterDeadline = P.not (before deadline validRange)

          noWins = gdNoCount inputDatum P.>= gdYesCount inputDatum
          outputIsRejected = gdState outDatum P.== ProposalRejected

  -- ═══════════════════════════════════════════════════════════════
  -- PHASE 5: Main entry point (parse datum and delegate)
  -- ═══════════════════════════════════════════════════════════════

  in case scriptInfo of
    SpendingScript _oref (Just (Datum datumData)) ->
      case PlutusTx.fromBuiltinData datumData of
        P.Nothing -> P.traceError "DGE006"
        P.Just datum -> validateSpend datum
    _ -> P.traceError "DGE005"
  where

    -- ═══════════════════════════════════════════════════════════════
    -- HELPER FUNCTIONS (all INLINEABLE for optimization)
    -- ═══════════════════════════════════════════════════════════════

    {-# INLINEABLE findVoterRecord #-}
    findVoterRecord :: PubKeyHash -> [VoteRecord] -> P.Maybe VoteRecord
    findVoterRecord _ [] = P.Nothing
    findVoterRecord pkh (vr:vrs) =
      if vrVoter vr P.== pkh
        then P.Just vr
        else findVoterRecord pkh vrs


    -- Verify ConfigDatum update matches proposal action
    -- CRIT-03: Each case verifies target field changed correctly AND all non-target fields preserved
    {-# INLINEABLE verifyConfigUpdate #-}
    verifyConfigUpdate :: ProposalAction -> ConfigDatum -> ConfigDatum -> Bool
    verifyConfigUpdate action inputCfg outputCfg = case action of
      ActionAddSigner pkh ->
        isInList pkh (msSigners (cdMultisig outputCfg))
        P.&& P.not (isInList pkh (msSigners (cdMultisig inputCfg)))
        -- msRequired should be unchanged
        P.&& msRequired (cdMultisig outputCfg) P.== msRequired (cdMultisig inputCfg)
        P.&& P.traceIfFalse "DGE015" (preservesNonMultisigFields inputCfg outputCfg)

      ActionRemoveSigner pkh ->
        isInList pkh (msSigners (cdMultisig inputCfg))
        P.&& P.not (isInList pkh (msSigners (cdMultisig outputCfg)))
        -- Deadlock prevention: required <= remaining signers
        P.&& P.traceIfFalse "DGE016"
          (msRequired (cdMultisig outputCfg) P.<= lengthOf (msSigners (cdMultisig outputCfg)))
        -- msRequired should be unchanged
        P.&& msRequired (cdMultisig outputCfg) P.== msRequired (cdMultisig inputCfg)
        P.&& P.traceIfFalse "DGE015" (preservesNonMultisigFields inputCfg outputCfg)

      ActionUpdateFeeAmount newAmt ->
        cdFeesAmount outputCfg P.== newAmt
        P.&& P.traceIfFalse "DGE015" (preservesAllExcept "feeAmount" inputCfg outputCfg)

      ActionUpdateFeeAddress newAddr ->
        cdFeesAddress outputCfg P.== newAddr
        P.&& P.traceIfFalse "DGE015" (preservesAllExcept "feeAddress" inputCfg outputCfg)

      ActionAddCategory cat ->
        isCategoryInList cat (cdCategories outputCfg)
        P.&& P.not (isCategoryInList cat (cdCategories inputCfg))
        P.&& P.traceIfFalse "DGE015" (preservesAllExcept "categories" inputCfg outputCfg)

      ActionRemoveCategory cat ->
        isCategoryInList cat (cdCategories inputCfg)
        P.&& P.not (isCategoryInList cat (cdCategories outputCfg))
        P.&& P.traceIfFalse "DGE015" (preservesAllExcept "categories" inputCfg outputCfg)

      ActionUpdateRequired newReq ->
        msRequired (cdMultisig outputCfg) P.== newReq
        -- Deadlock and no-auth prevention
        P.&& P.traceIfFalse "DGE016"
          (newReq P.>= 1 P.&& newReq P.<= lengthOf (msSigners (cdMultisig outputCfg)))
        -- Signers list should be unchanged
        P.&& msSigners (cdMultisig outputCfg) P.== msSigners (cdMultisig inputCfg)
        P.&& P.traceIfFalse "DGE015" (preservesNonMultisigFields inputCfg outputCfg)

      ActionUpdateProposalDuration newDur ->
        cdProposalDuration outputCfg P.== newDur
        P.&& P.traceIfFalse "DGE015" (preservesAllExcept "proposalDuration" inputCfg outputCfg)

      ActionUpdateScriptHash field newHash ->
        verifyScriptHashUpdate field newHash outputCfg
        P.&& P.traceIfFalse "DGE015" (preservesScriptHashExcept field inputCfg outputCfg)

    -- All non-script-hash, non-multisig fields preserved
    {-# INLINEABLE preservesNonMultisigFields #-}
    preservesNonMultisigFields :: ConfigDatum -> ConfigDatum -> Bool
    preservesNonMultisigFields i o =
      cdFeesAddress o P.== cdFeesAddress i
      P.&& cdFeesAmount o P.== cdFeesAmount i
      P.&& cdCategories o P.== cdCategories i
      P.&& cdProposalDuration o P.== cdProposalDuration i
      P.&& cdProjectPolicyId o P.== cdProjectPolicyId i
      P.&& cdProjectVaultHash o P.== cdProjectVaultHash i
      P.&& cdVotingHash o P.== cdVotingHash i
      P.&& cdCotPolicyId o P.== cdCotPolicyId i
      P.&& cdCetPolicyId o P.== cdCetPolicyId i
      P.&& cdUserVaultHash o P.== cdUserVaultHash i

    -- All fields except the named one preserved
    {-# INLINEABLE preservesAllExcept #-}
    preservesAllExcept :: P.BuiltinByteString -> ConfigDatum -> ConfigDatum -> Bool
    preservesAllExcept field i o =
      (field P.== "feeAddress" P.|| cdFeesAddress o P.== cdFeesAddress i)
      P.&& (field P.== "feeAmount" P.|| cdFeesAmount o P.== cdFeesAmount i)
      P.&& (field P.== "categories" P.|| cdCategories o P.== cdCategories i)
      P.&& cdMultisig o P.== cdMultisig i
      P.&& (field P.== "proposalDuration" P.|| cdProposalDuration o P.== cdProposalDuration i)
      P.&& cdProjectPolicyId o P.== cdProjectPolicyId i
      P.&& cdProjectVaultHash o P.== cdProjectVaultHash i
      P.&& cdVotingHash o P.== cdVotingHash i
      P.&& cdCotPolicyId o P.== cdCotPolicyId i
      P.&& cdCetPolicyId o P.== cdCetPolicyId i
      P.&& cdUserVaultHash o P.== cdUserVaultHash i

    -- Script hash fields: preserve all except the one being updated
    {-# INLINEABLE preservesScriptHashExcept #-}
    preservesScriptHashExcept :: P.BuiltinByteString -> ConfigDatum -> ConfigDatum -> Bool
    preservesScriptHashExcept field i o =
      cdFeesAddress o P.== cdFeesAddress i
      P.&& cdFeesAmount o P.== cdFeesAmount i
      P.&& cdCategories o P.== cdCategories i
      P.&& cdMultisig o P.== cdMultisig i
      P.&& cdProposalDuration o P.== cdProposalDuration i
      P.&& (field P.== "projectPolicy" P.|| cdProjectPolicyId o P.== cdProjectPolicyId i)
      P.&& (field P.== "projectVault" P.|| cdProjectVaultHash o P.== cdProjectVaultHash i)
      P.&& (field P.== "voting" P.|| cdVotingHash o P.== cdVotingHash i)
      P.&& (field P.== "cotPolicy" P.|| cdCotPolicyId o P.== cdCotPolicyId i)
      P.&& (field P.== "cetPolicy" P.|| cdCetPolicyId o P.== cdCetPolicyId i)
      P.&& (field P.== "userVault" P.|| cdUserVaultHash o P.== cdUserVaultHash i)

    {-# INLINEABLE lengthOf #-}
    lengthOf :: [a] -> Integer
    lengthOf [] = 0
    lengthOf (_:xs) = 1 P.+ lengthOf xs

    {-# INLINEABLE isCategoryInList #-}
    isCategoryInList :: P.BuiltinByteString -> [P.BuiltinByteString] -> Bool
    isCategoryInList _ [] = False
    isCategoryInList x (y:ys) = x P.== y P.|| isCategoryInList x ys

    {-# INLINEABLE verifyScriptHashUpdate #-}
    verifyScriptHashUpdate :: P.BuiltinByteString -> P.BuiltinByteString -> ConfigDatum -> Bool
    verifyScriptHashUpdate field newHash cfg
      | field P.== "projectPolicy"  = cdProjectPolicyId cfg P.== newHash
      | field P.== "projectVault"   = cdProjectVaultHash cfg P.== newHash
      | field P.== "voting"         = cdVotingHash cfg P.== newHash
      | field P.== "cotPolicy"      = cdCotPolicyId cfg P.== newHash
      | field P.== "cetPolicy"      = cdCetPolicyId cfg P.== newHash
      | field P.== "userVault"      = cdUserVaultHash cfg P.== newHash
      | P.otherwise                 = False

--------------------------------------------------------------------------------
-- COMPILED VALIDATORS
--------------------------------------------------------------------------------

{-# INLINEABLE untypedMintValidator #-}
untypedMintValidator :: BuiltinData -> BuiltinData -> P.BuiltinUnit
untypedMintValidator idNftPolicyData ctxData =
  P.check
    ( mintValidator
        (PlutusTx.unsafeFromBuiltinData idNftPolicyData)
        (PlutusTx.unsafeFromBuiltinData ctxData)
    )

compiledMintValidator :: CompiledCode (BuiltinData -> BuiltinData -> P.BuiltinUnit)
compiledMintValidator = $$(PlutusTx.compile [||untypedMintValidator||])

{-# INLINEABLE untypedSpendValidator #-}
untypedSpendValidator :: BuiltinData -> BuiltinData -> P.BuiltinUnit
untypedSpendValidator idNftPolicyData ctxData =
  P.check
    ( spendValidator
        (PlutusTx.unsafeFromBuiltinData idNftPolicyData)
        (PlutusTx.unsafeFromBuiltinData ctxData)
    )

compiledSpendValidator :: CompiledCode (BuiltinData -> BuiltinData -> P.BuiltinUnit)
compiledSpendValidator = $$(PlutusTx.compile [||untypedSpendValidator||])
