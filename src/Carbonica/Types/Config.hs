{- |
Module      : Carbonica.Types.Config
Description : Configuration types for Carbonica platform
License     : Apache-2.0

Defines the core configuration types used across all Carbonica validators.
All contracts read settings from ConfigDatum stored at the Config Holder address.

This module uses smart constructors to ensure ConfigDatum is always valid:
  - Fees must be positive
  - Categories list cannot be empty
  - Multisig requires at least 1 signer and positive required count
  - Required signatures cannot exceed total signers
-}
module Carbonica.Types.Config
  ( -- * Types
    ConfigDatum       -- Export type but NOT constructor
  , Multisig(..)      -- Constructor exported; safe because ConfigDatum hides its own
                      -- constructor and mkConfigDatum validates Multisig invariants.

    -- * Smart Constructors
  , mkConfigDatum
  , mkMultisig

    -- * Getters
  , cdFeesAddress
  , cdFeesAmount
  , cdCategories
  , cdMultisig
  , cdProposalDuration
  , cdProjectPolicyId
  , cdProjectVaultHash
  , cdVotingHash
  , cdCotPolicyId
  , cdCetPolicyId
  , cdUserVaultHash

    -- * Errors
  , ConfigError(..)
  , MultisigError(..)

    -- * Constants
  , identificationTokenName
  , oneWeekMs
  ) where

import           GHC.Generics              (Generic)
import           PlutusLedgerApi.V3        (BuiltinByteString, POSIXTime,
                                            PubKeyHash)
import           PlutusTx
import           PlutusTx.Blueprint
import qualified PlutusTx.Prelude          as P

import           Carbonica.Types.Core      (FeeAddress (..), Lovelace (..),
                                            feeToPkh, lovelaceValue)

--------------------------------------------------------------------------------
-- MULTISIG
-- Defines a multi-signature requirement for authorization
--------------------------------------------------------------------------------

-- | Multi-signature configuration
--   Specifies how many signatures are required from a group of signers
data Multisig = Multisig
  { msRequired :: Integer
  -- ^ Minimum number of signatures required (e.g., 3)
  , msSigners  :: [PubKeyHash]
  -- ^ List of authorized signers (e.g., 5 public key hashes)
  }
  deriving stock (Generic)
  deriving anyclass (HasBlueprintDefinition)

