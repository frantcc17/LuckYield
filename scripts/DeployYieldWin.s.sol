// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../contracts/YieldWinVault.sol";
import "../contracts/mocks/MockContracts.sol";

/**
 * @title DeployYieldWin
 * @notice Foundry deployment script for YieldWin on Arbitrum Sepolia testnet.
 *
 * Usage:
 *   forge script script/DeployYieldWin.s.sol \
 *     --rpc-url $ARB_SEPOLIA_RPC \
 *     --broadcast \
 *     --verify \
 *     -vvvv
 *
 * Required env vars:
 *   PRIVATE_KEY          – Deployer private key
 *   LP_REWARD_ADDRESS    – LP reward recipient
 *   TREASURY_ADDRESS     – Protocol treasury
 *   VRF_SUBSCRIPTION_ID  – Chainlink VRF subscription ID
 *   USE_MOCKS            – "true" for testnet (uses mock contracts)
 */
contract DeployYieldWin is Script {

    // ── Arbitrum Sepolia Chainlink addresses ──────────────────────────────────
    // Source: https://docs.chain.link/vrf/v2-5/supported-networks#arbitrum-sepolia
    address constant VRF_COORDINATOR_ARB_SEPOLIA =
        0x5CE8D5A2BC84beb22a398CCA51996F7930313D61;

    bytes32 constant KEY_HASH_ARB_SEPOLIA =
        0x1770bdc7eec7771f7ba4ffd640f34260d7f095b79c92d34a5b2551d6f6cfd2be;

    // ── Ondo Finance – Arbitrum Sepolia ───────────────────────────────────────
    // NOTE: Ondo does not have an official Sepolia deployment as of this writing.
    //       Set USE_MOCKS=true to deploy MockUSDY + MockUSDYOracle instead.
    address constant USDC_ARB_SEPOLIA   = address(0); // No official USDC on Sepolia
    address constant USDY_ARB_SEPOLIA   = address(0); // Use mock
    address constant ORACLE_ARB_SEPOLIA = address(0); // Use mock

    function run() external {
        uint256 deployerKey      = vm.envUint("PRIVATE_KEY");
        address lpReward         = vm.envAddress("LP_REWARD_ADDRESS");
        address treasury         = vm.envAddress("TREASURY_ADDRESS");
        uint256 vrfSubscriptionId = vm.envUint("VRF_SUBSCRIPTION_ID");
        bool    useMocks         = vm.envBool("USE_MOCKS");

        vm.startBroadcast(deployerKey);

        address usdcAddr;
        address usdyAddr;
        address oracleAddr;

        if (useMocks) {
            console.log("== Deploying Mock Contracts ==");

            MockUSDC mockUsdc = new MockUSDC();
            usdcAddr = address(mockUsdc);
            console.log("MockUSDC:         ", usdcAddr);

            MockUSDY mockUsdy = new MockUSDY();
            usdyAddr = address(mockUsdy);
            console.log("MockUSDY:         ", usdyAddr);

            MockUSDYOracle mockOracle = new MockUSDYOracle();
            oracleAddr = address(mockOracle);
            console.log("MockUSDYOracle:   ", oracleAddr);

            // Mint some test USDC to deployer for initial testing
            mockUsdc.mint(msg.sender, 100_000e6); // 100k USDC
        } else {
            usdcAddr   = USDC_ARB_SEPOLIA;
            usdyAddr   = USDY_ARB_SEPOLIA;
            oracleAddr = ORACLE_ARB_SEPOLIA;
            require(usdcAddr != address(0), "Set real USDC address");
        }

        console.log("\n== Deploying YieldWinVault ==");

        YieldWinVault vault = new YieldWinVault(
            usdcAddr,
            usdyAddr,
            oracleAddr,
            VRF_COORDINATOR_ARB_SEPOLIA,
            KEY_HASH_ARB_SEPOLIA,
            vrfSubscriptionId,
            lpReward,
            treasury
        );

        console.log("YieldWinVault:    ", address(vault));
        console.log("LP Reward:        ", lpReward);
        console.log("Treasury:         ", treasury);
        console.log("VRF Sub ID:       ", vrfSubscriptionId);
        console.log("Draw Threshold:   $2,000 USDC");

        // ── Post-deploy checklist ─────────────────────────────────────────────
        console.log("\n== Post-Deploy TODO ==");
        console.log("1. Add vault as consumer in Chainlink VRF subscription");
        console.log("   https://vrf.chain.link → Your Subscription → Add Consumer");
        console.log("2. Register vault in Chainlink Automation");
        console.log("   https://automation.chain.link → Register → Custom Logic");
        console.log("3. Fund VRF subscription with LINK");
        console.log("4. If using mocks: call MockUSDY.mint(vault, initialUSDY)");

        vm.stopBroadcast();

        // Write deployment addresses to JSON
        string memory json = string(abi.encodePacked(
            '{\n',
            '  "network": "arbitrum-sepolia",\n',
            '  "vault": "', vm.toString(address(vault)), '",\n',
            '  "usdc": "',  vm.toString(usdcAddr), '",\n',
            '  "usdy": "',  vm.toString(usdyAddr), '",\n',
            '  "oracle": "', vm.toString(oracleAddr), '",\n',
            '  "vrfCoordinator": "', vm.toString(VRF_COORDINATOR_ARB_SEPOLIA), '",\n',
            '  "drawThreshold": "2000000000"\n',
            '}'
        ));
        vm.writeFile("./deployments/arbitrum-sepolia.json", json);
        console.log("\nDeployment saved to ./deployments/arbitrum-sepolia.json");
    }
}
