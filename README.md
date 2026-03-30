# MT4EA Strategy Selector

一个基于 MT4（MQL4）的多策略自动交易项目，核心目标是：

- 在同一个 EA 中统一管理多种入场策略
- 根据市场状态动态选择当前最合适的策略信号
- 统一执行风控（止损止盈、熔断、利润保护、状态持久化）

如果你只看一眼就想知道这个项目做什么：  
这是一个“**多策略信号引擎 + 统一交易执行与风控**”的黄金（XAUUSD）自动交易框架。

## 项目结构

```text
MQL4/
├─ Experts/
│  └─ StrategySelector.mq4            # EA 入口，参数、调度、下单主流程
└─ Include/
   ├─ Core/
   │  ├─ Types.mqh                    # 上下文、运行态、信号等核心数据结构
   │  ├─ StrategyRegistry.mqh         # 策略注册与优先级选择
   │  ├─ StateStore.mqh               # 运行状态持久化（EA_State.txt）
   │  ├─ RiskManager.mqh              # 日内风控与熔断
   │  ├─ TradeExecutor.mqh            # 下单、平仓、保护逻辑
   │  ├─ MarketState.mqh              # 市场状态识别（regime）
   │  └─ StateStabilizer.mqh          # 状态去抖与稳定
   └─ Strategies/
      ├─ StrategyLinearTrend.mqh
      ├─ StrategyBreakout.mqh
      ├─ StrategyReversal.mqh
      ├─ StrategyRangeEdgeReversion.mqh
      ├─ StrategyWickRejection.mqh
      ├─ StrategySpikeMomentum.mqh
      └─ StrategySlopeChannel.mqh
```

## 主流程（每个 tick）

1. 读取并填充 `StrategyContext`
2. 更新日内统计与风控状态
3. 识别/稳定市场状态（`regime`）
4. 策略注册器评估全部策略信号并按优先级择优
5. 通过 `TradeExecutor` 统一执行下单、止损止盈、保护和持久化

## 最近重要变更（2026-03）

### 1) SlopeChannel 新增“回踩震荡突破”入场逻辑（重点）

目的：解决上涨中途急跌时，价格刚到趋势线附近就过早做多、容易止损的问题。

当前做多触发流程改为分阶段：

- `idle`：等待回踩场景出现
- `pullback`：记录这轮下跌起点（回踩前最高点）和支撑参考位
- `base`：要求在支撑附近出现“多次下破尝试但收盘未有效跌破”
- `armed`：当实时价格回升到本轮跌幅的 70% 时触发做多

触发价格公式：

```text
recoveryLevel = baseAvg + (pullbackHigh - baseAvg) * Channel_Recovery_Trigger_Ratio
```

其中：

- `pullbackHigh`：上涨过程中的本轮高点
- `baseAvg`：本轮“支撑防守”阶段若干根 K 线收盘价均值
- `Channel_Recovery_Trigger_Ratio`：默认 `0.70`

### 2) 新增 SlopeChannel 参数（可在 EA 输入中直接调）

- `Channel_Pullback_MinDrop_USD`：最小回踩幅度
- `Channel_SupportTestTolerance_USD`：支撑测试容差
- `Channel_BreakdownCloseTolerance_USD`：有效跌破判定容差（按收盘）
- `Channel_Base_MinTests`：支撑防守最少测试次数
- `Channel_Base_MaxBars`：防守统计最大 K 线数
- `Channel_Recovery_Trigger_Ratio`：回升触发比例（默认 70%）

### 3) 状态持久化与风控联动更新

- `RuntimeState` 增加回踩/筑底/恢复阶段相关字段
- `StateStore` 支持新字段写入与恢复
- `RiskManager` 在重置路径中同步清理该策略临时状态

### 4) SlopeChannel 已纳入统一策略注册

`StrategyRegistry` 现在会参与评估 `StrategySlopeChannel`，并与其他策略统一进行优先级比较和选信号。

## 关键参数分组建议

- 结构识别参数：`Channel_Lookback_Bars`、`Channel_MinSlope`、`Channel_ParallelTolerance`
- 风险参数：`Channel_SL_USD`、`Channel_TP_USD`、`Channel_MaxTradesPerDay`
- 回踩突破参数：`Channel_Pullback_MinDrop_USD`、`Channel_Base_MinTests`、`Channel_Recovery_Trigger_Ratio`

建议先固定 SL/TP 与交易时段，再单独回测回踩参数，不要同时大范围改全部输入。

## 编译与验证

1. 使用 MetaEditor 打开 `MQL4/Experts/StrategySelector.mq4`
2. 编译 EA，确认无错误
3. 在策略测试器重点验证以下场景：
- 上涨中急跌但未止跌时，不应提前做多
- 支撑位多次防守后，价格恢复到 70% 区域才允许做多
- 跌破支撑被确认后，旧 setup 应被正确重置

## 注意事项

- 本项目当前主要针对 XAUUSD 价格行为特征做参数化，迁移到其他品种需要重标定
- 回测与实盘点差/滑点差异会影响触发质量，建议在日志中重点观察 `waiting_base` / `waiting_recovery` / `trigger=long` 三类日志
