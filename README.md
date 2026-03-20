# 模块化 MQL4 EA 使用说明（StrategySelector）

> 本文档对应新架构 `MQL4/Experts/StrategySelector.mq4`。
> 旧文件 `XAUUSD_MultiSession_Strategy.mq4` 保留不变，可继续作为回退版本。

---

## 1. 目录结构

```text
MQL4/
├── Experts/
│   └── StrategySelector.mq4
│
└── Include/
    ├── Core/
    │   ├── Types.mqh
    │   ├── Logger.mqh
    │   ├── SessionClock.mqh
    │   ├── SignalEngine.mqh
    │   ├── StateStore.mqh
    │   ├── StateStabilizer.mqh
    │   ├── StrategyBase.mqh
    │   ├── MarketState.mqh
    │   ├── RiskManager.mqh
    │   ├── TradeExecutor.mqh
    │   └── StrategyRegistry.mqh
    │
    └── Strategies/
        ├── StrategyLinearTrend.mqh
        ├── StrategyOscillation.mqh
        ├── StrategyBreakout.mqh
        ├── StrategyReversal.mqh
        └── StrategySlopeChannel.mqh
```

---

## 2. 各模块职责

### Experts
- **StrategySelector.mq4**
  - EA 入口（OnInit / OnTick / OnDeinit）
  - 组装核心模块
  - 收集上下文参数
  - 调用策略注册器选择最佳信号并执行

### Core
- **Types.mqh**：公共枚举与结构体（市场状态、策略ID、上下文、运行态、交易信号）
- **Logger.mqh**：统一日志输出
- **SessionClock.mqh**：北京时间换算 + 会话识别
- **SignalEngine.mqh**：指标读取（EMA/RSI/MACD）+ SL/TP构建
- **StateStore.mqh**：运行态持久化（EA_State.txt）
- **StateStabilizer.mqh**：状态防抖
- **StrategyBase.mqh**：策略接口与信号初始化
- **MarketState.mqh**：市场状态识别（趋势/震荡/突破/反转）
- **RiskManager.mqh**：熔断与日内重置
- **TradeExecutor.mqh**：统一下单/平仓执行
- **StrategyRegistry.mqh**：策略注册与优先级选择

### Strategies
- **StrategyLinearTrend**：Session1/3，EMA+RSI+MACD 同向确认
- **StrategyOscillation**：Session4，亚盘区间边界反转
- **StrategyBreakout**：Session2/5/6，突破与动量跟随
- **StrategyReversal**：Session5，假突破反转 + EMA回踩
- **StrategySlopeChannel**：08:00-15:00 斜率平行通道策略（独立SL/TP）

---

## 3. 关键输入参数说明（StrategySelector.mq4）

- `TimeZoneOffset`：服务器时间偏移到北京时间（通常 6）
- `MagicNumber`：订单标识，避免与其他EA冲突
- `LogLevel`：日志级别（0/1/2）

价格差参数均为**图表价格差美元**（非点数）。

- `Session1_3_SL_USD / Session1_3_TP_USD`：Session1/3 止损止盈
- `Session2_SL_USD / Session2_TP_USD`：Session2 止损止盈
- `Session4_MinRange_USD`：Session4 最小区间宽度
- `Session4_EntryBuffer_USD`：Session4 边界触发缓冲
- `Session4_SL_Buffer_USD`：Session4 边界外SL缓冲
- `Session4_TP_USD`：Session4 止盈
- `Session5_FakeBreakout_Trigger_USD`：Session5 假突破触发阈值
- `Session5_ValidBreakout_Trigger_USD`：Session5 真突破触发阈值
- `Session5_SL_USD / Session5_TP_USD`：Session5 止损止盈
- `Session5_EMA_Tolerance_USD`：Session5 EMA回踩容差
- `Session6_MinBody_USD`：Session6 动量实体最小阈值
- `Session6_SL_USD / Session6_TP_USD`：Session6 止损止盈

斜率通道策略（独立参数）：

- `Channel_Lookback_Bars`：斜率回看K线数量
- `Channel_MinSlope`：最小斜率阈值
- `Channel_ParallelTolerance`：上下轨斜率平行容差
- `Channel_MaxWidth_USD`：通道平均宽度上限
- `Channel_EntryTolerance_USD`：靠近通道边界的入场容差
- `Channel_ADX_Min`：ADX最小阈值（趋势强度过滤）
- `Channel_SL_USD / Channel_TP_USD`：斜率通道策略独立止损止盈
- `Channel_MaxTradesPerDay`：斜率通道日内最大交易次数

---

## 3.2 最新执行规则与默认参数（已落地）

