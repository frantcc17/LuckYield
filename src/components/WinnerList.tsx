"use client";

import { useContractRead, useContractEvent } from "wagmi";
import { formatUnits } from "viem";
import { useState, useEffect } from "react";
import { VAULT_ABI, VAULT_ADDRESS } from "@/lib/contract";

// ─── Types ───────────────────────────────────────────────────────────────────

interface DrawResult {
  timestamp:    bigint;
  totalYield:   bigint;
  grandWinner:  `0x${string}`;
  smallWinners: readonly [`0x${string}`, `0x${string}`, `0x${string}`, `0x${string}`];
  grandPrize:   bigint;
  smallPrize:   bigint;
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function formatUSDC(raw: bigint): string {
  return new Intl.NumberFormat("en-US", {
    style:    "currency",
    currency: "USD",
  }).format(Number(formatUnits(raw, 6)));
}

function shortAddr(addr: string): string {
  return `${addr.slice(0, 6)}…${addr.slice(-4)}`;
}

function formatDate(ts: bigint): string {
  return new Date(Number(ts) * 1000).toLocaleString("en-US", {
    month:  "short",
    day:    "numeric",
    hour:   "2-digit",
    minute: "2-digit",
  });
}

// ─── Draw Card ────────────────────────────────────────────────────────────────

function DrawCard({ draw, index }: { draw: DrawResult; index: number }) {
  const [expanded, setExpanded] = useState(false);

  return (
    <div className="draw-card">
      <div
        className="draw-card__header"
        onClick={() => setExpanded((e) => !e)}
        role="button"
        tabIndex={0}
        onKeyDown={(e) => e.key === "Enter" && setExpanded((x) => !x)}
      >
        <div className="draw-card__meta">
          <span className="draw-card__number">Draw #{index + 1}</span>
          <span className="draw-card__date">{formatDate(draw.timestamp)}</span>
        </div>
        <div className="draw-card__prize-total">
          {formatUSDC(draw.totalYield)} distributed
        </div>
        <span className="draw-card__chevron">{expanded ? "▲" : "▼"}</span>
      </div>

      {expanded && (
        <div className="draw-card__body">
          {/* Grand Winner */}
          <div className="draw-card__winner draw-card__winner--grand">
            <div className="draw-card__winner-badge">🏆 Grand</div>
            <div className="draw-card__winner-info">
              <a
                href={`https://sepolia.arbiscan.io/address/${draw.grandWinner}`}
                target="_blank"
                rel="noopener noreferrer"
                className="draw-card__winner-addr"
              >
                {shortAddr(draw.grandWinner)}
              </a>
              <span className="draw-card__winner-amount">
                {formatUSDC(draw.grandPrize)}
              </span>
            </div>
          </div>

          {/* Small Winners */}
          {draw.smallWinners.map((addr, i) => (
            <div key={i} className="draw-card__winner draw-card__winner--small">
              <div className="draw-card__winner-badge">🥈 #{i + 1}</div>
              <div className="draw-card__winner-info">
                <a
                  href={`https://sepolia.arbiscan.io/address/${addr}`}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="draw-card__winner-addr"
                >
                  {shortAddr(addr)}
                </a>
                <span className="draw-card__winner-amount">
                  {formatUSDC(draw.smallPrize)}
                </span>
              </div>
            </div>
          ))}

          {/* Distribution Breakdown */}
          <div className="draw-card__breakdown">
            <span>Grand: 60%</span>
            <span>4× Small: 5% each</span>
            <span>LP: 10%</span>
            <span>Treasury: 10%</span>
          </div>
        </div>
      )}
    </div>
  );
}

// ─── Empty State ──────────────────────────────────────────────────────────────

function EmptyDraws() {
  return (
    <div className="winner-list__empty">
      <div className="winner-list__empty-icon">🎲</div>
      <p>No draws yet.</p>
      <p className="winner-list__empty-sub">
        The first draw triggers when yield reaches $2,000.
      </p>
    </div>
  );
}

// ─── Main WinnerList ──────────────────────────────────────────────────────────

export default function WinnerList() {
  const [draws, setDraws] = useState<DrawResult[]>([]);

  // Read total draw count
  const { data: drawCount } = useContractRead({
    address:      VAULT_ADDRESS,
    abi:          VAULT_ABI,
    functionName: "drawCount",
    watch:        true,
  });

  // Fetch all draw results
  useEffect(() => {
    if (!drawCount) return;

    const count = Number(drawCount);
    const fetched: DrawResult[] = [];

    // NOTE: In production, use multicall for efficiency
    // This is simplified for MVP clarity
    async function fetchAll() {
      for (let i = count - 1; i >= Math.max(0, count - 10); i--) {
        // Read each draw result (wagmi useContractRead can't loop cleanly here)
        // Use publicClient.readContract in a real implementation
        console.log(`Fetching draw ${i}…`);
      }
      setDraws(fetched);
    }

    fetchAll();
  }, [drawCount]);

  // Listen for new DrawCompleted events in real time
  useContractEvent({
    address:      VAULT_ADDRESS,
    abi:          VAULT_ABI,
    eventName:    "DrawCompleted",
    listener:     (log) => {
      console.log("New draw completed:", log);
      // Refresh draws list on new event
    },
  });

  const count = Number(drawCount ?? 0n);

  return (
    <section className="winner-list">
      <div className="winner-list__header">
        <h2 className="winner-list__title">Past Draws</h2>
        <span className="winner-list__count">
          {count} draw{count !== 1 ? "s" : ""} completed
        </span>
      </div>

      {/* Chain verification badge */}
      <div className="winner-list__vrf-badge">
        <span className="vrf-badge__icon">🔗</span>
        <span>All winners selected by Chainlink VRF — provably fair</span>
      </div>

      {count === 0 ? (
        <EmptyDraws />
      ) : (
        <div className="winner-list__draws">
          {draws.length === 0 ? (
            <p className="winner-list__loading">Loading draws…</p>
          ) : (
            draws.map((draw, i) => (
              <DrawCard key={i} draw={draw} index={count - 1 - i} />
            ))
          )}
        </div>
      )}

      {/* Distribution legend */}
      <div className="winner-list__legend">
        <div className="legend-item">
          <span className="legend-item__dot legend-item__dot--grand" />
          <span>Grand Prize (60%)</span>
        </div>
        <div className="legend-item">
          <span className="legend-item__dot legend-item__dot--small" />
          <span>4 × Small Prize (5% each)</span>
        </div>
        <div className="legend-item">
          <span className="legend-item__dot legend-item__dot--lp" />
          <span>LP Rewards (10%)</span>
        </div>
        <div className="legend-item">
          <span className="legend-item__dot legend-item__dot--treasury" />
          <span>Treasury (10%)</span>
        </div>
      </div>
    </section>
  );
}
