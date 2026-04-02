## 1. 目标与范围

为当前 MT4EA（XAUUSD / M5 / 双策略内核）新增一套**独立的“极端放量单边跟随策略”**（下文简称 `ExpansionFollow`），满足：

- 当出现“单根K线波动远超前几根 + 放量显著”的极端行情时，**在收盘即刻顺势入场**。
- 与现有 `Pullback`、`TrendContinuation` **相互独立且不冲突**。
- 不改变现有执行底座约束：`symbol+magic` 单持仓、同bar限频、固定 0.01 手、日内锁定逻辑。

非目标：

- 不引入马丁/网格/加仓摊平。
- 不放宽现有全局风控上限。

---

## 2. 现有架构约束（已确认）

- 主流程：`MQL4/Experts/StrategySelector.mq4`
  - 新开仓仅在新收盘 bar 评估一次。
  - 已有持仓则不重复开仓。
- 策略调度：`MQL4/Include/Core/StrategyRegistry.mqh`
  - 当前顺序：`Pullback -> TrendContinuation`。
- 市场过滤：`MQL4/Include/Core/MarketState.mqh`
  - 低波动拦截：`ATR points >= 120` 且 `ATR/Spread >= 3.0`。
- 策略接口：`MQL4/Include/Core/StrategyBase.mqh`
  - 新策略需实现 `IStrategy::GenerateSignal()`。

---

## 3. “超常放量”可量化定义（指标层）

在 bar[1]（最新已收盘K线）定义：

- `Range1 = High[1] - Low[1]`
- `Body1 = abs(Close[1] - Open[1])`
- `ATR = ctx.atr14`
- `TV1 = iVolume(Symbol(), PERIOD_M5, 1)`（MT4 tick volume）
- `VMA20 = SMA(TV,20, shift=1)`
- `BodyMed20 = 最近20根已收盘实体中位数`

触发需满足（多空镜像）：

1) **实体异常放大**
- `Body1 / ATR >= 1.25`
- `Body1 / BodyMed20 >= 2.20`
- `Body1 / max(Body[2],Body[3],Body[4]) >= 1.80`

2) **放量确认**
- `TV1 / VMA20 >= 1.90`

3) **方向纯度（防长上下影假动作）**
- `Body1 / Range1 >= 0.65`
- 反向影线占比 `<= 0.25`

4) **结构突破确认**
- 多头：`Close[1] > Highest(High[2..21]) + 0.10*ATR`
- 空头：`Close[1] < Lowest(Low[2..21]) - 0.10*ATR`

5) **防极端透支（方案B中为必选）**
- `Range1 / ATR <= 3.20`

说明：这里“放量”采用 MT4 可用的 tick volume 相对量化，不依赖交易所真实成交量。

---

## 4. 三种可行方案（含取舍）

### 方案A：纯阈值一次触发（最直接）

逻辑：满足上述 1~4 条即入场。

优点：
- 响应最快，最贴合“看到爆发就上”。
- 代码实现简单，便于快速上线。

缺点：
- 在新闻尖刺场景容易被假突破触发。
- 参数对交易时段变化较敏感。

适用：优先抓速度，接受较高回撤。

---

### 方案B：阈值 + 结构质量过滤（推荐）

逻辑：方案A基础上，增加“方向纯度 + 防透支 + 与EMA距离门控”。

附加门控：
- `abs(Close[1]-EMAFast)/ATR >= 0.60`（避免和回踩策略重叠）
- `Range1/ATR <= 3.20`（降低脉冲透支追高）

优点：
- 保留“收盘即入场”的及时性。
- 显著降低冲突与误触发概率。

缺点：
- 比方案A信号少一些。

适用：你的当前诉求（要抓单边，同时不与现有策略打架）。

---

### 方案C：自适应分位阈值（最稳但复杂）

逻辑：固定阈值改成滚动分位（如 Body/ATR > p85，TV/VMA > p80）。

