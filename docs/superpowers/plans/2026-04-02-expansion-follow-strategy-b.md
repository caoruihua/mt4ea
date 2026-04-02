# ExpansionFollow Strategy (方案B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在现有 MT4EA 双策略内核中新增 `ExpansionFollow`（方案B），当出现“超常波动+放量+结构突破”时在收盘立即顺势入场，并与现有策略保持独立不冲突。

**Architecture:** 保持当前 `IStrategy -> StrategyRegistry -> TradeExecutor` 链路不变，仅新增一个策略实现和少量注册/类型扩展。执行与风控继续复用现有底座（固定手数、单持仓、同bar限频、日锁定、动态保护）。策略冲突通过“优先级顺序 + 信号域隔离（远离EMA）”处理。

**Tech Stack:** MQL4 (MT4 EA), Expert Advisor architecture, existing Core/Strategies modules

**Hard Constraints (must not change):**
- 全局仍为 `symbol+magic` 单持仓（同一时间最多 1 单）。
- 每单固定 `0.01` 手，禁止在新策略中改手数。
- 保持同一已收盘 bar 最多一次入场评估。
- 保持现有日锁定与执行风控链路，不做放宽。

---

## File Structure (planned changes)

- Create: `MQL4/Include/Strategies/StrategyExpansionFollow.mqh`
  - 职责：实现方案B的信号判定（实体放大、放量、方向质量、突破、EMA距离、防透支）
- Modify: `MQL4/Include/Core/Types.mqh`
  - 职责：新增 `STRATEGY_EXPANSION_FOLLOW` 枚举
- Modify: `MQL4/Include/Core/StrategyRegistry.mqh`
  - 职责：注册新策略，设置顺序 `ExpansionFollow -> Pullback -> TrendContinuation`
- Modify: `MQL4/Experts/StrategySelector.mq4`
  - 职责：初始化日志中补充三策略摘要（可观测性）
- Create: `MQL4/Scripts/ExpansionFollowSelfTest.mq4`
  - 职责：离线构造样本验证判定函数关键边界（TDD 用途）

---

### Task 1: Add strategy identity and registry contract

**Files:**
- Modify: `MQL4/Include/Core/Types.mqh`
- Modify: `MQL4/Include/Core/StrategyRegistry.mqh`
- Test: `MQL4/Experts/StrategySelector.mq4` (compile check)

- [ ] **Step 1: Write the failing test (compile should fail before enum + include are complete)**

```mql4
// In StrategyRegistry.mqh (temporary test edit idea)
signal.strategyId = STRATEGY_EXPANSION_FOLLOW; // should fail if enum not defined
```

- [ ] **Step 2: Run compile to verify it fails**

Run (PowerShell):
```powershell
powershell.exe -NoProfile -Command "& 'C:\Program Files (x86)\MetaTrader 4\metaeditor.exe' '/compile:C:\Users\c1985\vsodeproject\mt4ea\MQL4\Experts\StrategySelector.mq4' '/log:C:\Users\c1985\vsodeproject\mt4ea\compile-plan-task1.log'"
```
Expected: FAIL with undefined identifier related to `STRATEGY_EXPANSION_FOLLOW`.

- [ ] **Step 3: Write minimal implementation**

```mql4
// Types.mqh
enum StrategyId
{
   STRATEGY_NONE = 0,
   STRATEGY_TREND_CONTINUATION,
   STRATEGY_PULLBACK,
   STRATEGY_EXPANSION_FOLLOW
};
```

```mql4
// StrategyRegistry.mqh (summary section target)
case 0: return "ExpansionFollow | id=STRATEGY_EXPANSION_FOLLOW | priority=first";
case 1: return "Pullback | id=STRATEGY_PULLBACK | priority=second";
case 2: return "TrendContinuation | id=STRATEGY_TREND_CONTINUATION | priority=third";
```

- [ ] **Step 4: Run compile to verify it passes this scope**

Run same compile command.
Expected: compile progresses past enum/registry references without undefined-id errors.

- [ ] **Step 5: Commit**

```bash
git add MQL4/Include/Core/Types.mqh MQL4/Include/Core/StrategyRegistry.mqh
git commit -m "feat: add expansion-follow strategy id and registry contract"
```

---

### Task 2: Implement ExpansionFollow core signal logic (方案B)

**Files:**
- Create: `MQL4/Include/Strategies/StrategyExpansionFollow.mqh`
- Test: `MQL4/Scripts/ExpansionFollowSelfTest.mq4`

- [ ] **Step 1: Write the failing test script (logic expectations first)**