- **区间高低点策略（StrategyOscillation）**：仅在 `10:00-15:00` 执行
- **斜率策略（StrategySlopeChannel）**：在 `08:00-15:00` 执行
- 在 `10:00-15:00` 内若触及日内高/低点：
  - 区间高低点策略优先（priority=20）
  - 斜率策略次级（priority=13）

关键默认参数：

- `Session6_MinBody_USD = 4.5`
- `Channel_SL_USD = 4.0`
- `Channel_TP_USD = 4.0`

---

## 3.1 日内K线判定窗口（你关心的“最近几根K线”）

当前版本的信号判定，主要基于**最近 1~2 根已收盘K线**（必要时结合当前K线）：

- `Close[1] / Open[1]`：上一根已收盘K线
- `Close[2] / Open[2]`：上两根已收盘K线
- `High[2] / Low[2]`：用于短期突破结构参考
- `Close[0] / High[0] / Low[0]`：当前形成中的K线（仅部分动量/区间更新场景使用）

对应策略里的典型用法：

- **MarketState**：用 `Close[1]` 对比 `High[2]/Low[2]` 判断短期突破状态
- **StrategyBreakout**：
  - Session2 用 `Open[1]/Close[1]` 判断首根5分钟K方向
  - Session5 用 `Close[1] + Close[2]` 做有效突破确认
  - Session6 用最近两根K（`[1]、[2]`）做动量确认
- **StrategyReversal**：先记录当前假突破，再用 `Close[1]` 回到区间内确认反转

如果你后面要改成“看最近 N 根K线”，建议下一步我给你加两个可调参数：

- `RegimeLookbackBars`（状态识别回看K线数）
- `SignalConfirmBars`（信号确认K线数）

这样可以在参数面板直接调，不需要改代码。

---

## 4. 部署步骤

1. 打开 MT4：`文件 -> 打开数据文件夹`
2. 将本项目中的以下内容复制到 MT4 的 `MQL4` 下（可覆盖同名）：
   - `Experts/StrategySelector.mq4`
   - `Include/Core/`（整目录）
   - `Include/Strategies/`（整目录）
3. 在 MetaEditor 打开 `StrategySelector.mq4`
4. 点击编译

> 已在当前工程环境验证：`StrategySelector` 编译日志为 `0 errors, 0 warnings`。

---

## 5. 运行与回退

- 运行：在 MT4 图表挂载 `StrategySelector` EA
- 回退：直接切回旧版 `XAUUSD_MultiSession_Strategy.mq4`
- 两者可共存（MagicNumber 不冲突即可）

---

## 6. 后续扩展建议

1. 在 `Core/Types.mqh` 中扩展 `StrategyContext` 字段（如 ATR、布林带）
2. 新增 `Include/Strategies/StrategyXXX.mqh` 并实现 `IStrategy`
3. 在 `StrategyRegistry.mqh` 注册新策略并设置优先级
4. 保持 RiskManager 与 TradeExecutor 统一，不在策略内重复风控/执行代码

---

## 7. 两连动量 EA（M5）最新变更说明

文件：`MQL4/Experts/伦敦金两连动量EA_M5.mq4`

已新增“按北京时间日封顶收手”与“日统计日志”能力：

### 7.1 日封顶（按价格差，不按美元盈亏）

- 新参数：`DailyPriceTargetUsd = 50.0`
- 统计口径（仅本EA、当前品种、当前 MagicNumber、已平仓订单）：
  - Buy：`OrderClosePrice - OrderOpenPrice`
  - Sell：`OrderOpenPrice - OrderClosePrice`
- 采用“净累计”方式（亏损会抵消盈利）。
- 当北京时间当日累计净价格差 `>= DailyPriceTargetUsd` 时，当日停止开新仓（不强平已有持仓）。

### 7.2 北京时间自然日统计

- 按北京时间 `00:00:00 ~ 23:59:59` 作为一天。
- 通过服务器时间与 GMT 偏移换算，避免券商服务器时区差异影响统计结果。

### 7.3 日志能力（新增）

- `EnableDailySummaryLog = true`
  - 北京时间跨日时输出“昨日汇总”：
  - 昨日净价格差 + 昨日美元净盈亏（`OrderProfit + OrderSwap + OrderCommission`）
- `EnablePerBarDailyStats = false`
  - 可选每根新K线输出“今日净价格差 + 今日美元净盈亏”（建议仅调试开启）
- 达到日封顶时会输出一次封顶日志（带当前净价格差、美元净盈亏与目标值）。

### 7.4 编译验证

- `compile_two_bar_momentum_m5.log`：`0 errors, 0 warnings`
