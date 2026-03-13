#ifndef __CORE_STRATEGY_BASE_MQH__
#define __CORE_STRATEGY_BASE_MQH__

/*
 * 文件作用：
 * - 定义策略统一接口 IStrategy
 * - 提供 ResetSignal，统一信号初始化
 */

#include "Types.mqh"

class IStrategy
{
public:
   virtual string Name() { return "BaseStrategy"; }
   virtual bool CanTrade(StrategyContext &ctx, RuntimeState &state) { return false; }
   virtual bool GenerateSignal(StrategyContext &ctx, RuntimeState &state, TradeSignal &signal) { return false; }
};

void ResetSignal(TradeSignal &signal)
{
   signal.valid = false;
   signal.strategyId = STRATEGY_NONE;
   signal.orderType = -1;
   signal.lots = 0.0;
   signal.stopLoss = 0.0;
   signal.takeProfit = 0.0;
   signal.comment = "";
   signal.reason = "";
   signal.priority = 0;
}

#endif
