// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vault} from "../src/Vault.sol";

// 极简 Mock ERC20，摆脱外部依赖
contract MockToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor() {
        balanceOf[msg.sender] = 1000000 * 1e18;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockOracle {
    uint256 public price;
    function setPrice(uint256 _price) external { price = _price; }
    function getLatestPrice() external view returns (uint256) { return price; }
}

contract VaultTest is Test {
    Vault vault;
    MockToken token;
    MockOracle oracle;

    address alice = address(0x1);
    address liquidator = address(0x2);

    function setUp() public {
        token = new MockToken();
        oracle = new MockOracle();
        
        vault = new Vault(address(token), address(oracle));
        
        token.transfer(address(vault), 100000 * 1e18);
        token.transfer(liquidator, 10000 * 1e18);
        
        oracle.setPrice(2000 * 1e18);
        vm.deal(alice, 10 ether);
    }

    function test_BorrowAndRevertOnHealthFactor() public {
        vm.startPrank(alice);
        vault.deposit{value: 1 ether}();
        
        vault.borrow(1600 * 1e18);
        
        vm.expectRevert(abi.encodeWithSelector(Vault.HealthFactorBroken.selector, 0.941176470588235294 * 1e18));
        vault.borrow(100 * 1e18);
        vm.stopPrank();
    }

    function test_LiquidationProcess() public {
        vm.prank(alice);
        vault.deposit{value: 1 ether}();
        
        vm.prank(alice);
        vault.borrow(1500 * 1e18);

        // Simulate market crash
        oracle.setPrice(1500 * 1e18);

        vm.startPrank(liquidator);
        token.approve(address(vault), 1500 * 1e18);
        vault.liquidate(alice);
        vm.stopPrank();

        assertEq(vault.debt(alice), 0);
        assertEq(vault.collateral(alice), 0);
        assertEq(liquidator.balance, 1 ether);
    }
}
