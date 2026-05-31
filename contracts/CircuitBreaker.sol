// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./ProtocolRegistry.sol";
import "./AnomalyDetector.sol";

/**
 * @title CircuitBreaker
 * @notice Main circuit breaker contract. Auto-pauses protocols when
 *         anomalies are detected. Supports:
 *         1. Auto-pause on anomaly detection
 *         2. Manual pause by governance
 *         3. Emergency multi-sig pause
 *         4. Gradual unpause with timelock
 */
contract CircuitBreaker {
    enum PauseReason {
        NONE,
        ANOMALY_DETECTED,
        GOVERNANCE_PAUSE,
        EMERGENCY_PAUSE,
        MANUAL_PAUSE
    }

    struct PauseRecord {
        address protocol;
        PauseReason reason;
        address pausedBy;
        uint256 timestamp;
        uint256 anomalyScore;
        bool unpaused;
        uint256 unpausedAt;
    }

    ProtocolRegistry public registry;
    AnomalyDetector public detector;

    address public governance;
    address[] public emergencySigners;
    uint256 public requiredSignatures;
    uint256 public constant PAUSE_COOLDOWN = 1 hours;
    uint256 public constant UNPAUSE_DELAY = 30 minutes;

    // State
    mapping(address => bool) public paused;
    mapping(address => PauseReason) public pauseReason;
    mapping(address => uint256) public pausedAt;
    mapping(address => uint256) public pauseCount;
    PauseRecord[] public pauseHistory;

    // Emergency multi-sig
    mapping(address => mapping(bytes32 => bool)) public emergencyApprovals;
    mapping(bytes32 => uint256) public approvalCount;
    mapping(bytes32 => bool) public executed;

    // Events
    event ProtocolPaused(
        address indexed protocol,
        PauseReason reason,
        address indexed pausedBy,
        uint256 anomalyScore,
        uint256 timestamp
    );
    event ProtocolUnpaused(address indexed protocol, address indexed unpausedBy, uint256 timestamp);
    event EmergencyApproval(address indexed signer, bytes32 indexed proposalHash);
    event EmergencyExecuted(bytes32 indexed proposalHash, address indexed protocol);

    modifier onlyGovernance() {
        require(msg.sender == governance, "Only governance");
        _;
    }

    modifier onlyWhenNotPaused(address protocol) {
        require(!paused[protocol], "Protocol is paused");
        _;
    }

    modifier onlyWhenPaused(address protocol) {
        require(paused[protocol], "Protocol is not paused");
        _;
    }

    constructor(
        address _registry,
        address _detector,
        address _governance,
        address[] memory _emergencySigners,
        uint256 _requiredSignatures
    ) {
        registry = ProtocolRegistry(_registry);
        detector = AnomalyDetector(_detector);
        governance = _governance;
        emergencySigners = _emergencySigners;
        requiredSignatures = _requiredSignatures;
    }

    /**
     * @notice Auto-pause triggered by anomaly detector
     */
    function autoPause(
        address protocol,
        uint256 txGasUsed,
        uint256 txValue,
        bytes4 functionSelector
    ) external onlyWhenNotPaused(protocol) {
        (uint256 score, bool isAnomaly) = detector.analyzeTransaction(
            protocol,
            txGasUsed,
            txValue,
            functionSelector
        );

        if (isAnomaly) {
            _pause(protocol, PauseReason.ANOMALY_DETECTED, score);
        }
    }

    /**
     * @notice Governance can manually pause a protocol
     */
    function governancePause(address protocol) external onlyGovernance onlyWhenNotPaused(protocol) {
        _pause(protocol, PauseReason.GOVERNANCE_PAUSE, 0);
    }

    /**
     * @notice Emergency pause via multi-sig
     */
    function emergencyPause(address protocol) external onlyWhenNotPaused(protocol) {
        require(_isEmergencySigner(msg.sender), "Not emergency signer");

        bytes32 proposalHash = keccak256(abi.encodePacked("emergency_pause", protocol));

        if (!emergencyApprovals[msg.sender][proposalHash]) {
            emergencyApprovals[msg.sender][proposalHash] = true;
            approvalCount[proposalHash]++;
        }

        if (approvalCount[proposalHash] >= requiredSignatures && !executed[proposalHash]) {
            executed[proposalHash] = true;
            _pause(protocol, PauseReason.EMERGENCY_PAUSE, 0);
            emit EmergencyExecuted(proposalHash, protocol);
        }

        emit EmergencyApproval(msg.sender, proposalHash);
    }

    /**
     * @notice Unpause a protocol (with timelock for non-emergency)
     */
    function unpause(address protocol) external onlyWhenPaused(protocol) {
        if (pauseReason[protocol] == PauseReason.EMERGENCY_PAUSE) {
            require(msg.sender == governance, "Only governance can unpause emergency");
        } else {
            require(
                block.timestamp >= pausedAt[protocol] + UNPAUSE_DELAY,
                "Timelock not expired"
            );
        }

        paused[protocol] = false;
        pauseReason[protocol] = PauseReason.NONE;

        // Update pause record
        uint256 lastIdx = pauseHistory.length - 1;
        pauseHistory[lastIdx].unpaused = true;
        pauseHistory[lastIdx].unpausedAt = block.timestamp;

        emit ProtocolUnpaused(protocol, msg.sender, block.timestamp);
    }

    /**
     * @notice Check if a protocol is safe to use
     */
    function isSafe(address protocol) external view returns (bool) {
        return !paused[protocol];
    }

    /**
     * @notice Get pause status details
     */
    function getPauseStatus(address protocol) external view returns (
        bool isPaused,
        PauseReason reason,
        uint256 since,
        uint256 count
    ) {
        return (
            paused[protocol],
            pauseReason[protocol],
            pausedAt[protocol],
            pauseCount[protocol]
        );
    }

    function getPauseHistoryLength() external view returns (uint256) {
        return pauseHistory.length;
    }

    function getPauseRecord(uint256 index) external view returns (PauseRecord memory) {
        require(index < pauseHistory.length, "Index out of bounds");
        return pauseHistory[index];
    }

    function _pause(address protocol, PauseReason reason, uint256 anomalyScore) internal {
        paused[protocol] = true;
        pauseReason[protocol] = reason;
        pausedAt[protocol] = block.timestamp;
        pauseCount[protocol]++;

        pauseHistory.push(PauseRecord({
            protocol: protocol,
            reason: reason,
            pausedBy: msg.sender,
            timestamp: block.timestamp,
            anomalyScore: anomalyScore,
            unpaused: false,
            unpausedAt: 0
        }));

        emit ProtocolPaused(protocol, reason, msg.sender, anomalyScore, block.timestamp);
    }

    function _isEmergencySigner(address signer) internal view returns (bool) {
        for (uint256 i = 0; i < emergencySigners.length; i++) {
            if (emergencySigners[i] == signer) return true;
        }
        return false;
    }

    function setGovernance(address newGovernance) external onlyGovernance {
        governance = newGovernance;
    }

    receive() external payable {}
}
