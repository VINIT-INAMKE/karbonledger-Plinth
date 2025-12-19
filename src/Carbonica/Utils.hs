{- |
Module      : Carbonica.Utils
Description : Shared utility functions for Carbonica validators
License     : Apache-2.0

This module provides shared utility functions:
  - tokenNameFromOref: Derive unique token name from OutputReference
  - payoutExact: Verify exact payment to address
  - payoutAtLeast: Verify minimum payment to address
  - mustBurnLessThan0: Verify all tokens of policy are burned
-}
module Carbonica.Utils where

import           PlutusLedgerApi.V3             (Address (..),
                                                 BuiltinByteString,
                                                 Credential (..),
                                                 CurrencySymbol,
                                                 Lovelace (..),
                                                 PubKeyHash,
                                                 TokenName (..),
                                                 TxOut (..),
                                                 TxOutRef)
import           PlutusLedgerApi.V1.Value       (Value, valueOf, flattenValue,
                                                 lovelaceValueOf)
import           PlutusTx
import qualified PlutusTx.Builtins              as Builtins
import qualified PlutusTx.Prelude               as P

--------------------------------------------------------------------------------
-- TOKEN NAME GENERATION
--------------------------------------------------------------------------------

{-# INLINEABLE tokenNameFromOref #-}
-- | Generate unique token name from TxOutRef (one-shot pattern)
--
--   Implementation:
--     blake2b_224(serialise(oref))
--
--   This ensures each minted token has a unique name derived from the
--   consumed UTxO, preventing double-minting.
tokenNameFromOref :: TxOutRef -> TokenName
tokenNameFromOref oref = TokenName $ 
  Builtins.blake2b_224 (Builtins.serialiseData (PlutusTx.toBuiltinData oref))

--------------------------------------------------------------------------------
-- PAYOUT VERIFICATION
--------------------------------------------------------------------------------

{-# INLINEABLE payoutExact #-}
-- | Verify exact lovelace payment to a PubKeyHash address
--
--   Returns True if an output exists to the specified address with
--   exactly the expected lovelace amount.
payoutExact :: PubKeyHash -> Integer -> [TxOut] -> Bool
payoutExact _ _ [] = False
payoutExact pkh expectedAmt (o:os) =
  let addr = txOutAddress o
      matchesPkh = case addressCredential addr of
        PubKeyCredential pk -> pk P.== pkh
        _                   -> False
      Lovelace lovelaceAmt = lovelaceValueOf (txOutValue o)
  in if matchesPkh P.&& lovelaceAmt P.== expectedAmt
       then True
       else payoutExact pkh expectedAmt os

{-# INLINEABLE payoutAtLeast #-}
-- | Verify minimum lovelace payment to a PubKeyHash address
--
--   Returns True if an output exists to the specified address with
--   at least the minimum lovelace amount.
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

{-# INLINEABLE payoutTokenExact #-}
-- | Verify exact token payment to a PubKeyHash address
--
--   Used for verifying COT payment to developer, etc.
payoutTokenExact :: PubKeyHash -> CurrencySymbol -> TokenName -> Integer -> [TxOut] -> Bool
payoutTokenExact _ _ _ _ [] = False
payoutTokenExact pkh policy tkn expectedAmt (o:os) =
  let addr = txOutAddress o
      matchesPkh = case addressCredential addr of
        PubKeyCredential pk -> pk P.== pkh
        _                   -> False
      tokenAmt = valueOf (txOutValue o) policy tkn
  in if matchesPkh P.&& tokenAmt P.== expectedAmt
       then True
       else payoutTokenExact pkh policy tkn expectedAmt os

--------------------------------------------------------------------------------
-- BURN VERIFICATION
--------------------------------------------------------------------------------

{-# INLINEABLE mustBurnLessThan0 #-}
-- | Verify all tokens of a policy are being burned (negative amounts)
--
--   Returns True if all token quantities for the policy are negative.
mustBurnLessThan0 :: Value -> CurrencySymbol -> Bool
mustBurnLessThan0 val policy =
  let tokens = getTokensForPolicy val policy
  in allNegative tokens

{-# INLINEABLE getTokensForPolicy #-}
-- | Get all tokens for a specific policy from a Value
getTokensForPolicy :: Value -> CurrencySymbol -> [(TokenName, Integer)]
getTokensForPolicy val policy =
  [(tkn, qty) | (cs, tkn, qty) <- flattenValue val, cs P.== policy]

{-# INLINEABLE allNegative #-}
-- | Check if all quantities are negative
allNegative :: [(TokenName, Integer)] -> Bool
allNegative [] = True
allNegative ((_, qty):rest) = qty P.< 0 P.&& allNegative rest

{-# INLINEABLE getTotalForPolicy #-}
-- | Sum all token quantities for a given policy
getTotalForPolicy :: Value -> CurrencySymbol -> Integer
getTotalForPolicy val policy =
  sumQty [qty | (cs, _, qty) <- flattenValue val, cs P.== policy]

{-# INLINEABLE sumQty #-}
-- | Sum a list of integers
sumQty :: [Integer] -> Integer
sumQty []     = 0
sumQty (x:xs) = x P.+ sumQty xs

--------------------------------------------------------------------------------
-- CATEGORY VALIDATION
--------------------------------------------------------------------------------

{-# INLINEABLE isCategorySupported #-}
-- | Check if a category is in the list of supported categories
isCategorySupported :: BuiltinByteString -> [BuiltinByteString] -> Bool
isCategorySupported _ [] = False
isCategorySupported cat (c:cs) = cat P.== c P.|| isCategorySupported cat cs

--------------------------------------------------------------------------------
-- MULTISIG VERIFICATION
--------------------------------------------------------------------------------

{-# INLINEABLE countMatchingSigners #-}
-- | Count how many transaction signatories are in the multisig group
countMatchingSigners :: [PubKeyHash] -> [PubKeyHash] -> Integer
countMatchingSigners [] _ = 0
countMatchingSigners (s:ss) multisig =
  if isInList s multisig
    then 1 P.+ countMatchingSigners ss multisig
    else countMatchingSigners ss multisig

{-# INLINEABLE verifyMultisig #-}
-- | Verify enough signatories from multisig have signed
verifyMultisig :: [PubKeyHash] -> [PubKeyHash] -> Integer -> Bool
verifyMultisig signatories multisigSigners required =
  countMatchingSigners signatories multisigSigners P.>= required

{-# INLINEABLE isInList #-}
-- | Check if a PubKeyHash is in a list
isInList :: PubKeyHash -> [PubKeyHash] -> Bool
isInList _ []     = False
isInList x (y:ys) = x P.== y P.|| isInList x ys
