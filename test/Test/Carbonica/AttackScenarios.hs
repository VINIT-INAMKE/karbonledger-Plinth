{- |
Module      : Test.Carbonica.AttackScenarios
Description : Attack scenario tests for CRIT-01 through CRIT-04 and HIGH-01 through HIGH-04
License     : Apache-2.0

Each test group constructs a malicious transaction that would have succeeded
before the patch and verifies the patched validator rejects it.
Multiple exploit variants per vulnerability test different attack angles.

All tests call the full untyped entry point (untypedValidator / untypedMintValidator /
untypedSpendValidator) with BuiltinData-serialized arguments for realistic end-to-end
testing. This exercises the full deserialization + validation + P.check pipeline,
matching on-chain behavior.
-}
module Test.Carbonica.AttackScenarios (attackScenarioTests) where

import Test.Tasty (TestTree, testGroup)

import PlutusTx (toBuiltinData)
import PlutusLedgerApi.V3
    ( Address (..)
    , BuiltinData
    , Credential (..)
    , CurrencySymbol (..)
    , Datum (..)
    , OutputDatum (..)
    , PubKeyHash (..)
    , Redeemer (..)
    , ScriptContext (..)
    , ScriptHash (..)
    , ScriptInfo (..)
    , TokenName (..)
    , TxId (..)
    , TxInInfo (..)
    , TxInfo (..)
    , TxOut (..)
    , TxOutRef (..)
    )
import PlutusLedgerApi.V1.Value (singleton, Value)
import qualified PlutusTx.Prelude as P

-- Import untyped entry points from each validator
import qualified Carbonica.Validators.ProjectVault as ProjectVault
import qualified Carbonica.Validators.DaoGovernance as DaoGovernance
import qualified Carbonica.Validators.ProjectPolicy as ProjectPolicy
import qualified Carbonica.Validators.CotPolicy as CotPolicy

-- Import types needed for building test data
import Carbonica.Types.Core (FeeAddress (..), Lovelace (..))
import Carbonica.Types.Config
    ( ConfigDatum, Multisig (..)
    , identificationTokenName, mkConfigDatum
    )
import Carbonica.Types.Project
    ( ProjectDatum, ProjectStatus (..)
    , ProjectVaultRedeemer (..)
    , ProjectMintRedeemer (..)
    )
import Carbonica.Types.Governance
    ( GovernanceDatum
    , ProposalAction (..)
    , ProposalState (..)
    , Vote (..)
    , VoteRecord (..)
    , VoterStatus (..)
    , DaoSpendRedeemer (..)
    , DaoMintRedeemer (..)
    )
import Carbonica.Validators.CotPolicy (CotRedeemer (..))

-- Import test helpers
import Test.Carbonica.TestHelpers

--------------------------------------------------------------------------------
-- TOP-LEVEL TEST GROUP
--------------------------------------------------------------------------------

attackScenarioTests :: TestTree
attackScenarioTests = testGroup "Attack Scenario Tests"
  [ crit01Tests   -- ProjectVault vote datum manipulation
  , crit02Tests   -- DaoGovernance mint without multisig
  , crit03Tests   -- DaoGovernance config field mutation
  , crit04Tests   -- CotPolicy unauthorized COT minting
  , high01Tests   -- ProjectPolicy NFT sent to wrong script
  , high02Tests   -- ProjectVault/DaoGovernance trivial signer bypass
  , high03Tests   -- DaoGovernance execute/reject without multisig
  , high04Tests   -- DaoGovernance vote impersonation
  ]

--------------------------------------------------------------------------------
-- SHARED HELPERS
--------------------------------------------------------------------------------

-- | Standard config for tests: vault at testVaultHash, multisig of [alice, bob, charlie], required 2
defaultConfig :: ConfigDatum
defaultConfig = mkTestConfigDatum testVaultHash [alice, bob, charlie] 2

-- | Build a spending TxOutRef for tests
testOref :: TxOutRef
testOref = TxOutRef (TxId "spent_utxo_id_00000000000000000") 0

-- | An empty Value (no tokens)
emptyValue :: Value
emptyValue = mempty

--------------------------------------------------------------------------------
-- CRIT-01: ProjectVault vote datum manipulation
-- The patched validator verifies continuing output datum:
--   - Vote count incremented by exactly 1 (PVE013)
--   - Developer address unchanged (PVE016)
--   - COT amount unchanged (PVE017)
--   - All other immutable fields preserved
--------------------------------------------------------------------------------

crit01Tests :: TestTree
crit01Tests = testGroup "CRIT-01: ProjectVault vote datum manipulation"
  [ crit01a_voteCountManipulated
  , crit01b_developerMutated
  , crit01c_cotAmountMutated
  , crit01_positive_legitimateVote
  ]

-- Common setup for CRIT-01 tests
-- Input: ProjectSubmitted, 0 yes, 0 no, no voters
crit01InputDatum :: ProjectDatum
crit01InputDatum = mkTestProjectDatum ProjectSubmitted dave 1000 0 0 []

crit01InputDatumData :: Datum
crit01InputDatumData = Datum (toBuiltinData crit01InputDatum)

