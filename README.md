# StrategySelector 当前实现说明

本仓库当前实际运行入口是 `MQL4/Experts/StrategySelector.mq4`。

这份 README 只描述当前代码里已经接入执行链的逻辑，不再沿用早期多 session 策略总览里的过期描述。

## 1. 当前架构

```text
MQL4/
├─ Experts/
│  └─ StrategySelector.mq4
└─ Include/
   ├─ Core/
   │  ├─ Types.mqh
   │  ├─ Logger.mqh
   │  ├─ SessionClock.mqh
   │  ├─ SignalEngine.mqh
   │  ├─ StateStore.mqh
   │  ├─ StateStabilizer.mqh
   │  ├─ MarketState.mqh
   │  ├─ RiskManager.mqh
   │  ├─ TradeExecutor.mqh
   │  ├─ StrategyBase.mqh
   │  └─ StrategyRegistry.mqh
   └─ Strategies/
      ├─ StrategyLinearTrend.mqh
      ├─ StrategyOscillation.mqh
      ├─ StrategyBreakout.mqh
      ├─ StrategyReversal.mqh
      ├─ StrategySlopeChannel.mqh
      ├─ StrategyRangeEdgeReversion.mqh
      └─ StrategySpikeMomentum.mqh
```

## 2. 主流程

`StrategySelector.mq4` 在每个 tick 上的执行顺序如下：

1. `FillContext()`
   将报价、指标、北京时间、session、风控参数、策略参数写入 `StrategyContext`。
2. `RiskManager.ResetDailyCounters()`
   按北京时间自然日重置计数器。
3. 每日 01:00 重置
   如果满足条件，平掉当前仓位并清空当日状态。
4. `TradeExecutor.CheckStopLossTakeProfit()`
   主动检查当前持仓是否触发 SL/TP。
5. `RiskManager.CheckCircuitBreaker()`
   当日盈利、亏损或累计价格位移达到阈值时触发熔断。
6. `TradeExecutor.ApplyGlobalProfitLockIfNeeded()`
   对当前持仓应用全局锁盈止损。
7. `TradeExecutor.ApplyProtectionIfNeeded()`
   仅对 `RangeEdgeReversion` 持仓应用保护性止损上移。
8. 指标可用性检查
   EMA / RSI / MACD / ATR / ADX 缺失时直接跳过。
9. `MarketState.Detect()` + `StateStabilizer.Stabilize()`
   先识别原始市场状态，再做稳定化处理。
10. `StrategyRegistry.EvaluateBestSignal()`
    统一评估当前已注册策略，返回最高优先级信号。
11. 若已有持仓则不再开新单；否则通过 `TradeExecutor.OpenOrder()` 下单。

## 3. 当前实际接入的策略集合

当前注册层实际参与评估的只有 6 类候选：

1. `TrendFollowLong | id=STRATEGY_LINEAR_TREND | priority=10`
   不是调用 `StrategyLinearTrend` 模块，而是注册层在 `REGIME_TREND_UP` 下直接构造做多信号。
2. `TrendFollowShort | id=STRATEGY_BREAKOUT | priority=10`
   不是调用 `StrategyBreakout` 模块，而是注册层在 `REGIME_TREND_DOWN` 下直接构造做空信号。
3. `BreakoutRetest | id=STRATEGY_REVERSAL | priority=12`
   由注册层在突破回踩确认状态下直接构造信号。
4. `RangeEdgeReversion | id=STRATEGY_RANGE_EDGE_REVERSION | priority=14`
   通过独立策略文件 `StrategyRangeEdgeReversion.mqh` 评估。
5. `WickRejection | id=STRATEGY_WICK_REJECTION | priority=13`
   由注册层内部根据 wick rejection 规则直接构造信号。
6. `SpikeMomentum | id=STRATEGY_SPIKE_MOMENTUM | priority=15`
   通过独立策略文件 `StrategySpikeMomentum.mqh` 评估。

优先级从高到低大致为：

- `SpikeMomentum` 15
- `RangeEdgeReversion` 14
- `WickRejection` 13
- `BreakoutRetest` 12
- `TrendFollowLong/Short` 10

## 4. 当前市场状态逻辑

`MarketState.mqh` 当前输出以下状态：

- `REGIME_UNKNOWN`
- `REGIME_RANGE`
- `REGIME_BREAKOUT_SETUP_UP`
- `REGIME_BREAKOUT_SETUP_DOWN`
- `REGIME_TREND_UP`
- `REGIME_TREND_DOWN`

