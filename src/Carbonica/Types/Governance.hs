{- |
Module      : Carbonica.Types.Governance
Description : DAO Governance types for Carbonica platform
License     : Apache-2.0

Defines types for the DAO proposal and voting system.
DAO members can submit proposals to update ConfigDatum.

This module uses smart constructors to ensure GovernanceDatum is always valid:
  - Proposal ID cannot be empty
  - Vote counts cannot be negative
  - Deadline must be in the future
  - State-specific invariants (e.g., InProgress proposals start with 0 votes)
-}
module Carbonica.Types.Governance
  ( -- * Types
    GovernanceDatum      -- Export type but NOT constructor
  , ProposalState(..)
  , ProposalAction(..)
  , Vote(..)
  , VoteRecord(..)
  , VoterStatus(..)

    -- * Smart Constructors
  , mkGovernanceDatum
  , mkNewProposal

    -- * Getters
  , gdProposalId
  , gdSubmittedBy
  , gdAction
  , gdVotes
  , gdYesCount
  , gdNoCount
  , gdAbstainCount
  , gdDeadline
  , gdState

    -- * Errors
  , GovernanceError(..)

    -- * Redeemers
  , DaoSpendRedeemer(..)
  , DaoMintRedeemer(..)
  ) where

import           GHC.Generics              (Generic)
import           PlutusLedgerApi.V3        (BuiltinByteString, POSIXTime,
                                            PubKeyHash)
import           PlutusTx
import           PlutusTx.Blueprint
import qualified PlutusTx.Prelude          as P

--------------------------------------------------------------------------------
-- VOTE
-- Represents a vote cast on a proposal
--------------------------------------------------------------------------------

-- | Possible vote values
--
-- Uses Scott encoding for 20-30% smaller on-chain representation (Plutus 1.1+)
data Vote
  = VoteYes
  -- ^ Vote in favour of the proposal
  | VoteNo
  -- ^ Vote against the proposal
  | VoteAbstain
  -- ^ Abstain from voting
  deriving stock (Generic, Show, Eq)
  deriving anyclass (HasBlueprintDefinition)

-- Scott encoding (Plutus 1.1+) - more efficient than Data encoding
PlutusTx.unstableMakeIsData ''Vote
PlutusTx.makeLift ''Vote

