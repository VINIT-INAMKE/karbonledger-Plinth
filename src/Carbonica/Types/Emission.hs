{- |
Module      : Carbonica.Types.Emission
Description : Carbon Emission Token (CET) types
License     : Apache-2.0

CET tokens represent carbon emissions that users report.
They are non-transferable and locked in User Vaults.
CETs can be offset by burning COT tokens.

This module uses smart constructors to ensure EmissionDatum and CetDatum
are always valid:
  - Emission amount must be positive
  - Offset must be non-negative and not exceed amount
  - CET quantity must be positive
-}
module Carbonica.Types.Emission
  ( -- * Types
    EmissionDatum      -- Export type but NOT constructor
  , CetDatum           -- Export type but NOT constructor

    -- * Smart Constructors
  , mkEmissionDatum
  , mkCetDatum

    -- * Getters
  , edOwner
  , edCategory
  , edAmount
  , edDescription
  , edReportedAt
  , edOffset
  , cetLocation
  , cetQty
  , cetTime

    -- * Errors
  , EmissionError(..)

    -- * Redeemers (constructors exported for pattern matching)
  , EmissionBurnRedeemer(..)
  , CetMintRedeemer(..)
  , UserVaultRedeemer(..)
  ) where

import           GHC.Generics              (Generic)
import           PlutusLedgerApi.V3        (BuiltinByteString, POSIXTime,
                                            PubKeyHash)
import           PlutusTx
import           PlutusTx.Blueprint
import qualified PlutusTx.Prelude          as P

--------------------------------------------------------------------------------
-- ERROR TYPES
--------------------------------------------------------------------------------

-- | Errors that can occur when constructing emission types
data EmissionError
  = InvalidEmissionAmount Integer
  -- ^ Emission amount must be positive
  | InvalidOffset Integer Integer
  -- ^ Offset (first) must be >= 0 and <= amount (second)
  | InvalidCetQuantity Integer
  -- ^ CET quantity must be positive
  deriving stock (Show, Eq, Generic)
  deriving anyclass (HasBlueprintDefinition)

