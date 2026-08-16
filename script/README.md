# Deployment

The executable form of [docs/16-deployment.md](../docs/16-deployment.md). Two scripts, run in order;
everything they do is also run by CI as a test (`test/Deploy.t.sol`), through the same code — if a
script rots, the build goes red before an operator finds out on a chain.

## 0 · What the operator provides

Everything the scripts need from a human, before anything runs:

| You provide | Where to get it | Where it goes |
|---|---|---|
| A deployer key | A **fresh** key for testnet; the operations multisig for mainnet — the factory's admin is the broadcaster and is not transferable | `PRIVATE_KEY` in `.env` |
| Base Sepolia gas | [Coinbase developer faucet](https://portal.cdp.coinbase.com/products/faucet) or the [Alchemy faucet](https://www.alchemy.com/faucets/base-sepolia) — ~0.05 ETH covers the whole stack many times over | The deployer address |
| An RPC URL | The public `https://sepolia.base.org`, or an Alchemy/Infura/QuickNode endpoint | `BASE_SEPOLIA_RPC_URL` in `.env` |
| A BaseScan API key | [basescan.org/myapikey](https://basescan.org/myapikey), free account | `BASESCAN_API_KEY` in `.env` |

```bash
cp .env.example .env    # fill in the four values; .env is never committed
```

With `.env` filled, steps 1–3 below run without further decisions.

## 1 · The stack — once per chain

```bash
forge script script/Deploy.s.sol:DeployStack \
  --rpc-url base_sepolia --broadcast --verify
```

| Env | Required | Meaning |
|---|---|---|
| `ADMIN` | no — defaults to the broadcaster | Owns the offering registry and the tier-0 allowlist |

What it deploys, in doc 16's order: the cut facet and treasury implementation, the factory, the
offering registry, the tier-0 `AllowlistRegistry`, the seven shared facet implementations, the shared
rule contracts, and then registers:

| Registered | Contents |
|---|---|
| `base.v1` | Compliance, Monetary, Roles, Freeze, Lockup |
| `base+purchase.v1` | `base.v1` + ERC-1404 surface + the offering door |
| `RegD506c` | identity AND accredited AND sanctions AND MaxHolders(2000) |
| `RegS` | identity AND JurisdictionDeny(US) AND sanctions |
| `Open` | identity AND sanctions |

No emergency package: installing seizure is a deliberate act an issuer performs by cut, never a
default anyone can pick blind. No MiCA presets: `MiCARule` is parameterised by the issuer's subject,
so a MiCA regime is composed per issuance, not registered chain-wide.

**The factory's admin is the broadcaster and is not transferable** — deploy from the address (ideally
a multisig) that should govern packages, presets and the fee, permanently.

## 2 · A token — per asset

```bash
FACTORY=0x… IDENTITY_REGISTRY=0x… OFFERING_REGISTRY=0x… \
forge script script/Deploy.s.sol:DeployDemoToken \
  --rpc-url base_sepolia --broadcast
```

| Env | Required | Meaning |
|---|---|---|
| `FACTORY` | yes | From step 1 |
| `IDENTITY_REGISTRY` | yes | Any `IIdentityRegistry` — the step-1 allowlist, or an EAS / StoboxDID adapter |
| `OFFERING_REGISTRY` | no | Zero disables the token's purchase door |
| `TOKEN_NAME`, `TOKEN_SYMBOL` | no | Default `Demo Asset` / `DEMO` |
| `MAX_SUPPLY` | no | Zero = unlimited |
| `UPGRADE_DELAY` | no | **Seconds; defaults to zero.** A token with a delay and one without are different instruments — choose deliberately |
| `ISSUER_ADMIN`, `UPGRADE_ADMIN`, `SUPPLY_OPERATOR`, `COMPLIANCE_OFFICER` | no | Each defaults to the broadcaster; separate them in production |

The token is created with the `Open` preset and the `base+purchase.v1` package. The factory bakes the
token its own policy set from the preset, hands it to the compliance officer, wires the treasury and
registry, grants the four roles, and gives up every right it held — all in the one transaction.

## 3 · Verify what you deployed

Nothing here requires trusting the deployer:

```bash
# ERC-7943, from the token's own mouth
cast call $TOKEN "supportsInterface(bytes4)(bool)" 0x3edbb4c4 --rpc-url base_sepolia

# the loupe: every facet and selector actually installed
cast call $TOKEN "facets()((address,bytes4[])[])" --rpc-url base_sepolia

# seizure is provably absent: the forcedTransfer selector routes nowhere
cast call $TOKEN "facetAddress(bytes4)(address)" \
  $(cast sig "forcedTransfer(address,address,uint256,string)") --rpc-url base_sepolia

# the delay the issuer chose, and the live compliance configuration
cast call $TOKEN "upgradeDelay()(uint64)" --rpc-url base_sepolia
cast call $TOKEN "policySet()(address)" --rpc-url base_sepolia

# the factory retains nothing
cast call $TOKEN "hasRole(bytes32,address)(bool)" \
  $(cast keccak "urwa.role.upgrade_admin") $FACTORY --rpc-url base_sepolia
```

## Running a Stobox (or any branded) instance

This repository stays free of any Stobox reference — CI enforces it. An operator's instance is a
**configuration of this stack, not a fork**: run step 1 from your operations multisig, install your
identity adapter (`StoboxDIDAdapter`, `EASAdapter`, or your own `IIdentityRegistry`), register any
additional presets your regimes need, and set your fee — which every deployer can read on chain
before paying it. The passport and attestation layer arrive as separate contracts (Phase 4) and bolt
on without touching anything deployed here.
