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

{- ══════════════════════════════════════════════════════════════════════════
   ERROR CODE REGISTRY - Marketplace Validator
   ══════════════════════════════════════════════════════════════════════════

   MKE000 - Invalid script context
            Cause: Not a spending context with inline datum
            Fix: Ensure UTxO has inline datum and is being spent

   MKE001 - Datum parse failed
            Cause: Datum bytes don't deserialize to MarketplaceDatum
            Fix: Verify datum structure matches MarketplaceDatum schema

   MKE002 - Redeemer parse failed
            Cause: Redeemer bytes don't deserialize to MarketplaceRedeemer
            Fix: Verify redeemer is MktBuy or MktWithdraw

   MKE003 - Seller not paid
            Cause: Seller PKH not receiving at least payout amount
            Fix: Ensure seller output exists with sufficient lovelace

   MKE004 - Platform not paid
            Cause: Royalty address not receiving at least royalty amount
            Fix: Ensure platform royalty output exists with sufficient lovelace

   MKE005 - Buyer not receiving COT
            Cause: No output to buyer with the listed COT tokens
            Fix: Ensure buyer receives the listed COT quantity

   MKE006 - Owner must sign
            Cause: Listing owner PKH not in transaction signatories
            Fix: Owner must sign the withdrawal transaction

   MKE007 - UTxO does not contain claimed COT tokens
            Cause: The spent UTxO value does not hold at least mdCotQty of mdCotPolicy/mdCotToken
            Fix: Ensure listing UTxO actually contains the tokens described in MarketplaceDatum

   MKE008 - Sale price not positive
            Cause: mdAmount is zero or negative
            Fix: Ensure listing has a positive sale price (mdAmount > 0)

   ══════════════════════════════════════════════════════════════════════════
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
                                                 TxInInfo (..),
                                                 TxInfo (..),
                                                 TxOut (..),
                                                 TxOutRef,
                                                 getRedeemer)
import           PlutusLedgerApi.V1.Value       (valueOf)
import           PlutusTx
import           PlutusTx.Blueprint
import qualified PlutusTx.Prelude               as P

import           Carbonica.Validators.Common    (findInputByOutRef,
                                                 isInList,
                                                 payoutAtLeast)

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

