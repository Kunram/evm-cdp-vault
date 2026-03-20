// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IOracle {
    function getLatestPrice() external view returns (uint256);
}

contract Vault {
    IERC20 public immutable debtToken;
    IOracle public immutable priceOracle;

    uint256 public constant LIQUIDATION_THRESHOLD = 80; // 80% LTV
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    
    // 简单的防重入锁，替代引入庞大的 OpenZeppelin ReentrancyGuard 以省 Gas
    uint256 private _status = 1; 

    mapping(address => uint256) public collateral;
    mapping(address => uint256) public debt;

    error TransferFailed();
    error HealthFactorBroken(uint256 healthFactor);
    error HealthFactorOk();
    error ZeroAmount();
    error ReentrancyGuard();

    event Deposited(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);
    event Liquidated(address indexed liquidator, address indexed user, uint256 debtCovered);

    modifier nonReentrant() {
        if (_status == 2) revert ReentrancyGuard();
        _status = 2;
        _;
        _status = 1;
    }

    constructor(address _debtToken, address _oracle) {
        debtToken = IERC20(_debtToken);
        priceOracle = IOracle(_oracle);
    }

    function deposit() external payable nonReentrant {
        if (msg.value == 0) revert ZeroAmount();
        collateral[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    function borrow(uint256 _amount) external nonReentrant {
        if (_amount == 0) revert ZeroAmount();
        
        debt[msg.sender] += _amount;
        
        uint256 hf = _calculateHealthFactor(msg.sender);
        if (hf < MIN_HEALTH_FACTOR) revert HealthFactorBroken(hf);

        if (!debtToken.transfer(msg.sender, _amount)) revert TransferFailed();
        emit Borrowed(msg.sender, _amount);
    }

    function repay(uint256 _amount) external nonReentrant {
        if (_amount == 0) revert ZeroAmount();
        
        debt[msg.sender] -= _amount;
        
        if (!debtToken.transferFrom(msg.sender, address(this), _amount)) revert TransferFailed();
        emit Repaid(msg.sender, _amount);
    }

    function liquidate(address _user) external nonReentrant {
        uint256 hf = _calculateHealthFactor(_user);
        if (hf >= MIN_HEALTH_FACTOR) revert HealthFactorOk();

        uint256 userDebt = debt[_user];
        uint256 userCollateral = collateral[_user];

        debt[_user] = 0;
        collateral[_user] = 0;

        if (!debtToken.transferFrom(msg.sender, address(this), userDebt)) revert TransferFailed();

        (bool ethSent, ) = msg.sender.call{value: userCollateral}("");
        if (!ethSent) revert TransferFailed();

        emit Liquidated(msg.sender, _user, userDebt);
    }

    function _calculateHealthFactor(address _user) internal view returns (uint256) {
        uint256 userDebt = debt[_user];
        if (userDebt == 0) return type(uint256).max;

        uint256 collateralValueInUsd = (collateral[_user] * priceOracle.getLatestPrice()) / 1e18;
        uint256 collateralAdjusted = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / 100;

        return (collateralAdjusted * 1e18) / userDebt;
    }
}
