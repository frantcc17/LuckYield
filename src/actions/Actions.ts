"use client";

import { useState, useCallback } from "react";
import {
  useAccount,
  useContractRead,
  useContractWrite,
  usePrepareContractWrite,
  useWaitForTransaction,
} from "wagmi";
import { parseUnits, formatUnits } from "viem";
import { VAULT_ABI, VAULT_ADDRESS, USDC_ABI, USDC_ADDRESS } from "@/lib/contract";

// ─── Types ───────────────────────────────────────────────────────────────────

type Tab = "deposit" | "withdraw";

interface TxState {
  hash?: `0x${string}`;
  status: "idle" | "pending" | "success" | "error";
  message?: string;
}

// ─── Status Banner ────────────────────────────────────────────────────────────

function TxBanner({ state }: { state: TxState }) {
  if (state.status === "idle") return null;

  const icons: Record<TxState["status"], string> = {
    idle:    "",
    pending: "⏳",
    success: "✓",
    error:   "✗",
  };

  return (
    <div className={`tx-banner tx-banner--${state.status}`}>
      <span>{icons[state.status]}</span>
      <span>{state.message}</span>
      {state.hash && (
        <a
          href={`https://sepolia.arbiscan.io/tx/${state.hash}`}
          target="_blank"
          rel="noopener noreferrer"
          className="tx-banner__link"
        >
          View on explorer →
        </a>
      )}
    </div>
  );
}

// ─── Amount Input ─────────────────────────────────────────────────────────────

interface AmountInputProps {
  value:     string;
  onChange:  (v: string) => void;
  max?:      string;
  label:     string;
  currency:  string;
  disabled?: boolean;
}

function AmountInput({ value, onChange, max, label, currency, disabled }: AmountInputProps) {
  return (
    <div className="amount-input">
      <label className="amount-input__label">{label}</label>
      <div className="amount-input__wrapper">
        <input
          type="number"
          min="0"
          step="any"
          placeholder="0.00"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          disabled={disabled}
          className="amount-input__field"
        />
        <span className="amount-input__currency">{currency}</span>
        {max && (
          <button
            type="button"
            onClick={() => onChange(max)}
            className="amount-input__max-btn"
            disabled={disabled}
          >
            MAX
          </button>
        )}
      </div>
      {max && (
        <span className="amount-input__balance">
          Balance: {Number(max).toLocaleString("en-US", { maximumFractionDigits: 2 })} {currency}
        </span>
      )}
    </div>
  );
}

// ─── Deposit Panel ────────────────────────────────────────────────────────────

function DepositPanel() {
  const { address } = useAccount();
  const [amount, setAmount] = useState("");
  const [txState, setTxState] = useState<TxState>({ status: "idle" });

  const parsedAmount = amount ? parseUnits(amount, 6) : 0n;

  // Read user USDC balance
  const { data: usdcBalance } = useContractRead({
    address:      USDC_ADDRESS,
    abi:          USDC_ABI,
    functionName: "balanceOf",
    args:         [address ?? "0x0000000000000000000000000000000000000000"],
    enabled:      !!address,
    watch:        true,
  });

  // Read current allowance
  const { data: allowance } = useContractRead({
    address:      USDC_ADDRESS,
    abi:          USDC_ABI,
    functionName: "allowance",
    args:         [address ?? "0x0000000000000000000000000000000000000000", VAULT_ADDRESS],
    enabled:      !!address,
    watch:        true,
  });

  const needsApproval = parsedAmount > 0n && (allowance as bigint ?? 0n) < parsedAmount;

  // ── Approve ──
  const { config: approveConfig } = usePrepareContractWrite({
    address:      USDC_ADDRESS,
    abi:          USDC_ABI,
    functionName: "approve",
    args:         [VAULT_ADDRESS, parsedAmount],
    enabled:      needsApproval && parsedAmount > 0n,
  });
  const { write: approve, data: approveTx } = useContractWrite(approveConfig);

  useWaitForTransaction({
    hash:    approveTx?.hash,
    onSuccess: () => setTxState({ status: "success", message: "Approval confirmed!", hash: approveTx?.hash }),
    onError:   () => setTxState({ status: "error",   message: "Approval failed." }),
  });

  // ── Deposit ──
  const { config: depositConfig } = usePrepareContractWrite({
    address:      VAULT_ADDRESS,
    abi:          VAULT_ABI,
    functionName: "deposit",
    args:         [parsedAmount, address ?? "0x0000000000000000000000000000000000000000"],
    enabled:      !needsApproval && parsedAmount > 0n,
  });
  const { write: deposit, data: depositTx } = useContractWrite(depositConfig);

  useWaitForTransaction({
    hash:    depositTx?.hash,
    onSuccess: () => {
      setTxState({ status: "success", message: `Deposited ${amount} USDC – tickets minted!`, hash: depositTx?.hash });
      setAmount("");
    },
    onError: () => setTxState({ status: "error", message: "Deposit failed." }),
  });

  const handleApprove = useCallback(() => {
    setTxState({ status: "pending", message: "Approving USDC spend…" });
    approve?.();
  }, [approve]);

  const handleDeposit = useCallback(() => {
    setTxState({ status: "pending", message: "Depositing USDC…" });
    deposit?.();
  }, [deposit]);

  const maxBalance = usdcBalance
    ? formatUnits(usdcBalance as bigint, 6)
    : "0";

  return (
    <div className="action-panel">
      <div className="action-panel__info-box">
        <p>Deposit USDC to receive Tickets (1:1). Your principal is always safe.</p>
        <p>After 48h, your tickets are eligible for the next draw.</p>
      </div>

      <AmountInput
        label="Amount to Deposit"
        value={amount}
        onChange={setAmount}
        max={maxBalance}
        currency="USDC"
        disabled={txState.status === "pending"}
      />

      <div className="action-panel__btn-group">
        {needsApproval ? (
          <button
            className="action-btn action-btn--secondary"
            onClick={handleApprove}
            disabled={!approve || txState.status === "pending" || !parsedAmount}
          >
            {txState.status === "pending" ? "Approving…" : "1. Approve USDC"}
          </button>
        ) : (
          <button
            className="action-btn action-btn--primary"
            onClick={handleDeposit}
            disabled={!deposit || txState.status === "pending" || !parsedAmount}
          >
            {txState.status === "pending" ? "Depositing…" : "Deposit USDC"}
          </button>
        )}
      </div>

      {needsApproval && (
        <p className="action-panel__hint">
          Step 1: Approve · Step 2: Deposit
        </p>
      )}

      <TxBanner state={txState} />
    </div>
  );
}