-- | CRIT-01a: Attacker increments vote count by +2 instead of +1
crit01a_voteCountManipulated :: TestTree
crit01a_voteCountManipulated =
  let -- Malicious output: 2 yes votes instead of 1
      badOutputDatum = mkTestProjectDatum ProjectSubmitted dave 1000 2 0 [alice]
      -- Input at vault script
      vaultInput = mkTxInInfo testOref
        (mkScriptTxOut testVaultHash (singleton testProjectPolicy (TokenName "Test Carbon Project") 1) crit01InputDatumData)
      -- Malicious continuing output with inflated votes
      badOutput = mkScriptTxOut testVaultHash
        (singleton testProjectPolicy (TokenName "Test Carbon Project") 1)
        (Datum (toBuiltinData badOutputDatum))
      -- Reference input with config
      configRef = mkRefInputWithConfig testIdNftPolicy defaultConfig
      -- Build context (alice is voter and signer)
      txInfo' = mkTxInfo [alice] [vaultInput] [badOutput] [configRef] emptyValue
      ctx = mkSpendingCtx txInfo' (Redeemer (toBuiltinData VaultVote)) testOref crit01InputDatumData
  in testAttackRejected3
       "CRIT-01a: vote count manipulated by +2 (PVE013)"
       ProjectVault.untypedValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData testProjectPolicy)
       (toBuiltinData ctx)

-- | CRIT-01b: Attacker changes pdDeveloper in output datum
crit01b_developerMutated :: TestTree
crit01b_developerMutated =
  let -- Malicious output: developer changed from dave to eve
      badOutputDatum = mkTestProjectDatum ProjectSubmitted eve 1000 1 0 [alice]
      vaultInput = mkTxInInfo testOref
        (mkScriptTxOut testVaultHash (singleton testProjectPolicy (TokenName "Test Carbon Project") 1) crit01InputDatumData)
      badOutput = mkScriptTxOut testVaultHash
        (singleton testProjectPolicy (TokenName "Test Carbon Project") 1)
        (Datum (toBuiltinData badOutputDatum))
      configRef = mkRefInputWithConfig testIdNftPolicy defaultConfig
      txInfo' = mkTxInfo [alice] [vaultInput] [badOutput] [configRef] emptyValue
      ctx = mkSpendingCtx txInfo' (Redeemer (toBuiltinData VaultVote)) testOref crit01InputDatumData
  in testAttackRejected3
       "CRIT-01b: developer address mutated in output (PVE016)"
       ProjectVault.untypedValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData testProjectPolicy)
       (toBuiltinData ctx)

-- | CRIT-01c: Attacker changes pdCotAmount in output datum
crit01c_cotAmountMutated :: TestTree
crit01c_cotAmountMutated =
  let -- Malicious output: COT amount changed from 1000 to 9999
      badOutputDatum = mkTestProjectDatum ProjectSubmitted dave 9999 1 0 [alice]
      vaultInput = mkTxInInfo testOref
        (mkScriptTxOut testVaultHash (singleton testProjectPolicy (TokenName "Test Carbon Project") 1) crit01InputDatumData)
      badOutput = mkScriptTxOut testVaultHash
        (singleton testProjectPolicy (TokenName "Test Carbon Project") 1)
        (Datum (toBuiltinData badOutputDatum))
      configRef = mkRefInputWithConfig testIdNftPolicy defaultConfig
      txInfo' = mkTxInfo [alice] [vaultInput] [badOutput] [configRef] emptyValue
      ctx = mkSpendingCtx txInfo' (Redeemer (toBuiltinData VaultVote)) testOref crit01InputDatumData
  in testAttackRejected3
       "CRIT-01c: COT amount mutated in output (PVE017)"
       ProjectVault.untypedValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData testProjectPolicy)
       (toBuiltinData ctx)

-- | CRIT-01 positive: Legitimate vote with correct +1 increment and unchanged fields
crit01_positive_legitimateVote :: TestTree
crit01_positive_legitimateVote =
  let -- Correct output: exactly +1 yes vote, alice added to voters, all fields preserved
      goodOutputDatum = mkTestProjectDatum ProjectSubmitted dave 1000 1 0 [alice]
      vaultInput = mkTxInInfo testOref
        (mkScriptTxOut testVaultHash (singleton testProjectPolicy (TokenName "Test Carbon Project") 1) crit01InputDatumData)
      goodOutput = mkScriptTxOut testVaultHash
        (singleton testProjectPolicy (TokenName "Test Carbon Project") 1)
        (Datum (toBuiltinData goodOutputDatum))
      configRef = mkRefInputWithConfig testIdNftPolicy defaultConfig
      txInfo' = mkTxInfo [alice] [vaultInput] [goodOutput] [configRef] emptyValue
      ctx = mkSpendingCtx txInfo' (Redeemer (toBuiltinData VaultVote)) testOref crit01InputDatumData
  in testAttackAccepted3
       "CRIT-01-positive: legitimate vote accepted"
       ProjectVault.untypedValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData testProjectPolicy)
       (toBuiltinData ctx)

--------------------------------------------------------------------------------
-- CRIT-02: DaoGovernance mint without multisig
-- The patched mintValidator requires multisig authorization (DGE014)
-- for proposal submission.
--------------------------------------------------------------------------------

crit02Tests :: TestTree
crit02Tests = testGroup "CRIT-02: DaoGovernance mint without multisig"
  [ crit02a_unauthorizedSigner
  , crit02b_noSignersAtAll
  , crit02_positive_authorizedSubmit
  ]

