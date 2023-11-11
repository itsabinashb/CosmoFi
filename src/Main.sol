// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

contract Main {
  error Provide_Enough_Eth();
  error Not_LP(address _caller);
  error Liquidity_Withdrawal_Failed(address _for, uint256 _amount);

  // tracking how much liquidity a LP is providing
  mapping(address => uint256) LPs;
  mapping(address => bool) isLP;

  function depositLiquidity() external payable {
    if (msg.value != 0.050 ether) {
      revert Provide_Enough_Eth();
    }
    LPs[msg.sender] = msg.value;
  }

  function withdrawLiquidity() external {
    if (!isLP[msg.sender]) {
      revert Not_LP(msg.sender);
    }
    uint256 _value = LPs[msg.sender];
    (bool success, ) = payable(msg.sender).call{value: _value}('');
    if (!success) {
      revert Liquidity_Withdrawal_Failed(msg.sender, _value);
    }
  }
}
