#ifndef __CORE_STRATEGY_REGISTRY_MQH__
#define __CORE_STRATEGY_REGISTRY_MQH__

/*
 * 文件作用：
 * - 注册并持有所有策略实例
 * - 汇总策略信号并按 priority 选择最佳信号
 */

#include "StrategyBase.mqh"
#include "../Strategies/StrategyLinearTrend.mqh"
#include "../Strategies/StrategyOscillation.mqh"
#include "../Strategies/StrategyBreakout.mqh"
#include "../Strategies/StrategyReversal.mqh"

class CStrategyRegistry
{
private:
   CStrategyLinearTrend m_linearTrend;
   CStrategyOscillation m_oscillation;
   CStrategyBreakout    m_breakout;
   CStrategyReversal    m_reversal;

public:
   bool EvaluateBestSignal(StrategyContext &ctx, RuntimeState &state, TradeSignal &best)
   {
      TradeSignal tmp;
      ResetSignal(best);

      if(m_linearTrend.CanTrade(ctx, state) && m_linearTrend.GenerateSignal(ctx, state, tmp))
      {
         if(!best.valid || tmp.priority > best.priority)
            best = tmp;
      }

      if(m_oscillation.CanTrade(ctx, state) && m_oscillation.GenerateSignal(ctx, state, tmp))
      {
         if(!best.valid || tmp.priority > best.priority)
            best = tmp;
      }

      if(m_breakout.CanTrade(ctx, state) && m_breakout.GenerateSignal(ctx, state, tmp))
      {
         if(!best.valid || tmp.priority > best.priority)
            best = tmp;
      }

      if(m_reversal.CanTrade(ctx, state) && m_reversal.GenerateSignal(ctx, state, tmp))
      {
         if(!best.valid || tmp.priority > best.priority)
            best = tmp;
      }

      return best.valid;
   }
};

#endif
