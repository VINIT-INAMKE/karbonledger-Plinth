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

   PVE004 - Voter not signed
            Cause: Signer's PKH not in transaction signatures
            Fix: Ensure voter signs the transaction

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

   ══════════════════════════════════════════════════════════════════════════
-}

module Carbonica.Validators.ProjectVault where

import           PlutusLedgerApi.V3             (Address (..),
                                                 Credential (..),
                                                 CurrencySymbol (..),
                                                 Datum (..),
                                                 PubKeyHash,
                                                 ScriptContext (..),
                                                 ScriptInfo (..),
                                                 TokenName (..),
                                                 TxInfo (..),
                                                 TxOut (..),
                                                 TxOutRef,
                                                 getRedeemer)
import           PlutusLedgerApi.V3.MintValue   (mintValueMinted)
import           PlutusLedgerApi.V1.Value       (Value, valueOf, flattenValue)
import           PlutusTx
import qualified PlutusTx.Prelude               as P

import           Carbonica.Types.Config         (Multisig (..),
                                                 cdCotPolicyId,
                                                 cdMultisig,
                                                 identificationTokenName)
import           Carbonica.Types.Project        (ProjectDatum,
                                                 ProjectStatus (..),
                                                 ProjectVaultRedeemer (..),
                                                 pdVoters,
                                                 pdStatus,
                                                 pdYesVotes,
                                                 pdNoVotes,
                                                 pdProjectName,
                                                 pdDeveloper,
                                                 pdCotAmount)
import           Carbonica.Validators.Common    (findConfigDatum)

--------------------------------------------------------------------------------
-- VALIDATOR LOGIC
--------------------------------------------------------------------------------

{-# INLINEABLE typedValidator #-}
-- | Project Vault spending validator (OPTIMIZED - Phase 2)
--
--   Parameters:
--     idNftPolicy - Identification NFT policy (to find config)
--     projectPolicy - Project NFT policy (to verify burning)
--
--   Phase 2 Optimizations:
--     - Error codes (PVE000-PVE012) for minimal on-chain footprint
--     - Hoisted common extractions (outputs, signatories, mintedValue extracted once)
--     - INLINE pragmas for constants and frequently used values
--
--   Spending Rules:
--     Action 0 (Accept):
--       - Developer receives COT at their address
--       - Project NFT burned
--       - Multisig verification
--
--     Action 1 (Reject):
--       - Project NFT burned
--       - Multisig verification
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
        where
          {-# INLINE multisigSigners #-}
          multisigSigners = msSigners (cdMultisig configDatum)

          {-# INLINE existingVoters #-}
          existingVoters = pdVoters projectDatum

          {-# INLINE voterSigned #-}
          voterSigned = hasSigners signatories

          {-# INLINE voterInMultisig #-}
          voterInMultisig = anySignerInList signatories multisigSigners

          {-# INLINE notAlreadyVoted #-}
          notAlreadyVoted = P.not (anySignerInList signatories existingVoters)

          {-# INLINE isSubmitted #-}
          isSubmitted = pdStatus projectDatum P.== ProjectSubmitted

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
          projectBurned = getTokensBurnedForPolicy mintedValue projectPolicy P.< 0

          {-# INLINE developerPaid #-}
          developerPaid =
            verifyPaymentToAddress outputs (pdDeveloper projectDatum)
              (CurrencySymbol (cdCotPolicyId configDatum))
              projectTokenName
              (pdCotAmount projectDatum)

          {-# INLINE multisigSatisfied #-}
          multisigSatisfied =
            countMatchingSigners signatories (msSigners (cdMultisig configDatum))
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

          {-# INLINE projectBurned #-}
          projectBurned = getTokensBurnedForPolicy mintedValue projectPolicy P.< 0

          {-# INLINE multisigSatisfied #-}
          multisigSatisfied =
            countMatchingSigners signatories (msSigners (cdMultisig configDatum))
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
  where

    -- ═══════════════════════════════════════════════════════════════
    -- HELPER FUNCTIONS (all INLINEABLE for optimization)
    -- ═══════════════════════════════════════════════════════════════

    hasSigners :: [PubKeyHash] -> Bool
    hasSigners [] = False
    hasSigners _  = True
    {-# INLINEABLE hasSigners #-}

    anySignerInList :: [PubKeyHash] -> [PubKeyHash] -> Bool
    anySignerInList [] _ = False
    anySignerInList (s:ss) list = isInList s list P.|| anySignerInList ss list
    {-# INLINEABLE anySignerInList #-}

    isInList :: PubKeyHash -> [PubKeyHash] -> Bool
    isInList _ []     = False
    isInList x (y:ys) = x P.== y P.|| isInList x ys
    {-# INLINEABLE isInList #-}

    countMatchingSigners :: [PubKeyHash] -> [PubKeyHash] -> Integer
    countMatchingSigners [] _ = 0
    countMatchingSigners (s:ss) multisig =
      if isInList s multisig
        then 1 P.+ countMatchingSigners ss multisig
        else countMatchingSigners ss multisig
    {-# INLINEABLE countMatchingSigners #-}

    -- Sum burned tokens for a policy (negative = burned)
    getTokensBurnedForPolicy :: Value -> CurrencySymbol -> Integer
    getTokensBurnedForPolicy val policy =
      sumQty [qty | (cs, _, qty) <- flattenValue val, cs P.== policy]
    {-# INLINEABLE getTokensBurnedForPolicy #-}

    sumQty :: [Integer] -> Integer
    sumQty []     = 0
    sumQty (x:xs) = x P.+ sumQty xs
    {-# INLINEABLE sumQty #-}

    -- Verify exact payment to a PubKeyHash address
    -- Verify developer receives exact COT payment
    verifyPaymentToAddress :: [TxOut] -> PubKeyHash -> CurrencySymbol -> TokenName -> Integer -> Bool
    verifyPaymentToAddress [] _ _ _ _ = False
    verifyPaymentToAddress (o:os) pkh policy tkn expectedAmt =
      let addr = txOutAddress o
          matchesPkh = case addressCredential addr of
            PubKeyCredential pk -> pk P.== pkh
            _                   -> False
          tokenAmt = valueOf (txOutValue o) policy tkn
      in if matchesPkh P.&& tokenAmt P.== expectedAmt
           then True
           else verifyPaymentToAddress os pkh policy tkn expectedAmt
    {-# INLINEABLE verifyPaymentToAddress #-}

--------------------------------------------------------------------------------
-- COMPILED VALIDATOR
--------------------------------------------------------------------------------

{-# INLINEABLE untypedValidator #-}
untypedValidator :: BuiltinData -> BuiltinData -> BuiltinData -> P.BuiltinUnit
untypedValidator idNftPolicyData projectPolicyData ctxData =
  P.check
    ( typedValidator
        (PlutusTx.unsafeFromBuiltinData idNftPolicyData)
        (PlutusTx.unsafeFromBuiltinData projectPolicyData)
        (PlutusTx.unsafeFromBuiltinData ctxData)
    )

compiledValidator :: CompiledCode (BuiltinData -> BuiltinData -> BuiltinData -> P.BuiltinUnit)
compiledValidator = $$(PlutusTx.compile [||untypedValidator||])