-- | Helper to build a DaoGovernance mint context for proposal submission
mkDaoMintCtx :: [PubKeyHash] -> CurrencySymbol -> ScriptContext
mkDaoMintCtx signers proposalPolicy =
  let proposalId = "test_proposal_001"
      -- GovernanceDatum for the output
      govDatum = mkTestGovernanceDatum
        proposalId alice (ActionUpdateFeeAmount 200_000_000) []
        0 0 0 (oneWeekMs P.+ 1000000) ProposalInProgress
      -- Output with proposal NFT and GovernanceDatum
      nftOutput = mkScriptTxOut "governance_script_hash_00000000"
        (singleton proposalPolicy (TokenName proposalId) 1)
        (Datum (toBuiltinData govDatum))
      -- Config reference input
      configRef = mkRefInputWithConfig testIdNftPolicy defaultConfig
      txInfo' = mkTxInfo signers [] [nftOutput] [configRef] emptyValue
  in mkMintingCtx txInfo' (Redeemer (toBuiltinData (DaoSubmitProposal proposalId))) proposalPolicy

-- | CRIT-02a: Unauthorized signer (eve, not in multisig) submits proposal
crit02a_unauthorizedSigner :: TestTree
crit02a_unauthorizedSigner =
  let ctx = mkDaoMintCtx [eve] testProposalPolicy
  in testAttackRejected2
       "CRIT-02a: unauthorized signer submits proposal (DGE014)"
       DaoGovernance.untypedMintValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData ctx)

-- | CRIT-02b: No signers at all
crit02b_noSignersAtAll :: TestTree
crit02b_noSignersAtAll =
  let ctx = mkDaoMintCtx [] testProposalPolicy
  in testAttackRejected2
       "CRIT-02b: no signers at all (DGE014)"
       DaoGovernance.untypedMintValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData ctx)

-- | CRIT-02 positive: Authorized multisig members submit
crit02_positive_authorizedSubmit :: TestTree
crit02_positive_authorizedSubmit =
  let ctx = mkDaoMintCtx [alice, bob] testProposalPolicy
  in testAttackAccepted2
       "CRIT-02-positive: authorized multisig members submit proposal"
       DaoGovernance.untypedMintValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData ctx)

--------------------------------------------------------------------------------
-- CRIT-03: DaoGovernance config field mutation
-- The patched verifyConfigUpdate checks non-target fields are preserved (DGE015).
--------------------------------------------------------------------------------

crit03Tests :: TestTree
crit03Tests = testGroup "CRIT-03: DaoGovernance config field mutation"
  [ crit03a_feeAmountButCategoriesChanged
  , crit03b_addSignerButFeeChanged
  , crit03_positive_onlyTargetFieldChanged
  ]

-- | Helper to build a DaoGovernance spend context for Execute action
mkDaoExecuteCtx
  :: [PubKeyHash]          -- signers
  -> GovernanceDatum       -- input governance datum
  -> GovernanceDatum       -- output governance datum
  -> ConfigDatum           -- input config (ref input)
  -> ConfigDatum           -- output config (in outputs)
  -> ScriptContext
mkDaoExecuteCtx signers inputGov outputGov inputCfg outputCfg =
  let govOref = TxOutRef (TxId "gov_utxo_id_000000000000000000") 0
      inputGovDatum = Datum (toBuiltinData inputGov)
      -- Governance input (being spent)
      govInput = mkTxInInfo govOref
        (mkScriptTxOut "governance_script_hash_00000000"
          (singleton testProposalPolicy (TokenName "test_proposal_001") 1)
          inputGovDatum)
      -- Governance continuing output
      govOutput = mkScriptTxOut "governance_script_hash_00000000"
        (singleton testProposalPolicy (TokenName "test_proposal_001") 1)
        (Datum (toBuiltinData outputGov))
      -- Config reference input (with ID NFT)
      configRef = mkRefInputWithConfig testIdNftPolicy inputCfg
      -- Config output (updated, with ID NFT)
      configOutput = TxOut
        (Address (ScriptCredential (ScriptHash "config_holder_hash_00000000000")) Nothing)
        (singleton testIdNftPolicy (TokenName identificationTokenName) 1)
        (OutputDatum (Datum (toBuiltinData outputCfg)))
        Nothing
      txInfo' = mkTxInfo signers [govInput] [govOutput, configOutput] [configRef] emptyValue
  in mkSpendingCtx txInfo' (Redeemer (toBuiltinData DaoExecute)) govOref inputGovDatum

-- | CRIT-03a: ActionUpdateFeeAmount but cdCategories also mutated
crit03a_feeAmountButCategoriesChanged :: TestTree
crit03a_feeAmountButCategoriesChanged =
  let inputCfg = defaultConfig
      -- Build output config: fee amount changed (intended) + categories mutated (attack)
      outputCfg = mkTestConfigDatum testVaultHash [alice, bob, charlie] 2
      -- We need a config where fee is different AND categories are different.
      -- Since mkTestConfigDatum always uses ["forestry","renewable"], we need to
      -- construct a malicious config. But we can't directly modify ConfigDatum
      -- fields since the constructor is not exported. The mutation would need to
      -- come from a separately constructed ConfigDatum.
      -- For this test, we simply provide a config with different vault hash,
      -- which will trigger DGE015 on the non-target field check.
      badOutputCfg = mkTestConfigDatum testAltHash [alice, bob, charlie] 2

      -- Governance datum: passed proposal to update fee amount
      -- Use past deadline so afterDeadline passes, and yes > no
      inputGov = mkTestGovernanceDatum
        "test_proposal_001" alice (ActionUpdateFeeAmount 200_000_000)
        [] 3 1 0 1000000 ProposalInProgress
      outputGov = mkTestGovernanceDatum
        "test_proposal_001" alice (ActionUpdateFeeAmount 200_000_000)
        [] 3 1 0 1000000 ProposalExecuted

      ctx = mkDaoExecuteCtx [alice, bob] inputGov outputGov inputCfg badOutputCfg
  in testAttackRejected2
       "CRIT-03a: ActionUpdateFeeAmount but vault hash also mutated (DGE015)"
       DaoGovernance.untypedSpendValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData ctx)

