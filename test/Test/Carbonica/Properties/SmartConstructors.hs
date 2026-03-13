{- |
Module      : Test.Carbonica.Properties.SmartConstructors
Description : Property-based tests for Carbonica smart constructors
License     : Apache-2.0

This module tests the invariants enforced by smart constructors using QuickCheck.
Properties are tested with 100 random test cases each.

Covers all 8 smart constructors:
  - mkLovelace, mkCotAmount (existing)
  - mkCetAmount, mkPercentage, mkMultisig, mkConfigDatum, mkProjectDatum, mkGovernanceDatum (new)
-}
module Test.Carbonica.Properties.SmartConstructors (propertyTests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.QuickCheck

import qualified PlutusTx.Prelude as P

import PlutusLedgerApi.V3 (PubKeyHash (..))

import Carbonica.Types.Core
    ( Lovelace (..)
    , CetAmount (..)
    , Percentage (..)
    , CotAmount (..)
    , DeveloperAddress (..)
    , FeeAddress (..)
    , mkLovelace
    , mkCotAmount
    , mkCetAmount
    , mkPercentage
    , cotValue
    , cetValue
    )
import Carbonica.Types.Config
    ( Multisig (..)
    , mkMultisig
    , mkConfigDatum
    , cdFeesAmount
    , cdCategories
    , oneWeekMs
    )
import Carbonica.Types.Project
    ( ProjectStatus (..)
    , mkProjectDatum
    , pdProjectName
    , pdCotAmount
    , pdYesVotes
    , pdNoVotes
    )
import Carbonica.Types.Governance
    ( ProposalAction (..)
    , ProposalState (..)
    , mkGovernanceDatum
    , gdProposalId
    , gdYesCount
    , gdNoCount
    , gdAbstainCount
    )

--------------------------------------------------------------------------------
-- PROPERTY TESTS
--------------------------------------------------------------------------------

propertyTests :: TestTree
propertyTests = testGroup "Property-Based Tests (QuickCheck)"
  [ lovelaceProperties
  , cotAmountProperties
  , cetAmountProperties
  , percentageProperties
  , multisigProperties
  , configDatumProperties
  , projectDatumProperties
  , governanceDatumProperties
  ]

--------------------------------------------------------------------------------
-- TEST HELPERS
--------------------------------------------------------------------------------

-- | Generate test PubKeyHashes from an integer index.
-- Each PubKeyHash is a 28-byte padded string for uniqueness.
mkTestPkh :: Int -> PubKeyHash
mkTestPkh 1 = PubKeyHash "prop_pkh_01_bytes_0000000000"
mkTestPkh 2 = PubKeyHash "prop_pkh_02_bytes_0000000000"
mkTestPkh 3 = PubKeyHash "prop_pkh_03_bytes_0000000000"
mkTestPkh 4 = PubKeyHash "prop_pkh_04_bytes_0000000000"
mkTestPkh 5 = PubKeyHash "prop_pkh_05_bytes_0000000000"
mkTestPkh _ = PubKeyHash "prop_pkh_xx_bytes_0000000000"

testAlice, testBob, testCharlie :: PubKeyHash
testAlice   = PubKeyHash "alice___pkh_bytes_0000000000"
testBob     = PubKeyHash "bob_____pkh_bytes_0000000000"
testCharlie = PubKeyHash "charlie_pkh_bytes_0000000000"

--------------------------------------------------------------------------------
-- LOVELACE PROPERTIES
--------------------------------------------------------------------------------

lovelaceProperties :: TestTree
lovelaceProperties = testGroup "Lovelace Smart Constructor Properties"
  [ testProperty "Positive lovelace accepted" prop_lovelaceAcceptsPositive
  , testProperty "Zero lovelace accepted" prop_lovelaceAcceptsZero
  , testProperty "Negative lovelace rejected" prop_lovelaceRejectsNegative
  , testProperty "Non-negative amounts accepted" prop_lovelaceAcceptsNonNegative
  ]

-- Property: Positive amounts should be accepted
prop_lovelaceAcceptsPositive :: Positive Integer -> Bool
prop_lovelaceAcceptsPositive (Positive amt) =
  case mkLovelace amt of
    P.Right (Lovelace actual) -> actual P.== amt
    P.Left _ -> False

-- Property: Zero should be accepted (lovelace allows zero)
prop_lovelaceAcceptsZero :: Bool
prop_lovelaceAcceptsZero =
  case mkLovelace 0 of
    P.Right (Lovelace 0) -> True
    _ -> False

-- Property: Non-negative amounts accepted
prop_lovelaceAcceptsNonNegative :: NonNegative Integer -> Bool
prop_lovelaceAcceptsNonNegative (NonNegative amt) =
  case mkLovelace amt of
    P.Right (Lovelace actual) -> actual P.== amt
    P.Left _ -> False

-- Property: Negative amounts should be rejected
prop_lovelaceRejectsNegative :: Positive Integer -> Bool
prop_lovelaceRejectsNegative (Positive posAmt) =
  let negativeAmt = negate posAmt
  in case mkLovelace negativeAmt of
       P.Left _ -> True
       P.Right _ -> False

--------------------------------------------------------------------------------
-- COT AMOUNT PROPERTIES
--------------------------------------------------------------------------------

cotAmountProperties :: TestTree
cotAmountProperties = testGroup "CotAmount Smart Constructor Properties"
  [ testProperty "Positive COT amount accepted" prop_cotAcceptsPositive
  , testProperty "Zero COT amount accepted" prop_cotAcceptsZero
  , testProperty "Negative COT amount rejected" prop_cotRejectsNegative
  , testProperty "CotAmount preserves value" prop_cotPreservesValue
  , testProperty "Non-negative COT amounts accepted" prop_cotAcceptsNonNegative
  ]

-- Property: Positive amounts should be accepted
prop_cotAcceptsPositive :: Positive Integer -> Bool
prop_cotAcceptsPositive (Positive amt) =
  case mkCotAmount amt of
    P.Right cotAmt -> cotValue cotAmt P.== amt
    P.Left _ -> False

-- Property: Zero should be accepted (CotAmount allows zero)
prop_cotAcceptsZero :: Bool
prop_cotAcceptsZero =
  case mkCotAmount 0 of
    P.Right cotAmt -> cotValue cotAmt P.== 0
    P.Left _ -> False

-- Property: Non-negative amounts accepted
prop_cotAcceptsNonNegative :: NonNegative Integer -> Bool
prop_cotAcceptsNonNegative (NonNegative amt) =
  case mkCotAmount amt of
    P.Right cotAmt -> cotValue cotAmt P.== amt
    P.Left _ -> False

-- Property: Negative amounts should be rejected
prop_cotRejectsNegative :: Positive Integer -> Bool
prop_cotRejectsNegative (Positive posAmt) =
  let negativeAmt = negate posAmt
  in case mkCotAmount negativeAmt of
       P.Left _ -> True
       P.Right _ -> False

-- Property: cotValue retrieves the original amount
prop_cotPreservesValue :: Positive Integer -> Bool
prop_cotPreservesValue (Positive amt) =
  case mkCotAmount amt of
    P.Right cotAmt -> cotValue cotAmt P.== amt
    P.Left _ -> False

--------------------------------------------------------------------------------
-- CET AMOUNT PROPERTIES
--------------------------------------------------------------------------------

cetAmountProperties :: TestTree
cetAmountProperties = testGroup "CetAmount Smart Constructor Properties"
  [ testProperty "Positive CET amount accepted" prop_cetAcceptsPositive
  , testProperty "Zero CET amount accepted" prop_cetAcceptsZero
  , testProperty "Negative CET amount rejected" prop_cetRejectsNegative
  , testProperty "CetAmount preserves value" prop_cetPreservesValue
  ]

-- Property: Positive amounts should be accepted, cetValue preserves
prop_cetAcceptsPositive :: Positive Integer -> Bool
prop_cetAcceptsPositive (Positive amt) =
  case mkCetAmount amt of
    P.Right cetAmt -> cetValue cetAmt P.== amt
    P.Left _ -> False

-- Property: Zero should be accepted
prop_cetAcceptsZero :: Bool
prop_cetAcceptsZero =
  case mkCetAmount 0 of
    P.Right cetAmt -> cetValue cetAmt P.== 0
    P.Left _ -> False

-- Property: Negative amounts should be rejected
prop_cetRejectsNegative :: Positive Integer -> Bool
prop_cetRejectsNegative (Positive posAmt) =
  let negativeAmt = negate posAmt
  in case mkCetAmount negativeAmt of
       P.Left _ -> True
       P.Right _ -> False

-- Property: cetValue retrieves the original amount (roundtrip)
prop_cetPreservesValue :: Positive Integer -> Bool
prop_cetPreservesValue (Positive amt) =
  case mkCetAmount amt of
    P.Right cetAmt -> cetValue cetAmt P.== amt
    P.Left _ -> False

--------------------------------------------------------------------------------
-- PERCENTAGE PROPERTIES
--------------------------------------------------------------------------------

percentageProperties :: TestTree
percentageProperties = testGroup "Percentage Smart Constructor Properties"
  [ testProperty "Zero percentage accepted" prop_percentageAcceptsZero
  , testProperty "100 percentage accepted" prop_percentageAcceptsHundred
  , testProperty "Range [0,100] accepted" prop_percentageAcceptsRange
  , testProperty "Above 100 rejected" prop_percentageRejectsAbove100
  , testProperty "Negative rejected" prop_percentageRejectsNegative
  , testProperty "Percentage preserves value" prop_percentagePreservesValue
  ]

-- Property: mkPercentage 0 succeeds
prop_percentageAcceptsZero :: Bool
prop_percentageAcceptsZero =
  case mkPercentage 0 of
    P.Right (Percentage 0) -> True
    _ -> False

-- Property: mkPercentage 100 succeeds
prop_percentageAcceptsHundred :: Bool
prop_percentageAcceptsHundred =
  case mkPercentage 100 of
    P.Right (Percentage 100) -> True
    _ -> False

-- Property: Values in [0,100] are always accepted
prop_percentageAcceptsRange :: NonNegative Integer -> Bool
prop_percentageAcceptsRange (NonNegative raw) =
  let n = raw `mod` 101  -- clamp to [0,100]
  in case mkPercentage n of
       P.Right _ -> True
       P.Left _  -> False

-- Property: Values above 100 are rejected
prop_percentageRejectsAbove100 :: Positive Integer -> Bool
prop_percentageRejectsAbove100 (Positive n) =
  case mkPercentage (100 + n) of
    P.Left _ -> True
    P.Right _ -> False

-- Property: Negative values are rejected
prop_percentageRejectsNegative :: Positive Integer -> Bool
prop_percentageRejectsNegative (Positive n) =
  case mkPercentage (negate n) of
    P.Left _ -> True
    P.Right _ -> False

-- Property: Value is preserved through construction
prop_percentagePreservesValue :: NonNegative Integer -> Bool
prop_percentagePreservesValue (NonNegative raw) =
  let n = raw `mod` 101  -- clamp to [0,100]
  in case mkPercentage n of
       P.Right (Percentage v) -> v P.== n
       P.Left _ -> False

--------------------------------------------------------------------------------
-- MULTISIG PROPERTIES
--------------------------------------------------------------------------------

multisigProperties :: TestTree
multisigProperties = testGroup "Multisig Smart Constructor Properties"
  [ testProperty "Valid multisig accepted" prop_multisigAcceptsValid
  , testProperty "Empty signers rejected" prop_multisigRejectsEmpty
  , testProperty "Zero required rejected" prop_multisigRejectsZeroRequired
  , testProperty "Excess required rejected" prop_multisigRejectsExcessRequired
  , testProperty "Required == length accepted" prop_multisigAcceptsEqualRequired
  ]

-- Property: Valid multisig with required in [1, length signers]
prop_multisigAcceptsValid :: Positive Int -> Bool
prop_multisigAcceptsValid (Positive rawN) =
  let n = (rawN `mod` 5) + 1  -- 1-5 signers
      signers = map mkTestPkh [1..n]
      required = fromIntegral ((rawN `mod` n) + 1)  -- [1, n]
  in case mkMultisig required signers of
       P.Right ms -> msRequired ms P.== required
                  && length (msSigners ms) == n
       P.Left _   -> False

-- Property: Empty signers list is always rejected
prop_multisigRejectsEmpty :: Bool
prop_multisigRejectsEmpty =
  case mkMultisig 1 [] of
    P.Left _ -> True
    P.Right _ -> False

-- Property: Zero required is rejected
prop_multisigRejectsZeroRequired :: Bool
prop_multisigRejectsZeroRequired =
  case mkMultisig 0 [testAlice, testBob] of
    P.Left _ -> True
    P.Right _ -> False

-- Property: Required > length signers is rejected
prop_multisigRejectsExcessRequired :: Bool
prop_multisigRejectsExcessRequired =
  case mkMultisig 4 [testAlice, testBob, testCharlie] of
    P.Left _ -> True
    P.Right _ -> False

-- Property: Required == length signers is accepted
prop_multisigAcceptsEqualRequired :: Bool
prop_multisigAcceptsEqualRequired =
  case mkMultisig 3 [testAlice, testBob, testCharlie] of
    P.Right ms -> msRequired ms P.== 3
    P.Left _   -> False

--------------------------------------------------------------------------------
-- CONFIG DATUM PROPERTIES
--------------------------------------------------------------------------------

configDatumProperties :: TestTree
configDatumProperties = testGroup "ConfigDatum Smart Constructor Properties"
  [ testProperty "Valid config accepted" prop_configDatumAcceptsValid
  , testProperty "Zero fee rejected" prop_configDatumRejectsZeroFee
  , testProperty "Empty categories rejected" prop_configDatumRejectsEmptyCategories
  , testProperty "Config preserves fee" prop_configDatumPreservesFee
  ]

-- Property: Known-good inputs produce Right, with correct fee and categories
prop_configDatumAcceptsValid :: Bool
prop_configDatumAcceptsValid =
  case mkConfigDatum
    (FeeAddress testAlice)
    (Lovelace 100_000_000)
    ["forestry", "renewable"]
    (Multisig 2 [testAlice, testBob, testCharlie])
    oneWeekMs
    "proj_policy" "vault_hash_" "voting_hash"
    "cot_policy_" "cet_policy_" "user_vault__"
  of
    P.Right cfg -> cdFeesAmount cfg P.== 100_000_000
               && length (cdCategories cfg) == 2
    P.Left _   -> False

-- Property: Zero fee is rejected
prop_configDatumRejectsZeroFee :: Bool
prop_configDatumRejectsZeroFee =
  case mkConfigDatum
    (FeeAddress testAlice)
    (Lovelace 0)
    ["forestry"]
    (Multisig 1 [testAlice])
    oneWeekMs
    "proj_policy" "vault_hash_" "voting_hash"
    "cot_policy_" "cet_policy_" "user_vault__"
  of
    P.Left _  -> True
    P.Right _ -> False

-- Property: Empty categories is rejected
prop_configDatumRejectsEmptyCategories :: Bool
prop_configDatumRejectsEmptyCategories =
  case mkConfigDatum
    (FeeAddress testAlice)
    (Lovelace 100_000_000)
    []
    (Multisig 1 [testAlice])
    oneWeekMs
    "proj_policy" "vault_hash_" "voting_hash"
    "cot_policy_" "cet_policy_" "user_vault__"
  of
    P.Left _  -> True
    P.Right _ -> False

-- Property: Fee value is preserved in the resulting datum
prop_configDatumPreservesFee :: Positive Integer -> Bool
prop_configDatumPreservesFee (Positive fee) =
  case mkConfigDatum
    (FeeAddress testAlice)
    (Lovelace fee)
    ["forestry"]
    (Multisig 1 [testAlice])
    oneWeekMs
    "proj_policy" "vault_hash_" "voting_hash"
    "cot_policy_" "cet_policy_" "user_vault__"
  of
    P.Right cfg -> cdFeesAmount cfg P.== fee
    P.Left _   -> False

--------------------------------------------------------------------------------
-- PROJECT DATUM PROPERTIES
--------------------------------------------------------------------------------

projectDatumProperties :: TestTree
projectDatumProperties = testGroup "ProjectDatum Smart Constructor Properties"
  [ testProperty "Valid project accepted" prop_projectDatumAcceptsValid
  , testProperty "Empty name rejected" prop_projectDatumRejectsEmptyName
  , testProperty "Zero COT rejected" prop_projectDatumRejectsZeroCot
  , testProperty "Negative yes votes rejected" prop_projectDatumRejectsNegativeVotes
  , testProperty "Project preserves name" prop_projectDatumPreservesName
  ]

-- Property: Known-good inputs produce Right
prop_projectDatumAcceptsValid :: Bool
prop_projectDatumAcceptsValid =
  case mkProjectDatum
    "Test Carbon Project"
    "forestry"
    (DeveloperAddress testAlice)
    (CotAmount 1000)
    "A test project"
    ProjectSubmitted
    0 0 [] 1000000
  of
    P.Right _ -> True
    P.Left _  -> False

-- Property: Empty name is rejected
prop_projectDatumRejectsEmptyName :: Bool
prop_projectDatumRejectsEmptyName =
  case mkProjectDatum
    ""
    "forestry"
    (DeveloperAddress testAlice)
    (CotAmount 1000)
    "A test project"
    ProjectSubmitted
    0 0 [] 1000000
  of
    P.Left _  -> True
    P.Right _ -> False

-- Property: Zero COT amount is rejected (cotValue cotAmt <= 0)
prop_projectDatumRejectsZeroCot :: Bool
prop_projectDatumRejectsZeroCot =
  case mkProjectDatum
    "Test Carbon Project"
    "forestry"
    (DeveloperAddress testAlice)
    (CotAmount 0)
    "A test project"
    ProjectSubmitted
    0 0 [] 1000000
  of
    P.Left _  -> True
    P.Right _ -> False

-- Property: Negative vote counts are rejected
prop_projectDatumRejectsNegativeVotes :: Bool
prop_projectDatumRejectsNegativeVotes =
  case mkProjectDatum
    "Test Carbon Project"
    "forestry"
    (DeveloperAddress testAlice)
    (CotAmount 1000)
    "A test project"
    ProjectSubmitted
    (-1) 0 [] 1000000
  of
    P.Left _  -> True
    P.Right _ -> False

-- Property: pdProjectName preserves the original name
prop_projectDatumPreservesName :: Bool
prop_projectDatumPreservesName =
  case mkProjectDatum
    "Test Carbon Project"
    "forestry"
    (DeveloperAddress testAlice)
    (CotAmount 1000)
    "A test project"
    ProjectSubmitted
    0 0 [] 1000000
  of
    P.Right pd -> pdProjectName pd P.== "Test Carbon Project"
    P.Left _   -> False

--------------------------------------------------------------------------------
-- GOVERNANCE DATUM PROPERTIES
--------------------------------------------------------------------------------

governanceDatumProperties :: TestTree
governanceDatumProperties = testGroup "GovernanceDatum Smart Constructor Properties"
  [ testProperty "Valid governance datum accepted" prop_governanceDatumAcceptsValid
  , testProperty "Empty proposal ID rejected" prop_governanceDatumRejectsEmptyId
  , testProperty "Negative yes count rejected" prop_governanceDatumRejectsNegativeYes
  , testProperty "Negative no count rejected" prop_governanceDatumRejectsNegativeNo
  , testProperty "Governance preserves proposal ID" prop_governanceDatumPreservesProposalId
  ]

-- Property: Known-good inputs produce Right
prop_governanceDatumAcceptsValid :: Bool
prop_governanceDatumAcceptsValid =
  case mkGovernanceDatum
    "test_proposal_001" testAlice (ActionUpdateFeeAmount 200_000_000)
    [] 0 0 0 (oneWeekMs P.+ 1000000) ProposalInProgress
  of
    P.Right _ -> True
    P.Left _  -> False

-- Property: Empty proposal ID is rejected
prop_governanceDatumRejectsEmptyId :: Bool
prop_governanceDatumRejectsEmptyId =
  case mkGovernanceDatum
    "" testAlice (ActionUpdateFeeAmount 200_000_000)
    [] 0 0 0 (oneWeekMs P.+ 1000000) ProposalInProgress
  of
    P.Left _  -> True
    P.Right _ -> False

-- Property: Negative yes count is rejected
prop_governanceDatumRejectsNegativeYes :: Bool
prop_governanceDatumRejectsNegativeYes =
  case mkGovernanceDatum
    "test_proposal_001" testAlice (ActionUpdateFeeAmount 200_000_000)
    [] (-1) 0 0 (oneWeekMs P.+ 1000000) ProposalInProgress
  of
    P.Left _  -> True
    P.Right _ -> False

-- Property: Negative no count is rejected
prop_governanceDatumRejectsNegativeNo :: Bool
prop_governanceDatumRejectsNegativeNo =
  case mkGovernanceDatum
    "test_proposal_001" testAlice (ActionUpdateFeeAmount 200_000_000)
    [] 0 (-1) 0 (oneWeekMs P.+ 1000000) ProposalInProgress
  of
    P.Left _  -> True
    P.Right _ -> False

-- Property: gdProposalId preserves the original proposal ID
prop_governanceDatumPreservesProposalId :: Bool
prop_governanceDatumPreservesProposalId =
  case mkGovernanceDatum
    "test_proposal_001" testAlice (ActionUpdateFeeAmount 200_000_000)
    [] 0 0 0 (oneWeekMs P.+ 1000000) ProposalInProgress
  of
    P.Right gd -> gdProposalId gd P.== "test_proposal_001"
    P.Left _   -> False