判定核心：

- 使用最近 30 根 K 线的高低点和 ATR 识别区间宽度。
- 使用 `EMA20 / EMA50 / ADX14` 和近 3 根 K 线结构识别趋势。
- 当区间内发生向上或向下有效突破时，进入 `BREAKOUT_SETUP_*`。
- 已记录突破回踩状态时，优先判断回踩是否成立或失效。
- 最终结果再经过 `StateStabilizer` 稳定化后写回 `ctx.regime`。

## 5. 各策略当前实现

### 5.1 TrendFollowLong / TrendFollowShort

这两类不是独立策略类，而是 `StrategyRegistry.mqh` 里的 regime 驱动规则：

- `REGIME_TREND_UP` 下，若没有明显连续创新低，构造做多信号。
- `REGIME_TREND_DOWN` 下，若没有明显连续创新高，构造做空信号。
- 止损缓冲优先使用 ATR 缓冲，否则使用固定 `SL_Buffer_Fixed_USD`。
- 止盈按 `TakeProfit_R_Multiple` 计算风险收益比。

### 5.2 BreakoutRetest

同样由注册层直接生成：

- `REGIME_BREAKOUT_SETUP_UP` 且 `breakoutRetestActive=true` 时，若低点回踩突破位附近，构造做多。
- `REGIME_BREAKOUT_SETUP_DOWN` 且 `breakoutRetestActive=true` 时，若高点回踩突破位附近，构造做空。

### 5.3 RangeEdgeReversion

文件：`MQL4/Include/Strategies/StrategyRangeEdgeReversion.mqh`

当前逻辑：

- 仅在 `REGIME_RANGE` 下允许评估。
- 使用观察窗口 `RangeEdge_Observation_Bars` 和交易窗口 `RangeEdge_Trading_Bars`。
- 价格接近交易区间上沿时尝试做空，接近下沿时尝试做多。
- 止损放在区间外侧：`tradeHigh + SL_Buffer` 或 `tradeLow - SL_Buffer`。
- 止盈使用区间中轴 `mid = (tradeHigh + tradeLow) / 2`。

当前内置三层趋势过滤：

- 价格结构过滤
- EMA 方向过滤
- 可选 ADX 过滤

对应参数：

- `InpEnableTrendFilter`
- `InpTrendFilterWindow`
- `InpTrendFilterThreshold`
- `InpEnableEmaFilter`
- `InpEmaFastPeriod`
- `InpEmaSlowPeriod`
- `InpEnableAdxFilter`
- `InpAdxPeriod`
- `InpAdxThreshold`

### 5.4 WickRejection

由 `StrategyRegistry.mqh` 内部直接生成：

- 统计最近 `Wick_Window_Bars` 根 K 线。
- 如果上沿附近出现足够多的长上影且未有效突破，生成做空。
- 如果下沿附近出现足够多的长下影且未有效跌破，生成做多。
- 使用独立的 `Wick_SL_USD / Wick_TP_USD`。

### 5.5 SpikeMomentum

文件：`MQL4/Include/Strategies/StrategySpikeMomentum.mqh`

当前逻辑：

- 仅当 `Spike_Enable=true` 时生效。
- 从 M1 数据中回看最近 `Spike_Window_Seconds` 秒。
- 计算窗口最高点、最低点与脉冲幅度 `impulse`。
- 幅度达到 `Spike_Trigger_USD` 后，判断当前价格相对脉冲极值的回吐比例。
- 若回吐比例不超过 `Spike_Max_Pullback_Ratio`，则按方向跟随入场。
- 使用固定 `Spike_SL_USD / Spike_TP_USD`。
- 记录最近一次 spike 事件，避免在同一脉冲上重复触发。

## 6. 当前风控与执行

### 6.1 熔断

`RiskManager.mqh` 当前有三类熔断条件：

- `dailyPriceDelta >= DailyPriceDeltaTargetUsd`
- `dailyProfit >= PROFIT_THRESHOLD_USD`
- `dailyLoss >= AccountBalance() * LOSS_THRESHOLD_PERCENT / 100`

触发后：

- 标记 `circuitBreakerActive=true`
- 若当前有持仓则立即平仓
- 本 tick 不再继续开仓评估

### 6.2 全局锁盈止损

`TradeExecutor.ApplyGlobalProfitLockIfNeeded()` 当前对所有受管持仓生效：

