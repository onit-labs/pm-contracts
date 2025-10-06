# Onit Prediction Market Contracts

Onit is a prediction market protocol which uses an 'Infinite Outcome Dynamic Pari-mutuel Market' (IODPM) mechanism. This mechanism makes Onit more expressive than existing markets, and enables everything from binary, to numerical, to normal distribution, to multi-select questions.


## Concepts

### Dynamic Pari-Mutuel Market
Pari-Mutuel markets are markets where funds are redistributed from some traders to others, they are common in sports betting where winners split a pot funded by all bettors. They benefit from 'infinite liquidity' meaning that you can make a bet at any point without waiting for someone to take the other side (like in order books). Their downside is that for events where information arrives over time, there is limited incentive to bet until immediately before the event.

[Dynamic pari-mutuel markets](http://dpennock.com/papers/pennock-ec-2004-dynamic-parimutuel.pdf) (DPMs) relate the price of an outcome to the relative demand of each outcome at any moment with a price function. This incentivies traders to bet early as they expect their option to increase in price if correct.

### Infinite Outcome
The [Infinite Outcome DPM](https://www.cs.toronto.edu/~axgao/papers/interval-WINE09.pdf) is simply a DPM where securities are created on the fly as particular outcomes come into demand. This means that there is no need to pre define options or ranges. This enables betting on any event that can be represented with countabley infinite outcomes on the real number line.


### Cost Function
When a trader selects some set of outcomes, they are quoted a cost for their bet based on the [cost function](./src/mechanisms/infinite-outcome-DPM/OnitInfiniteOutcomeDPMMechanism.sol#L100), which can be thought of as the integral of the price function over the range of outcomes selected. This acts as an AMM facilitating buy/sell orders between traders and the market.

#### Cost Function
$$C = C' - C$$

The cost of a trade is the difference in the cost potential before and after the trade.

#### Cost Potential
$$C_i(q) = k \cdot \sqrt{\sum q_j^2}$$

Where $k$ is a constant, $q_j$ represents the quantity of shares for outcome $j$.
 
#### Price Function
$$p_i(q) = \frac{q_i}{k \cdot \sqrt{\sum q_j^2}}$$

Where $p_i(q)$ is the price of outcome $i$ given the current state $q$. 


## Architecture
Onit markets are deployed as proxy contracts from the factory. Each market contains a question, set of resolvers, and other configuration variables. The markets implement the IODPM mechanism and let traders buy/sell shares which represent outcomes related to the question, mapped to buckets in the outcome domain. All trades are routed through the order router, which handles token transfers and allowances.

- **[OnitInfiniteOutcomeDPMProxyFactory](./src/OnitInfiniteOutcomeDPMProxyFactory.sol)**: Creates new prediction market proxies using a clone pattern for gas efficiency.

- **[OnitInfiniteOutcomeDPM](./src/OnitInfiniteOutcomeDPM.sol)**: The core contract that implements an Onit prediction market. Holds details about the question and trades.
   - [OnitIODPMOrderManager](./src/order-manager/OnitIODPMOrderManager.sol): Handles making trades and updating balances of the market.
    - [OnitInfiniteOutcomeDPMMechanism](./src/mechanisms/infinite-outcome-DPM/OnitInfiniteOutcomeDPMMechanism.sol): Includes the cost function, constants, and state related to the IODPM mechanism.
    - [OnitInfiniteOutcomeDPMOutcomeDomain](./src/mechanisms/infinite-outcome-DPM/OnitInfiniteOutcomeDPMOutcomeDomain.sol): Handles the relation between the prediction on the real line and the outcome domain of the IOPDM.
   - [OnitMarketResolver](./src/resolvers/OnitMarketResolver.sol): Handles market resolution, and stores resolvers and admin addresses.
   - ERC1155: To mint traders an NFT representing their position in the market.

- **[OnitMarketOrderRouter](./src/order-manager/OnitMarketOrderRouter.sol)**: Central contract that routes bets between traders and markets. It handles native or ERC20 transfers and allowances. Also enables market creators to set custom allowances for other traders to spend on their markets. 




## Deployments

| Network | Address |
| ------- | ------- |
| Implementation | [0x62e714eF889138eF0F33e2735a791E9127D4A1b8](https://basescan.org/address/https://basescan.org/address/0x62e714eF889138eF0F33e2735a791E9127D4A1b8#code) |
| Factory | [0xCc78B26c14e074D19F135a026636F665397AaF2c](https://basescan.org/address/0xCc78B26c14e074D19F135a026636F665397AaF2c) |
| Order Router | [0xEC5D856E023cA52d0c09ACb75636A76D5A80bef4](https://basescan.org/address/0xEC5D856E023cA52d0c09ACb75636A76D5A80bef4#code) |

*(Addresses for v0.0.3 deployed on Base and Base Sepolia)*

## Testing

### Running Tests

To run tests, you can use the following command:

```bash
forge test
```

To run tests for a specific contract, you can use the following commands:

```bash
// Test a specific contract (using simplified cmd from ./dev/test.sh)
bun run test OnitInfiniteOutcomeDPM

// Default Forge test command
forge test --match-contract <contract-name>
```

### Benchmarking

Benchmarking files for each release can be found in the `test/benchmarks` directory. These include:
- [gas snapshots](./test/benchmarks/.gas-snapshot)
- [full gas report](./test/benchmarks/gas-report.txt)
- [contract sizes](./test/benchmarks/contract-sizes.txt) 

To update these files for a new release, use the following command: 

```bash
bun run benchmarks
``` 