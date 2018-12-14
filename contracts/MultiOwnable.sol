/**
 * @title MultiOwnable.sol
 * @dev Provide multi-ownable functionality to a smart contract.
 * @dev Note this contract preserves the idea of a master owner where this owner
 * cannot be removed or deleted. Master owner's are the only owner's who can add
 * and remove other owner's. Transfer of master ownership is supported and can 
 * also only be transferred by the current master owner
 * @dev When master ownership is transferred the original master owner is not
 * removed from the additional owners list
 */
pragma solidity 0.4.25;

/**
 * @dev OpenZeppelin Solidity v2.0.0 imports (Using: npm openzeppelin-solidity@2.0.0)
 */
import 'openzeppelin-solidity/contracts/ownership/Ownable.sol';

contract MultiOwnable is Ownable {
	/**
	 * @dev Mapping of additional addresses that are considered owners
	 */
	mapping (address => bool) additionalOwners;

	/**
	 * @dev Modifier that overrides 'Ownable' to support multiple owners
	 */
	modifier onlyOwner() {
		// Ensure that msg.sender is an owner or revert
		require(isOwner(msg.sender), "Permission denied [owner].");
		_;
	}

	/**
	 * @dev Modifier that provides additional testing to ensure msg.sender
	 * is master owner, or first address to deploy contract
	 */
	modifier onlyMaster() {
		// Ensure that msg.sender is the master user
		require(super.isOwner(), "Permission denied [master].");
		_;
	}

	/**
	 * @dev Ownership added event for Dapps interested in this event
	 */
	event OwnershipAdded (
		address indexed addedOwner
	);
	
	/**
	 * @dev Ownership removed event for Dapps interested in this event
	 */
	event OwnershipRemoved (
		address indexed removedOwner
	);

  	/**
	 * @dev MultiOwnable .cTor responsible for initialising the masterOwner
	 * or contract super-user
	 * @dev The super user cannot be deleted from the ownership mapping and
	 * can only be transferred
	 */
	constructor() 
	Ownable()
	public
	{
		// Obtain owner of the contract (msg.sender)
		address masterOwner = owner();
		// Add the master owner to the additional owners list
		additionalOwners[masterOwner] = true;
	}

	/**
	 * @dev Returns the owner status of the specified address
	 */
	function isOwner(address _ownerAddressToLookup)
	public
	view
	returns (bool)
	{
		// Return the ownership state of the specified owner address
		return additionalOwners[_ownerAddressToLookup];
	}

	/**
	 * @dev Returns the master status of the specfied address
	 */
	function isMaster(address _masterAddressToLookup)
	public
	view
	returns (bool)
	{
		return (super.owner() == _masterAddressToLookup);
	}

	/**
	 * @dev Add a new owner address to additional owners mapping
	 * @dev Only the master owner can add additional owner addresses
	 */
	function addOwner(address _ownerToAdd)
	onlyMaster
	public
	returns (bool)
	{
		// Ensure the new owner address is not address(0)
		require(_ownerToAdd != address(0), "Invalid address specified (0x0)");
		// Ensure that new owner address is not already in the owners list
		require(!isOwner(_ownerToAdd), "Address specified already in owners list.");
		// Add new owner to additional owners mapping
		additionalOwners[_ownerToAdd] = true;
		emit OwnershipAdded(_ownerToAdd);
		return true;
	}

	/**
	 * @dev Add a new owner address to additional owners mapping
	 * @dev Only the master owner can add additional owner addresses
	 */
	function removeOwner(address _ownerToRemove)
	onlyMaster
	public
	returns (bool)
	{
		// Ensure that the address to remove is not the master owner
		require(_ownerToRemove != super.owner(), "Permission denied [master].");
		// Ensure that owner address to remove is actually an owner
		require(isOwner(_ownerToRemove), "Address specified not found in owners list.");
		// Add remove ownership from address in the additional owners mapping
		additionalOwners[_ownerToRemove] = false;
		emit OwnershipRemoved(_ownerToRemove);
		return true;
	}

	/**
	 * @dev Transfer ownership of this contract to another address
	 * @dev Only the master owner can transfer ownership to another address
	 * @dev Only existing owners can have ownership transferred to them
	 */
	function transferOwnership(address _newOwnership) 
	onlyMaster 
	public 
	{
		// Ensure the new ownership is not address(0)
		require(_newOwnership != address(0), "Invalid address specified (0x0)");
		// Ensure the new ownership address is not the current ownership addressess
		require(_newOwnership != owner(), "Address specified must not match current owner address.");		
		// Ensure that the new ownership is promoted from existing owners
		require(isOwner(_newOwnership), "Master ownership can only be transferred to an existing owner address.");
		// Call into the parent class and transfer ownership
		super.transferOwnership(_newOwnership);
		// If we get here, then add the new ownership address to the additional owners mapping
		// Note that the original master owner address was not removed and is still an owner until removed
		additionalOwners[_newOwnership] = true;
	}

}