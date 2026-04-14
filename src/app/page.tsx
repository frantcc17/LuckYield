"use client";

import Dashboard from "@/components/Dashboard";
import Actions   from "@/components/Actions";
import WinnerList from "@/components/WinnerList";
import { ConnectKitButton } from "connectkit";

export default function Home() {
  return (
    <div className="app">
      {/* ── Header ── */}
      <header className="app-header">
        <div className="app-header__logo">
          <span className="app-header__logo-mark">YW</span>
          <span className="app-header__logo-text">YieldWin</span>
        </div>
        <nav className="app-header__nav">
          <a href="#deposit"  className="app-header__nav-link">Deposit</a>
          <a href="#draws"    className="app-header__nav-link">Past Draws</a>
          <a href="https://docs.yieldwin.xyz" className="app-header__nav-link" target="_blank" rel="noopener noreferrer">
            Docs
          </a>
        </nav>
        <ConnectKitButton />
      </header>

      {/* ── Main Layout ── */}
      <main className="app-main">
        {/* Left: Stats */}
        <div className="app-main__left">
          <Dashboard />
          <div id="draws">
            <WinnerList />
          </div>
        </div>

        {/* Right: Actions */}
        <aside className="app-main__right" id="deposit">
          <div className="actions-wrapper">
            <h2 className="actions-wrapper__title">Manage Position</h2>
            <Actions />
          </div>
        </aside>
      </main>

      {/* ── Footer ── */}
      <footer className="app-footer">
        <p>YieldWin Protocol — No-Loss Lottery powered by Ondo Finance &amp; Chainlink</p>
        <p className="app-footer__sub">
          Contracts audited · Principal always protected · Built on Arbitrum
        </p>
      </footer>
    </div>
  );
}
