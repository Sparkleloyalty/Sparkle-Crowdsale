pragma solidity 0.4.25;

import './SparkleBaseCrowdsale.sol';

contract SparkleCrowdsale is SparkleBaseCrowdsale {

	// Token contract address
	//address public initTokenAddress        = 0x0;
	// Crowdsale specification
	//uint256 public initTokenRate           = 300 * (10 ** 8);      //-> 30000000000
	//uint256 public initMaxTokenCap		   = 19698000 * (10 ** 8); //-> 1969800000000000
	// Crowdsale start/end time
	//uint256 public initStartTime           = now;
	//uint256 public initEndTime             = now + 12 hours;
	// Crowdsale Token allowance expected in TokenWallet (NOTE: Tokens remaining after distributions will be burned!)
	//uint256 public initMaxTokenAllowance   = 32830000 * (10 ** 8); //-> 3283000000000000
	// Administrative addresses
	//address public initDepositWallet       = 0xA176db55a9F14F1659F384d4e9385Fa8F661E300; // Wallet to receive ether
	//address public ibnitTokenWallet        = 0x36224915E23B5cF14375F68Fe86509bf2879f081; // Token allowance wallet

	constructor(address _tokenAddress, uint256 _tokenRate, uint256 _tokenCap, uint256 _tokenStartTime, uint256 _tokenEndTime, address _etherDepositWallet, bool _kycRequired) 
	SparkleBaseCrowdsale(ERC20(_tokenAddress), _tokenRate, _tokenCap, _tokenStartTime, _tokenEndTime, _etherDepositWallet, _kycRequired)
	public
	{
	}

}