-- | CRIT-03b: ActionAddSigner but fee amount also changed
crit03b_addSignerButFeeChanged :: TestTree
crit03b_addSignerButFeeChanged =
  let inputCfg = defaultConfig
      -- Build a config with dave added to signers (intended) but different vault hash (attack)
      badOutputCfg = mkTestConfigDatum testAltHash [alice, bob, charlie, dave] 2

      inputGov = mkTestGovernanceDatum
        "test_proposal_001" alice (ActionAddSigner dave)
        [] 3 1 0 1000000 ProposalInProgress
      outputGov = mkTestGovernanceDatum
        "test_proposal_001" alice (ActionAddSigner dave)
        [] 3 1 0 1000000 ProposalExecuted

      ctx = mkDaoExecuteCtx [alice, bob] inputGov outputGov inputCfg badOutputCfg
  in testAttackRejected2
       "CRIT-03b: ActionAddSigner but vault hash also mutated (DGE015)"
       DaoGovernance.untypedSpendValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData ctx)

-- | CRIT-03 positive: ActionUpdateFeeAmount with only the target field changed
crit03_positive_onlyTargetFieldChanged :: TestTree
crit03_positive_onlyTargetFieldChanged =
  let inputCfg = defaultConfig
      -- Correct output config: same as input except fee amount is different
      -- Since mkTestConfigDatum has a fixed fee of 100_000_000, the inputCfg
      -- has that fee. The action says update to 200_000_000, so output must have 200_000_000.
      -- But we cannot change just the fee via mkTestConfigDatum (it always sets 100_000_000).
      -- The validator checks cdFeesAmount outputCfg P.== newAmt, and it uses preservesAllExcept.
      -- For this positive test, we need to use the actual smart constructor differently.
      -- However, mkConfigDatum always sets fee from its Lovelace parameter.
      -- We must build a config with 200_000_000 fee, same everything else.
      outputCfg = case mkConfigDatum
        (FeeAddress alice)
        (Lovelace 200_000_000)
        ["forestry", "renewable"]
        (Multisig 2 [alice, bob, charlie])
        oneWeekMs
        "test_project_policy_000000000"
        testVaultHash
        "test_voting_hash_000000000000000"
        "test_cot_policy_0000000000000000"
        "test_cet_policy_0000000000000000"
        "test_user_vault_000000000000000"
        of
          P.Right cfg -> cfg
          P.Left _ -> P.error "impossible"

      inputGov = mkTestGovernanceDatum
        "test_proposal_001" alice (ActionUpdateFeeAmount 200_000_000)
        [] 3 1 0 1000000 ProposalInProgress
      outputGov = mkTestGovernanceDatum
        "test_proposal_001" alice (ActionUpdateFeeAmount 200_000_000)
        [] 3 1 0 1000000 ProposalExecuted

      ctx = mkDaoExecuteCtx [alice, bob] inputGov outputGov inputCfg outputCfg
  in testAttackAccepted2
       "CRIT-03-positive: only target field changed accepted"
       DaoGovernance.untypedSpendValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData ctx)

--------------------------------------------------------------------------------
-- CRIT-04: CotPolicy unauthorized COT minting
-- The patched validator checks project status (CPE009) and
-- verifies minted amount matches pdCotAmount from datum (CPE010).
--------------------------------------------------------------------------------

crit04Tests :: TestTree
crit04Tests = testGroup "CRIT-04: CotPolicy unauthorized COT minting"
  [ crit04a_projectNotApproved
  , crit04b_cotAmountMismatch
  , crit04_positive_approvedCorrectAmount
  ]

-- | Helper to build a CotPolicy minting context
mkCotMintCtx
  :: ProjectDatum         -- project datum in input
  -> Integer              -- amount to mint
  -> [PubKeyHash]         -- signers
  -> CurrencySymbol       -- own policy (COT policy)
  -> ScriptContext
mkCotMintCtx projectDatum mintAmt signers cotPolicy =
  let projectOref = TxOutRef (TxId "project_utxo_id_0000000000000000") 0
      projectTokenName = TokenName "Test Carbon Project"
      -- Project input (being spent alongside vault)
      projectInput = mkTxInInfo projectOref
        (mkScriptTxOut testVaultHash
          (singleton testProjectPolicy projectTokenName 1)
          (Datum (toBuiltinData projectDatum)))
      -- Config reference input
      configRef = mkRefInputWithConfig testIdNftPolicy defaultConfig
      -- Mint value: burn vault token, mint COT
      mintVal = singleton testProjectPolicy projectTokenName (-1)
             <> singleton cotPolicy (TokenName "Test Carbon Project") mintAmt
      -- Redeemer for COT policy
      cotRed = CotRedeemer 0 projectOref mintAmt (TokenName "Test Carbon Project")
      txInfo' = mkTxInfo signers [projectInput] [] [configRef] mintVal
  in mkMintingCtx txInfo' (Redeemer (toBuiltinData cotRed)) cotPolicy

-- | CRIT-04a: Project not approved (still Submitted) but COT minting attempted
crit04a_projectNotApproved :: TestTree
crit04a_projectNotApproved =
  let projectDatum = mkTestProjectDatum ProjectSubmitted dave 1000 0 0 []
      cotPolicy = CurrencySymbol "test_cot_policy_0000000000000000"
      ctx = mkCotMintCtx projectDatum 1000 [alice, bob] cotPolicy
  in testAttackRejected3
       "CRIT-04a: project not approved but COT mint attempted (CPE009)"
       CotPolicy.untypedValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData testProjectPolicy)
       (toBuiltinData ctx)

