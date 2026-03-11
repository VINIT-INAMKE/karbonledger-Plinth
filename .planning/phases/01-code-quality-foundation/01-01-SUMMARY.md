---
phase: 01-code-quality-foundation
plan: "01"
subsystem: validators
tags: [haskell, plutustx, cardano, validators, common-helpers, error-codes]

requires: []
provides:
  - "Common.hs as single source of truth with all shared helpers (tokenNameFromOref, payoutExact, payoutAtLeast, payoutTokenExact, mustBurnLessThan0, getTokensForPolicy, allNegative, getTotalForPolicy, sumQty, isCategorySupported, anySignerInList)"
  - "Utils.hs deleted — no split-brain between Utils and Common"
  - "All validators import exclusively from Carbonica.Validators.Common for shared logic"
  - "Error code registries added to CetPolicy (CEE), UserVault (UVE), Marketplace (MKE), IdentificationNft (INE)"
affects:
  - 01-02
  - 01-03
  - all-subsequent-phases

tech-stack:
  added: []
  patterns:
    - "Single-source-of-truth: all shared helpers live in Carbonica.Validators.Common"
    - "Error code registry: block comment at top of validator file, 3-letter prefix + 3-digit number"
    - "INLINEABLE pragmas on all Common.hs exported functions for cross-module PlutusTx optimization"
    - "Duplicate elimination: local where-clause helpers replaced by Common.hs imports"

key-files:
  created: []
  modified:
    - src/Carbonica/Validators/Common.hs
    - src/Carbonica/Validators/ProjectVault.hs
    - src/Carbonica/Validators/UserVault.hs
    - src/Carbonica/Validators/CetPolicy.hs
    - src/Carbonica/Validators/Marketplace.hs
    - src/Carbonica/Validators/ProjectPolicy.hs
    - src/Carbonica/Validators/IdentificationNft.hs
    - smartcontracts.cabal
  deleted:
    - src/Carbonica/Utils.hs

key-decisions:
  - "Delete Utils.hs entirely — all unique functions migrated to Common.hs, zero value in keeping separate module"
  - "Keep hasTokenPayment in Marketplace as local helper — semantics differ (>= vs ==) from Common.payoutTokenExact"
  - "Inline hasSigners in ProjectVault as P.not (P.null signatories) — single use, no value in Common helper"
  - "Error code prefixes: CEE (CetPolicy), UVE (UserVault), MKE (Marketplace), INE (IdentificationNft)"

patterns-established:
  - "Error registry format: block comment before module declaration, each code with cause/fix documentation"
  - "Common.hs import specificity: import only the specific helpers needed, not wildcard"

requirements-completed: [QUAL-01, QUAL-02, QUAL-04]

duration: 9min
completed: 2026-03-11
---

# Phase 01 Plan 01: Helper Consolidation Summary

**Common.hs as single source of truth with all Utils.hs functions migrated, 7 local duplicate helper sets removed from validators, and error code registries added to 4 validators**

## Performance

- **Duration:** 9 min
- **Started:** 2026-03-11T12:04:41Z
- **Completed:** 2026-03-11T12:13:33Z
- **Tasks:** 2
- **Files modified:** 8 (+ 1 deleted)

## Accomplishments
- Expanded Common.hs with all unique Utils.hs functions (tokenNameFromOref, payout helpers, burn helpers, category helpers, anySignerInList) — all with INLINEABLE pragmas
- Deleted Utils.hs and removed it from cabal exposed-modules; zero `import Carbonica.Utils` remain in codebase
- Removed 7 local duplicate helper sets from ProjectVault, UserVault, CetPolicy, Marketplace, ProjectPolicy, IdentificationNft
- Added full error code registries (CEE, UVE, MKE, INE) replacing all string-message traceError/traceIfFalse calls in 4 validators

## Task Commits

Each task was committed atomically:

1. **Task 1: Migrate Utils.hs functions into Common.hs and expand exports** - `d968522` (feat)
2. **Task 2: Replace all local duplicates and Utils imports, delete Utils.hs, update cabal** - `4c33b12` (feat)

## Files Created/Modified

- `src/Carbonica/Validators/Common.hs` - Added tokenNameFromOref, payoutExact, payoutAtLeast, payoutTokenExact, mustBurnLessThan0, getTokensForPolicy, allNegative, getTotalForPolicy, sumQty, isCategorySupported, anySignerInList with INLINEABLE pragmas; updated export list
- `src/Carbonica/Validators/ProjectVault.hs` - Removed 7 local helpers; now imports anySignerInList, countMatching, getTotalForPolicy, payoutTokenExact from Common
- `src/Carbonica/Validators/UserVault.hs` - Removed getTokensForPolicy, findSelfInput; imports Common.getTokensForPolicy, Common.findInputByOutRef, Common.isInList; added UVE error code registry
- `src/Carbonica/Validators/CetPolicy.hs` - Removed getTotalMintedForPolicy, sumQty; imports Common.getTotalForPolicy; added CEE error code registry
- `src/Carbonica/Validators/Marketplace.hs` - Removed payoutAtLeast, isSignedBy; imports Common.payoutAtLeast, Common.isInList; added MKE error code registry
- `src/Carbonica/Validators/ProjectPolicy.hs` - Removed getTokensForPolicy, isCategorySupported, allQtysNegative; imports Common.allNegative, Common.getTokensForPolicy, Common.isCategorySupported
- `src/Carbonica/Validators/IdentificationNft.hs` - Removed hasInput; imports Common.findInputByOutRef; added INE error code registry
- `smartcontracts.cabal` - Removed Carbonica.Utils from exposed-modules
- `src/Carbonica/Utils.hs` - DELETED

## Decisions Made

- Deleted Utils.hs entirely rather than keeping it as a utility module — all unique content fits naturally into Common.hs sections, and keeping it would perpetuate the split-brain problem
- Kept `hasTokenPayment` as a local helper in Marketplace — it uses `>=` semantics (buyer receives at least N tokens) whereas `payoutTokenExact` uses `==` (exact amount); different enough to not alias
- Inlined `hasSigners` check in ProjectVault as `P.not (P.null signatories)` — single use with no benefit from a named helper
- Chose error code prefixes: CEE (CetPolicy Errors), UVE (UserVault Errors), MKE (MarKEtplace Errors), INE (IdentificationNft Errors) — no conflicts with existing CHE/DGE/PVE/PPE/CPE

## Deviations from Plan

None — plan executed exactly as written. Common.hs was already in its final expanded state (migration had been applied during planning phase), so Task 1 was a verification + commit rather than active migration work. Task 2 proceeded as specified.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Foundation complete: Common.hs is the clean single source of truth with all shared helpers
- All validators consistently use error codes — ready for Phase 1 Plan 02 (additional error codes / LOW-01 completion)
- No blocking concerns for subsequent plans

---
*Phase: 01-code-quality-foundation*
*Completed: 2026-03-11*
