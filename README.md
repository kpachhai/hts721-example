# HTS721 Example Suite (Hedera HTS NFT Management)

This repository demonstrates a modular, low‑bytecode approach to creating and managing **Hedera Token Service (HTS)** non‑fungible tokens through EVM smart contracts. These contracts focus on **creation, supply control, administrative actions, and irreversible key neutralization**, while leaving ordinary transfers & approvals to the native HTS ERC‑721 facade.

---

## Table of Contents

1. [Motivation](#motivation)  
2. [Architecture Overview](#architecture-overview)  
3. [Key Bits (keyMask)](#key-bits-keymask)  
4. [Contracts & Extensions](#contracts--extensions)  
5. [Simple Deployable Variants](#simple-deployable-variants)  
6. [Initialization (InitConfig)](#initialization-initconfig)  
7. [Mint / Burn Workflows](#mint--burn-workflows)  
8. [Management (KYC / Freeze / Pause / Wipe / Fees / Delete)](#management-kyc--freeze--pause--wipe--fees--delete)  
9. [Key Neutralization](#key-neutralization)  
10. [Enumeration Caveat](#enumeration-caveat)  
11. [Scripts (Deploy & Interact)](#scripts-deploy--interact)  
12. [Common Failure Codes](#common-failure-codes)  
13. [Security & Decentralization Path](#security--decentralization-path)  
14. [Development](#development)  
15. [License](#license)

---

## Motivation

Typical “wrapper” NFTs duplicate ERC‑721 logic and inflate bytecode. On Hedera, the underlying HTS NFT already exposes the canonical ERC‑721 interface. This project strips wrappers down to **the minimal surface necessary to:**

- Create a collection (one-time initialization)
- Mint / burn supply
- Apply token governance (pause, freeze, KYC, wipe)
- Update fee schedules
- Permanently relinquish control (neutralize keys)
- Provide optional naive enumeration for small sets

---

## Architecture Overview

```
                +-----------------------------+
                |         Application         |
                +-----------------------------+
                               |
                               v
+-----------------+     +---------------+     +---------------------------+
|  HTS721Core     | --> |  Extensions   | --> | Underlying HTS NFT Mirror |
| (initialize)    |     | (Mint, Mgmt,  |     | (canonical ERC-721 logic) |
|                 |     |  Neutralize,  |     +---------------------------+
|                 |     |  Enumerable)  |
+-----------------+     +---------------+
```

- **Core** only knows how to create the token & internal mint primitive.
- **Extensions** are opt‑in (supply, management, neutralization, enumeration).
- **Users** interact with the **underlying token** for transfers & approvals.

---

## Key Bits (keyMask)

| Bit | Constant | Purpose |
|-----|----------|---------|
| 1   | ADMIN  | Rotate keys, delete token, governance pivots |
| 2   | KYC    | Grant / revoke KYC |
| 4   | FREEZE | Freeze / unfreeze accounts |
| 8   | WIPE   | Wipe NFTs from accounts |
| 16  | SUPPLY | Mint / burn NFTs |
| 32  | FEE    | Update custom (royalty / fixed) fees |
| 64  | PAUSE  | Pause / unpause transfers |

> NFT creation **must** include SUPPLY (16) or HTS returns rc=180 (TOKEN_HAS_NO_SUPPLY_KEY).

Typical masks:
- Core only (still needs supply) → `ADMIN | SUPPLY`
- Mint/Burn + Pause → `ADMIN | SUPPLY | PAUSE`
- Full management → `ADMIN | KYC | FREEZE | WIPE | SUPPLY | FEE | PAUSE` (=127)

---

## Contracts & Extensions

| File | Purpose |
|------|---------|
| `HTS721Core.sol` | Initialization & internal mint primitive |
| `HTS721MintBurn.sol` | `mintTo`, `burn`, `burnFrom` |
| `HTS721Management.sol` | KYC / Freeze / Pause / Wipe / Fees / Delete |
| `HTS721KeyNeutralizerRandom.sol` | Irreversible key rotation (PRNG-based) |
| `HTS721Enumerable.sol` | Naive enumeration (small collections only) |
| `HTSCommon.sol` | Shared constants |
| `HTS721Errors.sol` | Custom error library |
| Interfaces (`/interfaces`) | Stable external surfaces for core, mint/burn, management |

---

## Simple Deployable Variants

| Contract | Composition | Use Case |
|----------|-------------|----------|
| `SimpleHTS721` | Core | Governance placeholder / future upgrade |
| `SimpleHTS721MintBurn` | Core + MintBurn (+ mgmt base) | Standard distribution + supply control |
| `SimpleHTS721Managed` | Core + MintBurn + Management + Neutralizer | Full lifecycle w/ decentralization path |
| `SimpleHTSEnumerable` | Core + MintBurn + Management + Enumerable | Small enumerated collections |

---

## Initialization (InitConfig)

```solidity
await wrapper.initialize({
  name: "Demo",
  symbol: "D1",
  memo: "phase0",
  keyMask: uint8(1 | 16 | 64), // ADMIN | SUPPLY | PAUSE
  freezeDefault: false,
  autoRenewAccount: ethers.ZeroAddress,
  autoRenewPeriod: 0
}, { value: ethers.parseEther("10") });
```

- `autoRenewAccount == 0` → wrapper treasury becomes autoRenew account.
- `autoRenewPeriod == 0` → default constant (7776000 seconds) used.
- `metadata` (during mint) limited to ≤ 100 bytes per HTS rules.

---

## Mint / Burn Workflows

| Action | Steps |
|--------|-------|
| Mint to user | `mintTo(user, metadata)` (wrapper supply key), wrapper transfers serial from treasury to user |
| Burn (treasury) | `burn(serial)` (ensures treasury holds serial) |
| Burn (user-owned) | User grants `approve(wrapper, serial)` → owner calls `burnFrom(user, serial)` |
| Pull then redistribute (custom) | Same pattern as burnFrom, but transfer elsewhere instead of burn (extend contract) |

---

## Management (KYC / Freeze / Pause / Wipe / Fees / Delete)

| Function | Requires Key | Notes |
|----------|--------------|-------|
| `grantKyc / revokeKyc` | KYC | Reverts if token not associated w/ account |
| `freeze / unfreeze` | FREEZE | Blocks transfers while frozen |
| `pause / unpause` | PAUSE | Pause blocks *all* token transfers (HTS-level) |
| `wipe(account, serials[])` | WIPE | Destroys specified serials from account |
| `updateNftRoyaltyFees(fixedBytes, royaltyBytes)` | FEE | ABI-packed arrays reduce code size |
| `deleteToken()` | ADMIN | All NFTs must be gone / prerequisites satisfied |

---

## Key Neutralization

> Renders keys permanently unusable by rotating them to random Ed25519 public keys derived from a single PRNG seed.

```solidity
neutralizeKeysRandom(
  Flags({
    admin:false, kyc:false,
    freeze:true, wipe:true,
    supply:false, fee:false, pause:false
  }),
  false
);
```

- Emits `KeysNeutralized(mask, rootSeed)`
- Auditors recompute derived pubkeys deterministically
- Neutralize `ADMIN` last (requires `confirmAdmin=true`)

---

## Enumeration Caveat

`HTS721Enumerable` linearly scans `1.._lastSerial`.

| Function | Complexity | Warning |
|----------|------------|---------|
| `tokenByIndex(i)` | O(lastSerial) worst-case | Use only for small sets |
| `tokensOfOwner(owner, maxScan)` | O(maxScan) | Provide sensible `maxScan` |
| `setEnumerationScanLimit(limit)` | Admin guard | Prevent pathological gas usage |

Use an off-chain indexer (Mirror Node / custom service) for large collections.

---

## Scripts (Deploy & Interact)

| Script | Description |
|--------|-------------|
| `deployCore.ts` | Deploy + initialize minimal wrapper |
| `deployMintBurn.ts` | Deploy mint/burn enabled wrapper |
| `deployManaged.ts` | Full management & neutralization |
| `deployEnumerable.ts` | Enumeration variant |
| `interactCore.ts` | Confirms minimal surface (no mint/burn) |
| `interactMintBurn.ts` | Mint, approval, burnFrom flows |
| `interactManaged.ts` | KYC, pause, freeze, neutralize, burn, delete attempt |
| `interactEnumerable.ts` | Mint + enumerate + underlying transfer |

**NOTE**: Replace placeholder addresses (`0xReplaceWith...`) post‑deployment.

---

## Common Failure Codes

| RC | Meaning | Fix |
|----|---------|-----|
| 180 | TOKEN_HAS_NO_SUPPLY_KEY | Include `SUPPLY` bit (16) in keyMask |
| 184 | TOKEN_NOT_ASSOCIATED_TO_ACCOUNT | User must associate underlying token first |
| 194 | TOKEN_ALREADY_ASSOCIATED | Benign – ignore in association flows |
| Other non‑22 | Generic failure | Inspect `HtsCallFailed` revert (selector + rc) |

---

## Security & Decentralization Path

1. Launch with full key set: `ADMIN|SUPPLY|FEE|PAUSE|FREEZE|WIPE|KYC`
2. Finalize royalties → neutralize FEE
3. Finish minting → neutralize SUPPLY
4. Decide on moderation stance → neutralize FREEZE / WIPE / KYC if no longer needed
5. Finalize operational readiness → neutralize PAUSE
6. Escrow / verify distribution → neutralize ADMIN (token immutable)

Maintain a public NOTION/markdown log of each neutralization tx (mask + rootSeed).

---

## Development

### Install & Build

```bash
npm install
npx hardhat build
```

### Recommended Hardhat Optimizer

`hardhat.config.ts`:

```ts
solidity: {
  version: "0.8.28",
  settings: {
    optimizer: { enabled: true, runs: 50 },
    viaIR: false
  }
}
```

Switch to `viaIR: true` only if you encounter deeper stack limits beyond `InitConfig`.

### Run a Deploy

```bash
npx hardhat run scripts/deploy_managed.ts --network testnet
```

### Interact

```bash
npx hardhat run scripts/interact_managed.ts --network testnet
```

---

## Example Neutralization (TS)

```ts
await managed.neutralizeKeysRandom(
  {
    admin: false,
    kyc: false,
    freeze: true,
    wipe: true,
    supply: false,
    fee: false,
    pause: false
  },
  false
);
```

---

## FAQ

**Q: Can I add ERC‑721 pass‑through later?**  
Yes. You’d build a separate “Vault” layer that holds all serials and implements virtual ownership; not included here to keep baseline lean.

**Q: How do I list NFTs on a marketplace?**  
Point marketplace indexing to the underlying HTS token (mirror) address; all standard ERC‑721 events originate there.

**Q: What happens if I neutralize the SUPPLY key too early?**  
No further minting is possible. Redeploy if you need more supply—cannot revert.

---

## License

Apache-2.0.

---

**See also:**  
- [`docs/1. hts-standard.md`](./docs/1.%20hts-standard.md) – Deep dive into the architectural standard  
- [`docs/2. simplehts721.md`](./docs/2.%20simplehts721.md) – Guide to simple example contracts  

Happy building on Hedera! 🚀