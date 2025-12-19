{- |
Module      : Test.Carbonica.Types
Description : Tests for Carbonica type definitions
-}
module Test.Carbonica.Types (typeTests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertEqual, assertBool)

import qualified PlutusTx.Prelude as P

import Carbonica.Types.Config
import Carbonica.Types.Governance
import Carbonica.Types.Project
import Carbonica.Types.Emission

--------------------------------------------------------------------------------
-- TYPE TESTS
--------------------------------------------------------------------------------

typeTests :: TestTree
typeTests = testGroup "Type Tests"
  [ configTests
  , governanceTests
  , projectTests
  ]

--------------------------------------------------------------------------------
-- CONFIG TESTS
--------------------------------------------------------------------------------

configTests :: TestTree
configTests = testGroup "Config Types"
  [ testCase "identificationTokenName is correct" $
      assertBool "Token name should be non-empty" 
        (P.lengthOfByteString identificationTokenName P.> 0)
  ]

--------------------------------------------------------------------------------
-- GOVERNANCE TESTS
--------------------------------------------------------------------------------

governanceTests :: TestTree
governanceTests = testGroup "Governance Types"
  [ testCase "Vote values are distinct" $ do
      assertBool "VoteYes /= VoteNo" (P.not (VoteYes P.== VoteNo))
      assertBool "VoteYes /= VoteAbstain" (P.not (VoteYes P.== VoteAbstain))
      assertBool "VoteNo /= VoteAbstain" (P.not (VoteNo P.== VoteAbstain))
      
  , testCase "ProposalState values are distinct" $ do
      assertBool "InProgress /= Executed" (P.not (ProposalInProgress P.== ProposalExecuted))
      assertBool "InProgress /= Rejected" (P.not (ProposalInProgress P.== ProposalRejected))
      assertBool "Executed /= Rejected" (P.not (ProposalExecuted P.== ProposalRejected))
      
  , testCase "ProposalState equality is reflexive" $ do
      assertBool "InProgress == InProgress" (ProposalInProgress P.== ProposalInProgress)
      assertBool "Executed == Executed" (ProposalExecuted P.== ProposalExecuted)
      assertBool "Rejected == Rejected" (ProposalRejected P.== ProposalRejected)
  ]

--------------------------------------------------------------------------------
-- PROJECT TESTS
--------------------------------------------------------------------------------

projectTests :: TestTree
projectTests = testGroup "Project Types"
  [ testCase "ProjectStatus values are distinct" $ do
      assertBool "Submitted /= Approved" (P.not (ProjectSubmitted P.== ProjectApproved))
      assertBool "Submitted /= Rejected" (P.not (ProjectSubmitted P.== ProjectRejected))
      assertBool "Approved /= Rejected" (P.not (ProjectApproved P.== ProjectRejected))
      
  , testCase "ProjectStatus equality is reflexive" $ do
      assertBool "Submitted == Submitted" (ProjectSubmitted P.== ProjectSubmitted)
      assertBool "Approved == Approved" (ProjectApproved P.== ProjectApproved)
      assertBool "Rejected == Rejected" (ProjectRejected P.== ProjectRejected)
  ]
