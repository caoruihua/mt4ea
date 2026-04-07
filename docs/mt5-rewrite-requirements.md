# sanqing-ea MT5 重写需求文档

## 1. 文档目的

本文档用于把当前活跃的 MT4 项目需求整理成一份可直接用于 MT5 重写的基线规格。

它的目标不是逐行翻译 MT4 代码，而是明确：

- 这个 EA 现在到底做什么
- 哪些行为必须保留
- 哪些模块边界必须维持
- MT5 重写时需要达到什么验收标准

## 2. 范围

本文档仅覆盖当前活跃主链路：

- [StrategySelector.mq4](C:\Users\c1985\vsodeproject\sanqing-ea\MQL4\Experts\StrategySelector.mq4)
- `MQL4/Include/Core` 下的核心模块
- `MQL4/Include/Strategies` 下的三套策略模块

明确不纳入本次主需求源的内容：

- [XAUUSD_MultiSession_Strategy.mq4](C:\Users\c1985\vsodeproject\sanqing-ea\XAUUSD_MultiSession_Strategy.mq4) 这类旧单文件 EA
- 已废弃、实验性、或不再由当前 `StrategySelector` 主流程调度的逻辑
- 仅属于 MT4 平台实现细节、应在 MT5 中重新设计的 API 细节

## 3. 产品目标

该系统是一个面向黄金交易的自动交易 EA，当前目标市场与运行约束为：

- 品种：`XAUUSD`
- 周期：`M5`
- 单一 `symbol + magic` 只允许存在一个持仓
- 所有交易决策基于已收盘 K 线
- 使用极简内核架构，把信号、风控、执行、状态做模块化分离

当前系统包含三套策略：

- `ExpansionFollow`
- `Pullback`
- `TrendContinuation`

策略调度优先级固定为：

1. `ExpansionFollow`
2. `Pullback`
3. `TrendContinuation`

## 4. 整体行为流程

EA 每个 tick 的主流程如下：

1. 从当前市场构建统一上下文快照
2. 同步日内风险状态
3. 对已有持仓执行保护逻辑
4. 仅在“新收盘 bar”时评估新开仓
5. 若日锁定已触发或当日交易次数达到上限，则禁止新开仓
6. 若已有同 `symbol + magic` 持仓，则禁止重复开仓
7. 执行市场过滤
8. 按固定优先级依次评估三套策略
9. 若得到有效信号，则只开一单
10. 保存重启后必须恢复的运行状态

## 5. 输入参数与默认值

当前主入口 [StrategySelector.mq4](C:\Users\c1985\vsodeproject\sanqing-ea\MQL4\Experts\StrategySelector.mq4) 的有效输入参数如下：

- `MagicNumber = 20260313`
- `LogLevel = 1`
- `MaxTradesPerDay = 30`
- `DailyProfitStopUsd = 50.0`
- `FixedLots = 0.01`
- `EMAFastPeriod = 9`
- `EMASlowPeriod = 21`
- `LowVolAtrPointsFloor = 300.0`
- `LowVolAtrSpreadRatioFloor = 3.0`
- `Slippage = 30`
- `MaxRetries = 6`

输入校验要求：

- `FixedLots > 0`
- `EMAFastPeriod > 0`
- `EMASlowPeriod > 0`
- `EMAFastPeriod < EMASlowPeriod`

## 6. 市场快照与指标要求

系统的决策基础是“最近一根已收盘 M5 K 线”，不是当前尚未收盘的 bar。

统一上下文必须包含以下字段：

- `symbol`
- `timeframe`
- `digits`
- `magicNumber`
- `bid`
- `ask`
- `emaFast`
- `emaSlow`
- `atr14`
- `spreadPoints`
- `lastClosedBarTime`

指标要求：

- 快 EMA：可配置周期，`PRICE_CLOSE`
- 慢 EMA：可配置周期，`PRICE_CLOSE`
- `ATR(14)`

当前实现特征：

- ATR 使用已收盘信号柱所在的快照值
- 因此如果一根爆发柱刚刚收盘，这根柱子本身会参与该次决策使用的 ATR 计算

## 7. 市场过滤要求

全局市场过滤器必须输出：

- 是否低波动
- 趋势方向
- 趋势是否有效

### 7.1 低波动过滤

出现以下任一条件时，必须阻止新开仓：

- `ATR points < LowVolAtrPointsFloor`
- `ATR points / spread points < LowVolAtrSpreadRatioFloor`

注意：

