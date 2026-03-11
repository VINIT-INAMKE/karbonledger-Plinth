# Concerns

## Critical Security Vulnerabilities

### 1. ProjectVault Vote: No Output Datum Verification
- **File:** `src/Carbonica/Validators/ProjectVault.hs:207-231`
- **Severity:** CRITICAL
- **Description:** `validateVote` checks signer is in multisig, hasn't voted, and project is Submitted, but **never validates the output datum**. No continuing output check, no vote count verification, no datum integrity check.
- **Impact:** A single multisig member can spend the project UTxO and return it with: yes votes set to threshold (instant approval), developer address changed, COT amount inflated, voter list wiped.
- **Fix:** Add continuing output verification: check exactly 1 output back to script, verify datum fields (vote count incremented by 1, voter added, all other fields unchanged).

### 2. DaoGovernance Mint: Trivial Authorization Bypass
- **File:** `src/Carbonica/Validators/DaoGovernance.hs:226-234`
- **Severity:** CRITICAL
- **Description:** `hasAuthorizedSigner` only checks if ANY signer exists (`hasSigner [] = False; hasSigner _ = True`). Every valid Cardano transaction has at least one signer.
- **Impact:** Anyone can submit DAO proposals and burn proposal NFTs. Attackers can spam governance or destroy legitimate proposals.
- **Fix:** Replace `hasSigner` with actual multisig verification using ConfigDatum. Require submitter to be in `msSigners`.

### 3. DaoGovernance verifyConfigUpdate: Partial Field Verification
- **File:** `src/Carbonica/Validators/DaoGovernance.hs:543-592`
- **Severity:** CRITICAL
- **Description:** Each `ProposalAction` case only verifies the target field. No check that other ConfigDatum fields remain unchanged.
- **Impact:** A benign "update fee" proposal can silently change multisig signers, categories, script hashes -- taking full platform control.
- **Fix:** Add comprehensive "other fields unchanged" check for each action. Compare all non-target fields between input and output ConfigDatum.

### 4. CotPolicy Mint: No Project Status or Amount Verification
- **File:** `src/Carbonica/Validators/CotPolicy.hs:172-191`
- **Severity:** CRITICAL
- **Description:** `projectInputValid` only checks that a ProjectDatum exists. Does not verify project is Approved, or that minted COT matches `pdCotAmount`. Amount comes entirely from redeemer.
- **Impact:** With multisig, COT tokens can be minted for unapproved/rejected projects with arbitrary amounts.
- **Fix:** Extract ProjectDatum, verify `pdStatus == ProjectApproved`, verify `cotAmount red == pdCotAmount projectDatum`.

## High Severity Issues

### 5. ProjectPolicy: NFT Sent to Any Script Address
- **File:** `src/Carbonica/Validators/ProjectPolicy.hs:222-227`
- **Severity:** HIGH
- **Description:** Checks NFT goes to **a** script address (`ScriptCredential _ -> True`), not specifically the ProjectVault script hash.
- **Impact:** Project NFTs can be sent to attacker-controlled scripts with weaker spending rules, bypassing the voting process.
- **Fix:** Verify against `cdProjectVaultHash` from ConfigDatum.

### 6. DaoGovernance/ProjectVault: Trivial Signer Checks
- **Files:** `DaoGovernance.hs:409,526-529`, `ProjectVault.hs:320-323`
- **Severity:** HIGH
- **Description:** `hasAnySigner` and `hasSigners` just check the list is non-empty. Always true for valid transactions.
- **Impact:** These checks provide zero security. Authorization relies entirely on downstream checks (`voterInMultisig`), but the misleading function names hide the gap.
- **Fix:** Replace with actual `txSignedBy` checks for specific authorized PKHs.

