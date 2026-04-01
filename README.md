# MT4EA StrategySelector（极简双策略版）

> 一个基于 MT4（MQL4）的现货黄金（XAUUSD）自动交易项目。  
> 当前版本已从“多策略复杂架构”重构为**双策略极简内核**，仅保留：
>
> - **趋势延续策略（TrendContinuation）**
> - **回踩策略（Pullback）**

---

## 1. 项目定位

本项目目标是：

- 保持主入口和目录结构稳定
- 将策略体系收敛为两套核心策略
- 用更少模块实现更清晰、更可维护的交易闭环

核心交易目标（当前版本约束）：

- 品种：`XAUUSD`
- 周期：`M5`
- 指标框架：`EMA15/30 + ATR14`
- 固定手数：`0.01`
- 同一 `symbol + magic` 最多 `1` 个持仓
- 日内收益达到 `+$50` 后，当天停止新开仓（次日恢复）

---

## 2. 使用前说明（非常重要）

本仓库不是“直接双击运行”类型工程。请先把对应目录复制到 MT4 数据目录，再编译：

1. 将仓库中的 `MQL4/Experts`、`MQL4/Include` 复制到你的 MT4 数据目录
2. 在 MetaEditor 中编译 `MQL4/Experts/StrategySelector.mq4`
3. 编译通过后，将 EA 挂到 XAUUSD M5 图表

---

## 3. 当前目录结构（核心）

```text
MQL4/
├─ Experts/
│  └─ StrategySelector.mq4                 # EA 主入口（极简主流程）
└─ Include/
   ├─ Core/
   │  ├─ Types.mqh                         # 核心类型（上下文/状态/信号）
   │  ├─ SessionClock.mqh                  # 日键/时间工具
   │  ├─ SignalEngine.mqh                  # EMA15/30 + ATR14 指标快照
   │  ├─ MarketState.mqh                   # 市场过滤（趋势有效/低波动）
   │  ├─ RiskManager.mqh                   # 日内收益锁定与跨日重置
   │  ├─ TradeExecutor.mqh                 # 下单/平仓/动态保护执行
   │  ├─ StrategyBase.mqh                  # 策略统一接口
   │  ├─ StrategyRegistry.mqh              # 双策略调度（Pullback 优先）
   │  └─ StateStore.mqh                    # 运行状态持久化
   └─ Strategies/
      ├─ StrategyPullback.mqh              # 回踩策略
      └─ StrategyTrendContinuation.mqh     # 趋势延续策略
```

说明：

- 旧策略文件已从主路径移除，不再参与编译/调度。
- 目前策略目录只保留需求策略两套实现。

---

## 4. 主流程（OnTick）

`StrategySelector.mq4` 当前流程：

1. 构建统一上下文（EMA15/30、ATR14、点差、已收盘 bar 时间）
2. 同步日内风险状态（按服务器日键重置，计算当日已平仓净收益）
3. 每 tick 执行已有持仓保护（动态止盈止损）
4. 仅在“新收盘 bar”评估新开仓
5. 检查日锁定和日内交易上限
6. 市场过滤（低波动拦截 + 趋势有效判定）
7. 策略调度：Pullback 优先，其次 TrendContinuation
8. 成功开仓后更新持久化状态

---

## 5. 策略说明

### 5.1 趋势延续（TrendContinuation）

方向框架：

- 多头：`EMA15 > EMA30`
- 空头：`EMA15 < EMA30`

入场要点（镜像规则）：

- 基于已收盘 K 线
- 突破前两根高/低点达到 ATR 比例阈值
- K 线实体需达到最小 ATR 比例要求

### 5.2 回踩（Pullback）

入场要点（镜像规则）：

- 价格回踩 `EMA15` 区域（容差按 ATR）
- 收盘重新回到趋势方向
- 影线拒绝满足最小比例约束

调度优先级：

- **Pullback > TrendContinuation**

---

## 6. 风险与执行约束

### 6.1 持仓与开仓约束

- 固定手数：`0.01`
- 同一 `symbol + magic` 仅允许一个持仓
- 同一已收盘 bar 最多一次新开仓评估

### 6.2 日内锁定

- 当日净收益（仅统计已平仓订单）达到 `+$50` 后
- `dailyLocked=true`
- 当天禁止新开仓
- 下一服务器日自动解除

### 6.3 低波动拦截

使用 ATR 与点差联合判定：

- ATR points 最小阈值
- ATR/Spread 比值最小阈值

任一不满足则拦截新开仓。

---

## 7. 动态止盈止损（执行层）

执行层采用分阶段保护思路：

1. 先给出初始 SL/TP
2. 浮盈达到阶段阈值后推进保护
3. 保护只朝有利方向移动，不允许回退
4. 修改单时考虑经纪商最小距离与冻结距离

---

## 8. 状态持久化（StateStore）

当前持久化只保留“重启后必须恢复”的关键字段，例如：

- 日键、日锁定、当日已平仓净收益、当日开仓次数
- 入场 bar 时间、入场价、入场 ATR
- 动态保护跟踪状态

目标是：

- 保持跨重启风控一致性
- 避免持久化无关复杂状态

---

## 9. 编译验证（推荐方式）

如果你在 Windows + PowerShell 下，可直接用：

```powershell
powershell.exe -NoProfile -Command "& 'C:\Program Files (x86)\MetaTrader 4\metaeditor.exe' '/compile:C:\Users\c1985\vsodeproject\mt4ea\MQL4\Experts\StrategySelector.mq4' '/log:C:\Users\c1985\vsodeproject\mt4ea\compile-task.log'"
```

成功标准：

- `compile-task.log` 末尾出现：
  - `Result: 0 errors, 0 warnings`

---

## 10. 常见日志说明

日志示例：

```text
Registry blocked: same closed bar already has an entry
```

含义：

- 当前这根已收盘 K 线已经开过单
- 为避免同 bar 重复开仓，注册器拦截本次信号
- 这属于保护逻辑触发，不是程序异常

---

## 11. 开发约定

当前版本采用以下约定：

- 关键逻辑注释统一中文
- 模块职责尽量单一
- 先保证编译通过，再做行为验证

---

## 12. 免责声明

本项目仅用于策略研究与工程实践，不构成任何投资建议。  
实盘前请先在模拟盘充分验证，并结合自身风险承受能力审慎使用。
