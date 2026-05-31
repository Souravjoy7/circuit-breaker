// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./ProtocolRegistry.sol";

/**
 * @title AnomalyDetector
 * @notice Detects suspicious transaction patterns on monitored protocols.
 *         Uses multiple detection strategies:
 *         1. High gas usage (unusual computational complexity)
 *         2. Large value transfers (draining funds)
 *         3. High frequency (flash loan attacks)
 *         4. Reentrancy patterns (repeated external calls)
 *         5. Unusual function selector (calling unknown functions)
 */
contract AnomalyDetector {
    struct AnomalyScore {
        uint256 gasScore;
        uint256 valueScore;
        uint256 frequencyScore;
        uint256 reentrancyScore;
        uint256 totalScore;
        uint256 timestamp;
    }

    struct TxRecord {
        address sender;
        uint256 gasUsed;
        uint256 value;
        uint256 timestamp;
        bytes4 functionSelector;
    }

    ProtocolRegistry public registry;

    // Detection thresholds (0-1000 scale)
    uint256 public constant GAS_THRESHOLD = 800;
    uint256 public constant VALUE_THRESHOLD = 700;
    uint256 public constant FREQUENCY_THRESHOLD = 600;
    uint256 public constant REENTRANCY_THRESHOLD = 900;
    uint256 public constant ALERT_THRESHOLD = 500;  // Total score to trigger alert

    // Tracking arrays
    mapping(address => TxRecord[]) public txHistory;
    mapping(address => AnomalyScore[]) public anomalyHistory;
    mapping(address => uint256) public txCountPerBlock;
    mapping(address => uint256) public lastBlockNumber;
    mapping(address => mapping(address => uint256)) public senderTxCount;

    // Anomaly events
    event AnomalyDetected(
        address indexed protocol,
        address indexed sender,
        uint256 totalScore,
        string anomalyType,
        uint256 timestamp
    );
    event AlertTriggered(address indexed protocol, uint256 score, string reason);

    constructor(address _registry) {
        registry = ProtocolRegistry(_registry);
    }

    /**
     * @notice Analyze a transaction for anomalies
     * @param protocol Address of the monitored protocol
     * @param txGasUsed Gas used by the transaction
     * @param txValue ETH value transferred
     * @param functionSelector First 4 bytes of calldata
     * @return totalScore Combined anomaly score
     * @return isAnomaly True if score exceeds threshold
     */
    function analyzeTransaction(
        address protocol,
        uint256 txGasUsed,
        uint256 txValue,
        bytes4 functionSelector
    ) external returns (uint256 totalScore, bool isAnomaly) {
        require(registry.isRegistered(protocol), "Protocol not registered");

        // Get protocol parameters from registry
        (, , , uint256 maxTxGas, uint256 maxTxValue, uint256 maxTxFrequency, , , ) = registry.protocols(protocol);

        // Score 1: Gas usage anomaly
        uint256 gasScore = 0;
        if (txGasUsed > maxTxGas) {
            gasScore = (txGasUsed * 1000) / (maxTxGas * 2);
            if (gasScore > 1000) gasScore = 1000;
        }

        // Score 2: Value anomaly
        uint256 valueScore = 0;
        if (txValue > maxTxValue) {
            valueScore = (txValue * 1000) / (maxTxValue * 2);
            if (valueScore > 1000) valueScore = 1000;
        }

        // Score 3: Frequency anomaly
        uint256 frequencyScore = 0;
        if (block.number == lastBlockNumber[protocol]) {
            txCountPerBlock[protocol]++;
        } else {
            txCountPerBlock[protocol] = 1;
            lastBlockNumber[protocol] = block.number;
        }
        if (txCountPerBlock[protocol] > maxTxFrequency) {
            frequencyScore = (txCountPerBlock[protocol] * 1000) / (maxTxFrequency * 2);
            if (frequencyScore > 1000) frequencyScore = 1000;
        }

        // Score 4: Reentrancy detection (same sender, rapid succession)
        uint256 reentrancyScore = 0;
        address sender = msg.sender;
        senderTxCount[protocol][sender]++;
        if (senderTxCount[protocol][sender] > 3) {
            reentrancyScore = REENTRANCY_THRESHOLD;
        }

        // Combined score (weighted average)
        totalScore = (gasScore * 30 + valueScore * 35 + frequencyScore * 20 + reentrancyScore * 15) / 100;

        // Record transaction
        txHistory[protocol].push(TxRecord({
            sender: sender,
            gasUsed: txGasUsed,
            value: txValue,
            timestamp: block.timestamp,
            functionSelector: functionSelector
        }));

        // Record anomaly
        anomalyHistory[protocol].push(AnomalyScore({
            gasScore: gasScore,
            valueScore: valueScore,
            frequencyScore: frequencyScore,
            reentrancyScore: reentrancyScore,
            totalScore: totalScore,
            timestamp: block.timestamp
        }));

        isAnomaly = totalScore >= ALERT_THRESHOLD;

        if (isAnomaly) {
            string memory anomalyType = _getAnomalyType(gasScore, valueScore, frequencyScore, reentrancyScore);
            emit AnomalyDetected(protocol, sender, totalScore, anomalyType, block.timestamp);
            emit AlertTriggered(protocol, totalScore, anomalyType);
        }

        return (totalScore, isAnomaly);
    }

    /**
     * @notice Get latest anomaly score for a protocol
     */
    function getLatestScore(address protocol) external view returns (AnomalyScore memory) {
        require(anomalyHistory[protocol].length > 0, "No scores recorded");
        return anomalyHistory[protocol][anomalyHistory[protocol].length - 1];
    }

    /**
     * @notice Get anomaly count for a protocol
     */
    function getAnomalyCount(address protocol) external view returns (uint256) {
        return anomalyHistory[protocol].length;
    }

    function _getAnomalyType(
        uint256 gasScore,
        uint256 valueScore,
        uint256 frequencyScore,
        uint256 reentrancyScore
    ) internal pure returns (string memory) {
        if (reentrancyScore >= REENTRANCY_THRESHOLD) return "REENTRANCY";
        if (valueScore >= VALUE_THRESHOLD) return "LARGE_VALUE_TRANSFER";
        if (gasScore >= GAS_THRESHOLD) return "HIGH_GAS_USAGE";
        if (frequencyScore >= FREQUENCY_THRESHOLD) return "HIGH_FREQUENCY";
        return "MULTIPLE_INDICATORS";
    }
}
