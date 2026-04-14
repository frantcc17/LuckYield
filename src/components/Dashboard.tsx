"use client";

import { useContractRead, useAccount } from "wagmi";
import { formatUnits } from "viem";
import { VAULT_ABI, VAULT_ADDRESS } from "@/lib/contract";
import { useEffect, useState } from "react";

// ─── Types ───────────────────────────────────────────────────────────────────

interface Stat {
  label: string;
  value: string;
  sub?: string;
  accent?: boolean;
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function formatUSDC(raw: bigint | undefined): string {
  if (raw === undefined) return "—";
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 2,
  }).format(Number(formatUnits(raw, 6)));
}

function formatTickets(raw: bigint | undefined): string {
  if (raw === undefined) return "—";
  return Number(formatUnits(raw, 6)).toLocaleString("en-US", {
    maximumFractionDigits: 2,
  });
}

// ─── Jackpot Meter ────────────────────────────────────────────────────────────

function JackpotMeter({ current }: { current: bigint | undefined }) {
  const THRESHOLD = 2_000_000_000n; // $2,000 USDC in 6 decimals
  const pct = current
    ? Math.min(100, Number((current * 100n) / THRESHOLD))
    : 0;

  return (
    <div className="jackpot-meter">
      <div className="jackpot-meter__header">
        <span className="jackpot-meter__label">Draw Progress</span>
        <span className="jackpot-meter__pct">{pct.toFixed(1)}%</span>
      </div>
      <div className="jackpot-meter__track">
        <div
          className="jackpot-meter__fill"
          style={{ width: `${pct}%` }}
        />
        <div className="jackpot-meter__threshold-marker" />
      </div>
      <div className="jackpot-meter__labels">
        <span>$0</span>
        <span>$2,000 triggers draw</span>
      </div>
    </div>
  );
}

// ─── Stat Card ────────────────────────────────────────────────────────────────

function StatCard({ label, value, sub, accent }: Stat) {
  return (
    <div className={`stat-card${accent ? " stat-card--accent" : ""}`}>
      <span className="stat-card__label">{label}</span>
      <span className="stat-card__value">{value}</span>
      {sub && <span className="stat-card__sub">{sub}</span>}
    </div>
  );
}

// ─── Live Ticker ──────────────────────────────────────────────────────────────

function LiveTicker({ tvl }: { tvl: bigint | undefined }) {
  const [displayed, setDisplayed] = useState(0);

  useEffect(() => {
    const target = tvl ? Number(formatUnits(tvl, 6)) : 0;
    const step   = target / 60;
    let current  = 0;
    const id = setInterval(() => {
      current = Math.min(current + step, target);
      setDisplayed(current);
      if (current >= target) clearInterval(id);
    }, 16);
    return () => clearInterval(id);
  }, [tvl]);

  return (
    <span className="live-ticker">
      {new Intl.NumberFormat("en-US", {
        style: "currency",
        currency: "USD",
        maximumFractionDigits: 0,
      }).format(displayed)}
    </span>
  );
}

// ─── Main Dashboard ───────────────────────────────────────────────────────────

export default function Dashboard() {
  const { address, isConnected } = useAccount();

  const { data: tvl } = useContractRead({
    address:      VAULT_ADDRESS,
    abi:          VAULT_ABI,
    functionName: "tvl",
    watch:        true,
  });

  const { data: jackpot } = useContractRead({
    address:      VAULT_ADDRESS,
    abi:          VAULT_ABI,
    functionName: "currentJackpot",
    watch:        true,
  });

  const { data: drawCount } = useContractRead({
    address:      VAULT_ADDRESS,
    abi:          VAULT_ABI,
    functionName: "drawCount",
    watch:        true,
  });

  const { data: userTickets } = useContractRead({
    address:      VAULT_ADDRESS,
    abi:          VAULT_ABI,
    functionName: "balanceOf",
    args:         [address ?? "0x0000000000000000000000000000000000000000"],
    enabled:      isConnected,
    watch:        true,
  });

  const { data: isEligible } = useContractRead({
    address:      VAULT_ADDRESS,
    abi:          VAULT_ABI,
    functionName: "isEligible",
    args:         [address ?? "0x0000000000000000000000000000000000000000"],
    enabled:      isConnected,
    watch:        true,
  });

  const stats: Stat[] = [
    {
      label: "Total Value Locked",
      value: formatUSDC(tvl as bigint | undefined),
      sub:   "Capital protected by Ondo USDY",
    },
    {
      label:  "Current Jackpot",
      value:  formatUSDC(jackpot as bigint | undefined),
      sub:    "Yield accumulated for next draw",
      accent: true,
    },
    {
      label: "Draws Completed",
      value: drawCount !== undefined ? String(drawCount) : "—",
      sub:   "Verified by Chainlink VRF",
    },
    ...(isConnected
      ? [
          {
            label: "Your Tickets",
            value: formatTickets(userTickets as bigint | undefined),
            sub:   isEligible ? "✓ Eligible for next draw" : "⏳ Lock-up pending (48h)",
          },
        ]
      : []),
  ];

  return (
    <section className="dashboard">
      {/* ── Hero ── */}
      <div className="dashboard__hero">
        <div className="dashboard__hero-eyebrow">No-Loss Lottery</div>
        <h1 className="dashboard__hero-title">
          Win prizes.<br />
          <em>Never lose principal.</em>
        </h1>
        <p className="dashboard__hero-sub">
          Your USDC earns yield through Ondo RWA. When the pot hits&nbsp;
          <strong>$2,000</strong>, Chainlink randomly picks 5 winners.
          You can always withdraw 100% of your deposit.
        </p>

        <div className="dashboard__tvl-display">
          <span className="dashboard__tvl-label">Total Deposits</span>
          <LiveTicker tvl={tvl as bigint | undefined} />
        </div>
      </div>

      {/* ── Stats Grid ── */}
      <div className="dashboard__stats">
        {stats.map((s) => (
          <StatCard key={s.label} {...s} />
        ))}
      </div>

      {/* ── Jackpot Meter ── */}
      <JackpotMeter current={jackpot as bigint | undefined} />

      {/* ── Protocol Info ── */}
      <div className="dashboard__protocol-info">
        <div className="protocol-badge">
          <span className="protocol-badge__dot" />
          Chainlink VRF
        </div>
        <div className="protocol-badge">
          <span className="protocol-badge__dot" />
          Ondo Finance USDY
        </div>
        <div className="protocol-badge">
          <span className="protocol-badge__dot" />
          ERC-4626 Vault
        </div>
        <div className="protocol-badge">
          <span className="protocol-badge__dot" />
          Non-custodial
        </div>
      </div>
    </section>
  );
}
