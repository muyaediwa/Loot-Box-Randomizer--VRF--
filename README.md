# 🎁 Loot Box Randomizer with VRF

A clean, educational Clarity smart contract implementing a loot box system with verifiable random function (VRF) concepts! 🎲

## 🌟 Overview

This contract demonstrates blockchain randomness using block hashes and timestamps to create an engaging loot box experience. Perfect for learning VRF concepts and probability distribution in smart contracts.

## ✨ Features

- 🎁 **Loot Box Mechanics**: Purchase and open mystery boxes
- 🎯 **5-Tier Rarity System**: From common to legendary items
- 🔐 **VRF-Style Randomness**: Block hash + timestamp seed generation
- 📦 **Inventory Management**: Track user item collections
- ⚙️ **Admin Controls**: Add items and manage contract settings
- 📊 **Analytics**: Comprehensive read-only functions

## 🎮 Rarity Distribution

| Rarity | Percentage | Description |
|--------|------------|-------------|
| 🟢 Common (1) | 60% | Basic items |
| 🔵 Uncommon (2) | 25% | Decent finds |
| 🟣 Rare (3) | 10% | Notable items |
| 🟠 Epic (4) | 4% | Powerful gear |
| 🔴 Legendary (5) | 1% | Ultimate treasures |

## 🚀 Quick Start

### Prerequisites
- Clarinet CLI installed
- Stacks wallet for testing

### Setup Commands

```bash
# Initialize contract
clarinet console
```

```clarity
# 1. Initialize rarity pools
(contract-call? .loot-box-randomizer initialize-rarity-pools)

# 2. Add some items (owner only)
(contract-call? .loot-box-randomizer add-item "Basic Sword" u1 u100)
(contract-call? .loot-box-randomizer add-item "Magic Potion" u2 u300)
(contract-call? .loot-box-randomizer add-item "Dragon Scale" u4 u5000)
(contract-call? .loot-box-randomizer add-item "Legendary Artifact" u5 u25000)
```

## 📋 Core Functions

### 🛒 Player Actions

**Purchase a Loot Box**
```clarity
(contract-call? .loot-box-randomizer purchase-box)
```

**Open Your Box**
```clarity
(contract-call? .loot-box-randomizer open-box u1)
```

**Check Your Inventory**
```clarity
(contract-call? .loot-box-randomizer get-user-item-count 'ST1EXAMPLE u1)
```

### 👑 Admin Functions

**Add New Items**
```clarity
(contract-call? .loot-box-randomizer add-item "Item Name" u3 u1000)
```

**Set Box Price**
```clarity
(contract-call? .loot-box-randomizer set-box-price u2000000)
```

**Update VRF Seed**
```clarity
(contract-call? .loot-box-randomizer update-vrf-seed u67890)
```

## 🔍 Read-Only Functions

### Box Information
- `get-box-info`: Get box details (owner, opened status)
- `get-box-reward`: See what was inside an opened box
- `is-box-opened`: Check if a box has been opened

### Item & Inventory
- `get-item-info`: View item details (name, rarity, value)
- `get-user-item-count`: Check how many of each item a user owns
- `get-rarity-pool`: See all items in a rarity tier

### Contract Stats
- `get-total-boxes`: Total boxes purchased
- `get-total-items`: Total item types created
- `get-current-box-price`: Current purchase price
- `get-current-vrf-seed`: Current randomness seed

### 🎲 Testing Randomness
- `preview-rarity-roll`: Test rarity determination
- `simulate-opening`: Preview what opening would yield

## 🔧 VRF Implementation

The contract uses a hybrid approach for randomness:

1. **Seed Evolution**: Internal seed updates with each use
2. **Block Hash Integration**: Uses previous block's VRF seed hash
3. **Temporal Mixing**: Combines with block height for uniqueness

```clarity
# Example randomness generation
(generate-randomness) # Returns updated seed value
(determine-rarity seed) # Converts to rarity (1-5)
```

## 🧪 Testing Workflow

```bash
# Test the contract
clarinet test

# Check contract syntax
clarinet check

# Deploy to testnet
clarinet deploy --testnet
```

## 🎯 Learning Objectives

This contract teaches:
- ✅ **VRF Concepts**: Understanding blockchain randomness
- ✅ **Probability Distribution**: Weighted random selection
- ✅ **State Management**: Complex data structures in Clarity
- ✅ **Access Control**: Owner vs user permissions
- ✅ **Economic Design**: Token-based purchasing mechanics

## ⚠️ Important Notes

- Uses **pseudo-randomness** for educational purposes
- Block hash dependency creates some predictability
- For production, consider Chainlink VRF or similar oracles
- Always test thoroughly before mainnet deployment

## 📚 Contract Structure

- **185+ lines** of clean Clarity code
- **8 error constants** for proper error handling
- **5 data maps** for comprehensive state management
- **15+ read-only functions** for data access
- **Rarity pools** supporting up to 20 items per tier

## 🤝 Contributing

Found a bug or want to add features? PRs welcome! 

## 📄 License

MIT License - Build, learn, and share freely! 🚀

---

*Happy looting! May RNG be ever in your favor* 🍀✨