-- | CRIT-04b: Minted COT amount differs from pdCotAmount
crit04b_cotAmountMismatch :: TestTree
crit04b_cotAmountMismatch =
  let projectDatum = mkTestProjectDatum ProjectApproved dave 1000 3 0 [alice, bob, charlie]
      cotPolicy = CurrencySymbol "test_cot_policy_0000000000000000"
      -- Attack: mint 9999 instead of the datum-specified 1000
      ctx = mkCotMintCtx projectDatum 9999 [alice, bob] cotPolicy
  in testAttackRejected3
       "CRIT-04b: minted COT amount differs from pdCotAmount (CPE010)"
       CotPolicy.untypedValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData testProjectPolicy)
       (toBuiltinData ctx)

-- | CRIT-04 positive: Approved project, correct COT amount
crit04_positive_approvedCorrectAmount :: TestTree
crit04_positive_approvedCorrectAmount =
  let projectDatum = mkTestProjectDatum ProjectApproved dave 1000 3 0 [alice, bob, charlie]
      cotPolicy = CurrencySymbol "test_cot_policy_0000000000000000"
      ctx = mkCotMintCtx projectDatum 1000 [alice, bob] cotPolicy
  in testAttackAccepted3
       "CRIT-04-positive: approved project with correct COT amount"
       CotPolicy.untypedValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData testProjectPolicy)
       (toBuiltinData ctx)

--------------------------------------------------------------------------------
-- HIGH-01: ProjectPolicy NFT sent to wrong script
-- The patched validator verifies NFT goes to exact cdProjectVaultHash (PPE007)
-- and has an inline datum (PPE009).
--------------------------------------------------------------------------------

high01Tests :: TestTree
high01Tests = testGroup "HIGH-01: ProjectPolicy NFT sent to wrong script"
  [ high01a_nftToWrongScript
  , high01b_nftToPkhAddress
  , high01c_nftToCorrectScriptNoDatum
  , high01_positive_nftToCorrectVault
  ]

-- | Helper to build ProjectPolicy mint context
mkProjectMintCtx :: [TxOut] -> [PubKeyHash] -> CurrencySymbol -> Value -> ScriptContext
mkProjectMintCtx outputs signers ownPolicy mintVal =
  let configRef = mkRefInputWithConfig testIdNftPolicy defaultConfig
      -- Fee payment output
      feeOutput = mkPkhTxOut alice (singleton (CurrencySymbol "") (TokenName "") 100_000_000)
      txInfo' = mkTxInfo signers [] (outputs ++ [feeOutput]) [configRef] mintVal
  in mkMintingCtx txInfo' (Redeemer (toBuiltinData MintProject)) ownPolicy

-- | HIGH-01a: NFT sent to different script hash (testAltHash)
high01a_nftToWrongScript :: TestTree
high01a_nftToWrongScript =
  let ownPolicy = testProjectPolicy
      tokenName = TokenName "Test Carbon Project"
      mintVal = singleton ownPolicy tokenName 1
      projectDatum = mkTestProjectDatum ProjectSubmitted dave 1000 0 0 []
      -- NFT goes to wrong script (testAltHash instead of testVaultHash)
      badOutput = mkScriptTxOut testAltHash
        (singleton ownPolicy tokenName 1)
        (Datum (toBuiltinData projectDatum))
      ctx = mkProjectMintCtx [badOutput] [alice] ownPolicy mintVal
  in testAttackRejected2
       "HIGH-01a: NFT sent to wrong script hash (PPE007)"
       ProjectPolicy.untypedValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData ctx)

-- | HIGH-01b: NFT sent to PubKeyCredential address
high01b_nftToPkhAddress :: TestTree
high01b_nftToPkhAddress =
  let ownPolicy = testProjectPolicy
      tokenName = TokenName "Test Carbon Project"
      mintVal = singleton ownPolicy tokenName 1
      projectDatum = mkTestProjectDatum ProjectSubmitted dave 1000 0 0 []
      -- NFT goes to a PubKey address (eve's) instead of script
      badOutput = TxOut
        (Address (PubKeyCredential eve) Nothing)
        (singleton ownPolicy tokenName 1)
        (OutputDatum (Datum (toBuiltinData projectDatum)))
        Nothing
      ctx = mkProjectMintCtx [badOutput] [alice] ownPolicy mintVal
  in testAttackRejected2
       "HIGH-01b: NFT sent to PubKey address instead of script (PPE007)"
       ProjectPolicy.untypedValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData ctx)

-- | HIGH-01c: NFT sent to correct script but no inline datum
high01c_nftToCorrectScriptNoDatum :: TestTree
high01c_nftToCorrectScriptNoDatum =
  let ownPolicy = testProjectPolicy
      tokenName = TokenName "Test Carbon Project"
      mintVal = singleton ownPolicy tokenName 1
      -- Output to correct vault hash but with no datum
      badOutput = TxOut
        (Address (ScriptCredential (ScriptHash testVaultHash)) Nothing)
        (singleton ownPolicy tokenName 1)
        NoOutputDatum
        Nothing
      ctx = mkProjectMintCtx [badOutput] [alice] ownPolicy mintVal
  in testAttackRejected2
       "HIGH-01c: NFT to correct script but missing inline datum (PPE009)"
       ProjectPolicy.untypedValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData ctx)

