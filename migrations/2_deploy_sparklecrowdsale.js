const SparkleCrowdsale = artifacts.require('./SparkleCrowdsale');
const SparkleToken = artifacts.require('./SparkleToken');

module.exports = function(deployer, network, accounts) {
	return deployer
		.then(() => {
			// NOTE: If for some reason after deployment and testing you need re-deploy then change false to true 
			return deployer.deploy(SparkleToken, {overwrite: true});
		})
		.then(() => {
			const _tokenAddress       = SparkleToken.address;
			const _tokenRate          = new web3.BigNumber(400e8);
			const _tokenCap           = new web3.BigNumber(19698000e8);
			const _startTime          = web3.eth.getBlock('latest').timestamp + 10;
			const _endTime            = _startTime + 86400 * 1;
			const _etherDepositWallet = accounts[5];
			const _kycRequired        = true;

			return deployer.deploy(SparkleCrowdsale,_tokenAddress, _tokenRate, _tokenCap, _startTime, _endTime, _etherDepositWallet, _kycRequired);
		});
};