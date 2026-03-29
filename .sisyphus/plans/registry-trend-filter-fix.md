# Plan: Registry Trend Filter Fix

## TL;DR
> **Summary**: 在 StrategyRegistry 中为 RiskReward 信号增加趋势过滤，防止暴涨后下跌时误判做多
> **Deliverables**: 修改后的 StrategyRegistry.mqh，编译通过
> **Effort**: Short
> **Parallel**: NO (单文件修改)
> **Critical Path**: 添加辅助函数 → 修改 EvaluateBestSignal → 编译验证

## Context
### Original Request
用户报告：在暴涨后下跌的趋势中，系统仍然提示做多，导致止损。问题根因是 MarketState 误判为 REGIME_TREND_UP 后，Registry 直接生成做多信号，没有趋势过滤。

### Interview Summary
- 问题确认：暴涨后下跌场景中，MarketState 误判趋势方向
- 根因：Registry 的 RiskReward 信号生成（line 192-195）没有趋势过滤
- RangeEdgeReversion 自带趋势过滤（正常工作），但 Registry 信号绕过了过滤
- 修复方案：在 Registry 中增加"连续新低/新高"检测

### Metis Review (gaps addressed)
- 确认修复范围精准：只改 Registry，不改 MarketState
- 确认风险可控：只在趋势方向明确相反时过滤
- 建议复用 RangeEdgeReversion 的价格结构过滤逻辑

## Work Objectives
### Core Objective
在 StrategyRegistry.mqh 中为 TREND_UP/TREND_DOWN 信号增加趋势过滤逻辑

### Deliverables
1. 在 StrategyRegistry.mqh 中添加两个辅助函数：
   - `HasConsecutiveLowerLows(int window, int threshold)` - 检测是否连续新低
   - `HasConsecutiveHigherHighs(int window, int threshold)` - 检测是否连续新高
2. 修改 `EvaluateBestSignal()` 函数，在生成 TREND_UP/TREND_DOWN 信号前检查
3. 编译验证通过

### Definition of Done (verifiable conditions with commands)
- [x] StrategyRegistry.mqh 编译通过（0 errors, 0 warnings）
- [x] 代码逻辑：regime=TREND_UP 时，连续3根新低则不生成做多信号
- [x] 代码逻辑：regime=TREND_DOWN 时，连续3根新高则不生成做空信号

### Must Have
- 使用与 RangeEdgeReversion 一致的参数：window=5, threshold=3
- 不修改 MarketState.mqh
- 不影响正常趋势判断（上涨中做多、下跌中做空正常工作）

### Must NOT Have
- 过度过滤导致系统一直观望
- 引入新的逻辑 bug
- 修改其他无关文件

## Verification Strategy
- Test decision: none (代码修改，编译通过即验证)
- QA policy: N/A
- Evidence: 编译日志

## Execution Strategy
### Parallel Execution Waves
Single wave, single file modification.

### Dependency Matrix
| Task | Dependencies |
|------|--------------|
| 1. 添加辅助函数 | 无 |
| 2. 修改 EvaluateBestSignal | 依赖 task 1 |
| 3. 编译验证 | 依赖 task 2 |

### Agent Dispatch Summary
- Category: quick (单文件修改)
- 直接执行，无需代理

## TODOs

- [x] 1. 在 StrategyRegistry.mqh 中添加趋势过滤辅助函数

  **What to do**: 在类中添加两个私有方法：
  ```cpp
  private:
     bool HasConsecutiveLowerLows(int window, int threshold);
     bool HasConsecutiveHigherHighs(int window, int threshold);
  ```
  实现逻辑（参考 RangeEdgeReversion.mqh:162-204）：
  - HasConsecutiveLowerLows: 遍历最近 window 根K线，统计 Low[i] < Low[i+1] 的次数
  - HasConsecutiveHigherHighs: 遍历最近 window 根K线，统计 High[i] > High[i+1] 的次数
  
  **Must NOT do**: 不要复制整个 RangeEdgeReversion 的过滤逻辑，只需要简化版

  **References**
  - Pattern: `StrategyRangeEdgeReversion.mqh:162-204` — 价格结构过滤实现
  - API/Type: `StrategyContext` — 需要 Bars 数量检查

  **Acceptance Criteria**:
  - [ ] 函数定义在类中，编译通过

  **QA Scenarios**: N/A

  **Commit**: NO

- [x] 2. 修改 EvaluateBestSignal 中的趋势信号生成逻辑

  **What to do**: 修改 mqh:192-195，将：
  ```cpp
  if(ctx.regime == REGIME_TREND_UP)
     BuildRiskRewardSignal(ctx, state, OP_BUY, STRATEGY_LINEAR_TREND, Low[1], "TrendUp-Long", "Regime trend up confirmed", 10, candidate);
  else if(ctx.regime == REGIME_TREND_DOWN)
     BuildRiskRewardSignal(ctx, state, OP_SELL, STRATEGY_BREAKOUT, High[1], "TrendDown-Short", "Regime trend down confirmed", 10, candidate);
  ```
  改为：
  ```cpp
  if(ctx.regime == REGIME_TREND_UP)
  {
     if(!HasConsecutiveLowerLows(5, 3))  // 5根窗口内，连续3根新低则禁止
        BuildRiskRewardSignal(ctx, state, OP_BUY, STRATEGY_LINEAR_TREND, Low[1], "TrendUp-Long", "Regime trend up confirmed", 10, candidate);
  }
  else if(ctx.regime == REGIME_TREND_DOWN)
  {
     if(!HasConsecutiveHigherHighs(5, 3))  // 5根窗口内，连续3根新高则禁止
        BuildRiskRewardSignal(ctx, state, OP_SELL, STRATEGY_BREAKOUT, High[1], "TrendDown-Short", "Regime trend down confirmed", 10, candidate);
  }
  ```
  
  **Must NOT do**: 不要修改 BREAKOUT_SETUP 相关的信号生成（那是反转逻辑）

  **References**
  - Pattern: `StrategyRegistry.mqh:192-195` — 当前实现
  - Pattern: `StrategyRangeEdgeReversion.mqh:162-204` — 过滤逻辑参考

  **Acceptance Criteria**:
  - [ ] TREND_UP 信号生成前有 HasConsecutiveLowerLows 检查
  - [ ] TREND_DOWN 信号生成前有 HasConsecutiveHigherHighs 检查

  **QA Scenarios**: N/A

  **Commit**: NO

- [x] 3. 编译验证 StrategySelector.mq4

  **What to do**: 在 MetaEditor 中编译 StrategySelector.mq4，确保 0 errors, 0 warnings
  
  **Must NOT do**: 不要修改其他文件

  **Acceptance Criteria**:
  - [ ] 编译通过，0 errors, 0 warnings

  **QA Scenarios**: N/A

  **Commit**: YES | Message: `fix(registry): add trend filter to prevent reverse trade` | Files: MQL4/Include/Core/StrategyRegistry.mqh

## Final Verification Wave (MANDATORY)
- [x] F1. Plan Compliance Audit — 确认修改范围正确
- [x] F2. Code Quality Review — 代码逻辑正确
- [x] F3. Compilation Check — 0 errors, 0 warnings

## Commit Strategy
- Single commit after all tasks complete
- Message: `fix(registry): add trend filter to prevent reverse trade`
- Files: MQL4/Include/Core/StrategyRegistry.mqh

## Success Criteria
1. StrategyRegistry.mqh 编译通过
2. 逻辑正确：暴涨后下跌（连续新低）时不会生成做多信号
3. 正常上涨趋势中依然可以正常做多
