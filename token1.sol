//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

//* In this case, there are two sets of tokens for trading:
//* one is MyToken1 and another is MyToken2..but you can create more such ERC20 tokens 

//! No need for using safemath...I have shown although in some cases. You can of course use normal arithmetic operators.

contract MyToken1 is ERC20, ERC20Burnable, ERC20Permit, Ownable{ 

    constructor(address initialOwner)
        ERC20("MyToken1", "MTK1")
        ERC20Permit("MyToken1")
        Ownable(initialOwner)
    {}

      function tokenmint(address to, uint256 amount) external onlyOwner{
    _mint(to, amount);
  }

  function safeTransfer(address _to, uint256 _amount) external onlyOwner{
    uint256 netBal = balanceOf(address(this));
    if (_amount > netBal){
      _mint(address(this),_amount-netBal);
    }
      transfer(_to, _amount);
  }

}
