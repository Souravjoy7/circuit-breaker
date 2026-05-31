import hre from "hardhat";

async function main() {
  const { ethers } = await hre.network.connect();
  const [deployer] = await ethers.getSigners();

  const network = await ethers.provider.getNetwork();
  const chainId = Number(network.chainId);
  const networkName = chainId === 59141 ? "Linea" : chainId === 84532 ? "Base" : `Chain ${chainId}`;
  console.log(`Deploying to ${networkName} Sepolia (chainId: ${chainId})...`);
  console.log(`Deployer: ${deployer.address}`);
  console.log(`Balance: ${ethers.formatEther(await ethers.provider.getBalance(deployer.address))} ETH`);

  // Deploy
  const Registry = await ethers.getContractFactory("ProtocolRegistry");
  const regDeploy = await Registry.deploy();
  await regDeploy.waitForDeployment();
  const registryAddr = await regDeploy.getAddress();
  console.log(`\n  ProtocolRegistry: ${registryAddr}`);

  const Detector = await ethers.getContractFactory("AnomalyDetector");
  const detDeploy = await Detector.deploy(registryAddr);
  await detDeploy.waitForDeployment();
  const detectorAddr = await detDeploy.getAddress();
  console.log(`  AnomalyDetector:  ${detectorAddr}`);

  const Breaker = await ethers.getContractFactory("CircuitBreaker");
  const brkDeploy = await Breaker.deploy(registryAddr, detectorAddr, deployer.address, [deployer.address], 1);
  await brkDeploy.waitForDeployment();
  const breakerAddr = await brkDeploy.getAddress();
  console.log(`  CircuitBreaker:   ${breakerAddr}`);

  // Create instances
  const rArt = await hre.artifacts.readArtifact("ProtocolRegistry");
  const dArt = await hre.artifacts.readArtifact("AnomalyDetector");
  const bArt = await hre.artifacts.readArtifact("CircuitBreaker");
  const registry = new ethers.Contract(registryAddr, rArt.abi, deployer);
  const detector = new ethers.Contract(detectorAddr, dArt.abi, deployer);
  const breaker = new ethers.Contract(breakerAddr, bArt.abi, deployer);

  // Demo
  console.log("\nRunning demo...");

  let tx = await registry.registerProtocol(deployer.address, "DemoProtocol", 500000, ethers.parseEther("10"), 5, ethers.parseEther("1000"));
  await ethers.provider.waitForTransaction(tx.hash, 1);
  console.log("  1. Protocol registered");

  // Verify registration
  const isReg = await registry.isRegistered(deployer.address);
  console.log(`     Verified: ${isReg}`);

  tx = await detector.analyzeTransaction(deployer.address, 200000, ethers.parseEther("1"), "0xa9059cbb");
  await ethers.provider.waitForTransaction(tx.hash, 1);
  console.log("  2. Normal tx analyzed");

  tx = await detector.analyzeTransaction(deployer.address, 600000, ethers.parseEther("20"), "0x12345678");
  await ethers.provider.waitForTransaction(tx.hash, 1);
  console.log("  3. Anomalous tx analyzed");

  tx = await breaker.autoPause(deployer.address, 600000, ethers.parseEther("20"), "0x12345678");
  await ethers.provider.waitForTransaction(tx.hash, 1);
  console.log("  4. Auto-pause triggered");

  const [isPaused, , , count] = await breaker.getPauseStatus(deployer.address);
  console.log(`\n  Paused: ${isPaused} | Pause count: ${count}`);

  const baseUrl = chainId === 59141 ? "https://sepolia.lineascan.build" : "https://sepolia.basescan.org";
  console.log(`\nVerify on ${networkName} Explorer:`);
  console.log(`  ProtocolRegistry: ${baseUrl}/address/${registryAddr}`);
  console.log(`  AnomalyDetector:  ${baseUrl}/address/${detectorAddr}`);
  console.log(`  CircuitBreaker:   ${baseUrl}/address/${breakerAddr}`);

  console.log(JSON.stringify({ network: `${networkName.toLowerCase()}_sepolia`, chainId, deployer: deployer.address, contracts: { ProtocolRegistry: registryAddr, AnomalyDetector: detectorAddr, CircuitBreaker: breakerAddr } }, null, 2));
}

main().then(() => process.exit(0)).catch(e => { console.error(e); process.exit(1); });