优点：
- 对市场状态变化适应性更强。

缺点：
- 实现与回测复杂度明显升高。
- 参数解释性差，调试成本高。

适用：后续迭代，不建议第一版上。

---

## 5. 推荐方案（B）详细设计

### 5.1 策略身份与独立性

- 新增 `StrategyId`：`STRATEGY_EXPANSION_FOLLOW`。
- 新建文件：`MQL4/Include/Strategies/StrategyExpansionFollow.mqh`。
- 仅通过统一 `TradeSignal` 输出与执行层交互，不复用旧策略内部判断。

### 5.2 入场规则（bar close 立即）

多头（空头镜像）：

1. 全局前置通过：
   - 非日锁定、未超日内次数、当前无持仓、同bar未入场。
2. 市场前置通过（沿用现有）：
   - 非低波动、趋势有效（EMA 快慢关系有效）。
3. ExpansionFollow 触发：
   - `Body1/ATR >= 1.25`
   - `Body1/BodyMed20 >= 2.20`
   - `Body1/max(Body2..4) >= 1.80`
   - `TV1/VMA20 >= 1.90`
   - `Body1/Range1 >= 0.65`
   - `Close[1] > HH20 + 0.10*ATR`
   - `abs(Close[1]-EMAFast)/ATR >= 0.60`
   - `Range1/ATR <= 3.20`

### 5.3 出场与保护

第一版沿用执行层现有规则（避免引入新耦合）：

- 初始 `SL = 1.2*ATR`，`TP = 2.0*ATR`（与现有策略一致）。
- 后续交给 `TradeExecutor` 三段式动态保护。

理由：保持执行一致性，减少策略间“只因执行差异”导致的归因噪声。

---

## 6. 与现有策略“不冲突”机制

### 6.1 调度层隔离

在 `StrategyRegistry` 中显式三策略顺序，建议：

1. `ExpansionFollow`（爆发行情优先）
2. `Pullback`
3. `TrendContinuation`

原因：极端单边窗口持续时间短，优先级应更高。

### 6.2 信号域隔离

通过规则层减少重叠：

- `ExpansionFollow` 强制要求远离 EMA（`>=0.60*ATR`）。
- `Pullback` 天然靠近 EMA 回踩区。
- `TrendContinuation` 条件较宽，保留作次优补位。

### 6.3 冲突处理规则

- 同一bar若多策略均有效，仅取调度优先级最高者。
- 日志明确记录“被哪条策略压制”，便于复盘。

---

## 7. 参数与调优边界

第一版建议只调 3 个主参数：

- `BodyAtrMin`（默认 1.25，范围 1.10~1.50）
- `VolRatioMin`（默认 1.90，范围 1.60~2.40）
- `BreakoutBufferAtr`（默认 0.10，范围 0.05~0.20）

其余参数先固定，避免过拟合。

---

## 8. 可行性评估结论

结论：**可行，且适合在当前架构内低风险增量接入**。

原因：

1. 架构已具备标准策略接口与统一执行通道，新增策略不需改动执行底座。
2. 现有低波动/日锁定/单持仓机制可直接兜底极端行情风险。
3. 通过“策略优先级 + EMA距离门控 + 同bar唯一信号”可实现与现有策略独立不冲突。

风险点：

- 新闻尖刺时段仍可能出现“高量假突破”；已通过方向纯度与防透支门控降低，但不能完全消除。

---

## 9. 实施清单（下一步编码时）

1. `Types.mqh` 增加 `STRATEGY_EXPANSION_FOLLOW`。
2. 新增 `StrategyExpansionFollow.mqh` 并实现 `GenerateSignal()`。
3. `StrategyRegistry.mqh` 注册新策略并调整优先级。
4. 主入口日志补充策略摘要，确保可观测。
5. 回测验证：事件日 + 常态日分组对比胜率、盈亏比、最大回撤、策略冲突率。
