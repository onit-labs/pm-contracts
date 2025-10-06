import { foundry } from "@wagmi/cli/plugins";

import type { Config } from "@wagmi/cli";

// get the version from the package.json
const version = require("./package.json").version;

const config: Config = {
  out: `abis/OnitInfiniteOutcomeDPMAbi.${version}.ts`,
  plugins: [
    foundry({
      include: [
        "OnitInfiniteOutcomeDPM.sol/**",
        "OnitInfiniteOutcomeDPMProxyFactory.sol/**",
        "OnitMarketOrderRouter.sol/**",
      ],
      // Disabled as we need to build using '--via-ir'
      forge: { build: false },
    }),
  ],
};

export default config;