PlutusTx.makeIsDataSchemaIndexed ''EmissionError
  [ ('InvalidEmissionAmount, 0)
  , ('InvalidOffset, 1)
  , ('InvalidCetQuantity, 2)
  ]

--------------------------------------------------------------------------------
-- EMISSION RECORD
--------------------------------------------------------------------------------

-- | Datum for a CET emission record in User Vault
--
--   NOTE: Constructor is NOT exported - use 'mkEmissionDatum' instead.
data EmissionDatum = EmissionDatum
  { edOwner'       :: PubKeyHash
  -- ^ User who reported the emission
  , edCategory'    :: BuiltinByteString
  -- ^ Emission category (transport, energy, etc.)
  , edAmount'      :: Integer
  -- ^ Amount of CET tokens (emission units, guaranteed positive)
  , edDescription' :: BuiltinByteString
  -- ^ Description or IPFS hash
  , edReportedAt'  :: POSIXTime
  -- ^ When the emission was reported
  , edOffset'      :: Integer
  -- ^ Amount already offset by COT (guaranteed 0 <= offset <= amount)
  }
  deriving stock (Generic)
  deriving anyclass (HasBlueprintDefinition)

PlutusTx.makeIsDataSchemaIndexed ''EmissionDatum [('EmissionDatum, 0)]
PlutusTx.makeLift ''EmissionDatum

instance P.Eq EmissionDatum where
  {-# INLINEABLE (==) #-}
  d1 == d2 =
    edOwner' d1 P.== edOwner' d2
    P.&& edCategory' d1 P.== edCategory' d2
    P.&& edAmount' d1 P.== edAmount' d2
    P.&& edDescription' d1 P.== edDescription' d2
    P.&& edReportedAt' d1 P.== edReportedAt' d2
    P.&& edOffset' d1 P.== edOffset' d2

--------------------------------------------------------------------------------
-- SMART CONSTRUCTORS
--------------------------------------------------------------------------------

-- | Smart constructor for EmissionDatum
--
-- Ensures:
--   - Amount is positive
--   - Offset is non-negative
--   - Offset does not exceed amount
{-# INLINEABLE mkEmissionDatum #-}
mkEmissionDatum
  :: PubKeyHash
  -> BuiltinByteString
  -> Integer
  -> BuiltinByteString
  -> POSIXTime
  -> Integer
  -> P.Either EmissionError EmissionDatum
mkEmissionDatum owner category amount description reportedAt offset
  | amount P.<= 0 = P.Left (InvalidEmissionAmount amount)
  | offset P.< 0 P.|| offset P.> amount = P.Left (InvalidOffset offset amount)
  | P.otherwise = P.Right $ EmissionDatum
      { edOwner'       = owner
      , edCategory'    = category
      , edAmount'      = amount
      , edDescription' = description
      , edReportedAt'  = reportedAt
      , edOffset'      = offset
      }

--------------------------------------------------------------------------------
-- GETTERS
--------------------------------------------------------------------------------

{-# INLINEABLE edOwner #-}
edOwner :: EmissionDatum -> PubKeyHash
edOwner = edOwner'

{-# INLINEABLE edCategory #-}
edCategory :: EmissionDatum -> BuiltinByteString
edCategory = edCategory'

{-# INLINEABLE edAmount #-}
edAmount :: EmissionDatum -> Integer
edAmount = edAmount'

{-# INLINEABLE edDescription #-}
edDescription :: EmissionDatum -> BuiltinByteString
edDescription = edDescription'

{-# INLINEABLE edReportedAt #-}
edReportedAt :: EmissionDatum -> POSIXTime
edReportedAt = edReportedAt'

{-# INLINEABLE edOffset #-}
edOffset :: EmissionDatum -> Integer
edOffset = edOffset'

--------------------------------------------------------------------------------
-- CET DATUM
-- Used for minting CET tokens with emission metadata
--------------------------------------------------------------------------------

-- | Datum for CET minting
--   Also serves as redeemer when minting
--
--   NOTE: Constructor is NOT exported - use 'mkCetDatum' instead.
data CetDatum = CetDatum
  { cetLocation' :: BuiltinByteString
  -- ^ Geographical location of the emission
  , cetQty'      :: Integer
  -- ^ Quantity of CET tokens to mint (guaranteed positive)
  , cetTime'     :: Integer
  -- ^ Timestamp of the emission event
  }
  deriving stock (Generic)
  deriving anyclass (HasBlueprintDefinition)

PlutusTx.makeIsDataSchemaIndexed ''CetDatum [('CetDatum, 0)]
PlutusTx.makeLift ''CetDatum

instance P.Eq CetDatum where
  {-# INLINEABLE (==) #-}
  d1 == d2 =
    cetLocation' d1 P.== cetLocation' d2
    P.&& cetQty' d1 P.== cetQty' d2
    P.&& cetTime' d1 P.== cetTime' d2

-- | Smart constructor for CetDatum
--
-- Ensures:
--   - Quantity is positive
{-# INLINEABLE mkCetDatum #-}
mkCetDatum
  :: BuiltinByteString
  -> Integer
  -> Integer
  -> P.Either EmissionError CetDatum
mkCetDatum location qty time
  | qty P.<= 0 = P.Left (InvalidCetQuantity qty)
  | P.otherwise = P.Right $ CetDatum
      { cetLocation' = location
      , cetQty'      = qty
      , cetTime'     = time
      }

-- CetDatum getters

{-# INLINEABLE cetLocation #-}
cetLocation :: CetDatum -> BuiltinByteString
cetLocation = cetLocation'

{-# INLINEABLE cetQty #-}
cetQty :: CetDatum -> Integer
cetQty = cetQty'

{-# INLINEABLE cetTime #-}
cetTime :: CetDatum -> Integer
cetTime = cetTime'

--------------------------------------------------------------------------------
-- EMISSION BURN REDEEMER
--------------------------------------------------------------------------------

-- | Redeemer for burning CET tokens (1:1 with COT)
data EmissionBurnRedeemer = EmissionBurnRedeemer
  { ebrCotPolicyId :: BuiltinByteString
  -- ^ COT policy ID (to verify 1:1 burn ratio)
  }
  deriving stock (Generic)
  deriving anyclass (HasBlueprintDefinition)

PlutusTx.makeIsDataSchemaIndexed ''EmissionBurnRedeemer [('EmissionBurnRedeemer, 0)]
PlutusTx.makeLift ''EmissionBurnRedeemer

--------------------------------------------------------------------------------
-- CET MINT REDEEMER
-- Distinguishes between mint (with CetDatum) and burn (with policy info)
--------------------------------------------------------------------------------

-- | Redeemer for CET Policy minting
--
-- Uses Scott encoding for optimized on-chain representation
data CetMintRedeemer
  = CetMintWithDatum CetDatum
  -- ^ Mint CET with emission metadata
  | CetBurnWithCot EmissionBurnRedeemer
  -- ^ Burn CET with COT (1:1 ratio)
  deriving stock (Generic)
  deriving anyclass (HasBlueprintDefinition)

-- Scott encoding (Plutus 1.1+) - more efficient than Data encoding
PlutusTx.unstableMakeIsData ''CetMintRedeemer

-- | Redeemer for User Vault spending
--
-- Uses Scott encoding for optimized on-chain representation
data UserVaultRedeemer
  = VaultOffset Integer
  -- ^ Offset emissions with COT (amount to offset)
  | VaultWithdraw
  -- ^ Withdraw (admin only, for account closure)
  deriving stock (Generic)
  deriving anyclass (HasBlueprintDefinition)

-- Scott encoding (Plutus 1.1+) - more efficient than Data encoding
PlutusTx.unstableMakeIsData ''UserVaultRedeemer