PlutusTx.makeLift ''Multisig
PlutusTx.makeIsDataSchemaIndexed ''Multisig [('Multisig, 0)]

instance P.Eq Multisig where
  {-# INLINEABLE (==) #-}
  (Multisig r1 s1) == (Multisig r2 s2) = r1 P.== r2 P.&& s1 P.== s2

--------------------------------------------------------------------------------
-- ERROR TYPES
--------------------------------------------------------------------------------

-- | Errors that can occur when constructing Multisig
data MultisigError
  = NoSigners
  -- ^ Multisig must have at least one signer
  | InvalidRequired
      { meRequired :: Integer
      , meSignersCount :: Integer
      }
  -- ^ Required count must be > 0 and <= total signers
  deriving stock (Show, Eq, Generic)
  deriving anyclass (HasBlueprintDefinition)

PlutusTx.makeIsDataSchemaIndexed ''MultisigError
  [('NoSigners, 0), ('InvalidRequired, 1)]

-- | Errors that can occur when constructing ConfigDatum
data ConfigError
  = InvalidFeeAmount Integer
  -- ^ Fee amount must be positive
  | NoCategoriesProvided
  -- ^ Must have at least one project category
  | InvalidMultisigConfig MultisigError
  -- ^ Invalid multisig configuration
  deriving stock (Show, Eq, Generic)
  deriving anyclass (HasBlueprintDefinition)

PlutusTx.makeIsDataSchemaIndexed ''ConfigError
  [ ('InvalidFeeAmount, 0)
  , ('NoCategoriesProvided, 1)
  , ('InvalidMultisigConfig, 2)
  ]

--------------------------------------------------------------------------------
-- CONFIG DATUM
-- The central configuration for the entire Carbonica platform
--------------------------------------------------------------------------------

-- | Platform configuration stored at Config Holder address
--   All validators read from this datum via the Identification NFT
--
--   NOTE: Constructor is NOT exported - use 'mkConfigDatum' instead.
--   This ensures ConfigDatum is always valid.
data ConfigDatum = ConfigDatum
  { cdFeesAddress'      :: FeeAddress
  -- ^ Treasury wallet where platform fees are sent (type-safe)

  , cdFeesAmount'       :: Lovelace
  -- ^ Platform fee in lovelace (type-safe, guaranteed positive)

  , cdCategories'       :: [BuiltinByteString]
  -- ^ Allowed project categories (guaranteed non-empty)

  , cdMultisig'         :: Multisig
  -- ^ Multisig group (guaranteed valid via mkMultisig)

  , cdProposalDuration' :: POSIXTime
  -- ^ How long DAO proposals stay open for voting (e.g., 1 week in ms)

  -- Phase 2/3 script references (empty initially, set via DAO)
  , cdProjectPolicyId'  :: BuiltinByteString
  -- ^ Project NFT minting policy ID

  , cdProjectVaultHash' :: BuiltinByteString
  -- ^ Project Vault script hash

  , cdVotingHash'       :: BuiltinByteString
  -- ^ Voting Validator script hash

  , cdCotPolicyId'      :: BuiltinByteString
  -- ^ Carbon Offset Token minting policy ID

  , cdCetPolicyId'      :: BuiltinByteString
  -- ^ Carbon Emission Token minting policy ID

  , cdUserVaultHash'    :: BuiltinByteString
  -- ^ User Vault script hash
  }
  deriving stock (Generic)
  deriving anyclass (HasBlueprintDefinition)

PlutusTx.makeLift ''ConfigDatum
PlutusTx.makeIsDataSchemaIndexed ''ConfigDatum [('ConfigDatum, 0)]

--------------------------------------------------------------------------------
-- SMART CONSTRUCTORS
--------------------------------------------------------------------------------

-- | Smart constructor for Multisig
--
-- Ensures:
--   - At least one signer exists
--   - Required count is positive
--   - Required count <= total signers
--
-- ==== Examples
--
-- >>> mkMultisig 3 [alice, bob, charlie, dave, eve]
-- Right (Multisig {msRequired = 3, msSigners = [alice,bob,charlie,dave,eve]})
--
-- >>> mkMultisig 6 [alice, bob, charlie]
-- Left (InvalidRequired {meRequired = 6, meSignersCount = 3})
{-# INLINEABLE mkMultisig #-}
mkMultisig :: Integer -> [PubKeyHash] -> P.Either MultisigError Multisig
mkMultisig required signers
  | isNull signers = P.Left NoSigners
  | required P.<= 0 P.|| required P.> signersCount =
      P.Left $ InvalidRequired
          { meRequired = required
          , meSignersCount = signersCount
          }
  | P.otherwise = P.Right $ Multisig required signers
  where
    signersCount :: Integer
    signersCount = lengthInteger signers

    lengthInteger :: [a] -> Integer
    lengthInteger [] = 0
    lengthInteger (_:xs) = 1 P.+ lengthInteger xs

    isNull :: [a] -> Bool
    isNull [] = True
    isNull _  = False

-- | Smart constructor for ConfigDatum
--
-- Ensures all invariants:
--   - Fee amount is positive
--   - At least one category exists
--   - Multisig is valid
--
-- ==== Examples
--
-- >>> let feeAddr = FeeAddress treasuryPkh
-- >>> let fee = Lovelace 100_000_000
-- >>> let categories = ["forestry", "renewable_energy"]
-- >>> let multisig = Multisig 3 [alice, bob, charlie, dave, eve]
-- >>> mkConfigDatum feeAddr fee categories multisig oneWeekMs "" "" "" "" "" ""
-- Right (ConfigDatum {...})
{-# INLINEABLE mkConfigDatum #-}
mkConfigDatum
  :: FeeAddress
  -> Lovelace
  -> [BuiltinByteString]
  -> Multisig
  -> POSIXTime
  -> BuiltinByteString  -- projectPolicyId
  -> BuiltinByteString  -- projectVaultHash
  -> BuiltinByteString  -- votingHash
  -> BuiltinByteString  -- cotPolicyId
  -> BuiltinByteString  -- cetPolicyId
  -> BuiltinByteString  -- userVaultHash
  -> P.Either ConfigError ConfigDatum
mkConfigDatum feeAddr (Lovelace feeAmt) categories multisig proposalDuration
              projectPolicyId projectVaultHash votingHash cotPolicyId cetPolicyId userVaultHash
  | feeAmt P.<= 0 = P.Left (InvalidFeeAmount feeAmt)
  | isNull categories = P.Left NoCategoriesProvided
  | P.not (validMultisig multisig) =
      P.Left (InvalidMultisigConfig (InvalidRequired
        { meRequired = msRequired multisig
        , meSignersCount = lengthInteger (msSigners multisig)
        }))
  | P.otherwise = P.Right $ ConfigDatum
      { cdFeesAddress' = feeAddr
      , cdFeesAmount' = Lovelace feeAmt
      , cdCategories' = categories
      , cdMultisig' = multisig
      , cdProposalDuration' = proposalDuration
      , cdProjectPolicyId' = projectPolicyId
      , cdProjectVaultHash' = projectVaultHash
      , cdVotingHash' = votingHash
      , cdCotPolicyId' = cotPolicyId
      , cdCetPolicyId' = cetPolicyId
      , cdUserVaultHash' = userVaultHash
      }
  where
    validMultisig :: Multisig -> Bool
    validMultisig (Multisig required signers) =
      let signersCount = lengthInteger signers
      in required P.> 0 P.&& required P.<= signersCount P.&& P.not (isNull signers)

    lengthInteger :: [a] -> Integer
    lengthInteger [] = 0
    lengthInteger (_:xs) = 1 P.+ lengthInteger xs

    isNull :: [a] -> Bool
    isNull [] = True
    isNull _  = False

--------------------------------------------------------------------------------
-- GETTERS
-- Public API to access ConfigDatum fields
--------------------------------------------------------------------------------

-- | Get the platform fee address as a raw 'PubKeyHash'.
{-# INLINEABLE cdFeesAddress #-}
cdFeesAddress :: ConfigDatum -> PubKeyHash
cdFeesAddress = feeToPkh . cdFeesAddress'

-- | Get the platform fee amount as a raw 'Integer' (lovelace).
{-# INLINEABLE cdFeesAmount #-}
cdFeesAmount :: ConfigDatum -> Integer
cdFeesAmount = lovelaceValue . cdFeesAmount'

-- | Get the list of supported project categories.
{-# INLINEABLE cdCategories #-}
cdCategories :: ConfigDatum -> [BuiltinByteString]
cdCategories = cdCategories'

-- | Get the multisig configuration (required count and signer list).
{-# INLINEABLE cdMultisig #-}
cdMultisig :: ConfigDatum -> Multisig
cdMultisig = cdMultisig'

-- | Get the proposal voting duration.
{-# INLINEABLE cdProposalDuration #-}
cdProposalDuration :: ConfigDatum -> POSIXTime
cdProposalDuration = cdProposalDuration'

-- | Get the Project NFT minting policy ID.
{-# INLINEABLE cdProjectPolicyId #-}
cdProjectPolicyId :: ConfigDatum -> BuiltinByteString
cdProjectPolicyId = cdProjectPolicyId'

-- | Get the Project Vault script hash.
{-# INLINEABLE cdProjectVaultHash #-}
cdProjectVaultHash :: ConfigDatum -> BuiltinByteString
cdProjectVaultHash = cdProjectVaultHash'

-- | Get the Voting Validator script hash.
{-# INLINEABLE cdVotingHash #-}
cdVotingHash :: ConfigDatum -> BuiltinByteString
cdVotingHash = cdVotingHash'

-- | Get the Carbon Offset Token (COT) minting policy ID.
{-# INLINEABLE cdCotPolicyId #-}
cdCotPolicyId :: ConfigDatum -> BuiltinByteString
cdCotPolicyId = cdCotPolicyId'

-- | Get the Carbon Emission Token (CET) minting policy ID.
{-# INLINEABLE cdCetPolicyId #-}
cdCetPolicyId :: ConfigDatum -> BuiltinByteString
cdCetPolicyId = cdCetPolicyId'

-- | Get the User Vault script hash.
{-# INLINEABLE cdUserVaultHash #-}
cdUserVaultHash :: ConfigDatum -> BuiltinByteString
cdUserVaultHash = cdUserVaultHash'

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------

-- | Token name for the Identification NFT
identificationTokenName :: BuiltinByteString
identificationTokenName = "CARBONICA_ID"
{-# INLINEABLE identificationTokenName #-}

-- | One week in milliseconds (default proposal duration)
oneWeekMs :: POSIXTime
oneWeekMs = 604_800_000
{-# INLINEABLE oneWeekMs #-}
