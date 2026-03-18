# XAUUSD Three Bar Momentum EA Design

## Goal
Build a dedicated MT4 EA for XAUUSD that detects short-term momentum bursts on M5 and enters in the trend direction after confirmation.

## Strategy
- Evaluate only on `PERIOD_M5`.
- Use the last three fully closed candles.
- Long setup:
  - `Close[3] > Open[3]`, `Close[2] > Open[2]`, `Close[1] > Open[1]`
  - `High[2] > High[3]` and `High[1] > High[2]`
  - `Close[2] > Close[3]` and `Close[1] > Close[2]`
  - `Close[1] - Open[3] >= 5.0`
- Short setup mirrors the long rules with lows/closes decreasing and `Open[3] - Close[1] >= 5.0`
- Enter on the first tick of the new bar after bar `1` closes.

## Risk Rules
- Fixed lot size `0.01`
- Maximum exposure managed by this EA: one open position, total `0.01` lot
- Take profit: `5.0` price units
- Stop loss:
  - Buy: lowest low of bars `1..3` minus `0.5`
  - Sell: highest high of bars `1..3` plus `0.5`
- Slippage: `50` points

## Execution Notes
- Use `MagicNumber` so the EA only manages its own position.
- Evaluate once per new M5 bar to prevent duplicate orders.
- Keep implementation self-contained in one EA file to simplify deployment.

## Verification
- Compile with local `MetaEditor`.
- If compilation succeeds, attach the EA to an XAUUSD M5 chart in MT4 and validate in Strategy Tester.
