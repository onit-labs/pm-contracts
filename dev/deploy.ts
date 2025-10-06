#!/usr/bin/env node

import { execSync } from "node:child_process";
import dotenv from "dotenv";

dotenv.config();

// Parse arguments, handling flags that may come before positional args
const args = process.argv.slice(2);
const nonFlagArgs = args.filter((arg) => !arg.startsWith("-"));

const network = nonFlagArgs[0];
const deployType = nonFlagArgs[1] || "both"; // router, factory, or both
let isAnvilRunning = network !== "local";
let checkCount = 0;
const MAX_CHECK_COUNT = 10;

if (process.env.APP_ENV !== "development") {
  console.log("Not running in non-development environment, exiting...");
  process.exit(0);
}

// Validate deploy type
if (!["router", "factory", "both"].includes(deployType)) {
  console.error("Invalid deploy type. Use: router, factory, or both");
  console.log("Usage: deploy.ts <network> [deploy-type] [-b] [-p]");
  console.log("  <network>: Network to deploy to");
  console.log("  [deploy-type]: What to deploy - 'router', 'factory', or 'both' (default: both)");
  console.log("  -b: Broadcast transactions");
  console.log("  -p: Use production profile");
  process.exit(1);
}

// check if anvil is running every second until it is ( 3 seconds )
do {
  if (isAnvilRunning) break;
  checkCount++;
  isAnvilRunning = await fetch("http://localhost:8545", {
    method: "POST",
    body: JSON.stringify({
      jsonrpc: "2.0",
      method: "eth_blockNumber",
      params: [],
      id: 1,
    }),
  })
    .then((res) => res.ok)
    .catch(() => {
      console.log("Anvil is not running, waiting for it to start...");
      return false;
    });
  if (!isAnvilRunning) {
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
} while (!isAnvilRunning && checkCount < MAX_CHECK_COUNT);

if (!isAnvilRunning) process.exit(0);

const broadcast = process.argv.includes("-b") ? "--broadcast" : "";
const profile = process.argv.includes("-p") ? "prod" : "";
const verify = network !== "local" && broadcast ? "--verify" : "";

// If local deploy we use an anvil private key
// if (network === "local") {
//   process.env.DEPLOYER_PRIVATE_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
//   process.env.ONIT_OWNER_ADDRESS = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";
// }

if (profile === "prod") {
  process.env.FOUNDRY_PROFILE = "prod";
}

// Deploy the Factory
if (deployType === "factory" || deployType === "both") {
  const factoryCommand = `forge script script/DeployFactory.s.sol:OnitInfiniteOutcomeDPMFactoryDeployer --rpc-url ${network} ${broadcast} ${verify} -vvvv`;
  console.log("Deploying Factory...");
  try {
    execSync(factoryCommand, { stdio: "inherit", env: process.env });
  } catch (error) {
    console.error("Factory deployment failed:", error);
    process.exit(1);
  }
}

// Deploy the new Order Router after the factory (later we will update the router on the factory)
if (deployType === "router" || deployType === "both") {
  const orderRouterCommand = `forge script script/DeployOrderRouter.s.sol:OnitOrderRouterDeployer --rpc-url ${network} ${broadcast} ${verify} -vvvv`;
  console.log("Deploying Order Router...");
  try {
    execSync(orderRouterCommand, { stdio: "inherit", env: process.env });
  } catch (error) {
    console.error("Order Router deployment failed:", error);
    process.exit(1);
  }
}

console.log("\n✅ Deployment completed successfully!");
if (deployType === "both") {
  console.log("📦 Deployed: Factory and Order Router");
} else {
  console.log(`📦 Deployed: ${deployType === "factory" ? "Factory" : "Order Router"}`);
}
