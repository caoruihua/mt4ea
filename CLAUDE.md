# CLAUDE.md

本文档为 Claude Code (claude.ai/code) 在本项目中工作提供指导。

## 项目概述

这是一个 MQL4（MetaTrader 4）智能交易系统项目，用于在 M5 时间框架下自动交易 XAUUSD（黄金）。采用最小化双策略核心架构：

- **TrendContinuation（趋势延续）**：基于 EMA 排列的趋势突破
- **Pullback（回撤）**：价格回撤至快速 EMA 并形成反转形态时入场
- **ExpansionFollow（扩张跟随）**：高动量突破蜡烛图（爆发蜡烛）入场

## 构建/编译命令

### 编译 EA

**通过 PowerShell（推荐）：**
```powershell
powershell.exe -NoProfile -Command "& 'C:\Program Files (x86)\MetaTrader 4\metaeditor.exe' '/compile:C:\Users\c1985\vsodeproject\sanqing-ea\MQL4\Experts\StrategySelector.mq4' '/log:C:\Users\c1985\vsodeproject\sanqing-ea\compile-task.log'"
```

**通过 VS Code：**
使用 `.vscode/tasks.json` 中配置的"编译 MQL4"任务

**成功标准：** 检查 `compile-task.log` 确认 `Result: 0 errors, 0 warnings`

### 部署

1. 将 `MQL4/Experts/` 和 `MQL4/Include/` 复制到 MT4 数据目录
2. 在 MetaEditor 中编译 `StrategySelector.mq4`
3. 将 EA 挂载到 XAUUSD M5 图表

## 架构

### 主入口点

`MQL4/Experts/StrategySelector.mq4` - EA 主文件，具备以下功能：
- 每tick构建统一上下文快照（EMA、ATR、点差）
- 同步每日风险状态（盈利锁定、交易次数）
- 每tick运行仓位保护（动态止损/止盈）
- 仅在"新收盘K线"事件时评估新入场
- 使用 `CStrategyRegistry` 从已注册策略中选择最佳信号

### 核心模块（MQL4/Include/Core/）

**Types.mqh** - 各模块共享的核心数据结构：
- `StrategyContext`：当前tick快照（价格、指标、配置）
- `RuntimeState`：持久化状态（每日统计、入场跟踪、追踪状态）
- `TradeSignal`：策略输出的统一信号格式
- `MarketFilterResult`：市场条件评估

**StrategyRegistry.mqh** - 固定优先级的策略调度器：
1. ExpansionFollow（最高优先级）
2. Pullback
3. TrendContinuation（最低优先级）

**TradeExecutor.mqh** - 订单执行与仓位管理：
- `OpenOrder()` / `CloseOrder()` 带重试逻辑
- `CheckStopLossTakeProfit()` - 硬性止损/止盈检查
- `ApplyGlobalProfitLockIfNeeded()` - 两阶段追踪保护：
  - 第一阶段（1.0×ATR 盈利）：移动止损至盈亏平衡+0.1×ATR，扩展止盈至2.5×ATR
  - 第二阶段（1.5×ATR 盈利）：基于 Close[1] 激活追踪止损

**RiskManager.mqh** - 每日风险控制：
- 计算已平仓订单的已实现盈亏
- 当 `dailyClosedProfit >= DailyProfitStopUsd` 时触发 `dailyLocked`
- 新服务器日重置统计

**MarketState.mqh** - 市场条件过滤：
- 低波动门控：ATR 点数和 ATR/点差比率检查
- 趋势有效性：EMA 排列与斜率确认

**StateStore.mqh** - 使用全局变量的持久化层：
- 保存/加载 `RuntimeState` 以便 EA 重启后恢复
- 持久化：dayKey、dailyLocked、dailyClosedProfit、tradesToday、入场跟踪、追踪状态

**SignalEngine.mqh** - 指标计算：
- 构建可配置 EMA 周期 + ATR(14) 的核心快照

**SessionClock.mqh** - 服务器日检测的时间工具

**Logger.mqh** - 分级日志（Error/Warning/Info/Debug）

**StrategyBase.mqh** - 所有策略的抽象基类 `IStrategy`

### 策略模块（MQL4/Include/Strategies/）

每个策略实现 `IStrategy`：
- `Name()`：返回策略标识符字符串
- `CanTrade()`：预检查（波动率、K线时机）
- `GenerateSignal()`：满足条件时返回 `TradeSignal`

**StrategyPullback.mqh：**
- 多头：EMA9 > EMA21，价格处于20根K线通道下半区，回撤至 EMA9 并形成看涨反转（下影线 >= 50% 实体）
- 空头：EMA9 < EMA21，价格处于20根K线通道上半区，回撤至 EMA9 并形成看跌反转（上影线 >= 50% 实体）

**StrategyTrendContinuation.mqh：**
- 多头：EMA9 > EMA21，Close[1] 突破 max(High[2], High[3]) + 0.20×ATR，实体 >= 0.35×ATR
- 空头：EMA9 < EMA21，Close[1] 跌破 min(Low[2], Low[3]) - 0.20×ATR，实体 >= 0.35×ATR

**StrategyExpansionFollow.mqh：**
- 检测相对于 ATR 和中位实体大小的"爆发蜡烛"
- 需要成交量确认、清晰方向（影线比率）、以及突破20根K线通道

## 关键约束

- **品种/时间框架**：仅限 XAUUSD M5
- **仓位限制**：每个 `symbol + magic` 组合最多一个仓位
- **交易手数**：固定 0.01 手（在执行器中强制执行）
- **每日限制**：每天最多 30 笔交易
- **盈利锁定**：每日已实现盈利达到 +$50 后停止新入场
- **入场时机**：每根收盘K线仅一次入场
- **指标默认值**：EMA9/EMA21 配合 ATR(14)
- **止损/止盈默认值**：1.2×ATR 止损，2.0×ATR 止盈（策略可覆盖）

## 开发注意事项

- 所有注释和日志消息使用中文
- 决策基于**上一根收盘K线**（bar[1]），而非正在形成的K线
- EA 使用 MQL4 传统订单池 API（`OrderSend`、`OrderSelect`、`OrderModify`）
- 状态使用 MT4 全局变量持久化以实现重启恢复
- `docs/mt5-rewrite-requirements.md` 文件包含 MT5 移植的详细规范

## Git 工作流

- 提交信息必须使用中文
- 遵循中文描述的常规提交格式

## 测试工作流

- 项目开发完成且所有单元测试通过后，自动删除创建的单元测试用例
- 不在仓库中留下临时测试文件