{- |
Module      : Carbonica.Types.Core
Description : Core domain types with compile-time safety guarantees
License     : Apache-2.0

This module provides domain-specific newtypes that prevent common errors:
  - Mixing up different quantity types (Lovelace, COT, CET)
  - Mixing up different address types (Developer, Fee, Validator)
  - Invalid values at construction time

These types leverage Haskell's type system for compile-time safety guarantees.
-}
module Carbonica.Types.Core
  ( -- * Quantity Types
    Lovelace(..)
  , CotAmount(..)
  , CetAmount(..)
  , Percentage(..)

    -- * Smart Constructors for Quantities
  , mkLovelace
  , mkCotAmount
  , mkCetAmount
  , mkPercentage

    -- * Address Types
  , DeveloperAddress(..)
  , FeeAddress(..)
  , ValidatorAddress(..)

    -- * Conversion Functions
  , toPubKeyHash
  , developerToPkh
  , feeToPkh
  , validatorToPkh
  , lovelaceValue
  , cotValue
  , cetValue

    -- * Error Types
  , QuantityError(..)
  ) where

import           GHC.Generics              (Generic)
import           PlutusLedgerApi.V3        (PubKeyHash)
import           PlutusTx
import           PlutusTx.Blueprint
import qualified PlutusTx.Prelude          as P

--------------------------------------------------------------------------------
-- QUANTITY TYPES
-- Prevent mixing different amounts (Lovelace vs COT vs CET)
--------------------------------------------------------------------------------

-- | Lovelace amount (1 ADA = 1,000,000 Lovelace)
--
-- This newtype prevents accidentally using Lovelace where COT/CET is expected.
--
-- ==== Examples
--
-- >>> let fee = Lovelace 100_000_000  -- 100 ADA
-- >>> let cot = CotAmount 1000
-- >>> fee + cot  -- COMPILE ERROR! Can't add Lovelace and CotAmount
newtype Lovelace = Lovelace Integer
  deriving stock (Generic, Show, Eq)
  deriving newtype (Ord)
  deriving anyclass (HasBlueprintDefinition)

