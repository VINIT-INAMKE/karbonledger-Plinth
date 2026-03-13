{- |
Module      : Test.Carbonica.TestHelpers
Description : ScriptContext builder functions and attack test wrappers
License     : Apache-2.0

Provides reusable builder functions for constructing PlutusLedgerApi V3
ScriptContext values from primitives, plus attack-test wrapper helpers
that call untyped entry points with BuiltinData arguments and catch exceptions.

All fields that validators do not check get sensible defaults.
-}
module Test.Carbonica.TestHelpers
  ( -- * Datum Builders
    mkTestConfigDatum
  , mkTestMultisig
  , mkTestProjectDatum
  , mkTestGovernanceDatum

    -- * TxOut Builders
  , mkScriptTxOut
  , mkPkhTxOut

    -- * TxInInfo Builders
  , mkRefInputWithConfig
  , mkTxInInfo

    -- * ScriptContext Builders
  , mkTxInfo
  , mkTxInfoWithRange
  , mkMintingCtx
  , mkSpendingCtx
  , mkMarketplaceCtx

    -- * Attack Test Wrappers
  , testAttackRejected2
  , testAttackRejected3
  , testAttackAccepted2
  , testAttackAccepted3

    -- * Value Helpers
  , lovelaceSingleton

    -- * Arbitrary Instances
  , ArbPubKeyHash(..)
  , ArbPOSIXTime(..)

    -- * Test Constants
  , alice, bob, charlie, dave, eve
  , testIdNftPolicy, testProjectPolicy, testProposalPolicy
  , testVaultHash, testAltHash
  , testIdTokenName
  , testRoyaltyAddr
  , oneWeekMs
  ) where

import Test.Tasty (TestTree)
import Test.Tasty.HUnit (testCase, assertFailure)
import Test.QuickCheck (Arbitrary(..), Gen, Positive(..), elements, vectorOf)

import Control.Exception (evaluate, try, SomeException)
import Data.String (fromString)

