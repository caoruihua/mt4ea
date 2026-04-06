# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an MQL4 (MetaTrader 4) Expert Advisor project for automated XAUUSD (gold) trading on the M5 timeframe. It uses a minimal dual-strategy kernel:

- **TrendContinuation**: Follows trend breakouts based on EMA alignment
- **Pullback**: Enters on price retracements to the fast EMA with rejection patterns
- **ExpansionFollow**: Enters on high-momentum breakout candles (burst candles)

## Build/Compile Commands

### Compiling the EA

**Via PowerShell (recommended):**
```powershell
powershell.exe -NoProfile -Command "& 'C:\Program Files (x86)\MetaTrader 4\metaeditor.exe' '/compile:C:\Users\c1985\vsodeproject\sanqing-ea\MQL4\Experts\StrategySelector.mq4' '/log:C:\Users\c1985\vsodeproject\sanqing-ea\compile-task.log'"
```

**Via VS Code:**
Use the "编译 MQL4" task configured in `.vscode/tasks.json`

**Success criteria:** Check `compile-task.log` for `Result: 0 errors, 0 warnings`

### Deployment

1. Copy `MQL4/Experts/` and `MQL4/Include/` to your MT4 data directory
2. Compile `StrategySelector.mq4` in MetaEditor
3. Attach the EA to an XAUUSD M5 chart

## Architecture

### Main Entry Point

`MQL4/Experts/StrategySelector.mq4` - The EA main file that:
- Builds a unified context snapshot (EMAs, ATR, spread) each tick
- Syncs daily risk status (profit lock, trade count)
- Runs position protection (dynamic SL/TP) every tick
- Only evaluates new entries on "new closed bar" events
- Uses `CStrategyRegistry` to select the best signal from registered strategies

### Core Modules (MQL4/Include/Core/)

**Types.mqh** - Central data structures shared across all modules:
- `StrategyContext`: Current tick snapshot (prices, indicators, config)
- `RuntimeState`: Persisted state (daily stats, entry tracking, trailing status)
- `TradeSignal`: Unified signal format from strategies
- `MarketFilterResult`: Market condition assessment

**StrategyRegistry.mqh** - Strategy dispatcher with fixed priority:
1. ExpansionFollow (highest priority)
2. Pullback
3. TrendContinuation (lowest priority)

**TradeExecutor.mqh** - Order execution and position management:
- `OpenOrder()` / `CloseOrder()` with retry logic
- `CheckStopLossTakeProfit()` - hard SL/TP checks
- `ApplyGlobalProfitLockIfNeeded()` - two-stage trailing protection:
  - Stage 1 (1.0×ATR profit): Move SL to breakeven+0.1×ATR, extend TP to 2.5×ATR
  - Stage 2 (1.5×ATR profit): Activate trailing based on Close[1]

**RiskManager.mqh** - Daily risk controls:
- Calculates realized PnL from closed orders
- Triggers `dailyLocked` when `dailyClosedProfit >= DailyProfitStopUsd`
- Resets stats on new server day

**MarketState.mqh** - Market condition filtering:
- Low volatility gate: ATR points and ATR/spread ratio checks
- Trend validity: EMA alignment with slope confirmation

**StateStore.mqh** - Persistence layer using global variables:
- Saves/loads `RuntimeState` to survive EA restarts
- Persists: dayKey, dailyLocked, dailyClosedProfit, tradesToday, entry tracking, trailing state

**SignalEngine.mqh** - Indicator calculations:
- Builds core snapshot with configurable EMA periods + ATR(14)

**SessionClock.mqh** - Time utilities for server day detection

**Logger.mqh** - Leveled logging (Error/Warning/Info/Debug)

**StrategyBase.mqh** - Abstract base class `IStrategy` for all strategies

### Strategy Modules (MQL4/Include/Strategies/)

Each strategy implements `IStrategy` with:
- `Name()`: Returns strategy identifier string
- `CanTrade()`: Pre-checks (volatility, bar timing)
- `GenerateSignal()`: Returns `TradeSignal` if conditions met

**StrategyPullback.mqh:**
- Long: EMA9 > EMA21, price in lower half of 20-bar channel, pullback to EMA9 with bullish rejection (lower wick >= 50% body)
- Short: EMA9 < EMA21, price in upper half of 20-bar channel, pullback to EMA9 with bearish rejection (upper wick >= 50% body)

**StrategyTrendContinuation.mqh:**
- Long: EMA9 > EMA21, Close[1] breaks above max(High[2], High[3]) + 0.20×ATR, body >= 0.35×ATR
- Short: EMA9 < EMA21, Close[1] breaks below min(Low[2], Low[3]) - 0.20×ATR, body >= 0.35×ATR

**StrategyExpansionFollow.mqh:**
- Detects "burst candles" with extreme body size relative to ATR and median body
- Requires volume confirmation, clean direction (shadow ratio), and breakout beyond 20-bar channel

## Key Constraints

- **Symbol/Timeframe**: XAUUSD M5 only
- **Position limit**: One position per `symbol + magic` combination
- **Trade size**: Fixed 0.01 lots (enforced in executor)
- **Daily limit**: Max 30 trades per day
- **Profit lock**: Stop new entries after +$50 daily realized profit
- **Entry timing**: Only one entry per closed bar
- **Indicator defaults**: EMA9/EMA21 with ATR(14)
- **SL/TP defaults**: 1.2×ATR stop, 2.0×ATR target (strategies may override)

## Development Notes

- All comments and log messages are in Chinese
- Decisions are based on the **previous closed bar** (bar[1]), never the forming bar
- The EA uses MQL4's legacy order pool API (`OrderSend`, `OrderSelect`, `OrderModify`)
- State is persisted using MT4 global variables for restart recovery
- The `docs/mt5-rewrite-requirements.md` file contains detailed specifications for an MT5 port

## Git Workflow

- Commit messages must be written in Chinese
- Follow the conventional commit format with Chinese descriptions

## Testing Workflow

- After project development is complete and all unit tests pass, automatically delete the created unit test cases
- Do not leave temporary test files in the repository
