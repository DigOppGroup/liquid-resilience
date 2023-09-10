# Liquid Resilience Protocol

> Liquid Resilience is a Treasury Management Solution created by Digital Opportunities Group.

Smart contracts are the next evolution in treasure management solutions.

## Testing

### Unit & Integration Tests

To run your tests with Forge against the Optimism protocol, use the following command:

```bash
# Optimism Mainnet
forge test -vv --fork-url https://mainnet.optimism.io/

# Optimism Fork
forge test -vv --fork-url {FORK_URL}
```

### Linting & Static Analysis

The project is set up to use both [solhint](https://github.com/protofire/solhint) and [slither](https://github.com/crytic/slither) for linting and static analysis.

The tools can each be run with the following commands:

```bash
# slither
npm run lint:slither

# solhint
npm run lint:sol
```

## Deployment

### Local Deployment

```bash
anvil --fork-url {FORK_URL}
# get your private key from the anvil output
forge script script/DeployVaultFactory.s.sol:DeployVaultFactory --fork-url http://localhost:8545 --broadcast --private-keys $DEPLOYER_PRIVATE_KEY
```

```bash
source .env
forge script script/DeployVaultFactory.s.sol:DeployVaultFactory --broadcast --slow --rpc-url https://mainnet.optimism.io/ --verify -vvvv --private-keys $DEPLOYER_PRIVATE_KEY
```
