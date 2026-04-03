# PRD: fixedLots 参数收口

## 背景

当前主链路里，手数语义表面上已经沿 `StrategySelector -> StrategyContext -> TradeSignal` 传递，但执行层仍在 [TradeExecutor.mqh](C:\Users\c1985\vsodeproject\sanqing-ea\MQL4\Include\Core\TradeExecutor.mqh) 内部写死 `0.01`。这导致“声明可配、执行写死”，后续修改手数会出现多处同步修改和行为不一致。

## 目标

将当前主链路的固定手数统一收口为单一真值，并形成可验证闭环：

`FixedLots -> g_ctx.fixedLots -> signal.lots -> OrderSend`

## 范围

仅包含当前活跃主链路：

- [StrategySelector.mq4](C:\Users\c1985\vsodeproject\sanqing-ea\MQL4\Experts\StrategySelector.mq4)
- [Types.mqh](C:\Users\c1985\vsodeproject\sanqing-ea\MQL4\Include\Core\Types.mqh)
- [TradeExecutor.mqh](C:\Users\c1985\vsodeproject\sanqing-ea\MQL4\Include\Core\TradeExecutor.mqh)

## 非目标

- 不引入动态仓位模型
- 不删除 `TradeSignal.lots`
- 不重构三类策略的手数赋值方式
- 不修改旧 EA 文件
- 不顺手清理其他配置散落点

## 需求

1. 主入口提供正式的 `FixedLots` 参数源。
2. `StrategyContext.fixedLots` 反映主入口配置值，而不是常量阴影。
3. 执行层真实下单时不再写死 `0.01`。
4. 日志中的 `lots` 与实际下单手数一致。
5. 基本输入校验应拒绝非正数手数。

## 实施约束

- 走最小改动路径
- 保持现有策略信号生成接口不变
- 保持现有编译入口不变
- 只在必要位置调整注释，避免大面积改写

## 验收标准

1. 搜索主链路后，不再存在执行层硬编码 `double lots = 0.01`。
2. [StrategySelector.mq4](C:\Users\c1985\vsodeproject\sanqing-ea\MQL4\Experts\StrategySelector.mq4) 可配置 `FixedLots`。
3. [TradeExecutor.mqh](C:\Users\c1985\vsodeproject\sanqing-ea\MQL4\Include\Core\TradeExecutor.mqh) 使用 `signal.lots` 或回退到 `ctx.fixedLots`。
4. 编译 [StrategySelector.mq4](C:\Users\c1985\vsodeproject\sanqing-ea\MQL4\Experts\StrategySelector.mq4) 通过。

## 风险

- 如果后续某策略开始传递非默认手数，行为将首次真正影响执行层。
- 旧 EA 仍保留自己的手数逻辑，本次不处理。