- 浮盈达到 `GlobalProfitLockTriggerUsd` 后，将止损移动到开仓价附近。
- 当浮盈继续扩大时，代码里还有固定阶梯式推进逻辑：
  - 浮盈 `>= 10` 时开始阶梯上移
  - 之后每增加 `5`，最多再上移 3 级

### 6.3 RangeEdge 专属保护

`TradeExecutor.ApplyProtectionIfNeeded()` 仅对注释中包含 `RangeEdgeReversion` 的订单生效：

- 浮盈达到 `RangeEdge_Protection_Trigger_USD` 后
- 将止损上移到开仓价附近
- 上移幅度由 `RangeEdge_Protection_Lock_USD` 控制

### 6.4 主动检查 SL/TP

`TradeExecutor.CheckStopLossTakeProfit()` 会在每个 tick 主动比较当前 Bid/Ask 与订单的 SL/TP：

- 触发止损则调用 `CloseOrder()`
- 触发止盈则调用 `CloseOrder()`
- 平仓结果会累加到 `dailyProfit / dailyLoss / dailyPriceDelta`

## 7. 参数说明

### 7.1 通用参数

- `TimeZoneOffset`
- `MagicNumber`
- `LogLevel`
- `EnableStrategyHealthReport`
- `UseAtrStopBuffer`
- `EnableGlobalProfitLockStop`
- `GlobalProfitLockTriggerUsd`
- `GlobalProfitLockOffsetUsd`
- `SL_Buffer_ATR_Multiplier`
- `SL_Buffer_Fixed_USD`
- `TakeProfit_R_Multiple`
- `DailyPriceDeltaTargetUsd`

### 7.2 RangeEdgeReversion 参数

- `RangeEdge_Observation_Bars`
- `RangeEdge_Trading_Bars`
- `RangeEdge_EntryTolerance_USD`
- `RangeEdge_SL_Buffer_USD`
- `RangeEdge_EnableProtection`
- `RangeEdge_Protection_Trigger_USD`
- `RangeEdge_Protection_Lock_USD`

以及策略文件内部 input：

- `InpEnableTrendFilter`
- `InpTrendFilterWindow`
- `InpTrendFilterThreshold`
- `InpEnableEmaFilter`
- `InpEmaFastPeriod`
- `InpEmaSlowPeriod`
- `InpEnableAdxFilter`
- `InpAdxPeriod`
- `InpAdxThreshold`

### 7.3 WickRejection 参数

- `Wick_Window_Bars`
- `Wick_Min_Upper_Ratio`
- `Wick_Min_Lower_Ratio`
- `Wick_Min_Length_USD`
- `Wick_Min_Count`
- `Wick_Break_Tolerance_USD`
- `Wick_SL_USD`
- `Wick_TP_USD`

### 7.4 SpikeMomentum 参数

- `Spike_Enable`
- `Spike_Window_Seconds`
- `Spike_Trigger_USD`
- `Spike_Max_Pullback_Ratio`
- `Spike_SL_USD`
- `Spike_TP_USD`
- `Spike_Log_Verbose`

### 7.5 仍保留在上下文中的旧参数

以下参数目前仍会写入 `StrategyContext`，仓库里也保留了对应旧策略文件，但当前注册层默认不直接调用这些旧策略模块：

- `Session1_3_*`
- `Session2_*`
- `Session4_*`
- `Session5_*`
- `Session6_*`
- `Channel_*`

这些参数和模块目前更适合视为历史遗留或备用实现，而不是当前默认执行链的一部分。

## 8. 当前已知事实

- 当前执行链是“regime 驱动 + 中央注册层仲裁”，不是早期 README 里那种按 session 直接切换完整策略类。
- 当前 `StrategyRegistry` 注册统计里会显示 6 个策略摘要，这与代码一致。
- 当前存在旧策略模块文件，但不代表它们都在默认执行链中实际参与信号生成。

## 9. 编译与验证

编译目标：

- `MQL4/Experts/StrategySelector.mq4`

建议验证项：

1. 在 MetaEditor 编译 `StrategySelector.mq4`
2. 在 MT4/策略测试器确认日志中输出的策略摘要与 README 第 3 节一致
3. 分别验证：
   - `REGIME_RANGE` 下是否能触发 `RangeEdgeReversion`
   - spike 条件满足时是否触发 `SpikeMomentum`
   - 全局锁盈和 RangeEdge 保护是否按预期移动止损
