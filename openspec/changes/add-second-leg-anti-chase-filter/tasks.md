## 1. Main Entry Parameters

- [x] 1.1 Add the second-leg anti-chase input parameters to `MQL4/Experts/StrategySelector.mq4` as the single external configuration source
- [x] 1.2 Extend shared context/types so strategies can consume the centralized anti-chase parameters without declaring their own external inputs

## 2. Anti-Chase Eligibility Logic

- [x] 2.1 Implement the bullish second-leg anti-chase checks for `1 ATR` resistance space, measurable pullback, 50% reclaim, and loose digestion structure
- [x] 2.2 Implement the bearish mirror logic for `1 ATR` support space, measurable rebound, 50% retrace down, and loose digestion structure
- [x] 2.3 Add reset and waiting-state handling so stale or invalid second-leg candidates do not survive structure breaks or new extremes

## 3. Selector And Logging Integration

- [x] 3.1 Integrate the anti-chase eligibility layer into the centralized strategy-selection flow without creating a separate execution path
- [x] 3.2 Add trigger and rejection logging for selected key levels, ATR-space calculations, reclaim thresholds, loose-structure outcomes, and reset reasons

## 4. Verification

- [x] 4.1 Validate that long second-leg entries are rejected when price is within `1 ATR` of the nearest key resistance or when no valid pullback confirmation exists
- [x] 4.2 Validate that short second-leg entries are rejected when price is within `1 ATR` of the nearest key support or when no valid rebound confirmation exists
- [x] 4.3 Validate that mirrored long and short setups can still trigger after loose digestion structure and 50% reclaim confirmation are both satisfied
