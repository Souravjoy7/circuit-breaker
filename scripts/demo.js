import hre from "hardhat";

async function main() {
  const { ethers } = await hre.network.connect();

  console.log("═".repeat(60));
  console.log("  Circuit Breaker — Decentralized Exploit Detection Demo");
  console.log("  Real-time anomaly detection + auto-pause for smart contracts");
  console.log("═".repeat(60));

  const [deployer, signer1, signer2] = await ethers.getSigners();
  console.log(`\nDeployer: ${deployer.address}`);
  console.log(`Signer1:  ${signer1.address}`);
  console.log(`Signer2:  ${signer2.address}`);

  // ═══ Deploy All Contracts ═══
  console.log("\n" + "━".repeat(60));
  console.log("  DEPLOYING CONTRACTS");
  console.log("━".repeat(60));

  const Registry = await ethers.getContractFactory("ProtocolRegistry");
  const registryDeploy = await Registry.deploy();
  await registryDeploy.waitForDeployment();
  const registryAddr = await registryDeploy.getAddress();
  const registry = new ethers.Contract(registryAddr, (await hre.artifacts.readArtifact("ProtocolRegistry")).abi, deployer);
  console.log(`  ProtocolRegistry:   ${registryAddr}`);

  const Detector = await ethers.getContractFactory("AnomalyDetector");
  const detectorDeploy = await Detector.deploy(registryAddr);
  await detectorDeploy.waitForDeployment();
  const detectorAddr = await detectorDeploy.getAddress();
  const detector = new ethers.Contract(detectorAddr, (await hre.artifacts.readArtifact("AnomalyDetector")).abi, deployer);
  console.log(`  AnomalyDetector:    ${detectorAddr}`);

  const Breaker = await ethers.getContractFactory("CircuitBreaker");
  const breakerDeploy = await Breaker.deploy(
    registryAddr,
    detectorAddr,
    deployer.address,
    [deployer.address, signer1.address, signer2.address],
    2
  );
  await breakerDeploy.waitForDeployment();
  const breakerAddr = await breakerDeploy.getAddress();
  const breaker = new ethers.Contract(breakerAddr, (await hre.artifacts.readArtifact("CircuitBreaker")).abi, deployer);
  console.log(`  CircuitBreaker:     ${breakerAddr}`);

  // ═══ 1. Register Protocol ═══
  console.log("\n" + "━".repeat(60));
  console.log("  1. REGISTER PROTOCOL FOR MONITORING");
  console.log("━".repeat(60));

  // Register a mock DeFi protocol
  const mockProtocol = ethers.Wallet.createRandom().address;
  let tx = await registry.registerProtocol(
    mockProtocol,
    "MockDeFi Protocol",
    500000,     // maxTxGas: 500K
    ethers.parseEther("10"),  // maxTxValue: 10 ETH
    5,          // maxTxFrequency: 5 per block
    ethers.parseEther("1000") // TVL: 1000 ETH
  );
  await tx.wait();
  console.log(`  Registered: MockDeFi Protocol at ${mockProtocol.slice(0, 18)}...`);
  console.log(`  Max gas: 500K | Max value: 10 ETH | Max freq: 5/block`);

  // ═══ 2. Normal Transaction (No Anomaly) ═══
  console.log("\n" + "━".repeat(60));
  console.log("  2. NORMAL TRANSACTION — NO ANOMALY");
  console.log("━".repeat(60));

  const normalTx = await detector.analyzeTransaction(
    mockProtocol,
    200000,                    // 200K gas (under 500K limit)
    ethers.parseEther("1"),    // 1 ETH (under 10 ETH limit)
    "0xa9059cbb"               // transfer() selector
  );
  const normalReceipt = await normalTx.wait();
  const normalResult = await detector.getLatestScore(mockProtocol);
  console.log(`  Gas used in tx: ${normalReceipt.gasUsed}`);
  console.log(`  Anomaly score: ${normalResult.totalScore}/1000`);
  console.log(`  Is anomaly: ${normalResult.totalScore >= 500 ? "YES" : "NO"}`);

  // ═══ 3. Anomalous Transaction (High Value) ═══
  console.log("\n" + "━".repeat(60));
  console.log("  3. ANOMALOUS TRANSACTION — HIGH VALUE TRANSFER");
  console.log("━".repeat(60));

  const anomalousTx = await detector.analyzeTransaction(
    mockProtocol,
    300000,                    // 300K gas
    ethers.parseEther("15"),   // 15 ETH (OVER 10 ETH limit!)
    "0xa9059cbb"
  );
  await anomalousTx.wait();
  const anomalousResult = await detector.getLatestScore(mockProtocol);
  console.log(`  Anomaly score: ${anomalousResult.totalScore}/1000`);
  console.log(`  Value score: ${anomalousResult.valueScore}/1000`);
  console.log(`  Is anomaly: ${anomalousResult.totalScore >= 500 ? "YES ⚠️" : "NO"}`);

  // ═══ 4. Auto-Pause Triggered ═══
  console.log("\n" + "━".repeat(60));
  console.log("  4. AUTO-PAUSE TRIGGERED BY ANOMALY");
  console.log("━".repeat(60));

  // Check if protocol is safe before
  const isSafeBefore = await breaker.isSafe(mockProtocol);
  console.log(`  Protocol safe before: ${isSafeBefore}`);

  // Trigger auto-pause with even more suspicious activity
  const autoPauseTx = await breaker.autoPause(
    mockProtocol,
    600000,                    // 600K gas (OVER 500K limit!)
    ethers.parseEther("20"),   // 20 ETH (OVER 10 ETH limit!)
    "0x12345678"               // Unknown function selector
  );
  await autoPauseTx.wait();

  // Check if protocol is paused
  const isSafeAfter = await breaker.isSafe(mockProtocol);
  const [isPaused, reason, since, count] = await breaker.getPauseStatus(mockProtocol);
  console.log(`  Protocol safe after: ${isSafeAfter}`);
  console.log(`  Paused: ${isPaused}`);
  console.log(`  Reason: ${reason === 1 ? "ANOMALY_DETECTED" : reason}`);
  console.log(`  Pause count: ${count}`);

  // ═══ 5. Emergency Multi-Sig Pause ═══
  console.log("\n" + "━".repeat(60));
  console.log("  5. EMERGENCY MULTI-SIG PAUSE");
  console.log("━".repeat(60));

  // Register another protocol for emergency demo
  const mockProtocol2 = ethers.Wallet.createRandom().address;
  tx = await registry.registerProtocol(
    mockProtocol2,
    "MockNFT Protocol",
    300000,
    ethers.parseEther("5"),
    3,
    ethers.parseEther("500")
  );
  await tx.wait();
  console.log(`  Registered: MockNFT Protocol`);

  // Signer1 approves emergency pause
  const emergencyTx1 = await breaker.connect(signer1).emergencyPause(mockProtocol2);
  await emergencyTx1.wait();
  console.log(`  Signer1 approved emergency pause`);

  // Signer2 approves emergency pause (2 required)
  const emergencyTx2 = await breaker.connect(signer2).emergencyPause(mockProtocol2);
  await emergencyTx2.wait();
  console.log(`  Signer2 approved emergency pause`);

  const [isPaused2, reason2, , count2] = await breaker.getPauseStatus(mockProtocol2);
  console.log(`  Protocol paused: ${isPaused2}`);
  console.log(`  Reason: ${reason2 === 2 ? "EMERGENCY_PAUSE" : reason2}`);
  console.log(`  Pause count: ${count2}`);

  // ═══ 6. Governance Unpause ═══
  console.log("\n" + "━".repeat(60));
  console.log("  6. GOVERNANCE UNPAUSE (with timelock)");
  console.log("━".repeat(60));

  // Note: In demo, timelock may not have expired yet
  // In production, wait 30 minutes
  console.log(`  Timelock: 30 minutes for non-emergency unpause`);
  console.log(`  Emergency unpause: governance only`);

  // ═══ 7. Check Pause History ═══
  console.log("\n" + "━".repeat(60));
  console.log("  7. PAUSE HISTORY (ON-CHAIN PROOF)");
  console.log("━".repeat(60));

  const historyLength = await breaker.getPauseHistoryLength();
  console.log(`  Total pause events: ${historyLength}`);

  for (let i = 0; i < Number(historyLength); i++) {
    const record = await breaker.getPauseRecord(i);
    const reasons = ["NONE", "ANOMALY", "GOVERNANCE", "EMERGENCY", "MANUAL"];
    console.log(`  [${i}] Protocol: ${record.protocol.slice(0, 14)}... | Reason: ${reasons[record.reason]} | Score: ${record.anomalyScore} | Unpaused: ${record.unpaused}`);
  }

  // ═══ Summary ═══
  console.log("\n" + "═".repeat(60));
  console.log("  SUMMARY — Decentralized Circuit Breaker");
  console.log("═".repeat(60));
  console.log(`  Contracts deployed:     3`);
  console.log(`  Protocols monitored:    ${await registry.getProtocolCount()}`);
  console.log(`  Pause events recorded:  ${historyLength}`);
  console.log(`  Auto-pause triggered:   1`);
  console.log(`  Emergency pauses:       1`);
  console.log("\n  All events stored on-chain — verifiable by anyone");
  console.log("═".repeat(60));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