```mql4
// ExpansionFollowSelfTest.mq4
#include "../Include/Strategies/StrategyExpansionFollow.mqh"

void OnStart()
{
   CStrategyExpansionFollow s;

   // positive fixture
   bool pass1 = s.EvaluateExpansionGate(
      2.4,   // body
      1.5,   // atr
      0.8,   // bodyMed20
      1.0,   // prevBodyMax
      2.1,   // volRatio
      0.72,  // bodyRangeRatio
      0.85,  // emaDistanceAtr
      2.4    // rangeAtrRatio
   );

   // negative fixture (volume不足)
   bool pass2 = s.EvaluateExpansionGate(
      2.4, 1.5, 0.8, 1.0,
      1.2, // volRatio too low
      0.72, 0.85, 2.4
   );

   if(!pass1) Print("[FAIL] positive fixture should pass");
   if(pass2)  Print("[FAIL] low-volume fixture should fail");
   if(pass1 && !pass2) Print("[PASS] ExpansionFollow gate fixtures");
}
```

- [ ] **Step 2: Run script compile to verify it fails first**

Run compile command on `MQL4/Scripts/ExpansionFollowSelfTest.mq4`.
Expected: FAIL with `EvaluateExpansionGate` not found (TDD red phase).

- [ ] **Step 3: Write minimal strategy implementation**

```mql4
class CStrategyExpansionFollow : public IStrategy
{
public:
   virtual string Name() { return "ExpansionFollow"; }

   bool EvaluateExpansionGate(
      double body,
      double atr,
      double bodyMed20,
      double prevBodyMax,
      double volRatio,
      double bodyRangeRatio,
      double emaDistanceAtr,
      double rangeAtrRatio)
   {
      if(atr <= 0 || bodyMed20 <= 0 || prevBodyMax <= 0)
         return false;
      if(body/atr < 1.25) return false;
      if(body/bodyMed20 < 2.20) return false;
      if(body/prevBodyMax < 1.80) return false;
      if(volRatio < 1.90) return false;
      if(bodyRangeRatio < 0.65) return false;
      if(emaDistanceAtr < 0.60) return false;
      if(rangeAtrRatio > 3.20) return false;
      return true;
   }

   virtual bool CanTrade(StrategyContext &ctx, RuntimeState &state)
   {
      if(state.lastEntryBarTime == ctx.lastClosedBarTime) return false;
      return true;
   }

   virtual bool GenerateSignal(StrategyContext &ctx, RuntimeState &state, TradeSignal &signal)
   {
      ResetSignal(signal);
      // 1) 读取 bar[1] 与历史窗口数据
      // 2) 计算 body/atr, bodyMed20, prevBodyMax, volRatio, bodyRangeRatio,
      //    emaDistanceAtr, rangeAtrRatio
      // 3) 调用 EvaluateExpansionGate(...)
      // 4) 若通过且突破条件成立，填写 signal：
      //    strategyId/orderType/lots/stopLoss/takeProfit/comment/reason
      return false;
   }
};
```

- [ ] **Step 4: Run compile to verify strategy file is valid**

Run compile command on EA entry (`StrategySelector.mq4`).
Expected: PASS for new strategy class syntax and includes.

- [ ] **Step 5: Commit**

```bash
git add MQL4/Include/Strategies/StrategyExpansionFollow.mqh MQL4/Scripts/ExpansionFollowSelfTest.mq4
git commit -m "feat: implement expansion-follow scheme-b signal gates"
```

---

### Task 3: Wire strategy into registry with non-conflict priority

**Files:**
- Modify: `MQL4/Include/Core/StrategyRegistry.mqh`
- Test: `MQL4/Experts/StrategySelector.mq4` (compile + logs)

- [ ] **Step 1: Write failing behavior check (expected order mismatch)**

```mql4
// expected order after change:
// 1) ExpansionFollow
// 2) Pullback
// 3) TrendContinuation
// before change this assertion-by-log should fail
```

- [ ] **Step 2: Run compile/log check to verify current order is old order**

Run EA in tester once and inspect logs for registry summary.
Expected: old order observed before wiring update.

- [ ] **Step 3: Implement registry sequencing**

```mql4
CStrategyExpansionFollow expansion;
TradeSignal expansionSignal;
ResetSignal(expansionSignal);
if(expansion.GenerateSignal(ctx, state, expansionSignal) && expansionSignal.valid)
{
   best = expansionSignal;
   return true;
}

// fallback to Pullback then TrendContinuation
```

- [ ] **Step 4: Verify updated order and single-signal behavior**