-- | HIGH-01 positive: NFT sent to correct vault hash with inline datum
high01_positive_nftToCorrectVault :: TestTree
high01_positive_nftToCorrectVault =
  let ownPolicy = testProjectPolicy
      tokenName = TokenName "Test Carbon Project"
      mintVal = singleton ownPolicy tokenName 1
      projectDatum = mkTestProjectDatum ProjectSubmitted dave 1000 0 0 []
      -- NFT goes to correct vault script with datum
      goodOutput = mkScriptTxOut testVaultHash
        (singleton ownPolicy tokenName 1)
        (Datum (toBuiltinData projectDatum))
      ctx = mkProjectMintCtx [goodOutput] [alice] ownPolicy mintVal
  in testAttackAccepted2
       "HIGH-01-positive: NFT sent to correct vault with inline datum"
       ProjectPolicy.untypedValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData ctx)

--------------------------------------------------------------------------------
-- HIGH-02: Trivial signer bypass
-- The patched validators use txSignedBy to verify the specific voter signed,
-- not just checking if signatories list is non-empty.
--------------------------------------------------------------------------------

high02Tests :: TestTree
high02Tests = testGroup "HIGH-02: Trivial signer bypass"
  [ high02a_projectVaultUnauthorizedVoter
  , high02b_daoGovernanceUnauthorizedVoter
  ]

-- | HIGH-02a: ProjectVault vote with unauthorized signer (eve not in multisig)
high02a_projectVaultUnauthorizedVoter :: TestTree
high02a_projectVaultUnauthorizedVoter =
  let inputDatum = mkTestProjectDatum ProjectSubmitted dave 1000 0 0 []
      inputDatumData = Datum (toBuiltinData inputDatum)
      -- Eve (not in multisig) tries to vote
      outputDatum = mkTestProjectDatum ProjectSubmitted dave 1000 1 0 [eve]
      vaultInput = mkTxInInfo testOref
        (mkScriptTxOut testVaultHash (singleton testProjectPolicy (TokenName "Test Carbon Project") 1) inputDatumData)
      output = mkScriptTxOut testVaultHash
        (singleton testProjectPolicy (TokenName "Test Carbon Project") 1)
        (Datum (toBuiltinData outputDatum))
      configRef = mkRefInputWithConfig testIdNftPolicy defaultConfig
      -- Eve signs but is not in multisig [alice, bob, charlie]
      txInfo' = mkTxInfo [eve] [vaultInput] [output] [configRef] emptyValue
      ctx = mkSpendingCtx txInfo' (Redeemer (toBuiltinData VaultVote)) testOref inputDatumData
  in testAttackRejected3
       "HIGH-02a: ProjectVault vote by non-multisig member (PVE005)"
       ProjectVault.untypedValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData testProjectPolicy)
       (toBuiltinData ctx)

-- | HIGH-02b: DaoGovernance vote with unauthorized signer
high02b_daoGovernanceUnauthorizedVoter :: TestTree
high02b_daoGovernanceUnauthorizedVoter =
  let inputGov = mkTestGovernanceDatum
        "test_proposal_001" alice (ActionUpdateFeeAmount 200_000_000)
        [VoteRecord alice VoterPending, VoteRecord bob VoterPending, VoteRecord eve VoterPending]
        0 0 0 (oneWeekMs P.+ 1000000) ProposalInProgress
      -- Eve's vote updated in output
      outputGov = mkTestGovernanceDatum
        "test_proposal_001" alice (ActionUpdateFeeAmount 200_000_000)
        [VoteRecord alice VoterPending, VoteRecord bob VoterPending, VoteRecord eve (VoterVoted VoteYes)]
        1 0 0 (oneWeekMs P.+ 1000000) ProposalInProgress
      govOref = TxOutRef (TxId "gov_utxo_id_000000000000000000") 0
      inputDatumData = Datum (toBuiltinData inputGov)
      govInput = mkTxInInfo govOref
        (mkScriptTxOut "governance_script_hash_00000000"
          (singleton testProposalPolicy (TokenName "test_proposal_001") 1)
          inputDatumData)
      govOutput = mkScriptTxOut "governance_script_hash_00000000"
        (singleton testProposalPolicy (TokenName "test_proposal_001") 1)
        (Datum (toBuiltinData outputGov))
      configRef = mkRefInputWithConfig testIdNftPolicy defaultConfig
      -- Eve signs but is not in multisig [alice, bob, charlie]
      txInfo' = mkTxInfo [eve] [govInput] [govOutput] [configRef] emptyValue
      ctx = mkSpendingCtx txInfo' (Redeemer (toBuiltinData (DaoVote VoteYes))) govOref inputDatumData
  in testAttackRejected2
       "HIGH-02b: DaoGovernance vote by non-multisig member (DGE008)"
       DaoGovernance.untypedSpendValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData ctx)

--------------------------------------------------------------------------------
-- HIGH-03: DaoGovernance execute/reject without multisig
-- The patched validateExecute and validateReject require multisig (DGE017/DGE018).
--------------------------------------------------------------------------------

high03Tests :: TestTree
high03Tests = testGroup "HIGH-03: DaoGovernance execute/reject without multisig"
  [ high03a_executeZeroSigners
  , high03b_executeUnauthorizedSigner
  , high03c_rejectZeroSigners
  , high03d_rejectUnauthorizedSigner
  , high03_positive_executeWithMultisig
  ]

-- | Helper: Build a DaoGovernance spend context for execute/reject
mkDaoFinalizeCtx
  :: [PubKeyHash]     -- signers
  -> DaoSpendRedeemer -- DaoExecute or DaoReject
  -> GovernanceDatum  -- input
  -> GovernanceDatum  -- output
  -> ConfigDatum      -- config
  -> ScriptContext
