// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ProtocolRegistry
 * @notice Registry of protocols protected by the circuit breaker.
 *         Protocols register themselves and set monitoring parameters.
 */
contract ProtocolRegistry {
    struct Protocol {
        address contractAddress;
        address owner;
        string name;
        uint256 maxTxGas;           // Max gas per transaction (anomaly threshold)
        uint256 maxTxValue;         // Max ETH value per transaction
        uint256 maxTxFrequency;     // Max transactions per block
        uint256 totalValueLocked;   // Total value locked in contract
        bool active;
        uint256 registeredAt;
    }

    mapping(address => Protocol) public protocols;
    address[] public registeredContracts;
    address public admin;

    event ProtocolRegistered(address indexed contractAddress, string name, uint256 timestamp);
    event ProtocolUpdated(address indexed contractAddress, string field, uint256 value);
    event ProtocolRemoved(address indexed contractAddress);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin");
        _;
    }

    modifier onlyProtocolOwner(address contractAddress) {
        require(protocols[contractAddress].owner == msg.sender, "Only protocol owner");
        _;
    }

    constructor() {
        admin = msg.sender;
    }

    /**
     * @notice Register a protocol for monitoring
     */
    function registerProtocol(
        address contractAddress,
        string calldata name,
        uint256 maxTxGas,
        uint256 maxTxValue,
        uint256 maxTxFrequency,
        uint256 totalValueLocked
    ) external {
        require(contractAddress != address(0), "Invalid address");
        require(!protocols[contractAddress].active, "Already registered");
        require(bytes(name).length > 0, "Name required");

        protocols[contractAddress] = Protocol({
            contractAddress: contractAddress,
            owner: msg.sender,
            name: name,
            maxTxGas: maxTxGas,
            maxTxValue: maxTxValue,
            maxTxFrequency: maxTxFrequency,
            totalValueLocked: totalValueLocked,
            active: true,
            registeredAt: block.timestamp
        });

        registeredContracts.push(contractAddress);
        emit ProtocolRegistered(contractAddress, name, block.timestamp);
    }

    /**
     * @notice Update protocol monitoring parameters
     */
    function updateProtocol(
        address contractAddress,
        uint256 maxTxGas,
        uint256 maxTxValue,
        uint256 maxTxFrequency
    ) external onlyProtocolOwner(contractAddress) {
        protocols[contractAddress].maxTxGas = maxTxGas;
        protocols[contractAddress].maxTxValue = maxTxValue;
        protocols[contractAddress].maxTxFrequency = maxTxFrequency;
    }

    /**
     * @notice Remove a protocol from monitoring
     */
    function removeProtocol(address contractAddress) external {
        require(
            msg.sender == admin || protocols[contractAddress].owner == msg.sender,
            "Not authorized"
        );
        protocols[contractAddress].active = false;
        emit ProtocolRemoved(contractAddress);
    }

    function isRegistered(address contractAddress) external view returns (bool) {
        return protocols[contractAddress].active;
    }

    function getProtocolCount() external view returns (uint256) {
        return registeredContracts.length;
    }

    function setAdmin(address newAdmin) external {
        require(msg.sender == admin, "Only admin");
        admin = newAdmin;
    }
}
