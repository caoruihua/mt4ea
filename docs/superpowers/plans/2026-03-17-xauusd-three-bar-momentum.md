# XAUUSD Three Bar Momentum EA Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a single-file MT4 EA for XAUUSD M5 that enters after a confirmed three-candle momentum burst and targets a 5-dollar move.

**Architecture:** The EA stays in one `Experts` file and performs new-bar detection, signal evaluation, position-limit checks, and order submission internally. Risk handling is intentionally simple: fixed lot, fixed take profit, and structure-based stop loss.

**Tech Stack:** MQL4, MT4 order API, local MetaEditor compiler

---

## Chunk 1: Single-File EA

### Task 1: Add the EA source file

**Files:**
- Create: `C:\Users\c1985\vsodeproject\mt4ea\MQL4\Experts\XAUUSD_ThreeBarMomentum_EA.mq4`

- [x] Define the EA inputs and constants for lot size, magic number, slippage, take profit, minimum move, and stop-loss buffer.
- [x] Add helpers for new-bar detection, open-position scanning, and structure calculations.
- [x] Implement bullish and bearish three-bar momentum checks using bars `1..3`.
- [x] Submit a market order only when no managed position is open.

## Chunk 2: Verification

### Task 2: Compile locally

**Files:**
- Verify: `C:\Users\c1985\vsodeproject\mt4ea\MQL4\Experts\XAUUSD_ThreeBarMomentum_EA.mq4`

- [x] Run local MetaEditor compile for the new EA file.
- [x] Inspect compile output and fix any errors.
- [x] Record that runtime validation in MT4 Strategy Tester is still required.
