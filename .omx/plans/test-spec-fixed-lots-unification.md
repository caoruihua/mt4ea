# Test Spec: fixedLots 参数收口

## 目标

验证主链路里的固定手数已经形成单一真值闭环，并且没有引入编译错误。

## 静态检查

1. 搜索主链路中的 `fixedLots`、`signal.lots`、`0.01`、`OrderSend`。
2. 确认执行层不再硬编码 `double lots = 0.01`。
3. 确认主入口将 `FixedLots` 注入 `g_ctx.fixedLots`。
4. 确认策略层现有 `signal.lots = ctx.fixedLots` 仍成立。

## 行为一致性检查

1. `FixedLots` 为正数时，`OnInit` 不失败。
2. `FixedLots <= 0` 时，初始化阶段应拒绝运行。
3. 执行层下单使用的 `lots` 与传入的 `signal.lots` / `ctx.fixedLots` 一致。
4. 成功下单日志里的 `lots=...` 与实际送单值一致。

## 编译验证

编译以下文件：

- [StrategySelector.mq4](C:\Users\c1985\vsodeproject\sanqing-ea\MQL4\Experts\StrategySelector.mq4)

成功标准：

- `compile-task.log` 末尾包含 `Result: 0 errors, 0 warnings`

## 不做的验证

- 不做回测
- 不改旧 EA，因此不验证旧 EA 的行为
- 不验证动态仓位场景
