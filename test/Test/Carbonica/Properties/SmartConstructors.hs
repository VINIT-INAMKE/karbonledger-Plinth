{- |
Module      : Test.Carbonica.Properties.SmartConstructors
Description : Property-based tests for Carbonica smart constructors
License     : Apache-2.0

This module tests the invariants enforced by smart constructors using QuickCheck.
Properties are tested with 100 random test cases each.
-}
module Test.Carbonica.Properties.SmartConstructors (propertyTests) where

import Test.Tasty (TestTree, testGroup)
import Test.Tasty.QuickCheck

import qualified PlutusTx.Prelude as P

import Carbonica.Types.Core (Lovelace(..), mkLovelace, mkCotAmount, cotValue)

--------------------------------------------------------------------------------
-- PROPERTY TESTS
--------------------------------------------------------------------------------

propertyTests :: TestTree
propertyTests = testGroup "Property-Based Tests (QuickCheck)"
  [ lovelaceProperties
  , cotAmountProperties
  ]

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