PlutusTx.makeIsDataSchemaIndexed ''Lovelace [('Lovelace, 0)]
PlutusTx.makeLift ''Lovelace

-- | Carbon Offset Token amount
--
-- Represents the quantity of COT tokens (carbon credits).
newtype CotAmount = CotAmount Integer
  deriving stock (Generic, Show, Eq)
  deriving newtype (Ord)
  deriving anyclass (HasBlueprintDefinition)

PlutusTx.makeIsDataSchemaIndexed ''CotAmount [('CotAmount, 0)]
PlutusTx.makeLift ''CotAmount

-- | Carbon Emission Token amount
--
-- Represents the quantity of CET tokens (emissions logged).
newtype CetAmount = CetAmount Integer
  deriving stock (Generic, Show, Eq)
  deriving newtype (Ord)
  deriving anyclass (HasBlueprintDefinition)

PlutusTx.makeIsDataSchemaIndexed ''CetAmount [('CetAmount, 0)]
PlutusTx.makeLift ''CetAmount

-- | Percentage value (0-100)
--
-- Used for royalty calculations in marketplace.
newtype Percentage = Percentage Integer
  deriving stock (Generic, Show, Eq)
  deriving newtype (Ord)
  deriving anyclass (HasBlueprintDefinition)

PlutusTx.makeIsDataSchemaIndexed ''Percentage [('Percentage, 0)]
PlutusTx.makeLift ''Percentage

--------------------------------------------------------------------------------
-- ADDRESS TYPES
-- Prevent mixing different address purposes
--------------------------------------------------------------------------------

-- | Developer wallet address
--
-- Receives COT tokens when project is approved.
newtype DeveloperAddress = DeveloperAddress PubKeyHash
  deriving stock (Generic, Show, Eq)
  deriving newtype (P.Eq)
  deriving anyclass (HasBlueprintDefinition)

PlutusTx.makeIsDataSchemaIndexed ''DeveloperAddress [('DeveloperAddress, 0)]
PlutusTx.makeLift ''DeveloperAddress

-- | Platform fee address
--
-- Receives platform fees from project submissions.
newtype FeeAddress = FeeAddress PubKeyHash
  deriving stock (Generic, Show, Eq)
  deriving newtype (P.Eq)
  deriving anyclass (HasBlueprintDefinition)

PlutusTx.makeIsDataSchemaIndexed ''FeeAddress [('FeeAddress, 0)]
PlutusTx.makeLift ''FeeAddress

-- | Validator script address
--
-- Represents a script credential (not a public key).
newtype ValidatorAddress = ValidatorAddress PubKeyHash
  deriving stock (Generic, Show, Eq)
  deriving newtype (P.Eq)
  deriving anyclass (HasBlueprintDefinition)

PlutusTx.makeIsDataSchemaIndexed ''ValidatorAddress [('ValidatorAddress, 0)]
PlutusTx.makeLift ''ValidatorAddress

--------------------------------------------------------------------------------
-- ERRORS
--------------------------------------------------------------------------------

-- | Errors that can occur when constructing quantities
data QuantityError
  = NegativeQuantity Integer
  -- ^ Quantity must be >= 0
  | InvalidPercentage Integer
  -- ^ Percentage must be 0-100
  deriving stock (Show, Eq, Generic)
  deriving anyclass (HasBlueprintDefinition)

PlutusTx.makeIsDataSchemaIndexed ''QuantityError
  [('NegativeQuantity, 0), ('InvalidPercentage, 1)]

--------------------------------------------------------------------------------
-- SMART CONSTRUCTORS
-- Enforce invariants at construction time
--------------------------------------------------------------------------------

-- | Smart constructor for Lovelace
--
-- Ensures amount is non-negative.
--
-- ==== Examples
--
-- >>> mkLovelace 100_000_000
-- Right (Lovelace 100000000)
--
-- >>> mkLovelace (-1000)
-- Left (NegativeQuantity (-1000))
{-# INLINEABLE mkLovelace #-}
mkLovelace :: Integer -> P.Either QuantityError Lovelace
mkLovelace n
  | n P.< 0   = P.Left (NegativeQuantity n)
  | P.otherwise = P.Right (Lovelace n)

-- | Smart constructor for CotAmount
--
-- Ensures amount is non-negative.
{-# INLINEABLE mkCotAmount #-}
mkCotAmount :: Integer -> P.Either QuantityError CotAmount
mkCotAmount n
  | n P.< 0   = P.Left (NegativeQuantity n)
  | P.otherwise = P.Right (CotAmount n)

-- | Smart constructor for CetAmount
--
-- Ensures amount is non-negative.
{-# INLINEABLE mkCetAmount #-}
mkCetAmount :: Integer -> P.Either QuantityError CetAmount
mkCetAmount n
  | n P.< 0   = P.Left (NegativeQuantity n)
  | P.otherwise = P.Right (CetAmount n)

-- | Smart constructor for Percentage
--
-- Ensures percentage is between 0 and 100 (inclusive).
--
-- ==== Examples
--
-- >>> mkPercentage 5
-- Right (Percentage 5)
--
-- >>> mkPercentage 150
-- Left (InvalidPercentage 150)
{-# INLINEABLE mkPercentage #-}
mkPercentage :: Integer -> P.Either QuantityError Percentage
mkPercentage n
  | n P.< 0 P.|| n P.> 100 = P.Left (InvalidPercentage n)
  | P.otherwise            = P.Right (Percentage n)

--------------------------------------------------------------------------------
-- CONVERSION FUNCTIONS
--------------------------------------------------------------------------------

-- | Extract PubKeyHash from address types
--
-- These are escape hatches when you need to work with raw PubKeyHash.

{-# INLINEABLE developerToPkh #-}
developerToPkh :: DeveloperAddress -> PubKeyHash
developerToPkh (DeveloperAddress pkh) = pkh

{-# INLINEABLE feeToPkh #-}
feeToPkh :: FeeAddress -> PubKeyHash
feeToPkh (FeeAddress pkh) = pkh

{-# INLINEABLE validatorToPkh #-}
validatorToPkh :: ValidatorAddress -> PubKeyHash
validatorToPkh (ValidatorAddress pkh) = pkh

-- | Generic toPubKeyHash for backward compatibility
{-# INLINEABLE toPubKeyHash #-}
toPubKeyHash :: DeveloperAddress -> PubKeyHash
toPubKeyHash = developerToPkh

-- | Convert Lovelace to raw Integer
--
-- Use sparingly - prefer keeping types wrapped.
{-# INLINEABLE lovelaceValue #-}
lovelaceValue :: Lovelace -> Integer
lovelaceValue (Lovelace n) = n

-- | Convert CotAmount to raw Integer
{-# INLINEABLE cotValue #-}
cotValue :: CotAmount -> Integer
cotValue (CotAmount n) = n

-- | Convert CetAmount to raw Integer
{-# INLINEABLE cetValue #-}
cetValue :: CetAmount -> Integer
cetValue (CetAmount n) = n

--------------------------------------------------------------------------------
-- PLUTUSTX INSTANCES
--------------------------------------------------------------------------------

-- Eq instances for use in validators
instance P.Eq Lovelace where
  {-# INLINEABLE (==) #-}
  Lovelace a == Lovelace b = a P.== b

instance P.Eq CotAmount where
  {-# INLINEABLE (==) #-}
  CotAmount a == CotAmount b = a P.== b

instance P.Eq CetAmount where
  {-# INLINEABLE (==) #-}
  CetAmount a == CetAmount b = a P.== b

instance P.Eq Percentage where
  {-# INLINEABLE (==) #-}
  Percentage a == Percentage b = a P.== b