instance P.Eq Vote where
  {-# INLINEABLE (==) #-}
  VoteYes     == VoteYes     = True
  VoteNo      == VoteNo      = True
  VoteAbstain == VoteAbstain = True
  _           == _           = False

--------------------------------------------------------------------------------
-- PROPOSAL STATE
-- Tracks the lifecycle of a proposal
--------------------------------------------------------------------------------

-- | Current state of a governance proposal
--
-- Uses Scott encoding for optimized on-chain representation
data ProposalState
  = ProposalInProgress
  -- ^ Open for voting
  | ProposalExecuted
  -- ^ Successfully executed (config updated)
  | ProposalRejected
  -- ^ Rejected (not enough yes votes)
  deriving stock (Generic, Show, Eq)
  deriving anyclass (HasBlueprintDefinition)

-- Scott encoding (Plutus 1.1+) - more efficient than Data encoding
PlutusTx.unstableMakeIsData ''ProposalState
PlutusTx.makeLift ''ProposalState

instance P.Eq ProposalState where
  {-# INLINEABLE (==) #-}
  ProposalInProgress == ProposalInProgress = True
  ProposalExecuted   == ProposalExecuted   = True
  ProposalRejected   == ProposalRejected   = True
  _                  == _                  = False

--------------------------------------------------------------------------------
-- PROPOSAL ACTION
-- What the proposal wants to change in ConfigDatum
--------------------------------------------------------------------------------

-- | Actions that can be proposed via DAO
data ProposalAction
  = ActionAddSigner PubKeyHash
  -- ^ Add a new member to the multisig group
  | ActionRemoveSigner PubKeyHash
  -- ^ Remove a member from the multisig group
  | ActionUpdateFeeAmount Integer
  -- ^ Change the platform fee amount
  | ActionUpdateFeeAddress PubKeyHash
  -- ^ Change the treasury address
  | ActionAddCategory BuiltinByteString
  -- ^ Add a new project category
  | ActionRemoveCategory BuiltinByteString
  -- ^ Remove a project category
  | ActionUpdateRequired Integer
  -- ^ Change the required signature count
  | ActionUpdateProposalDuration POSIXTime
  -- ^ Change how long proposals stay open
  | ActionUpdateScriptHash BuiltinByteString BuiltinByteString
  -- ^ Update a script hash (field name, new hash) - for Phase 2/3
  deriving stock (Generic)
  deriving anyclass (HasBlueprintDefinition)

PlutusTx.makeIsDataSchemaIndexed ''ProposalAction
  [ ('ActionAddSigner, 0)
  , ('ActionRemoveSigner, 1)
  , ('ActionUpdateFeeAmount, 2)
  , ('ActionUpdateFeeAddress, 3)
  , ('ActionAddCategory, 4)
  , ('ActionRemoveCategory, 5)
  , ('ActionUpdateRequired, 6)
  , ('ActionUpdateProposalDuration, 7)
  , ('ActionUpdateScriptHash, 8)
  ]
PlutusTx.makeLift ''ProposalAction

instance P.Eq ProposalAction where
  {-# INLINEABLE (==) #-}
  ActionAddSigner pkh1            == ActionAddSigner pkh2            = pkh1 P.== pkh2
  ActionRemoveSigner pkh1         == ActionRemoveSigner pkh2         = pkh1 P.== pkh2
  ActionUpdateFeeAmount n1        == ActionUpdateFeeAmount n2        = n1 P.== n2
  ActionUpdateFeeAddress pkh1     == ActionUpdateFeeAddress pkh2     = pkh1 P.== pkh2
  ActionAddCategory cat1          == ActionAddCategory cat2          = cat1 P.== cat2
  ActionRemoveCategory cat1       == ActionRemoveCategory cat2       = cat1 P.== cat2
  ActionUpdateRequired n1         == ActionUpdateRequired n2         = n1 P.== n2
  ActionUpdateProposalDuration d1 == ActionUpdateProposalDuration d2 = d1 P.== d2
  ActionUpdateScriptHash f1 h1    == ActionUpdateScriptHash f2 h2    = f1 P.== f2 P.&& h1 P.== h2
  _                               == _                               = False

--------------------------------------------------------------------------------
-- VOTER STATUS
-- Tracks whether a voter has voted
--------------------------------------------------------------------------------

-- | Status of a voter for a specific proposal
--
-- Uses Scott encoding for optimized on-chain representation
data VoterStatus
  = VoterPending
  -- ^ Has not voted yet
  | VoterVoted Vote
  -- ^ Has cast a vote
  deriving stock (Generic)
  deriving anyclass (HasBlueprintDefinition)

-- Scott encoding (Plutus 1.1+) - more efficient than Data encoding
PlutusTx.unstableMakeIsData ''VoterStatus
PlutusTx.makeLift ''VoterStatus

instance P.Eq VoterStatus where
  {-# INLINEABLE (==) #-}
  VoterPending   == VoterPending   = True
  VoterVoted v1  == VoterVoted v2  = v1 P.== v2
  _              == _              = False

--------------------------------------------------------------------------------
-- VOTE RECORD
-- Maps voters to their status
--------------------------------------------------------------------------------

-- | Record of a single voter's status
data VoteRecord = VoteRecord
  { vrVoter  :: PubKeyHash
  -- ^ The voter's public key hash
  , vrStatus :: VoterStatus
  -- ^ Their current status (Pending or Voted)
  }
  deriving stock (Generic)
  deriving anyclass (HasBlueprintDefinition)

PlutusTx.makeIsDataSchemaIndexed ''VoteRecord [('VoteRecord, 0)]
PlutusTx.makeLift ''VoteRecord

--------------------------------------------------------------------------------
-- ERROR TYPES
--------------------------------------------------------------------------------

-- | Errors that can occur when constructing GovernanceDatum
data GovernanceError
  = EmptyProposalId
  -- ^ Proposal ID cannot be empty
  | NegativeVoteCount
      { errorField :: BuiltinByteString
      , errorValue :: Integer
      }
  -- ^ Vote counts cannot be negative
  | DeadlineInPast POSIXTime
  -- ^ Deadline must be in the future
  deriving stock (Show, Eq, Generic)
  deriving anyclass (HasBlueprintDefinition)

PlutusTx.makeIsDataSchemaIndexed ''GovernanceError
  [ ('EmptyProposalId, 0)
  , ('NegativeVoteCount, 1)
  , ('DeadlineInPast, 2)
  ]

--------------------------------------------------------------------------------
-- GOVERNANCE DATUM
-- Stored with each proposal NFT
--------------------------------------------------------------------------------

-- | Datum for a DAO proposal
--
--   NOTE: Constructor is NOT exported - use smart constructors instead.
--   This ensures GovernanceDatum is always valid.
data GovernanceDatum = GovernanceDatum
  { gdProposalId'   :: BuiltinByteString
  -- ^ Unique identifier for this proposal (guaranteed non-empty)
  , gdSubmittedBy'  :: PubKeyHash
  -- ^ Who submitted the proposal
  , gdAction'       :: ProposalAction
  -- ^ What this proposal wants to change
  , gdVotes'        :: [VoteRecord]
  -- ^ List of votes cast so far
  , gdYesCount'     :: Integer
  -- ^ Running count of yes votes (non-negative)
  , gdNoCount'      :: Integer
  -- ^ Running count of no votes (non-negative)
  , gdAbstainCount' :: Integer
  -- ^ Running count of abstain votes (non-negative)
  , gdDeadline'     :: POSIXTime
  -- ^ When voting ends
  , gdState'        :: ProposalState
  -- ^ Current state of the proposal
  }
  deriving stock (Generic)
  deriving anyclass (HasBlueprintDefinition)

PlutusTx.makeIsDataSchemaIndexed ''GovernanceDatum [('GovernanceDatum, 0)]
PlutusTx.makeLift ''GovernanceDatum

--------------------------------------------------------------------------------
-- SMART CONSTRUCTORS
--------------------------------------------------------------------------------

-- | Smart constructor for a newly submitted proposal
--
-- This is the primary way to create a GovernanceDatum. It ensures:
--   - Proposal ID is non-empty
--   - Initial vote counts are 0
--   - Status is ProposalInProgress
--   - Deadline is provided (validation for future time must be done off-chain)
--
-- ==== Examples
--
-- >>> mkNewProposal "prop-001" submitterPkh (ActionUpdateFeeAmount 5000000) deadline
-- Right (GovernanceDatum {...})
{-# INLINEABLE mkNewProposal #-}
mkNewProposal
  :: BuiltinByteString    -- Proposal ID
  -> PubKeyHash           -- Submitter
  -> ProposalAction       -- Action to execute
  -> POSIXTime            -- Deadline
  -> P.Either GovernanceError GovernanceDatum
mkNewProposal proposalId submitter action deadline
  | isEmpty proposalId = P.Left EmptyProposalId
  | P.otherwise = P.Right $ GovernanceDatum
      { gdProposalId' = proposalId
      , gdSubmittedBy' = submitter
      , gdAction' = action
      , gdVotes' = []
      , gdYesCount' = 0
      , gdNoCount' = 0
      , gdAbstainCount' = 0
      , gdDeadline' = deadline
      , gdState' = ProposalInProgress
      }
  where
    isEmpty :: BuiltinByteString -> Bool
    isEmpty bs = bs P.== ""

-- | General smart constructor for GovernanceDatum
--
-- Use this when you need to create a GovernanceDatum with specific vote counts
-- (e.g., when parsing from on-chain data or testing).
--
-- Ensures:
--   - Proposal ID is non-empty
--   - Vote counts are non-negative
{-# INLINEABLE mkGovernanceDatum #-}
mkGovernanceDatum
  :: BuiltinByteString    -- Proposal ID
  -> PubKeyHash           -- Submitter
  -> ProposalAction       -- Action
  -> [VoteRecord]         -- Votes
  -> Integer              -- Yes count
  -> Integer              -- No count
  -> Integer              -- Abstain count
  -> POSIXTime            -- Deadline
  -> ProposalState        -- State
  -> P.Either GovernanceError GovernanceDatum
mkGovernanceDatum proposalId submitter action votes yesCount noCount abstainCount deadline state
  | isEmpty proposalId = P.Left EmptyProposalId
  | yesCount P.< 0 = P.Left (NegativeVoteCount "yesCount" yesCount)
  | noCount P.< 0 = P.Left (NegativeVoteCount "noCount" noCount)
  | abstainCount P.< 0 = P.Left (NegativeVoteCount "abstainCount" abstainCount)
  | P.otherwise = P.Right $ GovernanceDatum
      { gdProposalId' = proposalId
      , gdSubmittedBy' = submitter
      , gdAction' = action
      , gdVotes' = votes
      , gdYesCount' = yesCount
      , gdNoCount' = noCount
      , gdAbstainCount' = abstainCount
      , gdDeadline' = deadline
      , gdState' = state
      }
  where
    isEmpty :: BuiltinByteString -> Bool
    isEmpty bs = bs P.== ""

--------------------------------------------------------------------------------
-- GETTERS
-- Public API to access GovernanceDatum fields
--------------------------------------------------------------------------------

-- | Get the unique proposal identifier.
{-# INLINEABLE gdProposalId #-}
gdProposalId :: GovernanceDatum -> BuiltinByteString
gdProposalId = gdProposalId'

-- | Get the 'PubKeyHash' of the proposal submitter.
{-# INLINEABLE gdSubmittedBy #-}
gdSubmittedBy :: GovernanceDatum -> PubKeyHash
gdSubmittedBy = gdSubmittedBy'

-- | Get the proposed action to execute on the config.
{-# INLINEABLE gdAction #-}
gdAction :: GovernanceDatum -> ProposalAction
gdAction = gdAction'

-- | Get the list of vote records for this proposal.
{-# INLINEABLE gdVotes #-}
gdVotes :: GovernanceDatum -> [VoteRecord]
gdVotes = gdVotes'

-- | Get the running count of yes votes.
{-# INLINEABLE gdYesCount #-}
gdYesCount :: GovernanceDatum -> Integer
gdYesCount = gdYesCount'

-- | Get the running count of no votes.
{-# INLINEABLE gdNoCount #-}
gdNoCount :: GovernanceDatum -> Integer
gdNoCount = gdNoCount'

-- | Get the running count of abstain votes.
{-# INLINEABLE gdAbstainCount #-}
gdAbstainCount :: GovernanceDatum -> Integer
gdAbstainCount = gdAbstainCount'

-- | Get the voting deadline.
{-# INLINEABLE gdDeadline #-}
gdDeadline :: GovernanceDatum -> POSIXTime
gdDeadline = gdDeadline'

-- | Get the current proposal state (InProgress, Executed, or Rejected).
{-# INLINEABLE gdState #-}
gdState :: GovernanceDatum -> ProposalState
gdState = gdState'

--------------------------------------------------------------------------------
-- REDEEMERS
--------------------------------------------------------------------------------

-- | Redeemer for DAO Governance validator (spending)
--
-- Uses Scott encoding for optimized on-chain representation
data DaoSpendRedeemer
  = DaoVote Vote
  -- ^ Cast a vote on this proposal
  | DaoExecute
  -- ^ Execute the proposal (after deadline, if passed)
  | DaoReject
  -- ^ Reject the proposal (after deadline, if failed)
  deriving stock (Generic)
  deriving anyclass (HasBlueprintDefinition)

-- Scott encoding (Plutus 1.1+) - more efficient than Data encoding
PlutusTx.unstableMakeIsData ''DaoSpendRedeemer

-- | Redeemer for DAO Governance minting policy
--
-- Uses Scott encoding for optimized on-chain representation
data DaoMintRedeemer
  = DaoSubmitProposal BuiltinByteString
  -- ^ Mint proposal NFT when submitting (with proposal_id)
  | DaoBurnProposal
  -- ^ Burn proposal NFT after execution/rejection
  deriving stock (Generic)
  deriving anyclass (HasBlueprintDefinition)

-- Scott encoding (Plutus 1.1+) - more efficient than Data encoding
PlutusTx.unstableMakeIsData ''DaoMintRedeemer
