{- |
Module      : Carbonica.Validators.Common
Description : Shared validator helpers with aggressive on-chain optimization
License     : Apache-2.0
Maintainer  : Carbonica Platform
Stability   : experimental

This module provides battle-tested validation helpers used across all Carbonica validators.
All functions are marked with @INLINEABLE@ pragmas to enable cross-module optimization by GHC,
reducing on-chain script size and execution costs.

= Design Principles

* __DRY (Don't Repeat Yourself)__: Single source of truth for common validation patterns
* __Type Safety__: Generic functions with 'FromData' constraints for compile-time guarantees
* __On-Chain Optimization__: All helpers are @INLINEABLE@ to minimize script size
* __Consistency__: Same validation logic across all validators

= Performance Notes

All list traversals are tail-recursive and optimized for PlutusTx.
For validator sets >20 signers, consider Set-based implementations in future versions.

-}

module Carbonica.Validators.Common
  ( -- * NFT Finding
    findInputByNft
  , findOutputByNft
  , findInputByOutRef

    -- * Datum Extraction
  , extractDatum
  , findConfigDatum
  , findDatumInOutputs

    -- * Multisig Validation
  , validateMultisig

    -- * Value Helpers
  , hasTokenInOutputs
  , sumTokensByPolicy
  , countTokensWithName
  , hasSingleTokenWithName
  , getMintedAmountForToken

    -- * List Helpers
  , isInList
  , countMatching
  , anySignerInList

    -- * Payout Verification
  , payoutExact
  , payoutAtLeast
  , payoutTokenExact

    -- * Burn Verification
  , mustBurnLessThan0
  , getTokensForPolicy
  , allNegative
  , getTotalForPolicy
  , sumQty

    -- * Category Validation
  , isCategorySupported
  ) where

import           PlutusLedgerApi.V3             (Address (..),
                                                 BuiltinByteString,
                                                 Credential (..),
                                                 CurrencySymbol (..),
                                                 Datum (..),
                                                 Lovelace (..),
                                                 OutputDatum (..),
                                                 PubKeyHash,
                                                 TokenName (..),
                                                 TxInInfo (..),
                                                 TxOut (..),
                                                 TxOutRef (..))
import           PlutusLedgerApi.V1.Value       (Value, valueOf, flattenValue,
                                                 lovelaceValueOf)
import           PlutusTx
import qualified PlutusTx.Prelude               as P

--------------------------------------------------------------------------------
-- NFT FINDING (shared across all validators)
--------------------------------------------------------------------------------

-- | Find the first transaction input containing a specific NFT
--
-- Searches through transaction inputs to find one that holds at least 1 unit
-- of the specified NFT (identified by policy ID and token name).
--
-- ==== Example
--
-- @
-- -- Find input with Identification NFT
-- case findInputByNft inputs idNftPolicy (TokenName "carbonica_id") of
--   Just txIn -> -- Process input containing ID NFT
--   Nothing   -> P.traceError "ID NFT not found in inputs"
-- @
--
-- ==== Implementation
--
-- Linear search through inputs, checking 'valueOf' for each resolved output.
-- Returns the first match found.
--
-- ==== Performance
--
-- Time complexity: O(n) where n = number of inputs
--
-- For typical transactions with <10 inputs, this is negligible.
{-# INLINEABLE findInputByNft #-}
findInputByNft :: [TxInInfo] -> CurrencySymbol -> TokenName -> P.Maybe TxInInfo
findInputByNft [] _ _ = P.Nothing
findInputByNft (i:is) policy tkn =
  if valueOf (txOutValue (txInInfoResolved i)) policy tkn P.> 0
    then P.Just i
    else findInputByNft is policy tkn

-- | Find the first transaction output containing a specific NFT
--
-- Searches through transaction outputs to find one that holds at least 1 unit
-- of the specified NFT.
--
-- ==== Example
--
-- @
-- -- Find output with DAO proposal NFT
-- case findOutputByNft outputs daoPolicy (TokenName proposalId) of
--   Just txOut -> -- Process output containing proposal NFT
--   Nothing    -> P.traceError "Proposal NFT not found in outputs"
-- @
--
-- ==== Use Cases
--
-- * Verifying continuing outputs in spending validators
-- * Finding DAO proposal state in outputs
-- * Locating config updates after governance execution
{-# INLINEABLE findOutputByNft #-}
findOutputByNft :: [TxOut] -> CurrencySymbol -> TokenName -> P.Maybe TxOut
findOutputByNft [] _ _ = P.Nothing
findOutputByNft (o:os) policy tkn =
  if valueOf (txOutValue o) policy tkn P.> 0
    then P.Just o
    else findOutputByNft os policy tkn

-- | Find transaction input by its output reference
--
-- Locates the input that spends a specific UTXO, identified by 'TxOutRef'.
--
-- ==== Example
--
-- @
-- -- Find the project UTXO being spent (from redeemer)
-- case findInputByOutRef inputs projectOref of
--   Just txIn -> validateProjectDatum (txInInfoResolved txIn)
--   Nothing   -> P.traceError "Project UTXO not found"
-- @
--
-- ==== Use Cases
--
-- * COT minting: Verify project UTXO exists and contains valid ProjectDatum
-- * Validators that reference specific UTXOs in their redeemers
{-# INLINEABLE findInputByOutRef #-}
findInputByOutRef :: [TxInInfo] -> TxOutRef -> P.Maybe TxInInfo
findInputByOutRef [] _ = P.Nothing
findInputByOutRef (i:is) ref =
  if txInInfoOutRef i P.== ref
    then P.Just i
    else findInputByOutRef is ref

--------------------------------------------------------------------------------
-- DATUM EXTRACTION (type-safe, generic)
--------------------------------------------------------------------------------

-- | Extract and deserialize typed datum from a transaction output
--
-- This is a type-safe, generic function that works with any datum type
-- that implements 'PlutusTx.FromData'.
--
-- ==== Example
--
-- @
-- -- Extract ConfigDatum from a TxOut
-- case extractDatum txOut of
--   Just (cfg :: ConfigDatum) -> cdFeesAmount cfg
--   Nothing                   -> P.traceError "Invalid ConfigDatum"
-- @
--
-- ==== Type Safety
--
-- The return type is inferred from context, providing compile-time guarantees:
--
-- @
-- config :: ConfigDatum
-- config = case extractDatum txOut of
--   Just c  -> c  -- GHC knows this must be ConfigDatum
--   Nothing -> P.traceError "..."
-- @
--
-- ==== Implementation
--
-- Only inline OutputDatum is supported (not datum hashes).
-- Returns 'Nothing' if:
--
-- * Output has no inline datum
-- * Datum deserialization fails (wrong type)
--
-- | Extract typed datum from a TxOut
{-# INLINEABLE extractDatum #-}
extractDatum :: PlutusTx.FromData a => TxOut -> P.Maybe a
extractDatum txOut = case txOutDatum txOut of
  OutputDatum (Datum d) -> PlutusTx.fromBuiltinData d
  _ -> P.Nothing

-- | Find a typed datum in reference inputs by looking for a specific NFT.
--
-- Searches reference inputs for one holding the given policy/token name,
-- then extracts and deserializes its inline datum.
{-# INLINEABLE findConfigDatum #-}
findConfigDatum :: PlutusTx.FromData a => [TxInInfo] -> CurrencySymbol -> TokenName -> P.Maybe a
findConfigDatum [] _ _ = P.Nothing
findConfigDatum (i:is) policy tkn =
  let txOut = txInInfoResolved i
  in if valueOf (txOutValue txOut) policy tkn P.> 0
       then case extractDatum txOut of
         P.Just datum -> P.Just datum
         P.Nothing    -> findConfigDatum is policy tkn
       else findConfigDatum is policy tkn

-- | Find a typed datum in transaction outputs by looking for a specific NFT.
--
-- Used when configuration is being updated (e.g., during DAO proposal execution)
-- to locate the new ConfigDatum in outputs.
{-# INLINEABLE findDatumInOutputs #-}
findDatumInOutputs :: PlutusTx.FromData a => [TxOut] -> CurrencySymbol -> TokenName -> P.Maybe a
findDatumInOutputs [] _ _ = P.Nothing
findDatumInOutputs (o:os) policy tkn =
  if valueOf (txOutValue o) policy tkn P.> 0
    then case extractDatum o of
      P.Just datum -> P.Just datum
      P.Nothing    -> findDatumInOutputs os policy tkn
    else findDatumInOutputs os policy tkn

--------------------------------------------------------------------------------
-- MULTISIG VALIDATION (optimized)
--------------------------------------------------------------------------------

-- | Validate that enough authorized signers have signed the transaction
--
-- This function implements multisig verification by counting how many transaction
-- signatories are members of the authorized signer list and comparing against
-- the required threshold.
--
-- ==== Example
--
-- @
-- -- Multisig with 3 of 5 required
-- let authorized = [alice, bob, charlie, dave, eve]
-- let required = 3
-- let signatories = [alice, bob, charlie]  -- From txInfoSignatories
--
-- validateMultisig signatories authorized required  -- Returns True
-- @
--
-- ==== Properties
--
-- prop> \\sigs auth req -> validateMultisig sigs auth req == True
-- prop>   ==> countMatching sigs auth >= req
--
-- ==== Implementation Note
--
-- Uses linear search (O(n*m) where n = signatories, m = authorized).
-- For large validator sets (>20), consider Set-based implementations.
--
-- ==== Security Considerations
--
-- * Threshold must be validated off-chain (req > 0 && req <= length authorized)
-- * This check alone is insufficient - must verify authorized list is correct
-- * Always load authorized signers from trusted source (e.g., ConfigDatum)
{-# INLINEABLE validateMultisig #-}
validateMultisig :: [PubKeyHash] -> [PubKeyHash] -> Integer -> Bool
validateMultisig signatories authorized required =
  countMatching signatories authorized P.>= required

-- | Count how many items from the first list appear in the second list.
--
-- Used by 'validateMultisig' to count matching signatories against
-- the authorized signer list.
{-# INLINEABLE countMatching #-}
countMatching :: P.Eq a => [a] -> [a] -> Integer
countMatching signatories authorized = go signatories
  where
    go [] = 0
    go (x:xs) =
      if isInList x authorized
        then 1 P.+ go xs
        else go xs

-- | Check if an item is present in a list (linear search).
{-# INLINEABLE isInList #-}
isInList :: P.Eq a => a -> [a] -> Bool
isInList _ [] = False
isInList x (y:ys) = x P.== y P.|| isInList x ys

-- | Check if any item from the first list appears in the second list
--
-- Useful for checking if any transaction signer is in an authorized list.
{-# INLINEABLE anySignerInList #-}
anySignerInList :: P.Eq a => [a] -> [a] -> Bool
anySignerInList [] _list = False
anySignerInList (s:ss) list = isInList s list P.|| anySignerInList ss list

--------------------------------------------------------------------------------
-- VALUE HELPERS (token counting and validation)
--------------------------------------------------------------------------------

-- | Check if any transaction output contains the specified token.
--
-- Returns 'True' if at least one output holds a positive quantity of
-- the given policy and token name.
{-# INLINEABLE hasTokenInOutputs #-}
hasTokenInOutputs :: [TxOut] -> CurrencySymbol -> TokenName -> Bool
hasTokenInOutputs [] _ _ = False
hasTokenInOutputs (o:os) policy tkn =
  valueOf (txOutValue o) policy tkn P.> 0 P.|| hasTokenInOutputs os policy tkn

-- | Sum all token quantities for a given policy across all token names.
--
-- Operates on a flattened value list @[(CurrencySymbol, TokenName, Integer)]@.
{-# INLINEABLE sumTokensByPolicy #-}
sumTokensByPolicy :: [(CurrencySymbol, TokenName, Integer)] -> CurrencySymbol -> Integer
sumTokensByPolicy [] _ = 0
sumTokensByPolicy ((cs, _, qty):xs) policy =
  if cs P.== policy
    then qty P.+ sumTokensByPolicy xs policy
    else sumTokensByPolicy xs policy

-- | Count how many distinct tokens exist for a policy with a specific name.
--
-- Returns the count (should be 1 for NFTs). Fails fast if the policy
-- has a token with quantity other than 1.
{-# INLINEABLE countTokensWithName #-}
countTokensWithName :: [(CurrencySymbol, TokenName, Integer)] -> CurrencySymbol -> TokenName -> Integer
countTokensWithName tokens policy tkn = go tokens 0
  where
    go :: [(CurrencySymbol, TokenName, Integer)] -> Integer -> Integer
    go [] acc = acc
    go ((cs, tn, qty):xs) acc =
      if cs P.== policy P.&& tn P.== tkn P.&& qty P.== 1
        then go xs (acc P.+ 1)
        else if cs P.== policy
          then 0  -- Found policy but wrong quantity, fail fast
          else go xs acc

-- | Check if exactly 1 token with the given name exists under the policy.
--
-- Used to verify NFT uniqueness (quantity must be exactly 1).
{-# INLINEABLE hasSingleTokenWithName #-}
hasSingleTokenWithName :: [(CurrencySymbol, TokenName, Integer)] -> CurrencySymbol -> TokenName -> Bool
hasSingleTokenWithName tokens policy tkn =
  countTokensWithName tokens policy tkn P.== 1

-- | Get the minted amount for a specific token (policy + name).
--
-- Returns 0 if the token is not present. Suitable for fungible tokens
-- where only a single token name per policy is expected.
{-# INLINEABLE getMintedAmountForToken #-}
getMintedAmountForToken :: [(CurrencySymbol, TokenName, Integer)] -> CurrencySymbol -> TokenName -> Integer
getMintedAmountForToken [] _ _ = 0
getMintedAmountForToken ((cs, tkn, qty):xs) policy targetTkn =
  if cs P.== policy P.&& tkn P.== targetTkn
    then qty
    else getMintedAmountForToken xs policy targetTkn

--------------------------------------------------------------------------------
-- PAYOUT VERIFICATION
--------------------------------------------------------------------------------

-- | Verify exact lovelace payment to a PubKeyHash address
--
--   Returns True if an output exists to the specified address with
--   exactly the expected lovelace amount.
{-# INLINEABLE payoutExact #-}
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

-- | Verify minimum lovelace payment to a PubKeyHash address
--
--   Returns True if an output exists to the specified address with
--   at least the minimum lovelace amount.
{-# INLINEABLE payoutAtLeast #-}
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

-- | Verify exact token payment to a PubKeyHash address
--
--   Used for verifying COT payment to developer, etc.
{-# INLINEABLE payoutTokenExact #-}
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

-- | Verify all tokens of a policy are being burned (negative amounts)
--
--   Returns True if all token quantities for the policy are negative.
{-# INLINEABLE mustBurnLessThan0 #-}
mustBurnLessThan0 :: Value -> CurrencySymbol -> Bool
mustBurnLessThan0 val policy =
  let tokens = getTokensForPolicy val policy
  in allNegative tokens

-- | Get all tokens for a specific policy from a 'Value'.
--
-- Returns a list of @(TokenName, Integer)@ pairs for every token name
-- under the given 'CurrencySymbol'.
{-# INLINEABLE getTokensForPolicy #-}
getTokensForPolicy :: Value -> CurrencySymbol -> [(TokenName, Integer)]
getTokensForPolicy val policy =
  [(tkn, qty) | (cs, tkn, qty) <- flattenValue val, cs P.== policy]

-- | Check if all token quantities are negative (i.e., all are being burned).
{-# INLINEABLE allNegative #-}
allNegative :: [(TokenName, Integer)] -> Bool
allNegative [] = True
allNegative ((_, qty):rest) = qty P.< 0 P.&& allNegative rest

-- | Sum all token quantities for a given policy from a 'Value'.
--
-- Returns the total across all token names under the given 'CurrencySymbol'.
{-# INLINEABLE getTotalForPolicy #-}
getTotalForPolicy :: Value -> CurrencySymbol -> Integer
getTotalForPolicy val policy =
  sumQty [qty | (cs, _, qty) <- flattenValue val, cs P.== policy]

-- | Sum a list of integers (PlutusTx-compatible fold).
{-# INLINEABLE sumQty #-}
sumQty :: [Integer] -> Integer
sumQty []     = 0
sumQty (x:xs) = x P.+ sumQty xs

--------------------------------------------------------------------------------
-- CATEGORY VALIDATION
--------------------------------------------------------------------------------

-- | Check if a category is in the list of supported categories (linear search).
{-# INLINEABLE isCategorySupported #-}
isCategorySupported :: BuiltinByteString -> [BuiltinByteString] -> Bool
isCategorySupported _ [] = False
isCategorySupported cat (c:cs) = cat P.== c P.|| isCategorySupported cat cs
