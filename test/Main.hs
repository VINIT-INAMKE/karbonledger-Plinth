{- |
Module      : Main
Description : Test suite for Carbonica smart contracts
-}
module Main where

import Test.Tasty (defaultMain, testGroup)
import Test.Carbonica.Types (typeTests)
import Test.Carbonica.Validators (validatorTests)
import Test.Carbonica.Common (commonTests)
import Test.Carbonica.Properties.SmartConstructors (propertyTests)
import Test.Carbonica.AttackScenarios (attackScenarioTests)
import Test.Carbonica.Properties.DatumIntegrity (datumIntegrityTests)

main :: IO ()
main = defaultMain $ testGroup "Carbonica Tests"
  [ typeTests
  , validatorTests
  , commonTests
  , propertyTests
  , attackScenarioTests
  , datumIntegrityTests
  ]
