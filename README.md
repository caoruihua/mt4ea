# sanqing-ea

一个基于 MT4 / MQL4 的 XAUUSD 自动交易项目，主入口为 `StrategySelector.mq4`。当前版本使用统一上下文、集中参数管理和中央选股式策略调度，核心目标是让趋势延续与回踩两类入场更可控、更容易回测。

## 当前结构

- `MQL4/Experts/StrategySelector.mq4`
  EA 主入口，负责参数输入、上下文构建、风控检查、策略调度和下单执行。
- `MQL4/Include/Core/Types.mqh`
  共享类型定义，包含 `StrategyContext`、`RuntimeState`、`TradeSignal` 等核心结构。
- `MQL4/Include/Core/StrategyRegistry.mqh`
  中央视图层，按既定顺序评估策略并输出最终可执行信号。
- `MQL4/Include/Strategies/StrategyPullback.mqh`
  回踩类入场逻辑。
- `MQL4/Include/Strategies/StrategyTrendContinuation.mqh`
  趋势延续逻辑，当前已集成第二波防追高/防追空过滤。

## 当前策略顺序

按中央注册表顺序评估：

1. `ExpansionFollow`
2. `Pullback`
3. `TrendContinuation`
4. `PinbarReversal`

一根已收盘 K 线最多只允许一次新开仓决策。

## 第二波防追过滤

本次更新把第二波 continuation 过滤直接集成到 `TrendContinuation`，用于解决“第一波对了，第二波买在天花板/卖在地板附近，被正常回撤扫掉”的问题。

### 多头过滤

多头 continuation 除了原有 breakout 条件外，还要求：

- 到最近关键阻力至少保留 `1 ATR` 空间
- 已出现可识别回踩
- 回踩幅度至少达到 `SecondLegPullbackMinAtr`
- 回踩后价格至少收回该回踩区间的 `50%`
- 第二波前出现宽松整理/停顿，而不是直接垂直追高

### 空头过滤

空头使用镜像规则：

- 到最近关键支撑至少保留 `1 ATR` 空间
- 已出现可识别反抽
- 反抽幅度至少达到 `SecondLegPullbackMinAtr`
- 反抽后价格至少回吐该反抽区间的 `50%`
- 第二波前出现宽松整理/停顿，而不是直接垂直追空

### 关键位来源

当前实现使用以下近似关键位：

- 最近一小时高点 / 低点
- 当日高点 / 低点
- 近期 swing 高点 / 低点

系统会优先取离当前价格最近的有效阻力或支撑进行空间过滤。

## 主入口参数

第二波防追过滤参数统一放在主入口文件 `MQL4/Experts/StrategySelector.mq4`，策略文件只读取上下文，不单独暴露外部输入。

当前相关参数：

- `EnableSecondLegLongFilter`
- `EnableSecondLegShortFilter`
- `SecondLegMinSpaceAtr`
- `SecondLegPullbackMinAtr`
- `SecondLegMinPullbackBars`
- `SecondLegBaseMinBars`
- `SecondLegBaseMaxRangeAtr`
- `SecondLegReclaimRatio`

默认值思路：

- 空间过滤先用 `1 ATR`
- 回踩/反抽确认先用 `50%` 收回/回吐
- 结构管理使用宽松版，不要求标准旗形

## 风控与执行约束

- 固定手数由 `FixedLots` 控制
- 同一 `symbol + magic` 只允许一单持仓
- 达到日内盈亏阈值后停止新开仓
- 已有持仓时仍允许保护性检查和服务器平仓检测
- 下单、平仓与保护逻辑统一走 `TradeExecutor`

## 编译

在 MetaEditor 中直接编译：

- `MQL4/Experts/StrategySelector.mq4`

也可以在 Windows PowerShell 中执行：

```powershell
$args = @(
  '/compile:C:\Users\c1985\vsodeproject\sanqing-ea\MQL4\Experts\StrategySelector.mq4',
  '/log:C:\Users\c1985\vsodeproject\sanqing-ea\metaeditor_compile.log'
)
$p = Start-Process -FilePath 'C:\Program Files (x86)\MetaTrader 4\metaeditor.exe' -ArgumentList $args -Wait -PassThru
exit $p.ExitCode
```

成功标准：

- `metaeditor_compile.log` 中出现 `Result: 0 errors, 0 warnings`

## 本次更新摘要

这次更新主要完成了以下内容：

- 第二波多头防追高过滤
- 第二波空头镜像防追空过滤
- 主入口集中参数管理
- continuation 过滤日志纳入中央注册表输出
- OpenSpec 变更 `add-second-leg-anti-chase-filter` 已完成

## 说明

本项目仅用于策略研究、工程实现与回测验证，不构成任何投资建议。上线前请先做历史回测、样本外验证和模拟盘测试。