// ─── Withdraw Panel ───────────────────────────────────────────────────────────

function WithdrawPanel() {
  const { address } = useAccount();
  const [amount, setAmount]   = useState("");
  const [txState, setTxState] = useState<TxState>({ status: "idle" });

  const parsedAmount = amount ? parseUnits(amount, 6) : 0n;

  const { data: tickets } = useContractRead({
    address:      VAULT_ADDRESS,
    abi:          VAULT_ABI,
    functionName: "balanceOf",
    args:         [address ?? "0x0000000000000000000000000000000000000000"],
    enabled:      !!address,
    watch:        true,
  });

  const { data: isEligible } = useContractRead({
    address:      VAULT_ADDRESS,
    abi:          VAULT_ABI,
    functionName: "isEligible",
    args:         [address ?? "0x0000000000000000000000000000000000000000"],
    enabled:      !!address,
    watch:        true,
  });

  const { config: withdrawConfig } = usePrepareContractWrite({
    address:      VAULT_ADDRESS,
    abi:          VAULT_ABI,
    functionName: "redeem",
    args:         [
      parsedAmount,
      address ?? "0x0000000000000000000000000000000000000000",
      address ?? "0x0000000000000000000000000000000000000000",
    ],
    enabled: parsedAmount > 0n && !!address,
  });
  const { write: withdraw, data: withdrawTx } = useContractWrite(withdrawConfig);

  useWaitForTransaction({
    hash:    withdrawTx?.hash,
    onSuccess: () => {
      setTxState({ status: "success", message: `Withdrew ${amount} USDC successfully.`, hash: withdrawTx?.hash });
      setAmount("");
    },
    onError: () => setTxState({ status: "error", message: "Withdrawal failed." }),
  });

  const handleWithdraw = useCallback(() => {
    setTxState({ status: "pending", message: "Processing withdrawal…" });
    withdraw?.();
  }, [withdraw]);

  const maxTickets = tickets
    ? formatUnits(tickets as bigint, 6)
    : "0";

  const withinLockup = !isEligible && tickets && (tickets as bigint) > 0n;

  return (
    <div className="action-panel">
      <div className="action-panel__info-box">
        <p>Burn your Tickets to reclaim USDC principal (1:1).</p>
        {withinLockup && (
          <p className="action-panel__warning">
            ⚠ Within 48h lock-up period. A 0.5% early-exit fee applies.
          </p>
        )}
      </div>

      <AmountInput
        label="Tickets to Burn"
        value={amount}
        onChange={setAmount}
        max={maxTickets}
        currency="YWT"
        disabled={txState.status === "pending"}
      />

      <button
        className="action-btn action-btn--danger"
        onClick={handleWithdraw}
        disabled={!withdraw || txState.status === "pending" || !parsedAmount}
      >
        {txState.status === "pending" ? "Withdrawing…" : "Withdraw USDC"}
      </button>

      <TxBanner state={txState} />
    </div>
  );
}

// ─── Main Actions Component ───────────────────────────────────────────────────

export default function Actions() {
  const { isConnected } = useAccount();
  const [activeTab, setActiveTab] = useState<Tab>("deposit");

  if (!isConnected) {
    return (
      <div className="actions-connect-prompt">
        <p>Connect your wallet to deposit or withdraw.</p>
      </div>
    );
  }

  return (
    <div className="actions">
      <div className="actions__tabs">
        <button
          className={`actions__tab ${activeTab === "deposit" ? "actions__tab--active" : ""}`}
          onClick={() => setActiveTab("deposit")}
        >
          Deposit
        </button>
        <button
          className={`actions__tab ${activeTab === "withdraw" ? "actions__tab--active" : ""}`}
          onClick={() => setActiveTab("withdraw")}
        >
          Withdraw
        </button>
      </div>

      {activeTab === "deposit" ? <DepositPanel /> : <WithdrawPanel />}
    </div>
  );
}
