pragma solidity 0.4.25;

import './MultiOwnable.sol';
import 'openzeppelin-solidity/contracts/lifecycle/Pausable.sol';
import 'openzeppelin-solidity/contracts/token/ERC20/ERC20.sol';
import 'openzeppelin-solidity/contracts/crowdsale/validation/TimedCrowdsale.sol';

/**
 * @dev SparkelBaseCrowdsale: Core crowdsale functionality
 */
contract SparkleBaseCrowdsale is MultiOwnable, Pausable, TimedCrowdsale {
	using SafeMath for uint256;

	/**
	 * @dev CrowdsaleStage enumeration indicating which operational stage this contract is running
	 */
	enum CrowdsaleStage { 
		preICO, 
		bonusICO, 
		mainICO
	}

 	/**
 	 * @dev Internal contract variable stored
 	 */
	ERC20   public tokenAddress;
	uint256 public tokenRate;
	uint256 public tokenCap;
	uint256 public startTime;
	uint256 public endTime;
	address public depositWallet;
	bool    public kycRequired;	
	bool	public refundRemainingOk;

	uint256 public tokensSold;

	/**
	 * @dev Contribution structure representing a token purchase 
	 */
	struct OrderBook {
		uint256 weiAmount;   // Amount of Wei that has been contributed towards tokens by this address
		uint256 pendingTokens; // Total pending tokens held by this address waiting for KYC verification, and user to claim their tokens(pending restrictions)
		bool    kycVerified;   // Has this address been kyc validated
	}

	// Contributions mapping to user addresses
	mapping(address => OrderBook) private orders;

	// Initialize the crowdsale stage to preICO (this stage will change)
	CrowdsaleStage public crowdsaleStage = CrowdsaleStage.preICO;

	/**
	 * @dev Event signaling that a number of addresses have been approved for KYC
	 */
	event ApprovedKYCAddresses (address indexed _appovedByAddress, uint256 _numberOfApprovals);

	/**
	 * @dev Event signaling that a number of addresses have been revoked from KYC
	 */
	event RevokedKYCAddresses (address indexed _revokedByAddress, uint256 _numberOfRevokals);

	/**
	 * @dev Event signalling that tokens have been claimed from the crowdsale
	 */
	event TokensClaimed (address indexed _claimingAddress, uint256 _tokensClaimed);

	/**
	 * @dev Event signaling that tokens were sold and how many were sold
	 */
	event TokensSold(address indexed _beneficiary, uint256 _tokensSold);

	/**
	 * @dev Event signaling that toke burn approval has been changed
	 */
	event TokenRefundApprovalChanged(address indexed _approvingAddress, bool tokenBurnApproved);

	/**
	 * @dev Event signaling that token burn approval has been changed
	 */
	event CrowdsaleStageChanged(address indexed _changingAddress, uint _newStageValue);

	/**
	 * @dev Event signaling that crowdsale tokens have been burned
	 */
	event CrowdsaleTokensRefunded(address indexed _refundingToAddress, uint256 _numberOfTokensBurned);

	/**
	 * @dev SparkleTokenCrowdsale Contract contructor
	 */
	constructor(ERC20 _tokenAddress, uint256 _tokenRate, uint256 _tokenCap, uint256 _startTime, uint256 _endTime, address _depositWallet, bool _kycRequired)
	public
	Crowdsale(_tokenRate, _depositWallet, _tokenAddress)
	TimedCrowdsale(_startTime, _endTime)
	MultiOwnable()
	Pausable()
	{ 
		tokenAddress      = _tokenAddress;
		tokenRate         = _tokenRate;
		tokenCap          = _tokenCap;
		startTime         = _startTime;
		endTime           = _endTime;
		depositWallet     = _depositWallet;
		kycRequired       = _kycRequired;
		refundRemainingOk = false;
	}

	/**
	 * @dev claimPendingTokens() provides users with a function to receive their purchase tokens
	 * after their KYC Verification
	 */
	function claimTokens()
	whenNotPaused
	onlyWhileOpen
	public
	{
		// Ensure calling address is not address(0)
		require(msg.sender != address(0), "Invalid address specified: address(0)");
		// Obtain a copy of the caller's order record
		OrderBook storage order = orders[msg.sender];
		// Ensure caller has been KYC Verified
		require(order.kycVerified, "Address attempting to claim tokens is not KYC Verified.");
		// Ensure caller has pending tokens to claim
		require(order.pendingTokens > 0, "Address does not have any pending tokens to claim.");
		// For security sake grab the pending token value
		uint256 localPendingTokens = order.pendingTokens;
		// zero out pendingTokens to prevent potential re-entrancy vulnverability
		order.pendingTokens = 0;
		// Deliver the callers tokens
		_deliverTokens(msg.sender, localPendingTokens);
		// Emit event
		emit TokensClaimed(msg.sender, localPendingTokens);
	}

	/**
	 * @dev getExchangeRate() provides a public facing manner in which to 
	 * determine the current rate of exchange in the crowdsale
	 * @param _weiAmount is the amount of wei to purchase tokens with
	 * @return number of tokens the specified wei amount would purchase
	 */
	function getExchangeRate(uint256 _weiAmount)
	whenNotPaused
	onlyWhileOpen
	public
	view
	returns (uint256)
	{
		if (crowdsaleStage == CrowdsaleStage.preICO) {
			// Ensure _weiAmount is > than current stage minimum
			require(_weiAmount >= 1 ether, "PreICO minimum ether required: 1 ETH.");
		}
		else if (crowdsaleStage == CrowdsaleStage.bonusICO || crowdsaleStage == CrowdsaleStage.mainICO) {
			// Ensure _weiAmount is > than current stage minimum
			require(_weiAmount >= 500 finney, "bonusICO/mainICO minimum ether required: 0.5 ETH.");
		}

		// Calculate the number of tokens this amount of wei is worth
		uint256 tokenAmount = _getTokenAmount(_weiAmount);
		// Ensure the number of tokens requests will not exceed available tokens
		require(getRemainingTokens() >= tokenAmount, "Specified wei value woudld exceed amount of tokens remaining.");
		// Calculate and return the token amount this amount of wei is worth (includes bonus factor)
		return tokenAmount;
	}

	/**
	 * @dev getRemainingTokens() provides function to return the current remaining token count
	 * @return number of tokens remaining in the crowdsale to be sold
	 */
	function getRemainingTokens()
	whenNotPaused
	public
	view
	returns (uint256)
	{
		// Return the balance of the contract (IE: tokenCap - tokensSold)
		return tokenCap.sub(tokensSold);
	}

	/**
	 * @dev refundRemainingTokens provides functionn to refund remaining tokens to the specified address
	 * @param _addressToRefund is the address in which the remaining tokens will be refunded to
	 */
	function refundRemainingTokens(address _addressToRefund)
	onlyOwner
	whenNotPaused
	public
	{
		// Ensure the specified address is not address(0)
		require(_addressToRefund != address(0), "Specified address is invalid [0x0]");
		// Ensure the crowdsale has closed before burning tokens
		require(hasClosed(), "Crowdsale must be finished to burn tokens.");
		// Ensure that step-1 of the burning process is satisfied (owner set to true)
		require(refundRemainingOk, "Crowdsale remaining token refund is disabled.");
		uint256 tempBalance = token().balanceOf(this);
		// Transfer the remaining tokens to specified address
		_deliverTokens(_addressToRefund, tempBalance);
		// Emit event
		emit CrowdsaleTokensRefunded(_addressToRefund, tempBalance);
	}

	/**
	 * @dev approveRemainingTokenRefund approves the function to withdraw any remaining tokens
	 * after the crowdsale ends
	 * @dev This was put in place as a two-step process to burn tokens so burning was secure
	 */
	function approveRemainingTokenRefund()
	onlyOwner
	whenNotPaused
	public
	{
		// Ensure calling address is not address(0)
		require(msg.sender != address(0), "Calling address invalid [0x0]");
		// Ensure the crowdsale has closed before approving token burning
		require(hasClosed(), "Token burn approval can only be set after crowdsale closes");
		refundRemainingOk = true;
		emit TokenRefundApprovalChanged(msg.sender, refundRemainingOk);
	}

	/**
	 * @dev setStage() sets the current crowdsale stage to the specified value
	 * @param _newStageValue is the new stage to be changed to
	 */
	function changeCrowdsaleStage(uint _newStageValue)
	onlyOwner
	whenNotPaused
	onlyWhileOpen
	public
	{
		// Create temporary stage variable
		CrowdsaleStage _stage;
		// Determine if caller is trying to set: preICO
		if (uint(CrowdsaleStage.preICO) == _newStageValue) {
			// Set the internal stage to the new value
			_stage = CrowdsaleStage.preICO;
		}
		// Determine if caller is trying to set: bonusICO
		else if (uint(CrowdsaleStage.bonusICO) == _newStageValue) {
			// Set the internal stage to the new value
			_stage = CrowdsaleStage.bonusICO;
		}
		// Determine if caller is trying to set: mainICO
		else if (uint(CrowdsaleStage.mainICO) == _newStageValue) {
			// Set the internal stage to the new value
			_stage = CrowdsaleStage.mainICO;
		}
		else {
			revert("Invalid stage selected");
		}

		// Update the internal crowdsale stage to the new stage
		crowdsaleStage = _stage;
		// Emit event
		emit CrowdsaleStageChanged(msg.sender, uint(_stage));
	}

	/**
	 * @dev isAddressKYCVerified() checks the KYV Verification status of the specified address
	 * @param _addressToLookuo address to check status of KYC Verification
	 * @return kyc status of the specified address 
	 */
	function isKYCVerified(address _addressToLookuo) 
	whenNotPaused
	onlyWhileOpen
	public
	view
	returns (bool)
	{
		// Ensure _addressToLookuo is not address(0)
		require(_addressToLookuo != address(0), "Invalid address specified: address(0)");
		// Obtain the addresses order record
		OrderBook storage order = orders[_addressToLookuo];
		// Return the JYC Verification status for the specified address
		return order.kycVerified;
	}

	/**
	 * @dev Approve in bulk the specified addfresses indicating they were KYC Verified
	 * @param _addressesForApproval is a list of addresses that are to be KYC Verified
	 */
	function bulkApproveKYCAddresses(address[] _addressesForApproval) 
	onlyOwner
	whenNotPaused
	onlyWhileOpen
	public
	{

		// Ensure that there are any address(es) in the provided array
		require(_addressesForApproval.length > 0, "Specified address array is empty");
		// Interate through all addresses provided
		for (uint i = 0; i <_addressesForApproval.length; i++) {
			// Approve this address using the internal function
			_approveKYCAddress(_addressesForApproval[i]);
		}

		// Emit event indicating address(es) have been approved for KYC Verification
		emit ApprovedKYCAddresses(msg.sender, _addressesForApproval.length);
	}

	/**
	 * @dev Revoke in bulk the specified addfresses indicating they were denied KYC Verified
	 * @param _addressesToRevoke is a list of addresses that are to be KYC Verified
	 */
	function bulkRevokeKYCAddresses(address[] _addressesToRevoke) 
	onlyOwner
	whenNotPaused
	onlyWhileOpen
	public
	{
		// Ensure that there are any address(es) in the provided array
		require(_addressesToRevoke.length > 0, "Specified address array is empty");
		// Interate through all addresses provided
		for (uint i = 0; i <_addressesToRevoke.length; i++) {
			// Approve this address using the internal function
			_revokeKYCAddress(_addressesToRevoke[i]);
		}

		// Emit event indicating address(es) have been revoked for KYC Verification
		emit RevokedKYCAddresses(msg.sender, _addressesToRevoke.length);
	}

	/**
	 * @dev tokensPending() provides owners the function to retrieve an addresses pending
	 * token amount
	 * @param _addressToLookup is the address to return the pending token value for
	 * @return the number of pending tokens waiting to be claimed from specified address
	 */
	function tokensPending(address _addressToLookup)
	onlyOwner
	whenNotPaused
	onlyWhileOpen
	public
	view
	returns (uint256)
	{
		// Ensure specified address is not address(0)
		require(_addressToLookup != address(0), "Specified address is invalid [0x0]");
		// Obtain the order for specified address
		OrderBook storage order = orders[_addressToLookup];
		// Return the pendingTokens amount
		return order.pendingTokens;
	}

	/**
	 * @dev contributionAmount() provides owners the function to retrieve an addresses total
	 * contribution amount in eth
	 * @param _addressToLookup is the address to return the contribution amount value for
	 * @return the number of ether contribured to the crowdsale by specified address
	 */
	function contributionAmount(address _addressToLookup)
	onlyOwner
	whenNotPaused
	onlyWhileOpen
	public
	view
	returns (uint256)
	{
		// Ensure specified address is not address(0)
		require(_addressToLookup != address(0), "Specified address is Invalid [0x0]");
		// Obtain the order for specified address
		OrderBook storage order = orders[_addressToLookup];
		// Return the contribution amount in wei
		return order.weiAmount;
	}

	/**
	 * @dev _approveKYCAddress provides the function to approve the specified address 
	 * indicating KYC Verified
	 * @param _addressToApprove of the user that is being verified
	 */
	function _approveKYCAddress(address _addressToApprove) 
	onlyOwner
	internal
	{
		// Ensure that _addressToApprove is not address(0)
		require(_addressToApprove != address(0), "Invalid address specified: address(0)");
		// Get this addesses contribution record
		OrderBook storage order = orders[_addressToApprove];
		// Set the contribution record to indicate address has been kyc verified
		order.kycVerified = true;
	}

	/**
	 * @dev _revokeKYCAddress() provides the function to revoke previously
	 * granted KYC verification in cases of fraud or false/invalid KYC data
	 * @param _addressToRevoke is the address to remove KYC verification from
	 */
	function _revokeKYCAddress(address _addressToRevoke)
	onlyOwner
	internal
	{
		// Ensure address is not address(0)
		require(_addressToRevoke != address(0), "Invalid address specified: address(0)");
		// Obtain a copy of this addresses contribution record
		OrderBook storage order = orders[_addressToRevoke];
		// Revoke this addresses KYC verification
		order.kycVerified = false;
	}

	/**
	 * @dev _rate() provides the function of calcualting the rate based on crowdsale stage
	 * @param _weiAmount indicated the amount of ether intended to use for purchase
	 * @return number of tokens worth based on specified Wei value
	 */
	function _rate(uint _weiAmount)
	internal
	view
	returns (uint256)
	{
		require(_weiAmount > 0, "Specified wei amoount must be > 0");

		// Determine if the current operation stage of the crowdsale is preICO
		if (crowdsaleStage == CrowdsaleStage.preICO)
		{
			// Determine if the purchase is >= 21 ether
			if (_weiAmount >= 21 ether) { // 20% bonus
				return 480e8;
			}
			
			// Determine if the purchase is >= 11 ether
			if (_weiAmount >= 11 ether) { // 15% bonus
				return 460e8;
			}
			
			// Determine if the purchase is >= 5 ether
			if (_weiAmount >= 5 ether) { // 10% bonus
				return 440e8;
			}

		}
		else
		// Determine if the current operation stage of the crowdsale is bonusICO
		if (crowdsaleStage == CrowdsaleStage.bonusICO)
		{
			// Determine if the purchase is >= 21 ether
			if (_weiAmount >= 21 ether) { // 10% bonus
				return 440e8;
			}
			else if (_weiAmount >= 11 ether) { // 7% bonus
				return 428e8;
			}
			else
			if (_weiAmount >= 5 ether) { // 5% bonus
				return 420e8;
			}

		}

		// Rate is either < bounus or is main sale so return base rate only
		return rate();
	}

	/**
	 * @dev Performs token to wei converstion calculations based on crowdsale specification
	 * @param _weiAmount to spend
	 * @return number of tokens purchasable for the specified _weiAmount at crowdsale stage rates
	 */
	function _getTokenAmount(uint256 _weiAmount)
	whenNotPaused
	internal
	view
	returns (uint256)
	{
		// Get the current rate set in the constructor and calculate token units per wei
		uint256 currentRate = _rate(_weiAmount);
		// Calculate the total number of tokens buyable at based rate (before adding bonus)
		uint256 sparkleToBuy = currentRate.mul(_weiAmount).div(10e17);
		// Return proposed token amount
		return sparkleToBuy;
	}

	/**
	 * @dev
	 * @param _beneficiary is the address that is currently purchasing tokens
	 * @param _weiAmount is the number of tokens this address is attempting to purchase
	 */
	function _preValidatePurchase(address _beneficiary, uint256 _weiAmount) 
	whenNotPaused
	internal
	view
	{
		// Call into the parent validation to ensure _beneficiary and _weiAmount are valid
		super._preValidatePurchase(_beneficiary, _weiAmount);
		// Calculate amount of tokens for the specified _weiAmount
		uint256 requestedTokens = getExchangeRate(_weiAmount);
		// Calculate the currently sold tokens
		uint256 tempTotalTokensSold = tokensSold;
		// Incrememt total tokens		
		tempTotalTokensSold.add(requestedTokens);
		// Ensure total max token cap is > tempTotalTokensSold
		require(tempTotalTokensSold <= tokenCap, "Requested wei amount will exceed the max token cap and was not accepted.");
		// Ensure that requested tokens will not go over the remaining token balance
		require(requestedTokens <= getRemainingTokens(), "Requested tokens would exceed tokens available and was not accepted.");
		// Obtain the order record for _beneficiary if one exists
		OrderBook storage order = orders[_beneficiary];
		// Ensure this address has been kyc validated
		require(order.kycVerified, "Address attempting to purchase is not KYC Verified.");
		// Update this addresses order to reflect the purchase and ether spent
		order.weiAmount = order.weiAmount.add(_weiAmount);
		order.pendingTokens = order.pendingTokens.add(requestedTokens);
		// increment totalTokens sold
		tokensSold = tokensSold.add(requestedTokens);
		// Emit event
		emit TokensSold(_beneficiary, requestedTokens);
	}

	/**
	 * @dev _processPurchase() is overridden and will be called by OpenZep v2.0 internally
	 * @param _beneficiary is the address that is currently purchasing tokens
	 * @param _tokenAmount is the number of tokens this address is attempting to purchase
	 */
	function _processPurchase(address _beneficiary, uint256 _tokenAmount)
	whenNotPaused
	internal
	{
		// We do not call the base class _processPurchase() functions. This is needed here or the base
		// classes function will be called.
	}

}

