{- |
Module      : Carbonica.Validators.Marketplace
Description : Marketplace validator for trading COT tokens
License     : Apache-2.0

The Marketplace allows users to list COT tokens for sale and
enables buyers to purchase them with royalty fees to the platform.

VALIDATION LOGIC:

  MarketplaceDatum:
    - owner: Wallet (seller address)
    - amount: Int (price in lovelace)

  Buy action:
    - Seller receives payout minus royalty (5%)
    - Platform receives royalty fee
    - Uses royalty calculation utility

  Withdraw action:
    - Owner can withdraw their asset
    - Requires owner signature
-}
module Carbonica.Validators.Marketplace where

import           GHC.Generics                   (Generic)
import           PlutusLedgerApi.V3             (Address (..),
                                                 Credential (..),
                                                 CurrencySymbol,
                                                 Datum (..),
                                                 PubKeyHash,
                                                 ScriptContext (..),
                                                 ScriptInfo (..),
                                                 TokenName,
                                                 TxInfo (..),
                                                 TxOut (..),
                                                 getRedeemer)
import           PlutusLedgerApi.V1.Value       (Lovelace (..), lovelaceValueOf, valueOf)
import           PlutusTx
import           PlutusTx.Blueprint
import qualified PlutusTx.Prelude               as P

--------------------------------------------------------------------------------
-- DATUM AND REDEEMER
--------------------------------------------------------------------------------

-- | Wallet representation
data Wallet = Wallet
  { walletPkh   :: PubKeyHash
  -- ^ Payment key hash
  , walletStake :: P.Maybe PubKeyHash
  -- ^ Optional stake key hash
  }
  deriving stock (Generic)
  deriving anyclass (HasBlueprintDefinition)

