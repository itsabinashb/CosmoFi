// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
import './Aggregator/PriceFeed.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract Main is Ownable, PriceFeed {
  error Insufficient_balance();
  error Insufficient_collateral_provided();
  error Not_a_trader(address trader);
  error Not_LP();
  error Insufficient_amount_to_withdraw();
  error Max_Utilization_Limit_Reached();
  error Insufficient_size();
  error Insufficient_collateral();

  IERC20 private dai;
  uint256 minCollateral = 100;
  uint256 decimal = 1e18;
  int256 usdDecimal = 1e8;
  int256 daiDecimal = 1e18;
  uint256 leverage = 10;
  uint256 LIQUIDITY;
  uint256 OPEN_INTEREST;
  uint256 MAX_UTILIZATION_LIMIT_PERCENTAGE = 30;

  struct TraderUtils {
    uint256 collateral;
    int256 sizeInBTC;
    int256 sizeInUSD;
    int256 sizeInDai;
  }

  mapping(address => TraderUtils) traderUtils;
  mapping(address => uint256) isTrader; // if set to 1 means the address was validated as trader
  mapping(address => uint256) LpToFunded;

  constructor(address initialOwner) Ownable(initialOwner) {}

  //LPs can add liquidity
  function addLiquidity(uint _amount) external {
    uint256 amount = _amount / decimal;
    if (dai.balanceOf(msg.sender) < _amount) {
      revert Insufficient_balance();
    }
    dai.transferFrom(msg.sender, address(this), amount);
    LpToFunded[msg.sender] += amount;
    LIQUIDITY += amount;
  }

  // can open perpetual position
  // WEI -> DAI -> USD -> BTC
  function openPosition(uint256 amount) external {
    uint256 _amount = amount / decimal; // As input is in DAI form we are dividing it by 1e18
    if (_amount < minCollateral) {
      revert Insufficient_collateral_provided();
    }
    if (dai.balanceOf(msg.sender) < _amount) {
      revert Insufficient_balance();
    }
    dai.transferFrom(msg.sender, address(this), _amount);
    int256 size = int256(_amount) * 5;
    int256 currentBTCPriceInUSD = getPriceForBTC() / usdDecimal; // here we get BTC price in USD, dividing it by 1e8 to get actual value
    int256 daiToUSD = getPriceForDAI() / daiDecimal; // here we get DAI price in USD, dividing it by 1e8 to get actual value
    int256 sizeInUSD = int(size) * daiToUSD;
    int256 sizeInBTC = currentBTCPriceInUSD / int(sizeInUSD);
    traderUtils[msg.sender] = TraderUtils(_amount, sizeInBTC, sizeInUSD, size);
    isTrader[msg.sender] = 1;
    OPEN_INTEREST += uint256(size);
  }

  // can increase the size of the position
  function increaseSize(uint256 _amount) external onlyTrader {
    uint256 amount = _amount / decimal;
    if (dai.balanceOf(msg.sender) < amount) {
      revert Insufficient_balance();
    }
    int256 daiToUsd = getPriceForDAI() / daiDecimal;
    int256 sizeToBeIncreasedInUSD = daiToUsd * int(amount);
    int256 btcCurrentPriceInUSD = getPriceForBTC() / usdDecimal;
    int256 sizeToBeIncreasedInBTC = btcCurrentPriceInUSD / sizeToBeIncreasedInUSD; // if this USD to 1 BTC then  in this USD to how much BTC?
    traderUtils[msg.sender].sizeInBTC += sizeToBeIncreasedInBTC;
    traderUtils[msg.sender].sizeInUSD += sizeToBeIncreasedInUSD;
  }

  // can increase collateral
  function increaseCollateral(uint _amount) external onlyTrader {
    uint256 amount = _amount / decimal;
    if (dai.balanceOf(msg.sender) < amount) {
      revert Insufficient_balance();
    }
    traderUtils[msg.sender].collateral += amount;
  }

  //withdraw liquidity
  function withdrawLiquidity(uint _amount) external {
    uint256 amount = _amount / decimal;
    if (LpToFunded[msg.sender] == 0) {
      revert Not_LP();
    } else if (LpToFunded[msg.sender] < amount) {
      revert Insufficient_amount_to_withdraw();
    }
    if (OPEN_INTEREST < (LIQUIDITY * MAX_UTILIZATION_LIMIT_PERCENTAGE) / 100) {
      revert Max_Utilization_Limit_Reached();
    }
    dai.transferFrom(address(this), msg.sender, amount);
  }

// Decreasing position
  function decreasePosition(uint256 _amount) external onlyTrader {
    uint256 amount = _amount / decimal;
    if (int256(amount) > traderUtils[msg.sender].sizeInDai) {
      revert Insufficient_size();
    }
    int256 daiToUSD = getPriceForDAI() / daiDecimal;
    int256 amountInUSD = int256(amount) * daiToUSD;
    // Here we already saved the size in USD for all BTC they have in TraderUtils struct
    int256 sizeInBTC = traderUtils[msg.sender].sizeInBTC; // Getting the size in BTC for this trader
    int256 currentBTCInUSD = getPriceForBTC() / usdDecimal; //
    int256 currentSizeInUSD = sizeInBTC * currentBTCInUSD; // Getting the current size in USD for all the BTC this trader has
    int256 PnL = currentSizeInUSD - traderUtils[msg.sender].sizeInUSD; // Current Market value - Average position size
    int256 realizedPnL = (PnL * amountInUSD) / traderUtils[msg.sender].sizeInUSD;
    int256 realizedPnLInDai = realizedPnL / daiToUSD;
    int256 updatedSizeInDai = traderUtils[msg.sender].sizeInDai - int256(amount);
    int256 updatedSizeInUSD = traderUtils[msg.sender].sizeInUSD - amountInUSD;
    int256 BTC = amountInUSD / currentBTCInUSD;
    int256 updatedSizeInBTC = traderUtils[msg.sender].sizeInBTC - BTC;
    traderUtils[msg.sender].sizeInDai = updatedSizeInDai;
    traderUtils[msg.sender].sizeInUSD = updatedSizeInUSD;
    traderUtils[msg.sender].sizeInBTC = updatedSizeInBTC;
    // address(this) SHOULD BE REPLACED BY A SEPARATE CONTRACT NAMED LiquidityValult
    if (realizedPnL > 0) {
      dai.transferFrom(address(this), msg.sender, uint256(realizedPnLInDai));
    } else if (realizedPnL < 0) {
      dai.transferFrom(msg.sender, address(this), uint256(realizedPnLInDai));
    }
  }

  //decrease collateral
  function decreaseCollateral(uint256 _collateral) external onlyTrader {
    if (_collateral > traderUtils[msg.sender].collateral){
      revert Insufficient_collateral();
    }
    traderUtils[msg.sender].collateral -= _collateral;
  }

  // helper functions
  function setDaiAddress(IERC20 _dai) external onlyOwner {
    dai = IERC20(_dai);
  }

  modifier onlyTrader() {
    if (isTrader[msg.sender] != 1) {
      revert Not_a_trader(msg.sender);
    }
    _;
  }
}
