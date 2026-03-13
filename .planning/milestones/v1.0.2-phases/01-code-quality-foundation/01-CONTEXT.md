# Phase 1: Code Quality Foundation - Context

**Gathered:** 2026-03-11
**Status:** Ready for planning

<domain>
## Phase Boundary

Consolidate all shared validation helpers into a single source of truth (Common.hs), standardize error handling to error codes across all 9 validators, ensure consistent INLINEABLE pragmas, and set up a real Tasty test suite replacing all placeholder stubs. This is foundation work -- no vulnerability fixes, no new features.

</domain>

<decisions>
## Implementation Decisions

### Error code standardization
- Error registry format: Match existing block comment pattern at top of file (code/cause/fix) as used by ConfigHolder and ProjectPolicy
- All 3 missing validators (CetPolicy, UserVault, Marketplace) must get error code prefixes and registries
- Replace all string-message traceError/traceIfFalse calls with error codes

### Claude's Discretion: Error code prefixes
- Choose 3-letter prefixes for CetPolicy, UserVault, Marketplace
- CetPolicy prefix must NOT conflict with CPE (CotPolicy)
- Follow the existing pattern: abbreviation of validator name + E suffix

### Helper consolidation
- Fix ALL duplicate helper functions -- not just Utils.hs/Common.hs overlap, but also local duplicates inside individual validators (e.g., local isInList in DaoGovernance)
- Complete deduplication in this phase across the entire codebase

### Claude's Discretion: Utils.hs disposition
- Decide whether to delete Utils.hs entirely (merging everything into Common.hs) or keep it for non-validator-specific utilities
- Decide whether to update all imports immediately or lazily as validators are touched
- Organize Common.hs sections based on function relationships and usage patterns

### Test framework
- Replace ALL existing placeholder validator tests (assertBool "..." True) with real tests
- Not just Common.hs helper tests -- all stub tests across Types.hs, Validators.hs, and Properties/ must become real

### Claude's Discretion: Test infrastructure
- Decide test approach: helper isolation tests vs ScriptContext builders (considering STATE.md blocker about ScriptContext construction difficulty)
- Decide test module layout (dedicated Common test module vs expanding existing Validators.hs)
- Decide on additional test dependencies beyond current tasty + tasty-hunit + tasty-quickcheck

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- Common.hs: Well-organized with sections (NFT Finding, Datum Extraction, Multisig, Value Helpers) -- extend with new sections
- Test suite: Tasty + HUnit + QuickCheck already configured in cabal, Main.hs wired up
- Properties/SmartConstructors.hs: Real working property tests for Lovelace and CotAmount -- pattern to follow

### Established Patterns
- Error codes: 3-letter prefix + 3-digit number (CHE001, DGE007, PVE003, PPE001, CPE001)
- Error registry: Block comment at top of validator file listing code/cause/fix
- Validation chain: `P.traceIfFalse "CODE" condition1 P.&& P.traceIfFalse "CODE" condition2`
- INLINEABLE pragmas on all on-chain functions
- Section separators: `---- SECTION NAME ----` pattern

### Integration Points
- Utils.hs imported by: CotPolicy, Marketplace, IdentificationNft (via tokenNameFromOref, payoutExact, etc.)
- Common.hs imported by: ConfigHolder, DaoGovernance, ProjectPolicy, ProjectVault, CotPolicy, UserVault
- CetPolicy and Marketplace currently have NO Common.hs imports -- standalone
- cabal exposed-modules list must be updated if Utils.hs is removed

### Duplicate Functions (must resolve)
- `isInList`: exists in both Utils.hs and Common.hs (identical logic)
- `countMatchingSigners` (Utils) vs `countMatching` (Common): same logic, different names
- `verifyMultisig` (Utils) vs `validateMultisig` (Common): same logic, different names
- Individual validators may have local copies of these helpers

</code_context>

<specifics>
## Specific Ideas

No specific requirements -- open to standard approaches for consolidation and test organization.

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope.

</deferred>

---

*Phase: 01-code-quality-foundation*
*Context gathered: 2026-03-11*