PlutusTx.makeIsDataSchemaIndexed ''Wallet [('Wallet, 0)]
PlutusTx.makeLift ''Wallet

-- | Marketplace datum
data MarketplaceDatum = MarketplaceDatum
  { mdOwner      :: Wallet
  -- ^ Seller's wallet address
  , mdAmount     :: Integer
  -- ^ Price in lovelace
  , mdCotPolicy  :: CurrencySymbol
  -- ^ COT token policy ID being sold
  , mdCotToken   :: TokenName
  -- ^ COT token name being sold
  , mdCotQty     :: Integer
  -- ^ Quantity of COT tokens being sold
  }
  deriving stock (Generic)
  deriving anyclass (HasBlueprintDefinition)

PlutusTx.makeIsDataSchemaIndexed ''MarketplaceDatum [('MarketplaceDatum, 0)]
PlutusTx.makeLift ''MarketplaceDatum

-- | Marketplace redeemer
data MarketplaceRedeemer
  = MktBuy
  -- ^ Buy the listed asset
  | MktWithdraw
  -- ^ Owner withdraws (cancels listing)
  deriving stock (Generic)
  deriving anyclass (HasBlueprintDefinition)

PlutusTx.makeIsDataSchemaIndexed ''MarketplaceRedeemer
  [('MktBuy, 0), ('MktWithdraw, 1)]

--------------------------------------------------------------------------------
-- CONSTANTS
--------------------------------------------------------------------------------

-- | Royalty percentage (5% = 5/100)
royaltyNumerator :: Integer
royaltyNumerator = 5
{-# INLINEABLE royaltyNumerator #-}

royaltyDenominator :: Integer
royaltyDenominator = 100
{-# INLINEABLE royaltyDenominator #-}

--------------------------------------------------------------------------------
-- VALIDATOR LOGIC
--------------------------------------------------------------------------------

{-# INLINEABLE typedValidator #-}
-- | Marketplace spending validator
--
--   Parameters:
--     _idNftPolicy - (unused, for future config lookup if needed)
--     royaltyAddr  - Platform fee address
--
--   Buy action:
--     1. Calculate royalty: payout_amount = datum.amount * (100 - royalty) / 100
--     2. Calculate platform_fee = datum.amount * royalty / 100
--     3. Seller receives payout_amount
--     4. Platform receives platform_fee
--
--   Withdraw action:
--     1. Owner must sign
typedValidator :: CurrencySymbol -> PubKeyHash -> ScriptContext -> Bool
typedValidator _idNftPolicy royaltyAddr ctx = case scriptInfo of
  SpendingScript _oref (Just (Datum datumData)) ->
    case PlutusTx.fromBuiltinData datumData of
      P.Nothing -> P.traceError "Marketplace: Failed to parse MarketplaceDatum"
      P.Just mktDatum -> validateSpend mktDatum
  _ -> P.traceError "Marketplace: Expected spending context with datum"
  where
    ScriptContext txInfo rawRedeemer scriptInfo = ctx

    -- Parse redeemer
    redeemer :: MarketplaceRedeemer
    redeemer = case PlutusTx.fromBuiltinData (getRedeemer rawRedeemer) of
      P.Nothing -> P.traceError "Marketplace: Failed to parse redeemer"
      P.Just r  -> r

    outputs :: [TxOut]
    outputs = txInfoOutputs txInfo
    {-# INLINEABLE outputs #-}

    signatories :: [PubKeyHash]
    signatories = txInfoSignatories txInfo
    {-# INLINEABLE signatories #-}

    -- Main validation
    validateSpend :: MarketplaceDatum -> Bool
    validateSpend mktDatum = case redeemer of
      MktBuy      -> validateBuy mktDatum
      MktWithdraw -> validateWithdraw mktDatum
    {-# INLINEABLE validateSpend #-}

    --------------------------------------------------------------------------------
    -- BUY VALIDATION
    -- Rules:
    --   1. Calculate royalty: payout_amount = datum.amount * (100 - royalty) / 100
    --   2. Seller receives at least payout_amount
    --   3. Platform receives at least royalty_amount
    --   4. Buyer receives COT tokens (verified via signatories - buyer must sign)
    --------------------------------------------------------------------------------
    validateBuy :: MarketplaceDatum -> Bool
    validateBuy mktDatum =
      P.traceIfFalse "Marketplace: Seller not paid" sellerPaid
      P.&& P.traceIfFalse "Marketplace: Platform not paid" platformPaid
      P.&& P.traceIfFalse "Marketplace: Buyer not receiving COT" buyerReceivesCot
      where
        salePrice = mdAmount mktDatum

        -- Calculate royalty and payout amounts
        -- royalty = amount * royalty_percent / 100
        -- payout = amount - royalty
        royaltyAmount :: Integer
        royaltyAmount = (salePrice P.* royaltyNumerator) `P.divide` royaltyDenominator

        payoutAmount :: Integer
        payoutAmount = salePrice P.- royaltyAmount

        -- Seller wallet
        sellerPkh = walletPkh (mdOwner mktDatum)

        -- Verify seller receives payout
        sellerPaid :: Bool
        sellerPaid = payoutAtLeast sellerPkh payoutAmount outputs

        -- Platform receives royalty
        platformPaid :: Bool
        platformPaid = payoutAtLeast royaltyAddr royaltyAmount outputs

        -- Buyer must receive the COT tokens
        -- Buyer is identified as first signer who is NOT the seller
        buyerReceivesCot :: Bool
        buyerReceivesCot = case findBuyer signatories sellerPkh of
          P.Nothing -> False  -- No buyer found
          P.Just buyerPkh -> 
            hasTokenPayment buyerPkh (mdCotPolicy mktDatum) (mdCotToken mktDatum) (mdCotQty mktDatum) outputs
    {-# INLINEABLE validateBuy #-}

    --------------------------------------------------------------------------------
    -- WITHDRAW VALIDATION
    -- Rules:
    --   Owner signature required
    --------------------------------------------------------------------------------
    validateWithdraw :: MarketplaceDatum -> Bool
    validateWithdraw mktDatum =
      P.traceIfFalse "Marketplace: Owner must sign" ownerSigned
      where
        ownerPkh = walletPkh (mdOwner mktDatum)
        ownerSigned = isSignedBy ownerPkh signatories
    {-# INLINEABLE validateWithdraw #-}

    --------------------------------------------------------------------------------
    -- HELPERS
    --------------------------------------------------------------------------------

    -- Verify at least minAmount paid to address
    payoutAtLeast :: PubKeyHash -> Integer -> [TxOut] -> Bool
    payoutAtLeast _ _ [] = False
    payoutAtLeast pkh minAmt (o:os) =
      let addr = txOutAddress o
          matchesPkh = case addressCredential addr of
            PubKeyCredential pk -> pk P.== pkh
            _                   -> False
          Lovelace lovelaceAmt = lovelaceValueOf (txOutValue o)
      in if matchesPkh P.&& lovelaceAmt P.>= minAmt
           then True
           else payoutAtLeast pkh minAmt os
    {-# INLINEABLE payoutAtLeast #-}

    isSignedBy :: PubKeyHash -> [PubKeyHash] -> Bool
    isSignedBy _ []     = False
    isSignedBy p (s:ss) = p P.== s P.|| isSignedBy p ss
    {-# INLINEABLE isSignedBy #-}

    -- Find buyer: first signer who is NOT the seller
    findBuyer :: [PubKeyHash] -> PubKeyHash -> P.Maybe PubKeyHash
    findBuyer [] _ = P.Nothing
    findBuyer (s:ss) seller =
      if s P./= seller
        then P.Just s
        else findBuyer ss seller
    {-# INLINEABLE findBuyer #-}

    -- Verify token payment to a PubKeyHash address
    hasTokenPayment :: PubKeyHash -> CurrencySymbol -> TokenName -> Integer -> [TxOut] -> Bool
    hasTokenPayment _ _ _ _ [] = False
    hasTokenPayment pkh policy tkn expectedAmt (o:os) =
      let addr = txOutAddress o
          matchesPkh = case addressCredential addr of
            PubKeyCredential pk -> pk P.== pkh
            _                   -> False
          tokenAmt = valueOf (txOutValue o) policy tkn
      in if matchesPkh P.&& tokenAmt P.>= expectedAmt
           then True
           else hasTokenPayment pkh policy tkn expectedAmt os
    {-# INLINEABLE hasTokenPayment #-}



--------------------------------------------------------------------------------
-- COMPILED VALIDATOR
--------------------------------------------------------------------------------

{-# INLINEABLE untypedValidator #-}
untypedValidator :: BuiltinData -> BuiltinData -> BuiltinData -> P.BuiltinUnit
untypedValidator idNftPolicyData royaltyAddrData ctxData =
  P.check
    ( typedValidator
        (PlutusTx.unsafeFromBuiltinData idNftPolicyData)
        (PlutusTx.unsafeFromBuiltinData royaltyAddrData)
        (PlutusTx.unsafeFromBuiltinData ctxData)
    )

compiledValidator :: CompiledCode (BuiltinData -> BuiltinData -> BuiltinData -> P.BuiltinUnit)
compiledValidator = $$(PlutusTx.compile [||untypedValidator||])
