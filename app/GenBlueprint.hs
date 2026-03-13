{- |
Module      : Main
Description : Script envelope generator for all Carbonica validators
License     : Apache-2.0

Generates .plutus text envelope files for deployment with cardano-cli.

== Usage ==

  cabal run gen-scripts

Outputs unparameterized scripts to scripts/. These must have parameters
applied before on-chain deployment (see applyParam helper below).

== Deployment Order ==

  1. Mint IdentificationNft (needs a seed TxOutRef)
  2. Deploy ConfigHolder (needs idNftPolicy)
  3. Deploy DaoGovernance mint + spend (needs idNftPolicy)
  4. Deploy ProjectPolicy, ProjectVault, CotPolicy (need idNftPolicy + other hashes)
  5. Deploy CetPolicy, UserVault (need policy IDs)
  6. Deploy Marketplace (needs idNftPolicy + royaltyAddr)

After step 1, update ConfigDatum with all script hashes via DAO governance.
-}
module Main where

import qualified Data.ByteString       as BS
import qualified Data.ByteString.Short as Short
import           Data.Word             (Word8)
import           System.Directory      (createDirectoryIfMissing)

import           PlutusLedgerApi.Common (serialiseCompiledCode)
import           PlutusTx              (CompiledCode)

-- All Carbonica validators
import qualified Carbonica.Validators.IdentificationNft as IdNft
import qualified Carbonica.Validators.ConfigHolder      as ConfigHolder
import qualified Carbonica.Validators.DaoGovernance     as DaoGovernance
import qualified Carbonica.Validators.ProjectPolicy     as ProjectPolicy
import qualified Carbonica.Validators.ProjectVault      as ProjectVault
import qualified Carbonica.Validators.CotPolicy         as CotPolicy
import qualified Carbonica.Validators.CetPolicy         as CetPolicy
import qualified Carbonica.Validators.UserVault         as UserVault
import qualified Carbonica.Validators.Marketplace       as Marketplace

--------------------------------------------------------------------------------
-- TEXT ENVELOPE GENERATION
--------------------------------------------------------------------------------

-- | Write compiled Plutus code to a .plutus text envelope file.
--
-- The text envelope format is compatible with cardano-cli:
--   { "type": "PlutusScriptV3", "description": "...", "cborHex": "..." }
--
-- cborHex contains the CBOR-wrapped Flat-encoded UPLC program.
writeTextEnvelope :: FilePath -> String -> CompiledCode a -> IO ()
writeTextEnvelope path description code = do
  let flatBytes = BS.pack $ Short.unpack $ serialiseCompiledCode code
      cborBytes = cborWrapBytes flatBytes
      hex       = bytesToHex cborBytes
      json      = concat
        [ "{\n"
        , "    \"type\": \"PlutusScriptV3\",\n"
        , "    \"description\": \"", description, "\",\n"
        , "    \"cborHex\": \"", hex, "\"\n"
        , "}\n"
        ]
  writeFile path json
  putStrLn $ "  " ++ path ++ " (" ++ show (BS.length flatBytes) ++ " bytes flat)"

-- | CBOR-encode a bytestring (major type 2).
cborWrapBytes :: BS.ByteString -> BS.ByteString
cborWrapBytes bs
  | len < 24    = BS.cons (0x40 + fromIntegral len) bs
  | len < 256   = BS.pack [0x58, fromIntegral len] <> bs
  | len < 65536 = BS.pack [0x59, hi, lo] <> bs
  | otherwise   = BS.pack [0x5a, b3, b2, b1, b0] <> bs
  where
    len = BS.length bs
    hi  = fromIntegral (len `div` 256)
    lo  = fromIntegral (len `mod` 256)
    b3  = fromIntegral ((len `div` 16777216) `mod` 256)
    b2  = fromIntegral ((len `div` 65536) `mod` 256)
    b1  = fromIntegral ((len `div` 256) `mod` 256)
    b0  = fromIntegral (len `mod` 256)

-- | Hex-encode a ByteString.
bytesToHex :: BS.ByteString -> String
bytesToHex = concatMap toHexPair . BS.unpack
  where
    toHexPair :: Word8 -> String
    toHexPair w = [hexDigit (w `div` 16), hexDigit (w `mod` 16)]
    hexDigit :: Word8 -> Char
    hexDigit n
      | n < 10    = toEnum (fromIntegral n + fromEnum '0')
      | otherwise = toEnum (fromIntegral n - 10 + fromEnum 'a')

--------------------------------------------------------------------------------
-- MAIN
--------------------------------------------------------------------------------

main :: IO ()
main = do
  let dir = "scripts"
  createDirectoryIfMissing True dir
  putStrLn "Generating Carbonica script envelopes..."
  putStrLn ""

  -- Phase 1: Core infrastructure
  putStrLn "Phase 1 — Core Infrastructure:"
  writeTextEnvelope (dir ++ "/identification-nft.plutus")
    "Carbonica Identification NFT minting policy (param: TxOutRef)"
    IdNft.compiledValidator

  writeTextEnvelope (dir ++ "/config-holder.plutus")
    "Carbonica ConfigHolder spending validator (param: idNftPolicy, validatorHash)"
    ConfigHolder.compiledValidator

  writeTextEnvelope (dir ++ "/dao-governance-mint.plutus")
    "Carbonica DAO Governance minting policy (param: idNftPolicy)"
    DaoGovernance.compiledMintValidator

  writeTextEnvelope (dir ++ "/dao-governance-spend.plutus")
    "Carbonica DAO Governance spending validator (param: idNftPolicy)"
    DaoGovernance.compiledSpendValidator

  -- Phase 2: Project lifecycle
  putStrLn ""
  putStrLn "Phase 2 — Project Lifecycle:"
  writeTextEnvelope (dir ++ "/project-policy.plutus")
    "Carbonica Project NFT minting policy (params: idNftPolicy, projectVaultHash)"
    ProjectPolicy.compiledValidator

  writeTextEnvelope (dir ++ "/project-vault.plutus")
    "Carbonica ProjectVault spending validator (params: idNftPolicy, projectPolicy)"
    ProjectVault.compiledValidator

  writeTextEnvelope (dir ++ "/cot-policy.plutus")
    "Carbonica COT minting policy (params: idNftPolicy, projectPolicy)"
    CotPolicy.compiledValidator

  -- Phase 3: Emission tracking
  putStrLn ""
  putStrLn "Phase 3 — Emission Tracking:"
  writeTextEnvelope (dir ++ "/cet-policy.plutus")
    "Carbonica CET minting policy (params: userVaultHash, cotPolicy)"
    CetPolicy.compiledValidator

  writeTextEnvelope (dir ++ "/user-vault.plutus")
    "Carbonica UserVault spending validator (params: cetPolicy, cotPolicy)"
    UserVault.compiledValidator

  -- Phase 4: Marketplace
  putStrLn ""
  putStrLn "Phase 4 — Marketplace:"
  writeTextEnvelope (dir ++ "/marketplace.plutus")
    "Carbonica Marketplace spending validator (params: idNftPolicy, royaltyAddr)"
    Marketplace.compiledValidator

  putStrLn ""
  putStrLn "Done. 10 script envelopes written to scripts/"
  putStrLn ""
  putStrLn "NOTE: These are unparameterized scripts. Before on-chain deployment,"
  putStrLn "apply parameters using PlutusTx.applyCode + liftCode, then re-serialize."
  putStrLn "See app/ApplyParams.hs (TODO) for the parameterization step."