import PlutusLedgerApi.V3
    ( Address (..)
    , BuiltinByteString
    , BuiltinData
    , Credential (..)
    , CurrencySymbol (..)
    , Datum (..)
    , OutputDatum (..)
    , POSIXTime
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
import PlutusLedgerApi.V1.Interval (Interval, always)
import PlutusLedgerApi.V1.Value (Value, singleton)
import qualified PlutusLedgerApi.V1.Value as LV
import PlutusLedgerApi.V3.MintValue (MintValue)
import qualified PlutusTx
import qualified PlutusTx.Prelude as P
import qualified PlutusTx.AssocMap as AssocMap

import Carbonica.Types.Core
    ( FeeAddress (..)
    , Lovelace (..)
    , DeveloperAddress (..)
    , CotAmount (..)
    )
import Carbonica.Types.Config
    ( ConfigDatum
    , Multisig (..)
    , mkConfigDatum
    , identificationTokenName
    , oneWeekMs
    )
import Carbonica.Types.Project
    ( ProjectDatum
    , ProjectStatus (..)
    , mkProjectDatum
    )
import Carbonica.Types.Governance
    ( GovernanceDatum
    , ProposalAction (..)
    , ProposalState (..)
    , VoteRecord (..)
    , mkGovernanceDatum
    )
import Carbonica.Validators.Marketplace
    ( MarketplaceDatum (..)
    , MarketplaceRedeemer (..)
    , Wallet (..)
    )

--------------------------------------------------------------------------------
-- ARBITRARY INSTANCES (for QuickCheck property tests)
--------------------------------------------------------------------------------

-- | Newtype wrapper to avoid orphan Arbitrary PubKeyHash instance
newtype ArbPubKeyHash = ArbPubKeyHash { unArbPkh :: PubKeyHash }
  deriving (Show)

instance Arbitrary ArbPubKeyHash where
  arbitrary = ArbPubKeyHash . PubKeyHash . fromString <$> vectorOf 28 (elements ['a'..'f'])

-- | Newtype wrapper for POSIXTime generation
newtype ArbPOSIXTime = ArbPOSIXTime { unArbTime :: POSIXTime }
  deriving (Show)

instance Arbitrary ArbPOSIXTime where
  arbitrary = ArbPOSIXTime . fromIntegral . getPositive <$> (arbitrary :: Gen (Positive Integer))

--------------------------------------------------------------------------------
-- TEST CONSTANTS
--------------------------------------------------------------------------------

alice, bob, charlie, dave, eve :: PubKeyHash
alice   = PubKeyHash "alice___pkh_bytes_0000000000"
bob     = PubKeyHash "bob_____pkh_bytes_0000000000"
charlie = PubKeyHash "charlie_pkh_bytes_0000000000"
dave    = PubKeyHash "dave____pkh_bytes_0000000000"
eve     = PubKeyHash "eve_____pkh_bytes_0000000000"

testIdNftPolicy, testProjectPolicy, testProposalPolicy :: CurrencySymbol
testIdNftPolicy    = CurrencySymbol "test_id_nft_policy_00000000000"
testProjectPolicy  = CurrencySymbol "test_project_policy_000000000"
testProposalPolicy = CurrencySymbol "test_proposal_policy_00000000"

testVaultHash, testAltHash :: BuiltinByteString
testVaultHash = "test_vault_hash_0000000000000000"
testAltHash   = "test_alt_hash_00000000000000000"

testIdTokenName :: TokenName
testIdTokenName = TokenName identificationTokenName

testRoyaltyAddr :: PubKeyHash
testRoyaltyAddr = PubKeyHash "royalty_pkh_bytes_0000000000"

--------------------------------------------------------------------------------
-- VALUE HELPERS
--------------------------------------------------------------------------------

-- | Build a Value containing only ADA (lovelace).
lovelaceSingleton :: Integer -> Value
lovelaceSingleton n = singleton (CurrencySymbol "") (TokenName "") n

--------------------------------------------------------------------------------
-- DATUM BUILDERS
--------------------------------------------------------------------------------

-- | Build a test ConfigDatum using the smart constructor.
-- Passes valid defaults for all fields; caller specifies vault hash,
-- multisig signers, and required threshold.
mkTestConfigDatum :: BuiltinByteString -> [PubKeyHash] -> Integer -> ConfigDatum
mkTestConfigDatum vaultHash signers required =
  case mkConfigDatum
    (FeeAddress alice)                    -- fee address
    (Lovelace 100_000_000)                -- fee amount (100 ADA)
    ["forestry", "renewable"]             -- categories
    (Multisig required signers)           -- multisig
    oneWeekMs                             -- proposal duration
    "test_project_policy_000000000"       -- projectPolicyId
    vaultHash                             -- projectVaultHash
    "test_voting_hash_000000000000000"    -- votingHash
    "test_cot_policy_0000000000000000"    -- cotPolicyId
    "test_cet_policy_0000000000000000"    -- cetPolicyId
    "test_user_vault_000000000000000"     -- userVaultHash
  of
    P.Right cfg -> cfg
    P.Left _    -> error "mkTestConfigDatum: invalid test data"

-- | Build a test Multisig
mkTestMultisig :: [PubKeyHash] -> Integer -> Multisig
mkTestMultisig signers required = Multisig required signers

-- | Build a test ProjectDatum using the smart constructor.
mkTestProjectDatum :: ProjectStatus -> PubKeyHash -> Integer -> Integer -> Integer -> [PubKeyHash] -> ProjectDatum
mkTestProjectDatum status developer cotAmt yesVotes noVotes voters =
  case mkProjectDatum
    "Test Carbon Project"                 -- project name
    "forestry"                            -- category
    (DeveloperAddress developer)          -- developer
    (CotAmount cotAmt)                    -- COT amount
    "A test carbon offset project"        -- description
    status                                -- status
    yesVotes                              -- yes votes
    noVotes                               -- no votes
    voters                                -- voters
    1000000                               -- submitted at (POSIXTime)
  of
    P.Right pd -> pd
    P.Left _   -> error "mkTestProjectDatum: invalid test data"

-- | Build a test GovernanceDatum using the smart constructor.
mkTestGovernanceDatum
  :: BuiltinByteString -> PubKeyHash -> ProposalAction
  -> [VoteRecord] -> Integer -> Integer -> Integer
  -> POSIXTime -> ProposalState -> GovernanceDatum
mkTestGovernanceDatum proposalId submitter action votes yesCount noCount abstainCount deadline state =
  case mkGovernanceDatum proposalId submitter action votes yesCount noCount abstainCount deadline state of
    P.Right gd -> gd
    P.Left _   -> error "mkTestGovernanceDatum: invalid test data"

--------------------------------------------------------------------------------
-- TXOUT BUILDERS
--------------------------------------------------------------------------------

-- | Build a TxOut addressed to a script with an inline datum.
mkScriptTxOut :: BuiltinByteString -> Value -> Datum -> TxOut
mkScriptTxOut scriptHash val datum = TxOut
  (Address (ScriptCredential (ScriptHash scriptHash)) Nothing)
  val
  (OutputDatum datum)
  Nothing

-- | Build a TxOut addressed to a public key with no datum.
mkPkhTxOut :: PubKeyHash -> Value -> TxOut
mkPkhTxOut pkh val = TxOut
  (Address (PubKeyCredential pkh) Nothing)
  val
  NoOutputDatum
  Nothing

--------------------------------------------------------------------------------
-- TXININFO BUILDERS
--------------------------------------------------------------------------------

-- | Wrap a TxOutRef and TxOut into a TxInInfo.
mkTxInInfo :: TxOutRef -> TxOut -> TxInInfo
mkTxInInfo ref out = TxInInfo ref out

-- | Build a reference input containing a ConfigDatum with the ID NFT.
mkRefInputWithConfig :: CurrencySymbol -> ConfigDatum -> TxInInfo
mkRefInputWithConfig idPolicy cfg =
  TxInInfo
    (TxOutRef (TxId "config_tx_id_0000000000000000") 0)
    (TxOut
      (Address (ScriptCredential (ScriptHash "config_holder_hash_00000000000")) Nothing)
      (singleton idPolicy (TokenName identificationTokenName) 1)
      (OutputDatum (Datum (PlutusTx.toBuiltinData cfg)))
      Nothing)

--------------------------------------------------------------------------------
-- SCRIPTCONTEXT BUILDERS
--------------------------------------------------------------------------------

-- | Coerce a Value to MintValue via BuiltinData round-trip.
-- Both types have the same on-chain Data representation (Map CurrencySymbol (Map TokenName Integer)).
-- This is safe for tests where we need to construct TxInfo with a mint field.
-- NOTE: If plutus-ledger-api 1.56.0.0 exports a direct MintValue constructor or
-- unsafeMintValue, prefer that instead.
valueToMintValue :: Value -> MintValue
valueToMintValue v = PlutusTx.unsafeFromBuiltinData (PlutusTx.toBuiltinData v)

-- | Build a TxInfo with sensible defaults for fields validators typically
-- do not check. Caller provides signatories, inputs, outputs,
-- reference inputs, and the mint value (as a plain Value, converted to MintValue internally).
mkTxInfo :: [PubKeyHash] -> [TxInInfo] -> [TxOut] -> [TxInInfo] -> Value -> TxInfo
mkTxInfo = mkTxInfoWithRange always

-- | Like mkTxInfo but with a custom valid range (for validators that check time).
mkTxInfoWithRange :: Interval POSIXTime -> [PubKeyHash] -> [TxInInfo] -> [TxOut] -> [TxInInfo] -> Value -> TxInfo
mkTxInfoWithRange range signers ins outs refs mintVal = TxInfo
  { txInfoInputs             = ins
  , txInfoReferenceInputs    = refs
  , txInfoOutputs            = outs
  , txInfoFee                = LV.Lovelace 0
  , txInfoMint               = valueToMintValue mintVal
  , txInfoTxCerts            = []
  , txInfoWdrl               = AssocMap.empty
  , txInfoValidRange         = range
  , txInfoSignatories        = signers
  , txInfoRedeemers          = AssocMap.empty
  , txInfoData               = AssocMap.empty
  , txInfoId                 = TxId "test_tx_id_000000000000000000"
  , txInfoVotes              = AssocMap.empty
  , txInfoProposalProcedures = []
  , txInfoCurrentTreasuryAmount = Nothing
  , txInfoTreasuryDonation   = Nothing
  }

-- | Build a ScriptContext for a minting script.
mkMintingCtx :: TxInfo -> Redeemer -> CurrencySymbol -> ScriptContext
mkMintingCtx txInfo red policy = ScriptContext txInfo red (MintingScript policy)

-- | Build a ScriptContext for a spending script.
mkSpendingCtx :: TxInfo -> Redeemer -> TxOutRef -> Datum -> ScriptContext
mkSpendingCtx txInfo red oref datum = ScriptContext txInfo red (SpendingScript oref (Just datum))

-- | Build a Marketplace spending ScriptContext.
--
-- Creates a context with:
--   - A marketplace script input holding the given UTxO value with the datum
--   - The given outputs and signers
--   - Uses mkTxInfo (always valid range)
--   - Wraps in mkSpendingCtx with the given redeemer
mkMarketplaceCtx
  :: [PubKeyHash]          -- ^ Transaction signatories
  -> MarketplaceDatum      -- ^ Marketplace datum on the input UTxO
  -> MarketplaceRedeemer   -- ^ MktBuy or MktWithdraw
  -> Value                 -- ^ Value held in the marketplace UTxO
  -> [TxOut]               -- ^ Transaction outputs
  -> ScriptContext
mkMarketplaceCtx signers mktDatum red utxoVal outs =
  let oref = TxOutRef (TxId "mkt_utxo_id_0000000000000000000") 0
      datumData = Datum (PlutusTx.toBuiltinData mktDatum)
      mktScriptHash = "marketplace_script_hash_00000000"
      mktInput = mkTxInInfo oref
        (mkScriptTxOut mktScriptHash utxoVal datumData)
      txInfo' = mkTxInfo signers [mktInput] outs [] mempty
  in mkSpendingCtx txInfo' (Redeemer (PlutusTx.toBuiltinData red)) oref datumData

--------------------------------------------------------------------------------
-- ATTACK TEST WRAPPERS
--
-- These call the full untyped entry points with BuiltinData-serialized
-- arguments. The untyped validators use P.check internally, which throws
-- an exception when the typed validator returns False. Similarly,
-- traceError throws exceptions.
--
-- testAttackRejected* verifies that the validator REJECTS (throws).
-- testAttackAccepted* verifies that the validator ACCEPTS (returns BuiltinUnit).
--------------------------------------------------------------------------------

-- | Test that a 2-arg untyped validator (param -> ctx -> BuiltinUnit) rejects an attack.
-- Used for: ProjectPolicy.untypedValidator, DaoGovernance.untypedMintValidator,
--           DaoGovernance.untypedSpendValidator
testAttackRejected2
  :: String
  -> (BuiltinData -> BuiltinData -> P.BuiltinUnit)
  -> BuiltinData -> BuiltinData -> TestTree
testAttackRejected2 name validator param1 ctxData = testCase name $ do
  result <- try (evaluate (validator param1 ctxData)) :: IO (Either SomeException P.BuiltinUnit)
  case result of
    Left _  -> return ()  -- P.check/traceError threw exception, attack rejected (PASS)
    Right _ -> assertFailure "Validator should have rejected the attack but returned successfully"

-- | Test that a 3-arg untyped validator (param1 -> param2 -> ctx -> BuiltinUnit) rejects.
-- Used for: ProjectVault.untypedValidator, CotPolicy.untypedValidator
testAttackRejected3
  :: String
  -> (BuiltinData -> BuiltinData -> BuiltinData -> P.BuiltinUnit)
  -> BuiltinData -> BuiltinData -> BuiltinData -> TestTree
testAttackRejected3 name validator param1 param2 ctxData = testCase name $ do
  result <- try (evaluate (validator param1 param2 ctxData)) :: IO (Either SomeException P.BuiltinUnit)
  case result of
    Left _  -> return ()  -- P.check/traceError threw exception, attack rejected (PASS)
    Right _ -> assertFailure "Validator should have rejected the attack but returned successfully"

-- | Test that a 2-arg untyped validator accepts a legitimate transaction.
testAttackAccepted2
  :: String
  -> (BuiltinData -> BuiltinData -> P.BuiltinUnit)
  -> BuiltinData -> BuiltinData -> TestTree
testAttackAccepted2 name validator param1 ctxData = testCase name $ do
  result <- try (evaluate (validator param1 ctxData)) :: IO (Either SomeException P.BuiltinUnit)
  case result of
    Left ex -> assertFailure ("Validator should have accepted but threw: " ++ show ex)
    Right _ -> return ()  -- Returned BuiltinUnit successfully (PASS)

-- | Test that a 3-arg untyped validator accepts a legitimate transaction.
testAttackAccepted3
  :: String
  -> (BuiltinData -> BuiltinData -> BuiltinData -> P.BuiltinUnit)
  -> BuiltinData -> BuiltinData -> BuiltinData -> TestTree
testAttackAccepted3 name validator param1 param2 ctxData = testCase name $ do
  result <- try (evaluate (validator param1 param2 ctxData)) :: IO (Either SomeException P.BuiltinUnit)
  case result of
    Left ex -> assertFailure ("Validator should have accepted but threw: " ++ show ex)
    Right _ -> return ()  -- Returned BuiltinUnit successfully (PASS)
