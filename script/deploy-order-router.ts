#!/usr/bin/env node

import { execSync } from "node:child_process";
import dotenv from "dotenv";

dotenv.config();

let isAnvilRunning = false;
let checkCount = 0;
const MAX_CHECK_COUNT = 10;

// check if anvil is running every second until it is ( 3 seconds )
do {
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

console.log("isAnvilRunning", isAnvilRunning);

if (!isAnvilRunning) process.exit(0);

const network = process.argv[2];
const broadcast = process.argv.includes("-b") ? "--broadcast" : "";
const profile = process.argv.includes("-p") ? "prod" : "";
const verify = network !== "local" && broadcast ? "--verify" : "";

if (profile === "prod") {
  process.env.FOUNDRY_PROFILE = "prod";
}

const command = `forge script script/DeployOrderRouter.s.sol:OnitOrderRouterDeployer --rpc-url ${network} ${broadcast} ${verify} -vvvv`;
try {
  execSync(command, { stdio: "inherit", env: process.env });
} catch (error) {
  console.error(error);
  process.exit(1);
}