/*
Notes:
======

1) "tokenCap" has no real effect except to help calculate remaining tokens
	- Limit on purchase is based on how many tokens remain after purchases (including claimed and unclaimed tokens)
	- Make sure to send the same amount of tokens to the contract as declared by the tokenCap static variable 
	  (ex: 19698000e8)

2) Finalizing crowdsale
	- when crowdsale is finished a refund of the remaining tokens is possible
		- Obtaining the refund is a two-step process
			1) call approveRemainingTokenRefund() *can only be called once crowdsale has ended*
			2) call refundRemainingTokens(address) *can only be called once crowdsale has ended and refund approved (previous step)

3) Sending eth to contract (aKa: purchase tokens)
	- testing on ganache test network works out to about 200k units of gas to run purchase code (any not used is refunded to the caller)
	- IMPORTANT: Have noticed the odd time when there is enough gas but not enough gas (ethereum wtf?) it will say the tx
	             succeeded, it will take the eth and send it to the deposit wallet, however it will not actually update 
	             the order book to reflect their purchase. I have not looked at tx's here deeply to see if there is enough
	             data to faclitate a refund to someone should this happen, and why I was concerend with having an unlimited 
	             upped cap like we do. it is a lot to lose. Anyhow I said my peace, you said yours, and this is how it is, 
	             unlimited upper limit to purchase tokens. 
	- RECOMMENDED: 200000 units of gas should be sent when trying to buy tokens to ensure full processing
	- NOTE: Unable to replicate the IMPORTANT issue in any manner consistantly enough to know how to fix it.

4) Owner loopup, pendingTokens, and weiAmount
	- the orderbook mapping was made private to not disclose to much information abotu other addesses easily
	- added owner function tokensPending(address) and contributionAmount(address) to obtain this data easily for owner(s)

5) Remaining tokens
	- remaining tokens was changed a bit and now reflects all purchased tokens (it previously only listed claimed tokens as sold)
	- remaining tokens now uses tokenCap and tokensSold to determine how many tokens are remaining in the sale
	- call getRemainingTokens() to obtain the number of remaining tokens
	- NOTE: again, tokensSold reflects the number of tokens sold not just tokens claimed from being sold(ewps)

6) KYC IS REQUIRED
	- While the crowdsale contract COULD be used without and why I built it into it, it defaults to KYC being required 
	  for any token purchases, as well as claiming any pending tokens (for cases when KYC needs to be revoked preventing 
	  tokens from being claimed) 

7) Bulk Approval/Revokal
	- array format truffle: [0xAddress, 0xAddress, 0xAddress]
	- array format remix: ["0xAddress", "0xAddress", "0xAdress"]
	- NOTE: Top limit or max number of addresses in the array has not be tested and no idea what the max might be

8) Exchange rate
	- Exchangerate has been precalculated now and based upon 400 sparkle per 1 ETH
		- NOTE: Underlying rate is still used but only to define the base rate with no bonus (stage2, or purchase < bonus minimum)
		        This means that it still needs to be specified by the tokenRate static variable however tokenRate is not used
		        in calculations to determine bonus amounts (to save code/gas/make more simple).  
	- Exchange rate returns number of tokens including any bonus calculated based on crowdsale stage
		- Ex: 5eth purchase @ stage0 = 2200 Sparkle tokens (5 x 400 + stage0bonus)
		- changeCrowdsaleStage(0) -> PreICO
		- changeCrowdsaleStage(1) -> BonusICO
		- changeCrowdsaleStage(2) -> MainICO

9) Crowdsale stages
	- Are manually set by an owner
	- To be set to match public annoumcement structure

*/




