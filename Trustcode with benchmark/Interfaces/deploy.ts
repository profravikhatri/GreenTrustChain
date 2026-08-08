import { ethers } from "hardhat";
import fs from "fs";
import path from "path";

interface DeploymentRecord {
  contract: string;
  address: string;
  deployer: string;
  network: string;
  chainId: string;
  blockNumber: number;
  timestamp: string;
}

async function main() {
  console.log("\n==============================================");
  console.log(" GreenTrustChain Experimental Deployment");
  console.log("==============================================\n");

  const [deployer] = await ethers.getSigners();

  const network = await ethers.provider.getNetwork();
  const block = await ethers.provider.getBlock("latest");

  if (!block) {
    throw new Error("Unable to obtain latest block");
  }

  console.log("Deployer :", deployer.address);
  console.log("Network  :", network.name);
  console.log("Chain ID :", network.chainId.toString());
  console.log("Balance  :",
    ethers.formatEther(
      await ethers.provider.getBalance(deployer.address)
    ),
    "ETH"
  );

  /*
   * ------------------------------------------------------------
   * 1. GreenTrustChain
   * ------------------------------------------------------------
   */

  console.log("\n[1/4] Deploying GreenTrustChain...");

  const GreenTrustChain =
    await ethers.getContractFactory("GreenTrustChain");

  const greenTrustChain =
    await GreenTrustChain.deploy();

  await greenTrustChain.waitForDeployment();

  const greenAddress =
    await greenTrustChain.getAddress();

  console.log(
    "GreenTrustChain:",
    greenAddress
  );


  /*
   * ------------------------------------------------------------
   * 2. DeterministicBaseline
   * ------------------------------------------------------------
   */

  console.log(
    "\n[2/4] Deploying DeterministicBaseline..."
  );

  const DeterministicBaseline =
    await ethers.getContractFactory(
      "DeterministicBaseline"
    );

  const deterministicBaseline =
    await DeterministicBaseline.deploy();

  await deterministicBaseline.waitForDeployment();

  const deterministicAddress =
    await deterministicBaseline.getAddress();

  console.log(
    "DeterministicBaseline:",
    deterministicAddress
  );


  /*
   * ------------------------------------------------------------
   * 3. TrustOnlyBaseline
   * ------------------------------------------------------------
   */

  console.log(
    "\n[3/4] Deploying TrustOnlyBaseline..."
  );

  const TrustOnlyBaseline =
    await ethers.getContractFactory(
      "TrustOnlyBaseline"
    );

  const trustOnlyBaseline =
    await TrustOnlyBaseline.deploy();

  await trustOnlyBaseline.waitForDeployment();

  const trustOnlyAddress =
    await trustOnlyBaseline.getAddress();

  console.log(
    "TrustOnlyBaseline:",
    trustOnlyAddress
  );


  /*
   * ------------------------------------------------------------
   * 4. EnergyAwareBaseline
   * ------------------------------------------------------------
   */

  console.log(
    "\n[4/4] Deploying EnergyAwareBaseline..."
  );

  const EnergyAwareBaseline =
    await ethers.getContractFactory(
      "EnergyAwareBaseline"
    );

  const energyAwareBaseline =
    await EnergyAwareBaseline.deploy();

  await energyAwareBaseline.waitForDeployment();

  const energyAwareAddress =
    await energyAwareBaseline.getAddress();

  console.log(
    "EnergyAwareBaseline:",
    energyAwareAddress
  );


  /*
   * ------------------------------------------------------------
   * Register benchmark participant
   * ------------------------------------------------------------
   *
   * The deployer is used as the controlled experimental
   * participant to keep the first benchmark deterministic.
   */

  console.log(
    "\nRegistering benchmark participant..."
  );

  await (
    await greenTrustChain.registerParticipant(
      deployer.address
    )
  ).wait();

  await (
    await deterministicBaseline.registerParticipant(
      deployer.address
    )
  ).wait();

  await (
    await trustOnlyBaseline.registerParticipant(
      deployer.address
    )
  ).wait();

  await (
    await energyAwareBaseline.registerParticipant(
      deployer.address
    )
  ).wait();


  /*
   * ------------------------------------------------------------
   * Deployment manifest
   * ------------------------------------------------------------
   */

  const deploymentBlock =
    await ethers.provider.getBlock("latest");

  if (!deploymentBlock) {
    throw new Error(
      "Unable to obtain deployment block"
    );
  }

  const deploymentTime =
    new Date().toISOString();

  const deployments: DeploymentRecord[] = [
    {
      contract: "GreenTrustChain",
      address: greenAddress,
      deployer: deployer.address,
      network: network.name,
      chainId: network.chainId.toString(),
      blockNumber: deploymentBlock.number,
      timestamp: deploymentTime
    },
    {
      contract: "DeterministicBaseline",
      address: deterministicAddress,
      deployer: deployer.address,
      network: network.name,
      chainId: network.chainId.toString(),
      blockNumber: deploymentBlock.number,
      timestamp: deploymentTime
    },
    {
      contract: "TrustOnlyBaseline",
      address: trustOnlyAddress,
      deployer: deployer.address,
      network: network.name,
      chainId: network.chainId.toString(),
      blockNumber: deploymentBlock.number,
      timestamp: deploymentTime
    },
    {
      contract: "EnergyAwareBaseline",
      address: energyAwareAddress,
      deployer: deployer.address,
      network: network.name,
      chainId: network.chainId.toString(),
      blockNumber: deploymentBlock.number,
      timestamp: deploymentTime
    }
  ];


  /*
   * ------------------------------------------------------------
   * Save deployment manifest
   * ------------------------------------------------------------
   */

  const deploymentDirectory =
    path.join(
      process.cwd(),
      "deployments"
    );

  fs.mkdirSync(
    deploymentDirectory,
    {
      recursive: true
    }
  );

  const filename =
    `${network.name}-${network.chainId.toString()}.json`;

  const deploymentPath =
    path.join(
      deploymentDirectory,
      filename
    );

  fs.writeFileSync(
    deploymentPath,
    JSON.stringify(
      {
        experiment: "GreenTrustChain",
        version: "1.0",
        deployedAt: deploymentTime,
        deployer: deployer.address,
        network: network.name,
        chainId: network.chainId.toString(),
        contracts: deployments
      },
      null,
      2
    )
  );


  /*
   * ------------------------------------------------------------
   * Final output
   * ------------------------------------------------------------
   */

  console.log("\n==============================================");
  console.log(" Deployment Completed");
  console.log("==============================================");

  console.log(
    "\nGreenTrustChain       :",
    greenAddress
  );

  console.log(
    "DeterministicBaseline :",
    deterministicAddress
  );

  console.log(
    "TrustOnlyBaseline     :",
    trustOnlyAddress
  );

  console.log(
    "EnergyAwareBaseline   :",
    energyAwareAddress
  );

  console.log(
    "\nDeployment manifest:",
    deploymentPath
  );

  console.log(
    "\nThese addresses should be treated as experimental"
  );

  console.log(
    "artifacts and must not be hard-coded into source code."
  );
}


main().catch(
  (error) => {
    console.error(error);
    process.exitCode = 1;
  }
);