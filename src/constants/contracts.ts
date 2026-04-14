/**
 * @file contract.ts
 * @description Contract addresses and ABIs for YieldWin frontend.
 *              Update VAULT_ADDRESS after deployment.
 */

// ─── Addresses ────────────────────────────────────────────────────────────────

export const VAULT_ADDRESS = (
  process.env.NEXT_PUBLIC_VAULT_ADDRESS ?? "0x0000000000000000000000000000000000000000"
) as `0x${string}`;

export const USDC_ADDRESS = (
  process.env.NEXT_PUBLIC_USDC_ADDRESS ?? "0x0000000000000000000000000000000000000000"
) as `0x${string}`;

// ─── USDC ABI (minimal) ───────────────────────────────────────────────────────

export const USDC_ABI = [
  {
    name: "balanceOf",
    type: "function",
    stateMutability: "view",
    inputs:  [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "allowance",
    type: "function",
    stateMutability: "view",
    inputs:  [{ name: "owner", type: "address" }, { name: "spender", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "approve",
    type: "function",
    stateMutability: "nonpayable",
    inputs:  [{ name: "spender", type: "address" }, { name: "amount", type: "uint256" }],
    outputs: [{ name: "", type: "bool" }],
  },
] as const;

// ─── YieldWinVault ABI ────────────────────────────────────────────────────────

export const VAULT_ABI = [
  // ── View functions ──────────────────────────────────────────────────────────
  {
    name: "tvl",
    type: "function",
    stateMutability: "view",
    inputs:  [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "currentJackpot",
    type: "function",
    stateMutability: "view",
    inputs:  [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "drawCount",
    type: "function",
    stateMutability: "view",
    inputs:  [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "balanceOf",
    type: "function",
    stateMutability: "view",
    inputs:  [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "isEligible",
    type: "function",
    stateMutability: "view",
    inputs:  [{ name: "user", type: "address" }],
    outputs: [{ name: "", type: "bool" }],
  },
  {
    name: "getDrawResult",
    type: "function",
    stateMutability: "view",
    inputs:  [{ name: "index", type: "uint256" }],
    outputs: [
      {
        name: "",
        type: "tuple",
        components: [
          { name: "timestamp",    type: "uint256" },
          { name: "totalYield",   type: "uint256" },
          { name: "grandWinner",  type: "address" },
          { name: "smallWinners", type: "address[4]" },
          { name: "grandPrize",   type: "uint256" },
          { name: "smallPrize",   type: "uint256" },
        ],
      },
    ],
  },
  {
    name: "totalPrincipal",
    type: "function",
    stateMutability: "view",
    inputs:  [],
    outputs: [{ name: "", type: "uint256" }],
  },
  {
    name: "depositTimestamp",
    type: "function",
    stateMutability: "view",
    inputs:  [{ name: "", type: "address" }],
    outputs: [{ name: "", type: "uint48" }],
  },

  // ── Write functions ─────────────────────────────────────────────────────────
  {
    name: "deposit",
    type: "function",
    stateMutability: "nonpayable",
    inputs:  [
      { name: "assets",   type: "uint256" },
      { name: "receiver", type: "address" },
    ],
    outputs: [{ name: "shares", type: "uint256" }],
  },
  {
    name: "redeem",
    type: "function",
    stateMutability: "nonpayable",
    inputs:  [
      { name: "shares",   type: "uint256" },
      { name: "receiver", type: "address" },
      { name: "owner_",   type: "address" },
    ],
    outputs: [{ name: "assets", type: "uint256" }],
  },

  // ── Events ──────────────────────────────────────────────────────────────────
  {
    name: "DrawCompleted",
    type: "event",
    inputs: [
      { name: "requestId",    type: "uint256",   indexed: true },
      { name: "grandWinner",  type: "address",   indexed: false },
      { name: "smallWinners", type: "address[4]", indexed: false },
      { name: "totalYield",   type: "uint256",   indexed: false },
    ],
  },
  {
    name: "Deposited",
    type: "event",
    inputs: [
      { name: "user",       type: "address", indexed: true },
      { name: "usdcAmount", type: "uint256", indexed: false },
      { name: "tickets",    type: "uint256", indexed: false },
    ],
  },
  {
    name: "Withdrawn",
    type: "event",
    inputs: [
      { name: "user",       type: "address", indexed: true },
      { name: "usdcAmount", type: "uint256", indexed: false },
      { name: "tickets",    type: "uint256", indexed: false },
      { name: "earlyExit",  type: "bool",    indexed: false },
    ],
  },
] as const;
