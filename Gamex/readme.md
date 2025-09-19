# Gaming Loot Box Economy Smart Contract

A Clarity smart contract that enables creator royalties for rare game items and skins, implementing a complete loot box economy with developer revenue sharing.

## Overview

This contract allows game developers to create digital items with built-in royalty systems, where original creators and contributing developers earn ongoing revenue from secondary market trades. Perfect for gaming ecosystems, NFT marketplaces, and digital collectibles.

## Features

### Core Functionality
- **Item Creation**: Lead designers can create unique game items with custom royalty rates
- **Developer Collaboration**: Add multiple developers to items with proportional revenue sharing
- **Loot Box Minting**: Players can mint items by paying the market value
- **Marketplace Trading**: Secure trading with automatic royalty distribution
- **Royalty Claims**: Developers can claim accumulated rewards from trades

### Security Features
- Ownership tracking and validation
- Protection against self-trading
- Unchecked input validation (fixes security warnings)
- Maximum royalty caps (40%)
- Minting prevention for already-minted items

## Contract Structure

### Constants
```clarity
MAX-CREATOR-ROYALTY: 400 (40%)
LOOT-BASIS: 1000 (100% = 1000 basis points)
```

### Error Codes
- `ERR-UNAUTHORIZED-USER (100)`: User not authorized for this action
- `ERR-ITEM-DOES-NOT-EXIST (101)`: Item ID doesn't exist
- `ERR-PARAMETER-ERROR (102)`: Invalid parameter provided
- `ERR-ALREADY-MINTED (103)`: Item already minted
- `ERR-WALLET-INSUFFICIENT (104)`: Insufficient STX balance
- `ERR-NO-LOOT-REWARDS (105)`: No rewards to claim
- `ERR-INVALID-OWNER (106)`: Invalid ownership verification

## Usage Guide

### 1. Creating a Game Item

```clarity
(contract-call? .gaming-contract create-item 
  "Legendary Sword of Fire" 
  u1000000  ;; 1 STX market value
  u250)     ;; 25% royalty rate
```

**Parameters:**
- `item-name`: UTF-8 string (max 128 chars)
- `market-value`: Price in microSTX (1 STX = 1,000,000 microSTX)
- `creator-royalty`: Royalty percentage in basis points (250 = 25%)

### 2. Adding Developers

```clarity
(contract-call? .gaming-contract add-developer
  u1                    ;; item-id
  'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7  ;; developer principal
  u200                  ;; 20% share of royalties
  "animator")           ;; specialty
```

**Parameters:**
- `item-id`: The item to add developer to
- `developer`: Principal address of developer
- `creation-share`: Share of royalties in basis points
- `specialty`: ASCII string describing role (max 32 chars)

### 3. Minting from Loot Box

```clarity
(contract-call? .gaming-contract mint-from-lootbox u1)
```

Players pay the market value to mint and own the item.

### 4. Marketplace Trading

**Option A: Simplified Trading**
```clarity
(contract-call? .gaming-contract marketplace-trade
  u1        ;; item-id
  u1200000) ;; trade amount in microSTX
```

**Option B: Verified Trading**
```clarity
(contract-call? .gaming-contract marketplace-trade-verified
  u1                                              ;; item-id
  'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7     ;; previous owner
  u1200000)                                       ;; trade amount
```

### 5. Claiming Rewards

```clarity
(contract-call? .gaming-contract claim-loot-rewards u1)
```

Developers can claim accumulated royalties from trades.

### 6. Ownership Transfer

```clarity
(contract-call? .gaming-contract transfer-ownership
  u1                                              ;; item-id
  'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)     ;; new owner
```

## Read-Only Functions

### Get Item Information
```clarity
(contract-call? .gaming-contract get-item u1)
```
Returns: `{ item-name, lead-designer, current-owner, market-value, creator-royalty, minted, tradeable }`

### Get Developer Information
```clarity
(contract-call? .gaming-contract get-developer u1 'SP...)
```
Returns: `{ creation-share, specialty }`

### Check Rewards
```clarity
(contract-call? .gaming-contract get-loot-rewards u1 'SP...)
```
Returns: `{ reward-balance }`

### Get Current Owner
```clarity
(contract-call? .gaming-contract get-current-owner u1)
```
Returns: `(optional principal)`

## Economic Model

### Revenue Distribution
1. **Minting**: 100% goes to lead designer
2. **Trading**: 
   - Creator royalty % goes to developers (split by creation-share)
   - Remainder goes to previous owner

### Example Calculation
- Item trades for 1.2 STX with 25% royalty
- Royalties: 0.3 STX distributed to developers
- Seller receives: 0.9 STX
- If 3 developers with shares (600, 200, 200):
  - Dev 1: 0.18 STX (60%)
  - Dev 2: 0.06 STX (20%)  
  - Dev 3: 0.06 STX (20%)

## Security Considerations

### Ownership Validation
- Contract maintains authoritative ownership records
- All trades validate against stored ownership data
- Prevents self-trading and invalid ownership claims

### Input Validation
- All parameters validated for correctness
- Protection against overflow/underflow
- Maximum royalty caps enforced

### Access Control
- Only lead designers can add developers
- Only current owners can transfer items
- Only lead designers can toggle tradeable status

## Deployment Instructions

1. **Deploy Contract**
   ```bash
   clarinet deploy --network testnet
   ```

2. **Initialize Items**
   - Create your first game items using `create-item`
   - Add collaborating developers with `add-developer`

3. **Integration**
   - Connect to your game's marketplace
   - Implement loot box mechanics
   - Set up royalty distribution UI

## Testing

### Test Scenarios
- [ ] Create item with valid parameters
- [ ] Add developers with proper share allocation
- [ ] Mint items and verify ownership
- [ ] Execute trades and verify royalty distribution
- [ ] Claim rewards and verify balances
- [ ] Test ownership transfer functionality
- [ ] Verify security validations

### Example Test Commands
```bash
clarinet test
clarinet console
```

## Integration Examples

### Game Integration
```javascript
// Mint item when player opens loot box
const mintResult = await contractCall({
  contractAddress: 'ST1234...',
  contractName: 'gaming-contract',
  functionName: 'mint-from-lootbox',
  functionArgs: [uintCV(itemId)],
});
```

### Marketplace Integration
```javascript
// Execute trade on marketplace
const tradeResult = await contractCall({
  contractAddress: 'ST1234...',
  contractName: 'gaming-contract',
  functionName: 'marketplace-trade',
  functionArgs: [uintCV(itemId), uintCV(tradeAmount)],
});
```
