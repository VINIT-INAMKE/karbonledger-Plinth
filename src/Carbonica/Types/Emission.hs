{- |
Module      : Carbonica.Types.Emission
Description : Carbon Emission Token (CET) types
License     : Apache-2.0

CET tokens represent carbon emissions that users report.
They are non-transferable and locked in User Vaults.
CETs can be offset by burning COT tokens.
-}
module Carbonica.Types.Emission where

import           GHC.Generics              (Generic)
import           PlutusLedgerApi.V3        (BuiltinByteString, POSIXTime,
                                            PubKeyHash)
import           PlutusTx
import           PlutusTx.Blueprint

--------------------------------------------------------------------------------
-- EMISSION RECORD
--------------------------------------------------------------------------------

-- | Datum for a CET emission record in User Vault
data EmissionDatum = EmissionDatum
  { edOwner       :: PubKeyHash
  -- ^ User who reported the emission
  , edCategory    :: BuiltinByteString
  -- ^ Emission category (transport, energy, etc.)
  , edAmount      :: Integer
  -- ^ Amount of CET tokens (emission units)
  , edDescription :: BuiltinByteString
  -- ^ Description or IPFS hash
  , edReportedAt  :: POSIXTime
  -- ^ When the emission was reported
  , edOffset      :: Integer
  -- ^ Amount already offset by COT
  }
  deriving stock (Generic)
  deriving anyclass (HasBlueprintDefinition)

PlutusTx.makeIsDataSchemaIndexed ''EmissionDatum [('EmissionDatum, 0)]
PlutusTx.makeLift ''EmissionDatum

--------------------------------------------------------------------------------
-- CET DATUM
-- Used for minting CET tokens with emission metadata
--------------------------------------------------------------------------------

-- | Datum for CET minting
--   Also serves as redeemer when minting
data CetDatum = CetDatum
  { cetLocation :: BuiltinByteString
  -- ^ Geographical location of the emission
  , cetQty      :: Integer
  -- ^ Quantity of CET tokens to mint
  , cetTime     :: Integer
  -- ^ Timestamp of the emission event
  }
  deriving stock (Generic)
  deriving anyclass (HasBlueprintDefinition)

PlutusTx.makeIsDataSchemaIndexed ''CetDatum [('CetDatum, 0)]
PlutusTx.makeLift ''CetDatum

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
