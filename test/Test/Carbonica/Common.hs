{- |
Module      : Test.Carbonica.Common
Description : Tests for Carbonica.Validators.Common helper functions
License     : Apache-2.0

Unit tests for shared validation helpers in Common.hs.
Tests exercise helper functions in isolation using concrete values,
without requiring ScriptContext construction.
-}
module Test.Carbonica.Common (commonTests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.HUnit (testCase, assertBool, (@?=))
import Test.Tasty.QuickCheck (testProperty)

import PlutusLedgerApi.V3 (PubKeyHash (..), TokenName (..))
import qualified PlutusTx.Prelude as P

import Carbonica.Validators.Common
  ( isInList
  , countMatching
  , anySignerInList
  , validateMultisig
  , sumQty
  , allNegative
  , isCategorySupported
  )

--------------------------------------------------------------------------------
-- COMMON HELPER TESTS
--------------------------------------------------------------------------------

commonTests :: TestTree
commonTests = testGroup "Common Helper Tests"
  [ listHelperTests
  , multisigTests
  , valueHelperTests
  , propertyBasedTests
  ]

--------------------------------------------------------------------------------
-- LIST HELPERS
--------------------------------------------------------------------------------

listHelperTests :: TestTree
listHelperTests = testGroup "List Helpers"
  [ -- isInList tests
    testCase "isInList finds element present in list" $
      assertBool "pkh1 should be found in [pkh1, pkh2, pkh3]"
        (isInList (PubKeyHash "pkh1") [PubKeyHash "pkh1", PubKeyHash "pkh2", PubKeyHash "pkh3"])

  , testCase "isInList returns False for absent element" $
      assertBool "pkh4 should not be in [pkh1, pkh2, pkh3]"
        (P.not (isInList (PubKeyHash "pkh4") [PubKeyHash "pkh1", PubKeyHash "pkh2", PubKeyHash "pkh3"]))

  , testCase "isInList returns False for empty list" $
      assertBool "any element should not be in empty list"
        (P.not (isInList (PubKeyHash "pkh1") []))

  , -- countMatching tests
    testCase "countMatching counts correct number of matches" $
      -- 3 from [a,b,c] appear in [a,b,c,d,e]
      countMatching
        [PubKeyHash "a", PubKeyHash "b", PubKeyHash "c"]
        [PubKeyHash "a", PubKeyHash "b", PubKeyHash "c", PubKeyHash "d", PubKeyHash "e"]
        @?= 3

  , testCase "countMatching returns 0 for no matches" $
      countMatching
        [PubKeyHash "x", PubKeyHash "y"]
        [PubKeyHash "a", PubKeyHash "b", PubKeyHash "c"]
        @?= 0

  , testCase "countMatching handles empty first list" $
      countMatching ([] :: [PubKeyHash]) [PubKeyHash "a", PubKeyHash "b"] @?= 0

  , -- anySignerInList tests
    testCase "anySignerInList returns True when at least one match" $
      assertBool "pkh2 is in authorized list"
        (anySignerInList
          [PubKeyHash "pkh2", PubKeyHash "pkh5"]
          [PubKeyHash "pkh1", PubKeyHash "pkh2", PubKeyHash "pkh3"])

  , testCase "anySignerInList returns False when no match" $
      assertBool "none of [x,y] are in [a,b,c]"
        (P.not (anySignerInList
          [PubKeyHash "x", PubKeyHash "y"]
          [PubKeyHash "a", PubKeyHash "b", PubKeyHash "c"]))
  ]

--------------------------------------------------------------------------------
-- MULTISIG VALIDATION
--------------------------------------------------------------------------------

multisigTests :: TestTree
multisigTests = testGroup "Multisig Validation"
  [ testCase "validateMultisig passes with exactly required signers" $
      -- authorized: [a,b,c,d,e], signatories: [a,b,c], required: 3
      assertBool "3 of 5 authorized signed, need 3"
        (validateMultisig
          [PubKeyHash "a", PubKeyHash "b", PubKeyHash "c"]
          [PubKeyHash "a", PubKeyHash "b", PubKeyHash "c", PubKeyHash "d", PubKeyHash "e"]
          3)

  , testCase "validateMultisig passes with more than required" $
      -- authorized: [a,b,c,d,e], signatories: [a,b,c,d], required: 3
      assertBool "4 of 5 authorized signed, need 3"
        (validateMultisig
          [PubKeyHash "a", PubKeyHash "b", PubKeyHash "c", PubKeyHash "d"]
          [PubKeyHash "a", PubKeyHash "b", PubKeyHash "c", PubKeyHash "d", PubKeyHash "e"]
          3)

  , testCase "validateMultisig fails with fewer than required" $
      -- authorized: [a,b,c,d,e], signatories: [a,b], required: 3
      assertBool "2 of 5 authorized signed, need 3"
        (P.not (validateMultisig
          [PubKeyHash "a", PubKeyHash "b"]
          [PubKeyHash "a", PubKeyHash "b", PubKeyHash "c", PubKeyHash "d", PubKeyHash "e"]
          3))

  , testCase "validateMultisig fails with 0 signers" $
      assertBool "No signers, need 3"
        (P.not (validateMultisig
          []
          [PubKeyHash "a", PubKeyHash "b", PubKeyHash "c"]
          3))

  , testCase "validateMultisig ignores unauthorized signers" $
      -- authorized: [a,b,c], signatories: [a,b,x,y], required: 2
      -- x and y are unauthorized, only a and b count -> 2 >= 2
      assertBool "2 authorized + 2 unauthorized signed, need 2"
        (validateMultisig
          [PubKeyHash "a", PubKeyHash "b", PubKeyHash "x", PubKeyHash "y"]
          [PubKeyHash "a", PubKeyHash "b", PubKeyHash "c"]
          2)
  ]

--------------------------------------------------------------------------------
-- VALUE HELPERS
--------------------------------------------------------------------------------

valueHelperTests :: TestTree
valueHelperTests = testGroup "Value Helpers"
  [ -- sumQty tests
    testCase "sumQty sums positive integers correctly" $
      sumQty [10, 20, 30] @?= 60

  , testCase "sumQty returns 0 for empty list" $
      sumQty [] @?= 0

  , testCase "sumQty handles mix of positive and negative" $
      sumQty [10, -5, 3, -2] @?= 6

  , -- allNegative tests
    testCase "allNegative returns True for all-negative list" $
      assertBool "all quantities are negative"
        (allNegative
          [ (TokenName "tk1", -5)
          , (TokenName "tk2", -1)
          , (TokenName "tk3", -10)
          ])

  , testCase "allNegative returns False if any non-negative" $
      assertBool "one quantity is positive"
        (P.not (allNegative
          [ (TokenName "tk1", -5)
          , (TokenName "tk2", 1)
          , (TokenName "tk3", -10)
          ]))

  , testCase "allNegative returns True for empty list" $
      assertBool "vacuously true for empty list"
        (allNegative [])

  , -- isCategorySupported tests
    testCase "isCategorySupported finds category in list" $
      assertBool "forestry is in supported categories"
        (isCategorySupported "forestry" ["agriculture", "forestry", "renewable"])

  , testCase "isCategorySupported returns False for absent category" $
      assertBool "mining is not in supported categories"
        (P.not (isCategorySupported "mining" ["agriculture", "forestry", "renewable"]))

  , testCase "isCategorySupported returns False for empty category list" $
      assertBool "no categories supported"
        (P.not (isCategorySupported "forestry" []))
  ]

--------------------------------------------------------------------------------
-- PROPERTY-BASED TESTS (QuickCheck)
--------------------------------------------------------------------------------

propertyBasedTests :: TestTree
propertyBasedTests = testGroup "Common Helper Properties"
  [ testProperty "sumQty of singleton is identity" $ \(n :: Integer) ->
      sumQty [n] P.== n

  , testProperty "sumQty of two elements is commutative" $ \(a :: Integer) (b :: Integer) ->
      sumQty [a, b] P.== sumQty [b, a]

  , testProperty "validateMultisig with 0 required always passes" $
      -- With requirement of 0, any set of signatories should pass
      let authorized = [PubKeyHash "a", PubKeyHash "b", PubKeyHash "c"]
      in validateMultisig [] authorized 0
           P.&& validateMultisig [PubKeyHash "a"] authorized 0
           P.&& validateMultisig [PubKeyHash "x"] authorized 0

  , testProperty "allNegative rejects list with any zero" $
      -- Zero is not negative, so allNegative should return False
      P.not (allNegative [(TokenName "t", 0)])
        P.&& P.not (allNegative [(TokenName "t", -1), (TokenName "u", 0)])
  ]
