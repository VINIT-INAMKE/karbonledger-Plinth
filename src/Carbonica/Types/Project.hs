{- |
Module      : Carbonica.Types.Project
Description : Project types for Carbonica carbon credit platform
License     : Apache-2.0

Defines types for carbon offset projects submitted for verification.

This module uses smart constructors to ensure ProjectDatum is always valid:
  - Project name cannot be empty
  - COT amount must be positive
  - Vote counts cannot be negative
  - Status-specific invariants (e.g., Submitted projects have 0 votes initially)
-}
module Carbonica.Types.Project
  ( -- * Types
    ProjectDatum      -- Export type but NOT constructor
  , ProjectStatus(..)

    -- * Smart Constructors
  , mkProjectDatum
  , mkSubmittedProject

    -- * Getters
  , pdProjectName
  , pdCategory
  , pdDeveloper
  , pdCotAmount
  , pdDescription
  , pdStatus
  , pdYesVotes
  , pdNoVotes
  , pdVoters
  , pdSubmittedAt

    -- * Errors
  , ProjectError(..)

    -- * Redeemers
  , ProjectMintRedeemer(..)
  , ProjectVaultRedeemer(..)
  ) where

import           GHC.Generics              (Generic)
import           PlutusLedgerApi.V3        (BuiltinByteString, POSIXTime,
                                            PubKeyHash)
import           PlutusTx
import           PlutusTx.Blueprint
import qualified PlutusTx.Prelude          as P

import           Carbonica.Types.Core      (CotAmount (..), DeveloperAddress (..),
                                            cotValue, developerToPkh)

--------------------------------------------------------------------------------
-- PROJECT STATUS
--------------------------------------------------------------------------------

-- | Status of a project in the verification pipeline
--
-- Uses Scott encoding for optimized on-chain representation
data ProjectStatus
  = ProjectSubmitted
  -- ^ Newly submitted, awaiting votes
  | ProjectApproved
  -- ^ Approved by validators, COT can be minted
  | ProjectRejected
  -- ^ Rejected by validators
  deriving stock (Generic, Show, Eq)
  deriving anyclass (HasBlueprintDefinition)

-- Scott encoding (Plutus 1.1+) - more efficient than Data encoding
PlutusTx.unstableMakeIsData ''ProjectStatus
PlutusTx.makeLift ''ProjectStatus

