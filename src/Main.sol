// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;
import './Aggregator/PriceFeed.sol';
import '@openzeppelin/contracts/access/Ownable.sol';

contract Main is PriceFeed, Ownable {
  error Provide_Enough_Eth();
  error Not_LP(address _caller);
  error Liquidity_Withdrawal_Failed(address _for, uint256 _amount);
  error Zero_Address();
  error Not_Minimum_Collateral_Deposited();
  error Malicious_Call(address _by);
  error Profit_Sending_Failed_For_Closing_Long_Position();
  error Refunding_Failed_For_Closing_Long(address _for, int256 _value);
  error Reached_Liquidity_Reserve_Limit(uint256 _liquidity);

  // tracking how much liquidity a LP is providing
  mapping(address => uint256) LPs;
  mapping(address => bool) isLP;
  mapping(address => uint256) identifyTradersByDirection;

  uint256 allowBorrowPercentage = 99;
  uint256 allowedMinCollateral = 0.5 ether;
  uint256 liquidity;
  uint256 openInterest;
  uint256 maxUtilizationPercentage = 60;

  enum TradeStatus {
    Null,
    Open,
    Close
  }

  enum PositionStatus {
    Null,
    Long,
    Short
  }

  struct TraderUtils {
    uint256 collateral;
    uint256 borrowedAmount;
    int256 currentValue;
    TradeStatus tradeStatus;
    PositionStatus positionStatus;
  }

  mapping(address => TraderUtils) addressToTraderUtils;

  constructor(address initialOwner) Ownable(initialOwner) {}

  function depositLiquidity() external payable {
    if (msg.value != 0.05 ether) {
      revert Provide_Enough_Eth();
    }
    LPs[msg.sender] = msg.value;
    liquidity += msg.value;
  }

  function withdrawLiquidity() external {
    if (!isLP[msg.sender]) {
      revert Not_LP(msg.sender);
    }

    if (openInterest < (liquidity * maxUtilizationPercentage) / 100) {
      // LPs can't withdraw their liquidity if liquidity reserve limit reached
      revert Reached_Liquidity_Reserve_Limit(liquidity);
    }

    uint256 _value = LPs[msg.sender];
    (bool success, ) = payable(msg.sender).call{value: _value}('');
    if (!success) {
      revert Liquidity_Withdrawal_Failed(msg.sender, _value);
    }
  }

  function setPriceFeedAddress(AggregatorV3Interface _address) external onlyOwner {
    setAggregatorAddress(_address);
  }

  function openPositionForLong() external payable isAddress(msg.sender) {
    if (msg.value < allowedMinCollateral) {
      revert Not_Minimum_Collateral_Deposited();
    }
    int256 btcToEth = getPrice(); // getting 1 BTC = ? ETH
    uint256 borrowedAmount = (msg.value * allowBorrowPercentage) / 100; // this will be credited to traders to trade
    int256 currentValue = int256(borrowedAmount) / btcToEth; // current value in terms of BTC
    addressToTraderUtils[msg.sender] = TraderUtils(
      msg.value,
      borrowedAmount,
      currentValue,
      TradeStatus.Open,
      PositionStatus.Long
    );
    identifyTradersByDirection[msg.sender] = 1;
    openInterest += borrowedAmount; // recording openInterest in ETH
  }

  function closePositionForLong() external isAddress(msg.sender) {
    if (identifyTradersByDirection[msg.sender] != 1) {
      revert Malicious_Call(msg.sender);
    }
    delete addressToTraderUtils[msg.sender];
    int256 currentPrice = getPrice(); // Current BTC value in terms of ETH
    uint256 borrowedAmount = addressToTraderUtils[msg.sender].borrowedAmount; // Getting borrowed amount while opening the positio
    int256 currentValue = int256(borrowedAmount) / currentPrice; // the valu in terms of eth
    int256 priceDifference = currentValue - addressToTraderUtils[msg.sender].currentValue; // PnL
    if (currentValue > addressToTraderUtils[msg.sender].currentValue) {
      addressToTraderUtils[msg.sender].tradeStatus = TradeStatus.Close;
      // Deduct from LPs ⭐️
      liquidity - uint256(priceDifference);
      openInterest -= borrowedAmount; // Updating open interest after closing the position
      (bool success, ) = payable(msg.sender).call{value: uint256(priceDifference)}('');
      if (!success) {
        revert Profit_Sending_Failed_For_Closing_Long_Position();
      }
    } else if (currentValue < addressToTraderUtils[msg.sender].currentValue) {
      addressToTraderUtils[msg.sender].tradeStatus = TradeStatus.Close;
      int256 collateral = int256(addressToTraderUtils[msg.sender].collateral);
      int256 refundableAmountWithoutFee = collateral - priceDifference;
      int256 refundableAmountAfterFeeDeduction = refundableAmountWithoutFee -
        int256(addressToTraderUtils[msg.sender].collateral) /
        100; // liquidityFee is 1% of collateral
      (bool success, ) = payable(msg.sender).call{value: uint256(refundableAmountAfterFeeDeduction)}('');
      if (!success) {
        revert Refunding_Failed_For_Closing_Long(msg.sender, refundableAmountAfterFeeDeduction);
      }
    }
  }

  // traders can increase size & collateral of perpetual position
  function increasePositionSizeAndCollateralForLong() external payable isAddress(msg.sender) {
    if (identifyTradersByDirection[msg.sender] != 1) {
      revert Malicious_Call(msg.sender);
    }

    uint256 borrowedAmount = (msg.value * allowBorrowPercentage) / 100;
    addressToTraderUtils[msg.sender].collateral += msg.value;
    addressToTraderUtils[msg.sender].borrowedAmount += borrowedAmount; // size increased
  }

  modifier isAddress(address _addr) {
    if (_addr != address(0)) {
      revert Zero_Address();
    }
    _;
  }
}
// Net amount of liquidity pool was not tracked.
// During calculation of net PnL is it necessary to use USD here:
// (currentValueOfPosition*openInterestInTermsOfETH) - openInterestInTermsOfUSD