**How does the system work? How would a user interact with it?**

This perpetual protocol is working for Long direction right now. First liquidity providers can provide liquidity by calling this function: `depositLiquidity()`, minimum required amount is `0.05` ether. Liquidity providers can withdraw their liquidity by calling this function `withdrawLiquidity()` but condition is the `openInterest` should be less than 60% of total liquidity. If the withdrawal fails it will revert by `Liquidity_Withdrawal_Failed(msg.sender, _value)` error.

To open a position user can call `openPositionForLong()` by paying some ether, the minimum required amount is `0.5` ether. Then this function gets the current price of 1 BTC in ETH. We are then calculating the borrow amount which the trader can get, as we wanna make this protocol over collateralised the allowed borrow percentage is 99%. Then we are getting the current value in terms of ETH by this: `int256 currentValue = int256(borrowedAmount) / btcToEth;`. The contract keeps record of all data like collateral, borrowed amount, current value of BTC in terms of ETH, Status of position (is it still open or closed), the direction in which the trader staked etc. in a struct called `TraderUtils`:

```solidity
struct TraderUtils {
    uint256 collateral;
    uint256 borrowedAmount;
    int256 currentValue;
    TradeStatus tradeStatus;
    PositionStatus positionStatus;
  }
```

We are recording open interest in this function.

To close the position trader need to call `closePositionForLong()`, to avoid reentrancy we deleting the trader from contract. We are calculating PnL by substracting the current value (previous when they opened position) from current value (in current time when they wanna close the position):
`int256 priceDifference = currentValue - addressToTraderUtils[msg.sender].currentValue;`
current value is calculated like this:

```solidity
int256 currentPrice = getPrice(); // Current BTC value in terms of ETH from chainlink pricefeed
uint256 borrowedAmount = addressToTraderUtils[msg.sender].borrowedAmount; // Getting borrowed amount while opening the positio
int256 currentValue = int256(borrowedAmount) / currentPrice; // the valu in terms of eth
```

Now if current value is greter than previous current value then trader is in profit, so the `priceDifference` will be credited to his account, this will happen if price move upward.
If price decreases then current value will be less than previous current value, in that case the priceDifference will be deducted from the trader's collateral. We are having 1% liquidity fee of their collateral so it will be deducted as well, after that we are sending the rest of refundable amount to the trader:

```solidity
 int256 refundableAmountWithoutFee = collateral - priceDifference;
      int256 refundableAmountAfterFeeDeduction = refundableAmountWithoutFee -
        int256(addressToTraderUtils[msg.sender].collateral) /
        100; // liquidityFee is 1% of collateral
      (bool success, ) = payable(msg.sender).call{value: uint256(refundableAmountAfterFeeDeduction)}('');
      if (!success) {
        revert Refunding_Failed_For_Closing_Long(msg.sender, refundableAmountAfterFeeDeduction);
      }
```

Trader can increase their Size of position and collateral by calling this function: `increasePositionSizeAndCollateralForLong()`, to do this he/she just will have to deposit ether, the protocol will credit some amount of ether which will be calculated by following prefixed borrow percentage based on deposited amount which will increase their collateral as well as size.

I did not use *Leverage* logic here.

**What actors are involved? Is there a keeper? What is the admin tasked with?**

*Actors involved*: Liquidity providers, Traders, fixed allowed borrow percentage, minimum collateral that is accepted, maximum utilization percentage of liquidity pool, Long direction only.

*Keeper*: There is no keeper.

*Admin task*: For now admin can only set price feed address of BTC.

**What are the known risk/issues?**

1. I could not understand that is it necessary to use USD while calculating the net PnL using this formula:
```solidity
(currentValueOfPosition*openInterestInTermsOfETH) - openInterestInTermsOfUSD;
```
That's why I could not implement the logic of recording real time net amount of liquidity pool.

2. For this logic: *Traders cannot utilize more than a configured percentage of the deposited liquidity.* what factors should I need to keep in ming while setting the percentage ??

**Any pertinent formulas used?**

Yes, to calculate open interest I used mentioned condition :
```
totalOpenInterest < (depositedLiquidity * maxUtilizationPercentage)
```