-- | Royalty percentage numerator (5% = 5\/100).
royaltyNumerator :: Integer
royaltyNumerator = 5
{-# INLINEABLE royaltyNumerator #-}

-- | Royalty percentage denominator (5% = 5\/100).
royaltyDenominator :: Integer
royaltyDenominator = 100
{-# INLINEABLE royaltyDenominator #-}

--------------------------------------------------------------------------------
-- VALIDATOR LOGIC
--------------------------------------------------------------------------------

-- | Marketplace spending validator.
--
--   Parameters:
--     _idNftPolicy - reserved for future config lookup
--     royaltyAddr  - Platform fee address receiving royalty payments
--
--   Buy: price > 0, UTxO holds claimed COT, seller paid, platform gets royalty,
--        buyer receives COT.
--   Withdraw: owner must sign.
{-# INLINEABLE typedValidator #-}
typedValidator :: CurrencySymbol -> PubKeyHash -> ScriptContext -> Bool
typedValidator _idNftPolicy royaltyAddr ctx = case scriptInfo of
  SpendingScript oref (Just (Datum datumData)) ->
    case PlutusTx.fromBuiltinData datumData of
      P.Nothing -> P.traceError "MKE001"
      P.Just mktDatum -> validateSpend oref mktDatum
  _ -> P.traceError "MKE000"
  where
    ScriptContext txInfo rawRedeemer scriptInfo = ctx

    -- Parse redeemer
    redeemer :: MarketplaceRedeemer
    redeemer = case PlutusTx.fromBuiltinData (getRedeemer rawRedeemer) of
      P.Nothing -> P.traceError "MKE002"
      P.Just r  -> r

    outputs :: [TxOut]
    outputs = txInfoOutputs txInfo
    {-# INLINEABLE outputs #-}

    signatories :: [PubKeyHash]
    signatories = txInfoSignatories txInfo
    {-# INLINEABLE signatories #-}

    -- Main validation
    validateSpend :: TxOutRef -> MarketplaceDatum -> Bool
    validateSpend oref mktDatum = case redeemer of
      MktBuy      -> validateBuy oref mktDatum
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
    validateBuy :: TxOutRef -> MarketplaceDatum -> Bool
    validateBuy oref mktDatum =
      P.traceIfFalse "MKE008" pricePositive          -- MED-02: price > 0
      P.&& P.traceIfFalse "MKE007" cotVerified       -- MED-01: UTxO has claimed COT
      P.&& P.traceIfFalse "MKE003" sellerPaid
      P.&& P.traceIfFalse "MKE004" platformPaid
      P.&& P.traceIfFalse "MKE005" buyerReceivesCot
      where
        salePrice = mdAmount mktDatum

        -- MED-02: Price must be positive (checked first to prevent zero-price royalty issues)
        pricePositive :: Bool
        pricePositive = salePrice P.> 0

        -- MED-01: Verify the spent UTxO actually contains the claimed COT tokens
        cotVerified :: Bool
        cotVerified =
          case findInputByOutRef (txInfoInputs txInfo) oref of
            P.Nothing -> False
            P.Just i  ->
              let actualQty = valueOf (txOutValue (txInInfoResolved i))
                                (mdCotPolicy mktDatum) (mdCotToken mktDatum)
              in actualQty P.>= mdCotQty mktDatum

        -- Calculate royalty and payout amounts
        -- royalty = amount * royalty_percent / 100
        -- payout = amount - royalty
        -- MED-03: royalty floor of 1 lovelace to prevent royalty evasion via rounding
        royaltyAmount :: Integer
        royaltyAmount = P.max 1 ((salePrice P.* royaltyNumerator) `P.divide` royaltyDenominator)

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
      P.traceIfFalse "MKE006" ownerSigned
      where
        ownerPkh = walletPkh (mdOwner mktDatum)
        ownerSigned = isInList ownerPkh signatories
    {-# INLINEABLE validateWithdraw #-}

    --------------------------------------------------------------------------------
    -- HELPERS
    --------------------------------------------------------------------------------

    -- Find buyer: first signer who is NOT the seller
    findBuyer :: [PubKeyHash] -> PubKeyHash -> P.Maybe PubKeyHash
    findBuyer [] _ = P.Nothing
    findBuyer (s:ss) seller =
      if s P./= seller
        then P.Just s
        else findBuyer ss seller
    {-# INLINEABLE findBuyer #-}

    -- Verify token payment to a PubKeyHash address (at least expectedAmt)
    -- Note: uses >= semantics, distinct from payoutTokenExact which uses ==
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

-- | Untyped entry point for the Marketplace spending validator.
--
-- First arg: idNftPolicy (reserved). Second arg: royaltyAddr.
-- Third arg: ScriptContext.
{-# INLINEABLE untypedValidator #-}
untypedValidator :: BuiltinData -> BuiltinData -> BuiltinData -> P.BuiltinUnit
untypedValidator idNftPolicyData royaltyAddrData ctxData =
  P.check
    ( typedValidator
        (PlutusTx.unsafeFromBuiltinData idNftPolicyData)
        (PlutusTx.unsafeFromBuiltinData royaltyAddrData)
        (PlutusTx.unsafeFromBuiltinData ctxData)
    )

-- | Compiled UPLC code for on-chain deployment of the Marketplace validator.
compiledValidator :: CompiledCode (BuiltinData -> BuiltinData -> BuiltinData -> P.BuiltinUnit)
compiledValidator = $$(PlutusTx.compile [||untypedValidator||])