mkDaoFinalizeCtx signers red inputGov outputGov cfg =
  let govOref = TxOutRef (TxId "gov_utxo_id_000000000000000000") 0
      inputDatumData = Datum (toBuiltinData inputGov)
      govInput = mkTxInInfo govOref
        (mkScriptTxOut "governance_script_hash_00000000"
          (singleton testProposalPolicy (TokenName "test_proposal_001") 1)
          inputDatumData)
      govOutput = mkScriptTxOut "governance_script_hash_00000000"
        (singleton testProposalPolicy (TokenName "test_proposal_001") 1)
        (Datum (toBuiltinData outputGov))
      configRef = mkRefInputWithConfig testIdNftPolicy cfg
      -- For Execute, we also need a config output; for Reject, just governance output
      outputs = case red of
        DaoExecute ->
          let configOutput = TxOut
                (Address (ScriptCredential (ScriptHash "config_holder_hash_00000000000")) Nothing)
                (singleton testIdNftPolicy (TokenName identificationTokenName) 1)
                (OutputDatum (Datum (toBuiltinData cfg)))
                Nothing
          in [govOutput, configOutput]
        _ -> [govOutput]
      txInfo' = mkTxInfo signers [govInput] outputs [configRef] emptyValue
  in mkSpendingCtx txInfo' (Redeemer (toBuiltinData red)) govOref inputDatumData

-- | Passed governance datum for execute (yes > no, past deadline)
high03InputGovExecute :: GovernanceDatum
high03InputGovExecute = mkTestGovernanceDatum
  "test_proposal_001" alice (ActionUpdateFeeAmount 200_000_000)
  [] 3 1 0 1000000 ProposalInProgress

high03OutputGovExecute :: GovernanceDatum
high03OutputGovExecute = mkTestGovernanceDatum
  "test_proposal_001" alice (ActionUpdateFeeAmount 200_000_000)
  [] 3 1 0 1000000 ProposalExecuted

-- | Passed governance datum for reject (no >= yes, past deadline)
high03InputGovReject :: GovernanceDatum
high03InputGovReject = mkTestGovernanceDatum
  "test_proposal_001" alice (ActionUpdateFeeAmount 200_000_000)
  [] 1 3 0 1000000 ProposalInProgress

high03OutputGovReject :: GovernanceDatum
high03OutputGovReject = mkTestGovernanceDatum
  "test_proposal_001" alice (ActionUpdateFeeAmount 200_000_000)
  [] 1 3 0 1000000 ProposalRejected

-- | HIGH-03a: Execute with zero signers
high03a_executeZeroSigners :: TestTree
high03a_executeZeroSigners =
  let ctx = mkDaoFinalizeCtx [] DaoExecute high03InputGovExecute high03OutputGovExecute defaultConfig
  in testAttackRejected2
       "HIGH-03a: execute with zero signers (DGE017)"
       DaoGovernance.untypedSpendValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData ctx)

-- | HIGH-03b: Execute with unauthorized signer (eve)
high03b_executeUnauthorizedSigner :: TestTree
high03b_executeUnauthorizedSigner =
  let ctx = mkDaoFinalizeCtx [eve] DaoExecute high03InputGovExecute high03OutputGovExecute defaultConfig
  in testAttackRejected2
       "HIGH-03b: execute with unauthorized signer (DGE017)"
       DaoGovernance.untypedSpendValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData ctx)

-- | HIGH-03c: Reject with zero signers
high03c_rejectZeroSigners :: TestTree
high03c_rejectZeroSigners =
  let ctx = mkDaoFinalizeCtx [] DaoReject high03InputGovReject high03OutputGovReject defaultConfig
  in testAttackRejected2
       "HIGH-03c: reject with zero signers (DGE018)"
       DaoGovernance.untypedSpendValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData ctx)

-- | HIGH-03d: Reject with unauthorized signer
high03d_rejectUnauthorizedSigner :: TestTree
high03d_rejectUnauthorizedSigner =
  let ctx = mkDaoFinalizeCtx [eve] DaoReject high03InputGovReject high03OutputGovReject defaultConfig
  in testAttackRejected2
       "HIGH-03d: reject with unauthorized signer (DGE018)"
       DaoGovernance.untypedSpendValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData ctx)

-- | HIGH-03 positive: Execute with enough authorized signers
high03_positive_executeWithMultisig :: TestTree
high03_positive_executeWithMultisig =
  let -- For execute positive: need output config with updated fee
      outputCfg = case mkConfigDatum
        (FeeAddress alice)
        (Lovelace 200_000_000)
        ["forestry", "renewable"]
        (Multisig 2 [alice, bob, charlie])
        oneWeekMs
        "test_project_policy_000000000"
        testVaultHash
        "test_voting_hash_000000000000000"
        "test_cot_policy_0000000000000000"
        "test_cet_policy_0000000000000000"
        "test_user_vault_000000000000000"
        of
          P.Right cfg -> cfg
          P.Left _ -> P.error "impossible"
      ctx = mkDaoExecuteCtx [alice, bob] high03InputGovExecute high03OutputGovExecute defaultConfig outputCfg
  in testAttackAccepted2
       "HIGH-03-positive: execute with authorized multisig"
       DaoGovernance.untypedSpendValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData ctx)

--------------------------------------------------------------------------------
-- HIGH-04: DaoGovernance vote impersonation
-- The patched validator uses txSignedBy to verify the specific voter signed.
--------------------------------------------------------------------------------