### 7. DaoGovernance Execute/Reject: No Authorization Check
- **File:** `src/Carbonica/Validators/DaoGovernance.hs:454-508`
- **Severity:** HIGH
- **Description:** `validateExecute` and `validateReject` have no multisig or signature check. Anyone can trigger execution or rejection after deadline.
- **Impact:** Attackers can front-run or time execution to their advantage.
- **Fix:** Require at least one multisig signer to execute/reject.

## Medium Severity Issues

### 8. Marketplace: Listed Tokens Not Verified in UTxO
- **File:** `src/Carbonica/Validators/Marketplace.hs:60-72`
- **Severity:** MEDIUM
- **Description:** `MarketplaceDatum` claims token policy/name/qty but validator never checks the locked UTxO actually contains those tokens. `buyerReceivesCot` checks any output, tokens could come from different input.
- **Impact:** Fraudulent listings can claim to sell tokens they don't hold.

### 9. Marketplace: No Minimum Price & Royalty Rounding
- **File:** `src/Carbonica/Validators/Marketplace.hs:168-174`
- **Severity:** MEDIUM
- **Description:** No check that `mdAmount > 0`. With amount=0, both seller/platform checks trivially pass. For prices < 20 lovelace, royalty truncates to 0.
- **Impact:** COT tokens given away for free; platform receives no royalty on small transactions.

### 10. DaoGovernance: Empty Votes List on Proposal Creation
- **File:** `src/Carbonica/Types/Governance.hs:278-288`
- **Severity:** MEDIUM
- **Description:** `mkNewProposal` creates `gdVotes' = []`. But `validateVote` requires `findVoterRecord voter (gdVotes inputDatum)` to find a `VoterPending` entry. Empty list always returns Nothing.
- **Impact:** Proposals created via smart constructor can never be voted on. Off-chain code must use `mkGovernanceDatum` with pre-populated voter records.

### 11. DaoGovernance Vote: Incomplete Output Datum Integrity
- **File:** `src/Carbonica/Validators/DaoGovernance.hs:395-442`
- **Severity:** MEDIUM
- **Description:** Vote validation checks specific vote count increment and voter status change but doesn't verify other vote records, other counts, or non-vote fields remain unchanged.
- **Impact:** A voter could modify multiple vote records or other fields in single transaction.

## Performance Concerns

### Linear List Searches
- **All multisig checks** use O(n*m) linear search through signer lists
- **Voter record lookup** in governance is O(n) per vote
- **Category validation** is O(n) linear scan
- For current scale (5 signers, few categories) this is fine, but won't scale beyond ~20 signers

### Duplicate Helper Functions
- `isInList`, `countMatchingSigners`, `getTokensForPolicy`, `sumQty` are duplicated across multiple validators
- `Carbonica.Validators.Common` and `Carbonica.Utils` have overlapping functionality
- Increases on-chain script size unnecessarily

## Technical Debt

### Inconsistent Error Handling
- ConfigHolder, DaoGovernance, ProjectVault, ProjectPolicy use error codes (`CHE001`, `DGE007`)
- CetPolicy, UserVault, Marketplace use string messages (`"UserVault: Owner must sign"`)
- No unified error handling approach

### Unused/Stub Code
- `VaultWithdraw` redeemer in UserVault always fails with traceError
- `Validator.hs` is a template file not part of Carbonica platform
- `Utils.hs` has functions (`payoutExact`, `payoutAtLeast`, `verifyMultisig`) duplicated in validators

### Missing Validation
- No `proposalDuration > 0` check in ConfigDatum
- No deadline-in-future check in `mkNewProposal` (comment acknowledges this)
- No check that CET `cetQty > 0` in mint path (handled indirectly by flattenValue behavior)

## Attack Chain Summary

**Most exploitable chain (Vulnerabilities #1 + #4):**
A single multisig member can:
1. Submit a project (no special auth needed)
2. Cast a vote, manipulate output datum to set max yes votes + change developer to themselves + inflate COT amount (#1)
3. Immediately mint arbitrary COT with manipulated project data (#4)

This requires only 1 of the multisig members to be malicious.