- 该过滤只影响新开仓
- 不得阻止已有持仓的保护或平仓管理

### 7.2 趋势有效性判断

上升趋势成立条件：

- `emaFast > emaSlow`
- `emaFast > emaFastPrev3`
- `emaSlow > emaSlowPrev3`

下降趋势成立条件：

- `emaFast < emaSlow`
- `emaFast < emaFastPrev3`
- `emaSlow < emaSlowPrev3`

若两边都不满足，则视为“无有效趋势”。

## 8. 开仓门禁要求

任意策略在尝试开仓前，必须同时满足以下条件：

- 当前评估对象是一根新的已收盘 bar，且尚未处理过
- 当日日锁未触发
- `tradesToday < MaxTradesPerDay`
- 当前不存在同 `symbol + magic` 的持仓
- 策略自己的 `CanTrade()` 返回 true

系统约束：

- 同一根已收盘 bar 最多只允许开一单

## 9. 策略需求

### 9.1 TrendContinuation

目标：

- 在有效趋势中，跟随最近一根已收盘 K 线的结构突破继续入场

多头条件：

- `emaFast > emaSlow`
- `Close[1] >= max(High[2], High[3]) + 0.20 * ATR`
- `abs(Close[1] - Open[1]) >= 0.35 * ATR`

空头条件：

- `emaFast < emaSlow`
- `Close[1] <= min(Low[2], Low[3]) - 0.20 * ATR`
- `abs(Close[1] - Open[1]) >= 0.35 * ATR`

初始风控：

- 初始止损距离：`1.2 * ATR`
- 初始止盈距离：`2.0 * ATR`

### 9.2 Pullback

目标：

- 在趋势方向中等待价格回踩快 EMA，并通过拒绝形态确认后入场

公共约束：

- 非低波动环境
- 当前收盘 bar 尚未开过仓
- 至少有足够历史 bar

多头条件：

- `emaFast > emaSlow`
- 收盘位于最近 20 根通道下半区
- `bar[1]` 回踩快 EMA，容差为 `0.15 * ATR`
- 收盘重新站回快 EMA 上方
- K 线为阳线
- 下影线长度至少为实体的 `50%`

空头条件：

- `emaFast < emaSlow`
- 收盘位于最近 20 根通道上半区
- `bar[1]` 回踩快 EMA，容差为 `0.15 * ATR`
- 收盘重新跌回快 EMA 下方
- K 线为阴线
- 上影线长度至少为实体的 `50%`

初始风控：

- 初始止损距离：`1.2 * ATR`
- 初始止盈距离：`2.0 * ATR`

### 9.3 ExpansionFollow

目标：

- 识别一根“异常放大、放量、方向干净、并形成结构突破”的爆发柱，然后顺势入场

公共条件：

- 非低波动环境
- 至少有 30 根历史 bar
- `body > 0`
- `range > 0`

爆发门槛：

- `body / atr >= 4.0`
- `body / medianBody20 >= 2.20`
- `body / prev3BodyMax >= 1.80`
- `volume / volumeMA20 >= 1.90`
- `body / range >= 0.65`

方向条件：

- 多头：
  - 当前收盘柱为阳线
  - 反向下影线占比 `<= 0.25`
  - `Close[1] > high20 + 0.10 * ATR`
- 空头：
  - 当前收盘柱为阴线
  - 反向上影线占比 `<= 0.25`
  - `Close[1] < low20 - 0.10 * ATR`

初始风控：

- 多头止损：`Low[1] + range1 * 0.6`
- 空头止损：`High[1] - range1 * 0.6`
- 初始止盈：`2.0 * ATR`

重要说明：

- 之前的 `range / atr` 上限约束已经移除，因为它会和当前的实体强度约束形成逻辑冲突

## 10. 统一执行要求

所有下单、平仓、改单必须走统一执行模块。

执行层必须满足：

- 同一 `symbol + magic` 只允许一个持仓
- 实际手数来源必须闭环：
  - `FixedLots -> StrategyContext.fixedLots -> TradeSignal.lots -> OrderSend`
- 使用配置的 `Slippage`
- 下单失败时按 `MaxRetries` 重试
- 平仓失败时按 `MaxRetries` 重试

日志要求：

- 记录开仓成功
- 记录开仓失败与错误码
- 记录平仓成功
- 记录动态保护更新

## 11. 初始止盈止损与动态保护要求

每套策略自己决定初始 `SL/TP`，但进场后统一由执行层动态保护逻辑接管。

### 11.1 第一阶段保护