high04Tests :: TestTree
high04Tests = testGroup "HIGH-04: DaoGovernance vote impersonation"
  [ high04a_impersonateVoter
  , high04b_noSignerAtAll
  , high04_positive_voterSignsOwn
  ]

-- | Helper: Build DaoGovernance vote spend context
mkDaoVoteCtx
  :: [PubKeyHash]     -- signers
  -> PubKeyHash       -- voter (who is recorded as voting)
  -> Vote             -- vote direction
  -> ScriptContext
mkDaoVoteCtx signers voter vote =
  let inputGov = mkTestGovernanceDatum
        "test_proposal_001" alice (ActionUpdateFeeAmount 200_000_000)
        [ VoteRecord alice VoterPending
        , VoteRecord bob VoterPending
        , VoteRecord charlie VoterPending
        ]
        0 0 0 (oneWeekMs P.+ 1000000) ProposalInProgress
      -- Output: voter's status updated
      outputVotes = case () of
        _ | voter P.== alice -> [VoteRecord alice (VoterVoted vote), VoteRecord bob VoterPending, VoteRecord charlie VoterPending]
          | voter P.== bob   -> [VoteRecord alice VoterPending, VoteRecord bob (VoterVoted vote), VoteRecord charlie VoterPending]
          | P.otherwise      -> [VoteRecord alice VoterPending, VoteRecord bob VoterPending, VoteRecord charlie VoterPending]
      (yc, nc) = case vote of
        VoteYes -> (1, 0)
        VoteNo  -> (0, 1)
        _       -> (0, 0)
      outputGov = mkTestGovernanceDatum
        "test_proposal_001" alice (ActionUpdateFeeAmount 200_000_000)
        outputVotes yc nc 0 (oneWeekMs P.+ 1000000) ProposalInProgress
      govOref = TxOutRef (TxId "gov_utxo_id_000000000000000000") 0
      inputDatumData = Datum (toBuiltinData inputGov)
      govInput = mkTxInInfo govOref
        (mkScriptTxOut "governance_script_hash_00000000"
          (singleton testProposalPolicy (TokenName "test_proposal_001") 1)
          inputDatumData)
      govOutput = mkScriptTxOut "governance_script_hash_00000000"
        (singleton testProposalPolicy (TokenName "test_proposal_001") 1)
        (Datum (toBuiltinData outputGov))
      configRef = mkRefInputWithConfig testIdNftPolicy defaultConfig
      txInfo' = mkTxInfo signers [govInput] [govOutput] [configRef] emptyValue
  in mkSpendingCtx txInfo' (Redeemer (toBuiltinData (DaoVote vote))) govOref inputDatumData

-- | HIGH-04a: Eve signs but claims to vote as alice (impersonation)
-- Eve is the first signer, so voter = eve. But the output records alice as
-- having voted -- the validator should reject because eve's VoteRecord
-- is not found (eve is not in the votes list at all, since DGE002 checks
-- txSignedBy for the first signer, and the first signer is eve who is not
-- in multisig).
high04a_impersonateVoter :: TestTree
high04a_impersonateVoter =
  let -- Eve signs the transaction but is not in the multisig
      ctx = mkDaoVoteCtx [eve] alice VoteYes
  in testAttackRejected2
       "HIGH-04a: eve signs but tries to impersonate alice (DGE002)"
       DaoGovernance.untypedSpendValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData ctx)

-- | HIGH-04b: No signer at all
high04b_noSignerAtAll :: TestTree
high04b_noSignerAtAll =
  let -- No signers: voter extraction will fail with DGE002
      inputGov = mkTestGovernanceDatum
        "test_proposal_001" alice (ActionUpdateFeeAmount 200_000_000)
        [VoteRecord alice VoterPending, VoteRecord bob VoterPending]
        0 0 0 (oneWeekMs P.+ 1000000) ProposalInProgress
      outputGov = mkTestGovernanceDatum
        "test_proposal_001" alice (ActionUpdateFeeAmount 200_000_000)
        [VoteRecord alice (VoterVoted VoteYes), VoteRecord bob VoterPending]
        1 0 0 (oneWeekMs P.+ 1000000) ProposalInProgress
      govOref = TxOutRef (TxId "gov_utxo_id_000000000000000000") 0
      inputDatumData = Datum (toBuiltinData inputGov)
      govInput = mkTxInInfo govOref
        (mkScriptTxOut "governance_script_hash_00000000"
          (singleton testProposalPolicy (TokenName "test_proposal_001") 1)
          inputDatumData)
      govOutput = mkScriptTxOut "governance_script_hash_00000000"
        (singleton testProposalPolicy (TokenName "test_proposal_001") 1)
        (Datum (toBuiltinData outputGov))
      configRef = mkRefInputWithConfig testIdNftPolicy defaultConfig
      txInfo' = mkTxInfo [] [govInput] [govOutput] [configRef] emptyValue
      ctx = mkSpendingCtx txInfo' (Redeemer (toBuiltinData (DaoVote VoteYes))) govOref inputDatumData
  in testAttackRejected2
       "HIGH-04b: no signer at all (DGE002)"
       DaoGovernance.untypedSpendValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData ctx)

-- | HIGH-04 positive: Voter signs their own transaction
high04_positive_voterSignsOwn :: TestTree
high04_positive_voterSignsOwn =
  let ctx = mkDaoVoteCtx [alice] alice VoteYes
  in testAttackAccepted2
       "HIGH-04-positive: voter signs own transaction"
       DaoGovernance.untypedSpendValidator
       (toBuiltinData testIdNftPolicy)
       (toBuiltinData ctx)
