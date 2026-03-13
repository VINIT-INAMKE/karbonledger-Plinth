{- |
Module      : Test.Carbonica.Properties.DatumIntegrity
Description : QuickCheck property tests for datum integrity invariants
License     : Apache-2.0

Verifies via QuickCheck that validators reject mutations to protected fields
during vote and config update operations:

  1. ProjectVault vote preserves non-vote fields (pdDeveloper, pdCotAmount, etc.)
  2. DaoGovernance vote preserves non-vote fields (gdSubmittedBy, gdAction, gdDeadline)
  3. DaoGovernance execute preserves non-target ConfigDatum fields
-}
module Test.Carbonica.Properties.DatumIntegrity (datumIntegrityTests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.QuickCheck (testProperty, (==>))
import Test.QuickCheck (ioProperty, Property, Positive(..))

import Control.Exception (evaluate, try, SomeException)

import PlutusTx (toBuiltinData)
import PlutusLedgerApi.V3
    ( Address (..)
    , CurrencySymbol (..)
    , Credential (..)
    , Datum (..)
    , OutputDatum (..)
    , PubKeyHash (..)
    , Redeemer (..)
    , ScriptContext
    , ScriptHash (..)
    , TokenName (..)
    , TxId (..)
    , TxOut (..)
    , TxOutRef (..)
    )
import PlutusLedgerApi.V1.Value (Value, singleton)
import qualified PlutusTx.Prelude as P

-- Import validators (qualified)
import qualified Carbonica.Validators.ProjectVault as ProjectVault
import qualified Carbonica.Validators.DaoGovernance as DaoGovernance

-- Import types
import Carbonica.Types.Core (FeeAddress (..), Lovelace (..))
import Carbonica.Types.Config
    ( ConfigDatum, Multisig (..)
    , identificationTokenName, mkConfigDatum
    )
import Carbonica.Types.Project
    ( ProjectDatum, ProjectStatus (..)
    , ProjectVaultRedeemer (..)
    )
import Carbonica.Types.Governance
    ( GovernanceDatum
    , ProposalAction (..)
    , ProposalState (..)
    , Vote (..)
    , VoteRecord (..)
    , VoterStatus (..)
    , DaoSpendRedeemer (..)
    )

-- Import test helpers
import Test.Carbonica.TestHelpers

--------------------------------------------------------------------------------
-- TOP-LEVEL TEST GROUP
--------------------------------------------------------------------------------

datumIntegrityTests :: TestTree
datumIntegrityTests = testGroup "Datum Integrity Properties"
  [ projectVaultVoteIntegrity
  , daoGovernanceVoteIntegrity
  , configUpdateIntegrity
  ]

--------------------------------------------------------------------------------
-- SHARED TEST INFRASTRUCTURE
--------------------------------------------------------------------------------

-- | Standard config for property tests
defaultConfig :: ConfigDatum
defaultConfig = mkTestConfigDatum testVaultHash [alice, bob, charlie] 2

-- | Standard spending TxOutRef
testOref :: TxOutRef
testOref = TxOutRef (TxId "spent_utxo_id_00000000000000000") 0

-- | Empty Value (no tokens)
emptyValue :: Value
emptyValue = mempty

--------------------------------------------------------------------------------
-- INVARIANT 1: ProjectVault vote preserves non-vote fields
--
-- When a voter casts a vote via VaultVote, the continuing output datum must
-- have identical non-vote fields (pdProjectName, pdCategory, pdDeveloper,
-- pdCotAmount, pdDescription, pdStatus, pdSubmittedAt). Only pdYesVotes,
-- pdNoVotes, and pdVoters may change.
--------------------------------------------------------------------------------

projectVaultVoteIntegrity :: TestTree
projectVaultVoteIntegrity = testGroup "ProjectVault vote preserves non-vote fields"
  [ testProperty "rejects mutated developer (PVE016)" prop_pvVoteRejectsMutatedDeveloper
  , testProperty "rejects mutated COT amount (PVE017)" prop_pvVoteRejectsMutatedCotAmount
  ]

-- | Build a ProjectVault spending context for vote action.
--
-- Creates: vault input with project NFT + input datum, continuing output with
-- project NFT + output datum, config ref with defaultConfig, provided signers.
mkProjectVaultVoteCtx
  :: ProjectDatum      -- ^ Input datum (on the UTxO being spent)
  -> ProjectDatum      -- ^ Output datum (on the continuing output)
  -> [PubKeyHash]      -- ^ Transaction signers
  -> ScriptContext
mkProjectVaultVoteCtx inputDatum outputDatum signers =
  let inputDatumData = Datum (toBuiltinData inputDatum)
      projectNftVal = singleton testProjectPolicy (TokenName "Test Carbon Project") 1
      -- Vault input (being spent)
      vaultInput = mkTxInInfo testOref
        (mkScriptTxOut testVaultHash projectNftVal inputDatumData)
      -- Continuing output with updated datum
      vaultOutput = mkScriptTxOut testVaultHash
        projectNftVal
        (Datum (toBuiltinData outputDatum))
      -- Config reference input
      configRef = mkRefInputWithConfig testIdNftPolicy defaultConfig
      txInfo' = mkTxInfo signers [vaultInput] [vaultOutput] [configRef] emptyValue
  in mkSpendingCtx txInfo' (Redeemer (toBuiltinData VaultVote)) testOref inputDatumData

-- | Property: mutating pdDeveloper causes rejection.
-- Input has dave as developer; output has a random different developer.
prop_pvVoteRejectsMutatedDeveloper :: ArbPubKeyHash -> Property
prop_pvVoteRejectsMutatedDeveloper (ArbPubKeyHash badDev) =
  badDev P./= dave ==>
    let inputDatum  = mkTestProjectDatum ProjectSubmitted dave 1000 0 0 []
        outputDatum = mkTestProjectDatum ProjectSubmitted badDev 1000 1 0 [alice]
        ctx = mkProjectVaultVoteCtx inputDatum outputDatum [alice]
    in ioProperty $ do
      result <- try (evaluate (ProjectVault.untypedValidator
        (toBuiltinData testIdNftPolicy)
        (toBuiltinData testProjectPolicy)
        (toBuiltinData ctx))) :: IO (Either SomeException P.BuiltinUnit)
      return $ case result of
        Left _  -> True   -- Rejected (expected)
        Right _ -> False  -- Accepted (unexpected -- mutation should be caught)

-- | Property: mutating pdCotAmount causes rejection.
-- Input has COT amount 1000; output has a random different amount.
prop_pvVoteRejectsMutatedCotAmount :: Positive Integer -> Property
prop_pvVoteRejectsMutatedCotAmount (Positive badAmt) =
  badAmt /= 1000 ==>
    let inputDatum  = mkTestProjectDatum ProjectSubmitted dave 1000 0 0 []
        outputDatum = mkTestProjectDatum ProjectSubmitted dave badAmt 1 0 [alice]
        ctx = mkProjectVaultVoteCtx inputDatum outputDatum [alice]
    in ioProperty $ do
      result <- try (evaluate (ProjectVault.untypedValidator
        (toBuiltinData testIdNftPolicy)
        (toBuiltinData testProjectPolicy)
        (toBuiltinData ctx))) :: IO (Either SomeException P.BuiltinUnit)
      return $ case result of
        Left _  -> True   -- Rejected (expected)
        Right _ -> False  -- Accepted (unexpected)

--------------------------------------------------------------------------------
-- INVARIANT 2: DaoGovernance vote preserves non-vote fields
--
-- When voting on a DAO proposal via DaoVote, the continuing output datum must
-- preserve gdSubmittedBy (DGE019), gdAction (DGE020), and gdDeadline (DGE021).
--------------------------------------------------------------------------------

daoGovernanceVoteIntegrity :: TestTree
daoGovernanceVoteIntegrity = testGroup "DaoGovernance vote preserves non-vote fields"
  [ testProperty "rejects mutated submitter (DGE019)" prop_dgVoteRejectsMutatedSubmitter
  , testProperty "rejects mutated action (DGE020)" prop_dgVoteRejectsMutatedAction
  , testProperty "rejects mutated deadline (DGE021)" prop_dgVoteRejectsMutatedDeadline
  ]

-- | Build a DaoGovernance vote spending context.
--
-- Creates: governance input with proposal NFT + input datum, continuing output
-- with updated datum, config ref, provided signers. Uses always valid range
-- (satisfies before-deadline check for any finite deadline).
mkDaoVoteIntegrityCtx
  :: GovernanceDatum   -- ^ Input datum
  -> GovernanceDatum   -- ^ Output datum
  -> [PubKeyHash]      -- ^ Transaction signers
  -> Vote              -- ^ Vote direction
  -> ScriptContext
mkDaoVoteIntegrityCtx inputGov outputGov signers vote =
  let govOref = TxOutRef (TxId "gov_utxo_id_000000000000000000") 0
      inputDatumData = Datum (toBuiltinData inputGov)
      proposalNftVal = singleton testProposalPolicy (TokenName "test_proposal_001") 1
      -- Governance input (being spent)
      govInput = mkTxInInfo govOref
        (mkScriptTxOut "governance_script_hash_00000000" proposalNftVal inputDatumData)
      -- Continuing output with updated datum
      govOutput = mkScriptTxOut "governance_script_hash_00000000"
        proposalNftVal
        (Datum (toBuiltinData outputGov))
      -- Config reference input
      configRef = mkRefInputWithConfig testIdNftPolicy defaultConfig
      txInfo' = mkTxInfo signers [govInput] [govOutput] [configRef] emptyValue
  in mkSpendingCtx txInfo' (Redeemer (toBuiltinData (DaoVote vote))) govOref inputDatumData

-- | Base input governance datum for vote integrity tests.
-- alice is submitter, ActionUpdateFeeAmount, 3 pending voters, deadline = oneWeekMs + 1M.
baseInputGov :: GovernanceDatum
baseInputGov = mkTestGovernanceDatum
  "test_proposal_001" alice (ActionUpdateFeeAmount 200_000_000)
  [ VoteRecord alice VoterPending
  , VoteRecord bob VoterPending
  , VoteRecord charlie VoterPending
  ]
  0 0 0 (oneWeekMs P.+ 1_000_000) ProposalInProgress

-- | Valid output governance datum (alice votes yes, count incremented).
baseOutputGov :: GovernanceDatum
baseOutputGov = mkTestGovernanceDatum
  "test_proposal_001" alice (ActionUpdateFeeAmount 200_000_000)
  [ VoteRecord alice (VoterVoted VoteYes)
  , VoteRecord bob VoterPending
  , VoteRecord charlie VoterPending
  ]
  1 0 0 (oneWeekMs P.+ 1_000_000) ProposalInProgress

-- | Property: mutating gdSubmittedBy causes rejection.
prop_dgVoteRejectsMutatedSubmitter :: ArbPubKeyHash -> Property
prop_dgVoteRejectsMutatedSubmitter (ArbPubKeyHash badSubmitter) =
  badSubmitter P./= alice ==>
    let badOutputGov = mkTestGovernanceDatum
          "test_proposal_001" badSubmitter (ActionUpdateFeeAmount 200_000_000)
          [ VoteRecord alice (VoterVoted VoteYes)
          , VoteRecord bob VoterPending
          , VoteRecord charlie VoterPending
          ]
          1 0 0 (oneWeekMs P.+ 1_000_000) ProposalInProgress
        ctx = mkDaoVoteIntegrityCtx baseInputGov badOutputGov [alice] VoteYes
    in ioProperty $ do
      result <- try (evaluate (DaoGovernance.untypedSpendValidator
        (toBuiltinData testIdNftPolicy)
        (toBuiltinData ctx))) :: IO (Either SomeException P.BuiltinUnit)
      return $ case result of
        Left _  -> True
        Right _ -> False

-- | Property: mutating gdAction causes rejection.
-- Uses a fixed different action (ActionAddSigner dave instead of ActionUpdateFeeAmount).
prop_dgVoteRejectsMutatedAction :: Property
prop_dgVoteRejectsMutatedAction =
  let badOutputGov = mkTestGovernanceDatum
        "test_proposal_001" alice (ActionAddSigner dave)
        [ VoteRecord alice (VoterVoted VoteYes)
        , VoteRecord bob VoterPending
        , VoteRecord charlie VoterPending
        ]
        1 0 0 (oneWeekMs P.+ 1_000_000) ProposalInProgress
      ctx = mkDaoVoteIntegrityCtx baseInputGov badOutputGov [alice] VoteYes
  in ioProperty $ do
    result <- try (evaluate (DaoGovernance.untypedSpendValidator
      (toBuiltinData testIdNftPolicy)
      (toBuiltinData ctx))) :: IO (Either SomeException P.BuiltinUnit)
    return $ case result of
      Left _  -> True
      Right _ -> False

-- | Property: mutating gdDeadline causes rejection.
prop_dgVoteRejectsMutatedDeadline :: ArbPOSIXTime -> Property
prop_dgVoteRejectsMutatedDeadline (ArbPOSIXTime badDeadline) =
  badDeadline P./= (oneWeekMs P.+ 1_000_000) ==>
    let badOutputGov = mkTestGovernanceDatum
          "test_proposal_001" alice (ActionUpdateFeeAmount 200_000_000)
          [ VoteRecord alice (VoterVoted VoteYes)
          , VoteRecord bob VoterPending
          , VoteRecord charlie VoterPending
          ]
          1 0 0 badDeadline ProposalInProgress
        ctx = mkDaoVoteIntegrityCtx baseInputGov badOutputGov [alice] VoteYes
    in ioProperty $ do
      result <- try (evaluate (DaoGovernance.untypedSpendValidator
        (toBuiltinData testIdNftPolicy)
        (toBuiltinData ctx))) :: IO (Either SomeException P.BuiltinUnit)
      return $ case result of
        Left _  -> True
        Right _ -> False

--------------------------------------------------------------------------------
-- INVARIANT 3: verifyConfigUpdate preserves non-target fields
--
-- When executing a DAO proposal (DaoExecute), the output ConfigDatum must
-- only differ from the input ConfigDatum in the field targeted by the
-- ProposalAction. All other fields must be identical (DGE015).
--------------------------------------------------------------------------------

configUpdateIntegrity :: TestTree
configUpdateIntegrity = testGroup "ConfigUpdate preserves non-target fields"
  [ testProperty "execute rejects non-target field mutation (DGE015)"
      prop_executeRejectsNonTargetFieldMutation
  ]

-- | Property: ActionUpdateFeeAmount proposal, but output config has different
-- vault hash (non-target field). Uses concrete values (same pattern as CRIT-03).
prop_executeRejectsNonTargetFieldMutation :: Property
prop_executeRejectsNonTargetFieldMutation =
  let inputCfg = defaultConfig
      -- Malicious output config: vault hash changed (testAltHash instead of testVaultHash)
      badOutputCfg = mkTestConfigDatum testAltHash [alice, bob, charlie] 2

      -- Governance datum: passed proposal to update fee amount
      inputGov = mkTestGovernanceDatum
        "test_proposal_001" alice (ActionUpdateFeeAmount 200_000_000)
        [] 3 1 0 1_000_000 ProposalInProgress
      outputGov = mkTestGovernanceDatum
        "test_proposal_001" alice (ActionUpdateFeeAmount 200_000_000)
        [] 3 1 0 1_000_000 ProposalExecuted

      ctx = mkDaoExecuteIntegrityCtx [alice, bob] inputGov outputGov inputCfg badOutputCfg
  in ioProperty $ do
    result <- try (evaluate (DaoGovernance.untypedSpendValidator
      (toBuiltinData testIdNftPolicy)
      (toBuiltinData ctx))) :: IO (Either SomeException P.BuiltinUnit)
    return $ case result of
      Left _  -> True   -- Rejected (expected -- non-target field mutated)
      Right _ -> False  -- Accepted (unexpected)

-- | Build a DaoGovernance execute spending context.
--
-- Builds governance input/output and config ref/output for Execute action.
-- Mirrors mkDaoExecuteCtx from AttackScenarios.
mkDaoExecuteIntegrityCtx
  :: [PubKeyHash]       -- ^ Signers
  -> GovernanceDatum    -- ^ Input governance datum
  -> GovernanceDatum    -- ^ Output governance datum
  -> ConfigDatum        -- ^ Input config (ref input)
  -> ConfigDatum        -- ^ Output config (in outputs)
  -> ScriptContext
mkDaoExecuteIntegrityCtx signers inputGov outputGov inputCfg outputCfg =
  let govOref = TxOutRef (TxId "gov_utxo_id_000000000000000000") 0
      inputGovDatum = Datum (toBuiltinData inputGov)
      proposalNftVal = singleton testProposalPolicy (TokenName "test_proposal_001") 1
      -- Governance input (being spent)
      govInput = mkTxInInfo govOref
        (mkScriptTxOut "governance_script_hash_00000000" proposalNftVal inputGovDatum)
      -- Governance continuing output
      govOutput = mkScriptTxOut "governance_script_hash_00000000"
        proposalNftVal
        (Datum (toBuiltinData outputGov))
      -- Config reference input (with ID NFT)
      configRef = mkRefInputWithConfig testIdNftPolicy inputCfg
      -- Config output (updated, with ID NFT)
      configOutput = TxOut
        (Address
          (ScriptCredential (ScriptHash "config_holder_hash_00000000000"))
          Nothing)
        (singleton testIdNftPolicy (TokenName identificationTokenName) 1)
        (OutputDatum (Datum (toBuiltinData outputCfg)))
        Nothing
      txInfo' = mkTxInfo signers [govInput] [govOutput, configOutput] [configRef] emptyValue
  in mkSpendingCtx txInfo' (Redeemer (toBuiltinData DaoExecute)) govOref inputGovDatum