instance P.Eq ProjectStatus where
  {-# INLINEABLE (==) #-}
  ProjectSubmitted == ProjectSubmitted = True
  ProjectApproved  == ProjectApproved  = True
  ProjectRejected  == ProjectRejected  = True
  _                == _                = False

--------------------------------------------------------------------------------
-- ERROR TYPES
--------------------------------------------------------------------------------

-- | Errors that can occur when constructing ProjectDatum
data ProjectError
  = EmptyProjectName
  -- ^ Project name cannot be empty
  | InvalidCotAmount Integer
  -- ^ COT amount must be positive
  | NegativeVoteCount
      { errorField :: BuiltinByteString
      , errorValue :: Integer
      }
  -- ^ Vote counts cannot be negative
  | InvalidStatusTransition
      { fromStatus :: ProjectStatus
      , toStatus :: ProjectStatus
      }
  -- ^ Invalid status transition attempted
  deriving stock (Show, Eq, Generic)
  deriving anyclass (HasBlueprintDefinition)

PlutusTx.makeIsDataSchemaIndexed ''ProjectError
  [ ('EmptyProjectName, 0)
  , ('InvalidCotAmount, 1)
  , ('NegativeVoteCount, 2)
  , ('InvalidStatusTransition, 3)
  ]

--------------------------------------------------------------------------------
-- PROJECT DATUM
--------------------------------------------------------------------------------

-- | Datum attached to a Project NFT in the Project Vault
--
--   NOTE: Constructor is NOT exported - use smart constructors instead.
--   This ensures ProjectDatum is always valid.
data ProjectDatum = ProjectDatum
  { pdProjectName'     :: BuiltinByteString
  -- ^ Name of the carbon offset project (guaranteed non-empty)
  , pdCategory'        :: BuiltinByteString
  -- ^ Project category (must be in ConfigDatum.cdCategories)
  , pdDeveloper'       :: DeveloperAddress
  -- ^ Project developer who receives COT tokens (type-safe)
  , pdCotAmount'       :: CotAmount
  -- ^ Number of COT tokens to mint if approved (type-safe, positive)
  , pdDescription'     :: BuiltinByteString
  -- ^ Project description / IPFS hash
  , pdStatus'          :: ProjectStatus
  -- ^ Current status in verification pipeline
  , pdYesVotes'        :: Integer
  -- ^ Running count of approval votes (non-negative)
  , pdNoVotes'         :: Integer
  -- ^ Running count of rejection votes (non-negative)
  , pdVoters'          :: [PubKeyHash]
  -- ^ List of validators who have voted
  , pdSubmittedAt'     :: POSIXTime
  -- ^ When the project was submitted
  }
  deriving stock (Generic)
  deriving anyclass (HasBlueprintDefinition)

PlutusTx.makeIsDataSchemaIndexed ''ProjectDatum [('ProjectDatum, 0)]
PlutusTx.makeLift ''ProjectDatum

instance P.Eq ProjectDatum where
  {-# INLINEABLE (==) #-}
  d1 == d2 =
    pdProjectName' d1 P.== pdProjectName' d2
    P.&& pdCategory' d1 P.== pdCategory' d2
    P.&& pdDeveloper' d1 P.== pdDeveloper' d2
    P.&& pdCotAmount' d1 P.== pdCotAmount' d2
    P.&& pdDescription' d1 P.== pdDescription' d2
    P.&& pdStatus' d1 P.== pdStatus' d2
    P.&& pdYesVotes' d1 P.== pdYesVotes' d2
    P.&& pdNoVotes' d1 P.== pdNoVotes' d2
    P.&& pdVoters' d1 P.== pdVoters' d2
    P.&& pdSubmittedAt' d1 P.== pdSubmittedAt' d2

--------------------------------------------------------------------------------
-- SMART CONSTRUCTORS
--------------------------------------------------------------------------------

-- | Smart constructor for a newly submitted project
--
-- This is the primary way to create a ProjectDatum. It ensures:
--   - Project name is non-empty
--   - COT amount is positive
--   - Initial vote counts are 0
--   - Status is ProjectSubmitted
--
-- ==== Examples
--
-- >>> let devAddr = DeveloperAddress developerPkh
-- >>> let cotAmt = CotAmount 1000
-- >>> mkSubmittedProject "Reforestation Project" "forestry" devAddr cotAmt "ipfs://..." currentTime
-- Right (ProjectDatum {...})
{-# INLINEABLE mkSubmittedProject #-}
mkSubmittedProject
  :: BuiltinByteString    -- Project name
  -> BuiltinByteString    -- Category
  -> DeveloperAddress     -- Developer
  -> CotAmount            -- COT amount to mint if approved
  -> BuiltinByteString    -- Description
  -> POSIXTime            -- Submission time
  -> P.Either ProjectError ProjectDatum
mkSubmittedProject name category developer cotAmt description submittedAt
  | isEmpty name = P.Left EmptyProjectName
  | cotValue cotAmt P.<= 0 = P.Left (InvalidCotAmount (cotValue cotAmt))
  | P.otherwise = P.Right $ ProjectDatum
      { pdProjectName' = name
      , pdCategory' = category
      , pdDeveloper' = developer
      , pdCotAmount' = cotAmt
      , pdDescription' = description
      , pdStatus' = ProjectSubmitted
      , pdYesVotes' = 0
      , pdNoVotes' = 0
      , pdVoters' = []
      , pdSubmittedAt' = submittedAt
      }
  where
    isEmpty :: BuiltinByteString -> Bool
    isEmpty bs = bs P.== ""

-- | General smart constructor for ProjectDatum
--
-- Use this when you need to create a ProjectDatum with specific vote counts
-- (e.g., when parsing from on-chain data or testing).
--
-- Ensures:
--   - Project name is non-empty
--   - COT amount is positive
--   - Vote counts are non-negative
{-# INLINEABLE mkProjectDatum #-}
mkProjectDatum
  :: BuiltinByteString    -- Project name
  -> BuiltinByteString    -- Category
  -> DeveloperAddress     -- Developer
  -> CotAmount            -- COT amount
  -> BuiltinByteString    -- Description
  -> ProjectStatus        -- Status
  -> Integer              -- Yes votes
  -> Integer              -- No votes
  -> [PubKeyHash]         -- Voters
  -> POSIXTime            -- Submission time
  -> P.Either ProjectError ProjectDatum
mkProjectDatum name category developer cotAmt description status yesVotes noVotes voters submittedAt
  | isEmpty name = P.Left EmptyProjectName
  | cotValue cotAmt P.<= 0 = P.Left (InvalidCotAmount (cotValue cotAmt))
  | yesVotes P.< 0 = P.Left (NegativeVoteCount "yesVotes" yesVotes)
  | noVotes P.< 0 = P.Left (NegativeVoteCount "noVotes" noVotes)
  | P.otherwise = P.Right $ ProjectDatum
      { pdProjectName' = name
      , pdCategory' = category
      , pdDeveloper' = developer
      , pdCotAmount' = cotAmt
      , pdDescription' = description
      , pdStatus' = status
      , pdYesVotes' = yesVotes
      , pdNoVotes' = noVotes
      , pdVoters' = voters
      , pdSubmittedAt' = submittedAt
      }
  where
    isEmpty :: BuiltinByteString -> Bool
    isEmpty bs = bs P.== ""

--------------------------------------------------------------------------------
-- GETTERS
-- Public API to access ProjectDatum fields
--------------------------------------------------------------------------------

-- | Get the project name.
{-# INLINEABLE pdProjectName #-}
pdProjectName :: ProjectDatum -> BuiltinByteString
pdProjectName = pdProjectName'

-- | Get the project category (must be in ConfigDatum.cdCategories).
{-# INLINEABLE pdCategory #-}
pdCategory :: ProjectDatum -> BuiltinByteString
pdCategory = pdCategory'

-- | Get the developer's 'PubKeyHash' (unwrapped from 'DeveloperAddress').
{-# INLINEABLE pdDeveloper #-}
pdDeveloper :: ProjectDatum -> PubKeyHash
pdDeveloper = developerToPkh . pdDeveloper'

-- | Get the COT amount as a raw 'Integer' (unwrapped from 'CotAmount').
{-# INLINEABLE pdCotAmount #-}
pdCotAmount :: ProjectDatum -> Integer
pdCotAmount = cotValue . pdCotAmount'

-- | Get the project description or IPFS hash.
{-# INLINEABLE pdDescription #-}
pdDescription :: ProjectDatum -> BuiltinByteString
pdDescription = pdDescription'

-- | Get the current project status in the verification pipeline.
{-# INLINEABLE pdStatus #-}
pdStatus :: ProjectDatum -> ProjectStatus
pdStatus = pdStatus'

-- | Get the running count of approval votes.
{-# INLINEABLE pdYesVotes #-}
pdYesVotes :: ProjectDatum -> Integer
pdYesVotes = pdYesVotes'

-- | Get the running count of rejection votes.
{-# INLINEABLE pdNoVotes #-}
pdNoVotes :: ProjectDatum -> Integer
pdNoVotes = pdNoVotes'

-- | Get the list of validators who have voted.
{-# INLINEABLE pdVoters #-}
pdVoters :: ProjectDatum -> [PubKeyHash]
pdVoters = pdVoters'

-- | Get the submission timestamp.
{-# INLINEABLE pdSubmittedAt #-}
pdSubmittedAt :: ProjectDatum -> POSIXTime
pdSubmittedAt = pdSubmittedAt'

--------------------------------------------------------------------------------
-- REDEEMERS
--------------------------------------------------------------------------------

-- | Redeemer for Project Policy minting
--
-- Uses Scott encoding for optimized on-chain representation
data ProjectMintRedeemer
  = MintProject
  -- ^ Mint a new project NFT
  | BurnProject
  -- ^ Burn project NFT after voting completes
  deriving stock (Generic)
  deriving anyclass (HasBlueprintDefinition)

-- Scott encoding (Plutus 1.1+) - more efficient than Data encoding
PlutusTx.unstableMakeIsData ''ProjectMintRedeemer

-- | Redeemer for Project Vault spending
--
-- Uses Scott encoding for optimized on-chain representation
data ProjectVaultRedeemer
  = VaultVote
  -- ^ Cast a vote on the project
  | VaultApprove
  -- ^ Finalize as approved (mint COT)
  | VaultReject
  -- ^ Finalize as rejected
  deriving stock (Generic)
  deriving anyclass (HasBlueprintDefinition)

-- Scott encoding (Plutus 1.1+) - more efficient than Data encoding
PlutusTx.unstableMakeIsData ''ProjectVaultRedeemer