当浮盈达到 `1.0 * ATR` 时：

- 止损推进到保本附近：
  - 多单：`entry + 0.1 * ATR`
  - 空单：`entry - 0.1 * ATR`
- 止盈至少扩到：
  - 多单：`entry + 2.5 * ATR`
  - 空单：`entry - 2.5 * ATR`

### 11.2 第二阶段保护

当浮盈达到 `1.5 * ATR` 时：

- 启动基于 `Close[1]` 的追踪
- 多单：
  - `SL = Close[1] - 0.9 * ATR`
  - `TP = Close[1] + 0.8 * ATR`
- 空单：
  - `SL = Close[1] + 0.9 * ATR`
  - `TP = Close[1] - 0.8 * ATR`

### 11.3 动态保护不变量

- 止盈止损只允许向有利方向推进
- 不允许回撤后把保护条件放松
- 改单必须满足经纪商最小距离和冻结距离
- 即使禁止新开仓，也必须继续管理已有持仓

## 12. 日内风险控制要求

系统必须基于服务器日而不是本地日来管理日内风险。

日锁逻辑要求：

- 使用 `YYYY.MM.DD 00:00:00` 作为服务器日键
- 每个 tick 都根据历史已平仓订单重算当日已实现净收益：
  - `OrderProfit + OrderSwap + OrderCommission`
- 若 `dailyClosedProfit >= DailyProfitStopUsd`，则设置 `dailyLocked = true`
- `dailyLocked = true` 时：
  - 禁止新开仓
- 跨到新的服务器日时：
  - 重置 `dayKey`
  - 重置 `dailyLocked`
  - 重置 `dailyClosedProfit`
  - 重置 `tradesToday`

## 13. 运行时状态持久化要求

系统必须持久化最小但必要的运行状态，以保证重启后行为连续。

必须持久化的字段：

- `dayKey`
- `dailyLocked`
- `dailyClosedProfit`
- `tradesToday`
- `lastEntryBarTime`
- `entryPrice`
- `entryAtr`
- `highestCloseSinceEntry`
- `lowestCloseSinceEntry`
- `trailingActive`

持久化时机要求：

- `OnDeinit`
- 开仓成功后
- 保护或止盈止损触发平仓后
- `OnInit` 时加载

## 14. 日志要求

系统至少应记录以下日志类型：

- 初始化摘要
- 策略注册摘要
- 心跳 / 运行快照
- 被拦截的原因
- 开仓成功 / 失败
- 平仓成功 / 失败
- 动态保护更新

当前实现问题：

- 心跳日志和日锁重复日志占比过高，日志体积膨胀明显

MT5 重写建议：

- 保留诊断价值
- 控制心跳与重复阻断日志的输出频率

## 15. 非功能性要求

- 所有交易决策基于已收盘 K 线
- 策略模块只负责信号生成，不直接下单
- 市场快照、风控、执行、状态持久化必须保持中心化管理
- 架构应尽量清晰、可维护、可验证

## 16. MT5 重写要求

MT5 重写必须保留行为语义，但不要求照搬 MT4 代码结构。

MT5 重写时应满足：

- 使用 MT5 的持仓、订单、成交 API 替代 MT4 订单池 API
- 用 MT5 原生方式替代：
  - `OrderSend`
  - `OrderClose`
  - `OrderModify`
  - `OrdersTotal`
  - `OrdersHistoryTotal`
- 保留当前三套策略的判定语义与阈值，除非明确决定重构
- 保留基于已收盘 bar 的决策模型
- 保留按已实现收益触发的日锁语义
- 保留同 `symbol + magic` 单持仓约束
- 保留动态保护语义
- 持久化方案可重构，但必须保证重启后行为连续

## 17. MT5 重写验收标准

MT5 重写版本至少必须满足：

1. 可以在 MT5 中正常编译
2. 可运行于 `XAUUSD` `M5`
3. 维持单 `symbol + magic` 单持仓约束
4. 正确重现三套策略的判定语义
5. 正确重现日锁逻辑
6. 正确重现动态止盈止损推进逻辑
7. 正确持久化并恢复运行状态
8. 输出足够的日志用于诊断拦截、开平仓和保护行为

## 18. 建议的下一步文档

如果你要基于本文档启动 MT5 重写，建议下一步补齐以下文档：

- `MT4 -> MT5 API 对照表`
- MT5 项目目录与模块设计稿
- 行为一致性测试计划
- MT4 与 MT5 回测结果对比方案