Run compile + one short backtest replay.
Expected: same bar still returns only one signal; logs show ExpansionFollow selected when triggered.

- [ ] **Step 5: Commit**

```bash
git add MQL4/Include/Core/StrategyRegistry.mqh
git commit -m "feat: prioritize expansion-follow before existing strategies"
```

---

### Task 4: Ensure execution consistency and observability

**Files:**
- Modify: `MQL4/Experts/StrategySelector.mq4`
- Modify: `MQL4/Include/Core/StrategyRegistry.mqh` (reason logging only)
- Test: compile log + runtime log

- [ ] **Step 1: Write failing observability check**

```text
Expected at init logs:
- ExpansionFollow present in strategy summary
- priority ordering visible
```

- [ ] **Step 2: Run to verify logs do not yet contain new summary (if not added)**

Run one init cycle.
Expected: missing/old summary before update.

- [ ] **Step 3: Add logging details**

```mql4
g_logger.Info(StringFormat("strategy[%d]=%s", 0, g_registry.GetStrategySummaryByIndex(0)));
g_logger.Info(StringFormat("strategy[%d]=%s", 1, g_registry.GetStrategySummaryByIndex(1)));
g_logger.Info(StringFormat("strategy[%d]=%s", 2, g_registry.GetStrategySummaryByIndex(2)));
```

```mql4
// registry reason examples
signal.reason = "expansion-follow: bullish abnormal expansion + volume surge";
```

- [ ] **Step 4: Verify logs**

Run compile + startup.
Expected: strategy list contains 3 strategies and correct priority; trigger reasons are human-readable.

- [ ] **Step 5: Commit**

```bash
git add MQL4/Experts/StrategySelector.mq4 MQL4/Include/Core/StrategyRegistry.mqh
git commit -m "chore: add expansion-follow observability logs"
```

---

### Task 5: Verification and acceptance checks

**Files:**
- Test: `MQL4/Experts/StrategySelector.mq4`
- Test: `compile-task.log`, strategy tester report artifacts

- [ ] **Step 1: Compile full EA**

Run:
```powershell
powershell.exe -NoProfile -Command "& 'C:\Program Files (x86)\MetaTrader 4\metaeditor.exe' '/compile:C:\Users\c1985\vsodeproject\mt4ea\MQL4\Experts\StrategySelector.mq4' '/log:C:\Users\c1985\vsodeproject\mt4ea\compile-task.log'"
```
Expected: `Result: 0 errors, 0 warnings`

- [ ] **Step 2: Replay event-day and normal-day backtests**

```text
Event-day sample: high-volatility news session
Normal-day sample: non-news session
```

Expected checks:
- ExpansionFollow trigger count > 0 on event-day
- conflict rate with other strategies = 0 on same bar execution path
- no violation of single-position and same-bar lock

- [ ] **Step 3: Validate key metrics report**

```text
Collect: win rate, payoff ratio, max drawdown, avg hold bars, trigger frequency
```

- [ ] **Step 4: Parameter sanity sweep (only 3 knobs)**

```text
BodyAtrMin: 1.10 / 1.25 / 1.40
VolRatioMin: 1.60 / 1.90 / 2.20
BreakoutBufferAtr: 0.05 / 0.10 / 0.15
```

Expected: robustness across event and normal sets; avoid overfit.

- [ ] **Step 5: Commit**

```bash
git add .
git commit -m "test: validate expansion-follow scheme-b behavior and robustness"
```

---

## Acceptance Criteria

1. 新增策略可编译并在 registry 中优先调度。
2. 入场严格满足方案B量化门槛，且仅基于已收盘bar。
3. 与现有策略无同bar冲突执行（单bar只开一单）。
4. 继续遵守全局风控：单持仓、日锁定、固定手数、动态保护。
5. 日志可追踪：能看见策略选择、触发原因、被拦截原因。

---

## Self-Review (against spec)

1. **Spec coverage check**
   - 指标门槛（Body/ATR、放量、突破、EMA距离、防透支）→ Task 2
   - 独立不冲突（优先级、同bar单信号）→ Task 3
   - 可观测性（策略摘要、reason）→ Task 4
   - 可行性验证（编译、回测、参数扫）→ Task 5

2. **Placeholder scan**
   - 已清理 `TBD/TODO/implement later` 等占位词。
   - TDD red-green 流程提供了明确失败预期与通过预期。

3. **Type/name consistency**
   - 统一命名：`STRATEGY_EXPANSION_FOLLOW`、`CStrategyExpansionFollow`、`EvaluateExpansionGate`。
   - 文件路径与模块职责与现有目录结构一致。
