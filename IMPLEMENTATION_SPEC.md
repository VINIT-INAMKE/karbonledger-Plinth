# Carbonica Ledger — Implementation Specification

> Functional requirements specification for building the Carbonica carbon credit platform.

---

## Document Purpose

This document defines **WHAT** needs to be built for the Carbonica Ledger platform. It covers:

- User registration and authentication
- Project registration and submission
- Project NFT minting
- Validator voting and project verification
- Token issuance (COT) and lifecycle management

**Note**: Smart contracts will be written separately. This spec defines the contract interfaces and expected behaviors, not the implementation details.

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Module 1: User Registration](#2-module-1-user-registration)
3. [Module 2: Project Registration](#3-module-2-project-registration)
4. [Module 3: Project NFT Minting](#4-module-3-project-nft-minting)
5. [Module 4: Validator Voting](#5-module-4-validator-voting)
6. [Module 5: COT Token Issuance](#6-module-5-cot-token-issuance)
7. [Module 6: Token Lifecycle Tracking](#7-module-6-token-lifecycle-tracking)
8. [Data Models](#8-data-models)
9. [Smart Contract Interfaces](#9-smart-contract-interfaces)
10. [Business Rules](#10-business-rules)

---

## 1. System Overview

### 1.1 Platform Purpose

Carbonica Ledger is a decentralized carbon credit platform that:

- Allows project developers to register carbon offset projects
- Enables independent validators to verify project legitimacy
- Issues tradeable Carbon Offset Tokens (COT) for approved projects
- Tracks full token lifecycle (mint, transfer, burn) for audit purposes

### 1.2 User Roles

| Role | Description |
|------|-------------|
| **Developer** | Submits carbon offset projects for verification |
| **Validator** | Reviews and votes on submitted projects |
| **Admin** | Manages platform configuration and validator assignments |

### 1.3 Token Types

| Token | Name | Purpose |
|-------|------|---------|
| **Project NFT** | Project Token | Temporary token representing a submitted project (burned after voting) |
| **COT** | Carbon Offset Token | Tradeable carbon credits issued to approved projects |
| **CET** | Carbon Emission Token | Non-transferable token representing logged emissions |

---

## 2. Module 1: User Registration

### 2.1 Objective

Allow users to create accounts by connecting their Cardano wallet.

### 2.2 Functional Requirements

| ID | Requirement |
|----|-------------|
| UR-01 | User must be able to connect a Cardano wallet (CIP-30 compatible) |
| UR-02 | System must extract wallet address upon connection |
| UR-03 | System must create a user record if wallet address is new |
| UR-04 | System must retrieve existing user record if wallet address exists |
| UR-05 | Default role for new users must be "developer" |
| UR-06 | User session must persist until explicit disconnect |
| UR-07 | One wallet address = one unique user account |
| UR-08 | User must complete profile before submitting projects |
| UR-09 | Email must be verified before project submission (optional, configurable) |
| UR-10 | KYC verification required for projects above threshold (optional, configurable) |

### 2.3 User Data to Store

**Core Identity:**

| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `user_id` | UUID | Unique identifier | Auto-generated |
| `wallet_address` | String | Cardano address (bech32) | Yes |
| `stake_address` | String | Stake address (for rewards) | No |
| `role` | Enum | developer, validator, admin | Yes (default: developer) |
| `created_at` | Timestamp | Account creation time | Auto-generated |
| `updated_at` | Timestamp | Last profile update | Auto-generated |
| `last_login` | Timestamp | Last wallet connection | Auto-generated |

**Profile Information:**

| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `display_name` | String | Public display name (max 50 chars) | Yes (for project submission) |
| `email` | String | Contact email | Yes (for project submission) |
| `email_verified` | Boolean | Whether email is verified | Auto-generated |
| `avatar_url` | String | Profile picture URL | No |
| `bio` | Text | Short biography (max 500 chars) | No |
| `website` | String | Personal/company website | No |
| `social_links` | JSON | Social media links (Twitter, LinkedIn, etc.) | No |

**Organization Details (for Developers):**

| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `organization_name` | String | Company/NGO name | Yes (for project submission) |
| `organization_type` | Enum | individual, company, ngo, government, other | Yes (for project submission) |
| `organization_country` | String | Country of registration (ISO 3166-1) | Yes (for project submission) |
| `organization_registration_number` | String | Business/NGO registration number | No |
| `organization_address` | Text | Physical address | No |
| `organization_logo_url` | String | Organization logo | No |

**KYC/Verification Status:**

| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `kyc_status` | Enum | not_started, pending, approved, rejected | Auto (default: not_started) |
| `kyc_submitted_at` | Timestamp | When KYC was submitted | Auto |
| `kyc_verified_at` | Timestamp | When KYC was approved | Auto |
| `kyc_rejection_reason` | Text | Reason for KYC rejection | Auto |
| `kyc_documents` | JSON | List of submitted KYC document references | No |

**Activity Metrics (Computed/Cached):**

| Field | Type | Description |
|-------|------|-------------|
| `projects_count` | Integer | Total projects submitted |
| `projects_verified_count` | Integer | Projects that were approved |
| `total_cot_minted` | Integer | Total COT tokens received |
| `votes_cast_count` | Integer | Total votes cast (validators only) |

### 2.4 Organization Types

| Type Key | Display Name | Description |
|----------|--------------|-------------|
| `individual` | Individual | Solo developer/researcher |
| `company` | Company | For-profit corporation |
| `ngo` | NGO | Non-governmental organization |
| `government` | Government | Government agency or body |
| `cooperative` | Cooperative | Community-owned organization |
| `other` | Other | Other organization type |

### 2.5 KYC Status Flow

```
not_started → pending → approved
                     → rejected → pending (resubmit)
```

| Status | Description |
|--------|-------------|
| `not_started` | User has not initiated KYC |
| `pending` | KYC documents submitted, awaiting review |
| `approved` | KYC verified successfully |
| `rejected` | KYC failed, user can resubmit |

### 2.6 Profile Completion Requirements

**Minimum for Project Submission:**

- ✅ `display_name` - Required
- ✅ `email` - Required
- ✅ `organization_name` - Required
- ✅ `organization_type` - Required
- ✅ `organization_country` - Required

**Optional but Recommended:**

- `bio` - Helps validators understand the developer
- `website` - Adds credibility
- `organization_registration_number` - Adds legitimacy
- `avatar_url` / `organization_logo_url` - Visual identity

### 2.7 User Flow

```
1. User visits platform
2. User clicks "Connect Wallet"
3. Wallet extension prompts for permission
4. User approves connection
5. System extracts wallet address
6. System checks if user exists:
   - If NO: Create new user record → Redirect to profile setup
   - If YES: Load existing user → Redirect to dashboard
7. New users must complete profile:
   - Fill display name, email
   - Verify email (if required)
   - Fill organization details
   - (Optional) Complete KYC
8. User can now access role-appropriate features
```

### 2.8 Access Control by Role

| Feature | Developer | Validator | Admin |
|---------|-----------|-----------|-------|
| View own profile | ✅ | ✅ | ✅ |
| Edit own profile | ✅ | ✅ | ✅ |
| Register projects | ✅ | ❌ | ❌ |
| View own projects | ✅ | ❌ | ✅ |
| Vote on projects | ❌ | ✅ | ❌ |
| View pending verifications | ❌ | ✅ | ✅ |
| Manage users | ❌ | ❌ | ✅ |
| Configure platform | ❌ | ❌ | ✅ |
| Review KYC submissions | ❌ | ❌ | ✅ |

---

## 3. Module 2: Project Registration

### 3.1 Objective

Allow developers to submit carbon offset projects for verification.

### 3.2 Functional Requirements

| ID | Requirement |
|----|-------------|
| PR-01 | Only users with "developer" role can register projects |
| PR-02 | User must have connected wallet before registering |
| PR-03 | System must validate all required fields before submission |
| PR-04 | System must validate project category against allowed categories |
| PR-05 | User must pay platform fee during submission |
| PR-06 | Project must be saved with status "draft" before on-chain submission |
| PR-07 | After successful on-chain submission, status must update to "submitted" |
| PR-08 | System must store transaction hash after on-chain submission |

### 3.3 Project Data to Collect

**Basic Information:**

| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `name` | String | Project name (max 100 chars) | Yes |
| `short_description` | String | Brief summary (max 250 chars) | Yes |
| `description` | Text | Detailed project description | Yes |
| `category` | Enum | Project category (see below) | Yes |
| `sub_category` | String | Specific type within category | No |
| `thumbnail` | File | Project cover image | Yes |
| `gallery` | File[] | Additional project images | No |

**Location & Geography:**

| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `country` | String | Country (ISO 3166-1) | Yes |
| `region` | String | State/Province/Region | Yes |
| `location_name` | String | City or area name | Yes |
| `coordinates` | Object | GPS coordinates {lat, lng} | No |
| `area_size` | Number | Project area in hectares | Yes |
| `area_unit` | Enum | hectares, acres, sq_km | Yes (default: hectares) |

**Carbon Credit Details:**

| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `expected_credits` | Integer | Estimated annual COT to be generated | Yes |
| `credit_period_years` | Integer | Project crediting period in years | Yes |
| `total_expected_credits` | Integer | Total credits over lifetime (computed) | Auto |
| `methodology` | String | Carbon accounting methodology used | Yes |
| `certification_standard` | Enum | VCS, Gold Standard, CDM, Plan Vivo, etc. | No |
| `vintage_year` | Integer | Year credits are issued for | No |

**Project Timeline:**

| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `start_date` | Date | Project start date | Yes |
| `end_date` | Date | Expected project end date | No |
| `crediting_start_date` | Date | When credit generation begins | Yes |
| `crediting_end_date` | Date | When credit generation ends | Yes |

**Team & Contact:**

| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `project_lead_name` | String | Primary contact person | Yes |
| `project_lead_email` | String | Contact email | Yes |
| `project_lead_phone` | String | Contact phone | No |
| `team_size` | Integer | Number of people working on project | No |
| `partners` | JSON[] | List of partner organizations | No |

**Documentation:**

| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `project_design_document` | File | PDD or equivalent | Yes |
| `validation_report` | File | Third-party validation (if available) | No |
| `monitoring_report` | File | Monitoring data | No |
| `land_ownership_proof` | File | Proof of land rights | Yes |
| `environmental_impact` | File | Environmental impact assessment | No |
| `additional_documents` | File[] | Any other supporting docs | No |

**Co-Benefits (Optional):**

| Field | Type | Description | Required |
|-------|------|-------------|----------|
| `sdg_goals` | Integer[] | UN SDG goals addressed (1-17) | No |
| `biodiversity_impact` | Text | Impact on local biodiversity | No |
| `community_impact` | Text | Impact on local communities | No |
| `jobs_created` | Integer | Number of jobs created | No |

### 3.4 Allowed Categories

The following categories must be supported:

| Category Key | Display Name | Description | Sub-categories |
|--------------|--------------|-------------|----------------|
| `forestry` | Forestry | Forest-related carbon sequestration | reforestation, afforestation, avoided_deforestation, forest_management |
| `agriculture` | Agriculture | Farming and soil carbon | regenerative_farming, soil_carbon, agroforestry, rice_cultivation |
| `renewable_energy` | Renewable Energy | Clean energy projects | solar, wind, hydro, geothermal, biomass |
| `waste_management` | Waste Management | Emissions from waste | landfill_gas, composting, waste_to_energy, recycling |
| `blue_carbon` | Blue Carbon | Ocean and coastal | mangroves, seagrass, coastal_wetlands, kelp_forests |
| `industrial` | Industrial | Industrial emissions reduction | energy_efficiency, process_improvement, carbon_capture |

### 3.5 Certification Standards

| Standard Key | Full Name |
|--------------|-----------|
| `vcs` | Verified Carbon Standard |
| `gold_standard` | Gold Standard |
| `cdm` | Clean Development Mechanism |
| `plan_vivo` | Plan Vivo |
| `acr` | American Carbon Registry |
| `car` | Climate Action Reserve |
| `none` | No certification (self-reported) |

### 3.6 Project Registration Flow

```
1. Developer navigates to "Register Project"
2. System checks profile completion:
   - If incomplete: Redirect to complete profile first
   - If complete: Show registration form
3. Developer fills multi-step form:
   Step 1: Basic Information (name, description, category)
   Step 2: Location & Geography
   Step 3: Carbon Credit Details
   Step 4: Timeline
   Step 5: Team & Contact
   Step 6: Documentation Upload
   Step 7: Co-Benefits (optional)
4. System validates all fields at each step
5. Developer can save draft at any step
6. Developer reviews full submission summary
7. Developer sees fee breakdown:
   - Platform fee: [configurable, default 100 ADA]
   - Transaction fee: ~2-3 ADA
8. Developer clicks "Submit"
9. System saves project with status "draft"
10. System initiates on-chain transaction:
    - Pay platform fee
    - Mint Project NFT
    - Send NFT to validator contract
11. Wallet prompts for signature
12. Developer signs transaction
13. System waits for confirmation
14. On success:
    - Update project status to "submitted"
    - Store transaction hash
    - Send confirmation email
    - Show success message
15. On failure:
    - Show error message
    - Project remains in "draft" status
```

### 3.7 Project Data to Store

**Off-chain (Database):**

| Field | Type | Description |
|-------|------|-------------|
| `project_id` | UUID | Unique identifier |
| `user_id` | UUID | FK to users table |
| `name` | String | Project name |
| `short_description` | String | Brief summary |
| `description` | Text | Full project description |
| `category` | String | Category key |
| `sub_category` | String | Sub-category |
| `country` | String | Country code |
| `region` | String | Region/state |
| `location_name` | String | Location name |
| `coordinates` | JSON | {lat, lng} |
| `area_size` | Decimal | Project area |
| `area_unit` | String | Unit of measurement |
| `expected_credits` | Integer | Annual credits |
| `credit_period_years` | Integer | Crediting period |
| `methodology` | String | Carbon methodology |
| `certification_standard` | String | Certification (if any) |
| `start_date` | Date | Project start |
| `crediting_start_date` | Date | Credit period start |
| `crediting_end_date` | Date | Credit period end |
| `project_lead_name` | String | Contact name |
| `project_lead_email` | String | Contact email |
| `sdg_goals` | JSON | Array of SDG numbers |
| `status` | Enum | draft, submitted, in_review, verified, rejected |
| `tx_hash` | String | On-chain transaction hash (null until submitted) |
| `created_at` | Timestamp | Creation time |
| `updated_at` | Timestamp | Last update time |
| `submitted_at` | Timestamp | When submitted on-chain |

**On-chain (Project Datum):**

| Field | Description |
|-------|-------------|
| `developer` | Wallet credentials (payment key hash, stake key hash) |
| `document_hash` | Hash of all uploaded documents combined |
| `category` | Project category |
| `asset_name` | Project identifier |
| `expected_credits` | Expected COT amount |
| `fees_paid` | Platform fee amount |

---

## 4. Module 3: Project NFT Minting

### 4.1 Objective

Mint a unique NFT representing each submitted project, locked in validator contract.

### 4.2 Functional Requirements

| ID | Requirement |
|----|-------------|
| NFT-01 | Each project submission must mint exactly 1 NFT |
| NFT-02 | NFT must be sent to validator contract, not user wallet |
| NFT-03 | NFT must have project data attached as datum |
| NFT-04 | NFT must have CIP-25 compliant metadata |
| NFT-05 | NFT policy must only allow minting if category is valid |
| NFT-06 | NFT policy must only allow minting if platform fee is paid |
| NFT-07 | NFT must be burned after voting (regardless of outcome) |

### 4.3 Project NFT Structure

**Token Identity:**

| Property | Value |
|----------|-------|
| Policy ID | Hash of minting policy |
| Asset Name | Project name (hex encoded) |
| Quantity | 1 (unique) |

**CIP-25 Metadata:**

```
{
  "721": {
    "<policy_id>": {
      "<asset_name>": {
        "name": "<project name>",
        "image": "<thumbnail URL or IPFS hash>",
        "description": "<short description>",
        "category": "<category>",
        "standards": ["<certification standards>"]
      }
    }
  }
}
```

### 4.4 NFT Lifecycle

```
MINT (Project Submission)
    │
    ▼
LOCKED (At Validator Contract)
    │
    ├──── Validators Vote ────┐
    │                         │
    ▼                         ▼
BURN (Approved)          BURN (Rejected)
    │                         │
    ▼                         ▼
COT Minted              No COT Issued
```

### 4.5 Minting Validation Rules

The minting policy must enforce:

1. **Category Check**: Project category must exist in platform configuration
2. **Fee Check**: Correct platform fee must be sent to fee address
3. **Destination Check**: NFT must be sent to validator contract address
4. **Datum Check**: Valid project datum must be attached
5. **Quantity Check**: Exactly 1 token must be minted

---

## 5. Module 4: Validator Voting

### 5.1 Objective

Allow validators to review and vote on submitted projects.

### 5.2 Functional Requirements

| ID | Requirement |
|----|-------------|
| VV-01 | Only users with "validator" role can vote |
| VV-02 | Validators must be able to view pending projects |
| VV-03 | Validators must be able to view project details and documents |
| VV-04 | Validators can vote "Yes" (approve) or "No" (reject) |
| VV-05 | Each validator can only vote once per project |
| VV-06 | Validators cannot vote on their own projects |
| VV-07 | Quorum must be configurable (default: 3 of 5 validators) |
| VV-08 | When quorum is reached, verification is finalized |

### 5.3 Verification States

| Status | Description |
|--------|-------------|
| `pending` | Submitted, waiting for review |
| `in_review` | At least one validator has viewed |
| `approved` | Quorum reached with majority "Yes" votes |
| `rejected` | Quorum reached with majority "No" votes |

### 5.4 Voting Flow

```
1. Validator views verification dashboard
2. Validator sees list of pending projects
3. Validator clicks on a project to review
4. Validator views:
   - Project details
   - Uploaded documents
   - Current vote tally (anonymous)
5. Validator clicks "Approve" or "Reject"
6. System creates vote transaction
7. Wallet prompts for signature
8. Validator signs
9. System records vote:
   - On-chain: Part of multisig witness
   - Off-chain: Vote record in database
10. If quorum reached:
    - Finalize verification
    - Execute outcome transaction
```

### 5.5 Vote Data to Store

| Field | Type | Description |
|-------|------|-------------|
| `vote_id` | UUID | Unique identifier |
| `verification_id` | UUID | FK to verification |
| `user_id` | UUID | FK to validator user |
| `vote_value` | Enum | approve, reject |
| `voted_at` | Timestamp | When vote was cast |

### 5.6 Multisig Requirements

- Number of required signatures: Configurable (default: 3)
- Total validator pool: Configurable (default: 5)
- Each validator's vote is recorded as a signature
- Final transaction requires multisig threshold

---

## 6. Module 5: COT Token Issuance

### 6.1 Objective

Mint Carbon Offset Tokens (COT) for approved projects and send to developer.

### 6.2 Functional Requirements

| ID | Requirement |
|----|-------------|
| COT-01 | COT must only be minted when project is approved |
| COT-02 | COT minting must burn the Project NFT |
| COT-03 | COT must be sent to the project developer's wallet |
| COT-04 | COT amount must be configurable per project |
| COT-05 | COT must be tradeable (can be transferred) |
| COT-06 | COT can be burned to offset emissions |
| COT-07 | All COT actions must be trackable |

### 6.3 COT Token Structure

| Property | Value |
|----------|-------|
| Policy ID | Hash of COT minting policy |
| Asset Name | Derived from project output reference |
| Quantity | Configurable (represents carbon credits) |

### 6.4 COT Issuance Flow

```
1. Verification reaches "approved" status
2. System builds finalization transaction:
   - Input: Project NFT UTxO from validator contract
   - Mint: COT tokens (positive amount)
   - Burn: Project NFT (negative amount)
   - Output: COT tokens to developer wallet
3. Multisig validators sign transaction
4. Transaction submitted
5. On confirmation:
   - Project status → "verified"
   - COT record created in database
   - Developer receives COT tokens
```

### 6.5 COT Data to Store

| Field | Type | Description |
|-------|------|-------------|
| `asset_id` | String | Full token unit (policy_id + asset_name) |
| `project_id` | UUID | FK to project |
| `minted_for` | UUID | FK to developer user |
| `amount` | Integer | Number of tokens minted |
| `tx_hash` | String | Minting transaction hash |
| `created_at` | Timestamp | When minted |

---

## 7. Module 6: Token Lifecycle Tracking

### 7.1 Objective

Track all token actions (mint, transfer, burn) for complete audit trail.

### 7.2 Functional Requirements

| ID | Requirement |
|----|-------------|
| TL-01 | All COT mints must be recorded |
| TL-02 | All COT transfers must be recorded |
| TL-03 | All COT burns must be recorded |
| TL-04 | Each action must have transaction hash |
| TL-05 | Token balances must be derivable from actions |
| TL-06 | Token status must be trackable (active, transferred, retired) |

### 7.3 Action Types

| Action | Description | Sender | Receiver |
|--------|-------------|--------|----------|
| `mint` | New tokens created | null | Developer address |
| `transfer` | Tokens moved between wallets | Sender address | Receiver address |
| `burn` | Tokens destroyed (offset) | Holder address | null |

### 7.4 Token Action Data to Store

| Field | Type | Description |
|-------|------|-------------|
| `action_id` | UUID | Unique identifier |
| `asset_id` | String | Token unit |
| `action_type` | Enum | mint, transfer, burn |
| `sender_address` | String | From address (null if mint) |
| `receiver_address` | String | To address (null if burn) |
| `amount` | Integer | Token quantity |
| `tx_hash` | String | Transaction hash |
| `status` | Enum | active, transferred, retired |
| `created_at` | Timestamp | Action timestamp |

### 7.5 Token Status Flow

```
MINT (status: active)
    │
    ▼
TRANSFER (status: transferred)
    │
    ├── TRANSFER (continues as "transferred")
    │
    ▼
BURN (status: retired)
```

### 7.6 Balance Calculation

User balance for a token = SUM of received amounts - SUM of sent amounts

```
Received = mints to address + transfers to address
Sent = burns from address + transfers from address
Balance = Received - Sent
```

---

## 8. Data Models

### 8.1 Entity Relationship Overview

```
┌─────────┐       ┌──────────┐       ┌──────────────┐
│  Users  │──────<│ Projects │──────<│ Verification │
└─────────┘       └──────────┘       └──────────────┘
     │                 │                    │
     │                 │                    │
     ▼                 ▼                    ▼
┌─────────┐       ┌─────────┐         ┌─────────┐
│  Votes  │       │  COT    │         │  Votes  │
└─────────┘       │ Tokens  │         └─────────┘
                  └─────────┘
                       │
                       ▼
                  ┌─────────┐
                  │ Actions │
                  └─────────┘
```

### 8.2 Users Table

```
users
│
├── CORE IDENTITY
├── user_id (PK, UUID)
├── wallet_address (String, unique, not null)
├── stake_address (String, nullable)
├── role (Enum: developer, validator, admin, default: developer)
├── created_at (Timestamp)
├── updated_at (Timestamp)
├── last_login (Timestamp, nullable)
│
├── PROFILE INFORMATION
├── display_name (String, max 50, nullable)
├── email (String, nullable)
├── email_verified (Boolean, default: false)
├── avatar_url (String, nullable)
├── bio (Text, max 500, nullable)
├── website (String, nullable)
├── social_links (JSON, nullable)
│
├── ORGANIZATION DETAILS
├── organization_name (String, nullable)
├── organization_type (Enum: individual, company, ngo, government, cooperative, other, nullable)
├── organization_country (String, ISO 3166-1, nullable)
├── organization_registration_number (String, nullable)
├── organization_address (Text, nullable)
├── organization_logo_url (String, nullable)
│
├── KYC/VERIFICATION
├── kyc_status (Enum: not_started, pending, approved, rejected, default: not_started)
├── kyc_submitted_at (Timestamp, nullable)
├── kyc_verified_at (Timestamp, nullable)
├── kyc_rejection_reason (Text, nullable)
├── kyc_documents (JSON, nullable)
│
└── ACTIVITY METRICS (computed/cached)
    ├── projects_count (Integer, default: 0)
    ├── projects_verified_count (Integer, default: 0)
    ├── total_cot_minted (Integer, default: 0)
    └── votes_cast_count (Integer, default: 0)

Constraints:
- Unique(wallet_address)
- Check(role IN ('developer', 'validator', 'admin'))
- Check(kyc_status IN ('not_started', 'pending', 'approved', 'rejected'))
- Check(organization_type IN ('individual', 'company', 'ngo', 'government', 'cooperative', 'other'))
```

### 8.3 Projects Table

```
projects
│
├── CORE IDENTITY
├── project_id (PK, UUID)
├── user_id (FK → users, not null)
├── status (Enum: draft, submitted, in_review, verified, rejected, default: draft)
├── tx_hash (String, nullable)
├── created_at (Timestamp)
├── updated_at (Timestamp)
├── submitted_at (Timestamp, nullable)
│
├── BASIC INFORMATION
├── name (String, max 100, not null)
├── short_description (String, max 250, not null)
├── description (Text, not null)
├── category (String, not null)
├── sub_category (String, nullable)
├── thumbnail_url (String, nullable)
├── gallery_urls (JSON, nullable)
│
├── LOCATION & GEOGRAPHY
├── country (String, ISO 3166-1, not null)
├── region (String, not null)
├── location_name (String, not null)
├── coordinates (JSON: {lat, lng}, nullable)
├── area_size (Decimal, not null)
├── area_unit (Enum: hectares, acres, sq_km, default: hectares)
│
├── CARBON CREDIT DETAILS
├── expected_credits (Integer, not null)
├── credit_period_years (Integer, not null)
├── total_expected_credits (Integer, computed)
├── methodology (String, not null)
├── certification_standard (String, nullable)
├── vintage_year (Integer, nullable)
│
├── PROJECT TIMELINE
├── start_date (Date, not null)
├── end_date (Date, nullable)
├── crediting_start_date (Date, not null)
├── crediting_end_date (Date, not null)
│
├── TEAM & CONTACT
├── project_lead_name (String, not null)
├── project_lead_email (String, not null)
├── project_lead_phone (String, nullable)
├── team_size (Integer, nullable)
├── partners (JSON, nullable)
│
└── CO-BENEFITS
    ├── sdg_goals (JSON: Integer[], nullable)
    ├── biodiversity_impact (Text, nullable)
    ├── community_impact (Text, nullable)
    └── jobs_created (Integer, nullable)

Constraints:
- FK(user_id) REFERENCES users(user_id)
- Check(status IN ('draft', 'submitted', 'in_review', 'verified', 'rejected'))
- Check(area_unit IN ('hectares', 'acres', 'sq_km'))
- Check(expected_credits > 0)
- Check(credit_period_years > 0)
- Check(crediting_end_date > crediting_start_date)
```

### 8.4 Project Documents Table

```
project_documents
├── document_id (PK, UUID)
├── project_id (FK → projects, not null)
├── document_type (Enum: pdd, validation_report, monitoring_report, land_ownership, environmental_impact, other)
├── file_name (String, not null)
├── file_url (String, not null)
├── file_size (Integer, bytes)
├── file_hash (String, SHA-256)
├── uploaded_at (Timestamp)
└── is_required (Boolean, default: false)

Constraints:
- FK(project_id) REFERENCES projects(project_id) ON DELETE CASCADE
```

### 8.5 Verification Table

```
verification
├── verification_id (PK, UUID)
├── project_id (FK → projects, not null)
├── unsigned_tx (Text, CBOR encoded)
├── witness_set (Text, CBOR encoded)
├── status (Enum: pending, in_review, approved, rejected)
├── rejection_reason (Text, nullable)
└── created_at (Timestamp)
```

### 8.6 Votes Table

```
votes
├── vote_id (PK, UUID)
├── verification_id (FK → verification, not null)
├── user_id (FK → users, not null)
├── vote_value (Enum: approve, reject)
└── voted_at (Timestamp)

Constraints:
- Unique(verification_id, user_id) -- one vote per validator per project
```

### 8.7 Carbon Offset Tokens Table

```
carbon_offset_tokens
├── asset_id (PK, String)
├── project_id (FK → projects, not null)
├── minted_for (FK → users, not null)
├── amount (Integer, not null)
├── tx_hash (String, not null)
└── created_at (Timestamp)
```

### 8.8 Carbon Offset Actions Table

```
carbon_offset_actions
├── action_id (PK, UUID)
├── asset_id (String, not null)
├── action_type (Enum: mint, transfer, burn)
├── sender_address (String, nullable)
├── receiver_address (String, nullable)
├── amount (Integer, not null)
├── tx_hash (String, not null)
├── status (Enum: active, transferred, retired)
└── created_at (Timestamp)
```

---

## 9. Smart Contract Interfaces

### 9.1 Platform Configuration Contract

**Purpose**: Store platform-wide configuration data.

**Required Datum Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `fees_address` | Address | Where platform fees are sent |
| `fees_amount` | Integer | Platform fee in lovelace |
| `categories` | List<String> | Allowed project categories |
| `multisig_validators` | List<PubKeyHash> | Validator public key hashes |
| `multisig_required` | Integer | Number of required signatures |
| `cot_policy_id` | PolicyId | COT minting policy (set after deployment) |

**Required Behaviors**:

- Must be protected by identification NFT
- Updates require multisig approval

---

### 9.2 Project Minting Policy

**Purpose**: Control Project NFT minting and burning.

**Minting Conditions** (must all be true):

1. Category in datum matches allowed categories in config
2. Platform fee sent to fee address
3. NFT sent to validator contract address
4. Valid project datum attached
5. Exactly 1 token minted

**Burning Conditions** (must all be true):

1. Multisig threshold met
2. Token exists in inputs

---

### 9.3 Validator Contract

**Purpose**: Hold Project NFTs during verification.

**Spending Conditions for Approval**:

1. Multisig threshold met
2. Project NFT burned
3. COT tokens minted
4. COT sent to developer address

**Spending Conditions for Rejection**:

1. Multisig threshold met
2. Project NFT burned
3. No COT minted

---

### 9.4 COT Minting Policy

**Purpose**: Control Carbon Offset Token minting and burning.

**Minting Conditions**:

1. Associated Project NFT being burned in same transaction
2. Multisig approval present
3. Tokens sent to project developer

**Burning Conditions**:

1. Token holder signature present
2. (Optional) Equal CET burned for offset

---

## 10. Business Rules

### 10.1 Fee Structure

| Fee Type | Amount | Recipient |
|----------|--------|-----------|
| Platform Fee | 100 ADA (configurable) | Platform fee address |
| Transaction Fee | ~2-3 ADA | Cardano network |

### 10.2 Voting Rules

| Rule | Value |
|------|-------|
| Total Validators | 5 (configurable) |
| Required for Approval | 3 (configurable) |
| Required for Rejection | 3 (configurable) |
| Self-voting | Not allowed |
| Double-voting | Not allowed |

### 10.3 Status Transitions

**Project Status**:

```
draft → submitted → in_review → verified
                              → rejected
```

**Allowed Transitions**:

| From | To | Trigger |
|------|----|---------|
| draft | submitted | Successful on-chain submission |
| submitted | in_review | First validator views project |
| in_review | verified | Approval quorum reached |
| in_review | rejected | Rejection quorum reached |

### 10.4 Token Rules

| Rule | COT | Project NFT |
|------|-----|-------------|
| Transferable | Yes | No (locked in contract) |
| Burnable | Yes | Yes (after voting) |
| Mintable by user | No | No |
| Quantity per project | Configurable | Exactly 1 |

---

## Summary Checklist

### Module 1: User Registration
- [ ] Wallet connection (CIP-30)
- [ ] User record creation/retrieval
- [ ] Role assignment
- [ ] Session management

### Module 2: Project Registration
- [ ] Project form with validation
- [ ] Document upload
- [ ] Category validation
- [ ] Draft saving
- [ ] Status management

### Module 3: Project NFT Minting
- [ ] Transaction building
- [ ] Fee payment
- [ ] NFT minting
- [ ] Datum attachment
- [ ] CIP-25 metadata

### Module 4: Validator Voting
- [ ] Verification dashboard
- [ ] Vote casting
- [ ] Multisig collection
- [ ] Quorum detection
- [ ] Outcome execution

### Module 5: COT Issuance
- [ ] COT minting on approval
- [ ] Project NFT burning
- [ ] Token delivery to developer
- [ ] Token record creation

### Module 6: Token Lifecycle
- [ ] Action recording (mint/transfer/burn)
- [ ] Balance calculation
- [ ] Status tracking
- [ ] Audit trail

---

*Document Version: 1.0*
*Last Updated: December 2024*
