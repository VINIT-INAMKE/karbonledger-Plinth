{- |
Module      : Main
Description : Generic Blueprint Generator for Plutus V3 Validators
License     : Apache-2.0

This generates a CIP-57 compliant blueprint JSON file from your compiled validator.
The blueprint can be imported into frontend applications using MeshJS.

== Usage ==

  cabal run gen-blueprint

This will output: blueprints/contract.json

-}
module Main where

import qualified Data.ByteString.Short  as Short
import qualified Data.Set               as Set
import           System.Directory       (createDirectoryIfMissing)

import           PlutusLedgerApi.Common (serialiseCompiledCode)
import           PlutusTx.Blueprint

-- Import your validator module with qualified name to avoid collision
import qualified Validator              as V

--------------------------------------------------------------------------------
-- BLUEPRINT CONFIGURATION
-- Modify this section to match your project
--------------------------------------------------------------------------------

-- | Blueprint metadata
myContractBlueprint :: ContractBlueprint
myContractBlueprint = MkContractBlueprint
  { contractId = Just "my-contract"
  , contractPreamble = myPreamble
  , contractValidators = Set.singleton myValidator
  , contractDefinitions = deriveDefinitions @[V.MyDatum, V.MyRedeemer]
  }

-- | Project information
myPreamble :: Preamble
myPreamble = MkPreamble
  { preambleTitle = "My Smart Contract"
  , preambleDescription = Just "A Plutus V3 smart contract"
  , preambleVersion = "1.0.0"
  , preamblePlutusVersion = PlutusV3
  , preambleLicense = Just "Apache-2.0"
  }

-- | Validator configuration
myValidator :: ValidatorBlueprint referencedTypes
myValidator = MkValidatorBlueprint
  { validatorTitle = "Main Validator"
  , validatorDescription = Just "Spending validator"
  , validatorParameters = []
  , validatorRedeemer =
      MkArgumentBlueprint
        { argumentTitle = Just "Redeemer"
        , argumentDescription = Just "The action to perform"
        , argumentPurpose = Set.singleton Spend
        , argumentSchema = definitionRef @V.MyRedeemer
        }
  , validatorDatum =
      Just $ MkArgumentBlueprint
        { argumentTitle = Just "Datum"
        , argumentDescription = Just "The UTxO state"
        , argumentPurpose = Set.singleton Spend
        , argumentSchema = definitionRef @V.MyDatum
        }
  , validatorCompiled = do
      let code = Short.fromShort (serialiseCompiledCode V.compiledValidator)
      Just (compiledValidator PlutusV3 code)
  }

--------------------------------------------------------------------------------
-- MAIN
--------------------------------------------------------------------------------

main :: IO ()
main = do
  createDirectoryIfMissing True "blueprints"
  let outputPath = "blueprints/contract.json"
  writeBlueprint outputPath myContractBlueprint
  putStrLn $ "✓ Generated: " ++ outputPath
