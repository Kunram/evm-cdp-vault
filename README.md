# evm-cdp-vault

A highly gas-optimized Collateralized Debt Position (CDP) engine. This implementation allows users to lock native ETH as collateral and borrow ERC20 tokens against it, governed by strict Loan-to-Value (LTV) ratios and decentralized oracle price feeds.

## Core Mechanics

The protocol enforces solvency through a mathematical Health Factor ($H$). A position becomes eligible for liquidation if $H < 1.0$.

$$H = \frac{C \times P \times L_{threshold}}{D}$$

Where:
- $C$ = Collateral balance
- $P$ = Oracle price feed
- $L_{threshold}$ = Liquidation threshold (e.g., 0.80 or 80%)
- $D$ = Outstanding debt

## Security Architecture

- **Reentrancy Protection**: Implemented a custom lightweight mutex (`_status`) to replace OpenZeppelin's `ReentrancyGuard`, significantly reducing deployment and runtime gas costs. State updates strictly precede external calls (Checks-Effects-Interactions pattern).
- **Custom Errors**: Utilizes custom errors (`error TransferFailed();`) instead of string-based require statements for EVM gas efficiency.
- **Oracle Decoupling**: Price feeds are abstracted via interfaces, allowing integration with external data providers without altering core state logic.

## Usage

Built and tested with [Foundry](https://book.getfoundry.sh/).

### Build
```bash
forge build
```

### Test
Tests cover standard borrowing state flows and edge-case liquidation triggers via manipulated oracle mocks.
```bash
forge test -vvv
```
