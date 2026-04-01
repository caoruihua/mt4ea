#ifndef __CORE_STRATEGY_REGISTRY_MQH__
#define __CORE_STRATEGY_REGISTRY_MQH__

/*
 * 文件作用：
 * - 两策略极简调度器
 * - 固定调度顺序：Pullback -> TrendContinuation
 * - 同一根已收盘K线最多只返回一个可执行信号
 */

#include "StrategyBase.mqh"
#include "Logger.mqh"
#include "../Strategies/StrategyPullback.mqh"
#include "../Strategies/StrategyTrendContinuation.mqh"

class CStrategyRegistry
{
private:
   CLogger *m_logger;

public:
   void Init(CLogger &logger) { m_logger = &logger; }

   int GetRegisteredStrategyCount() { return 2; }

   string GetStrategySummaryByIndex(int index)
   {
      switch(index)
      {
         case 0: return "Pullback | id=STRATEGY_PULLBACK | priority=first";
         case 1: return "TrendContinuation | id=STRATEGY_TREND_CONTINUATION | priority=second";
      }
      return "UnknownStrategy";
   }

   // 中文说明：
   // 1) 先评估 Pullback（更保守、质量优先）
   // 2) Pullback 无信号时，再评估 TrendContinuation
   // 3) 同一根已收盘K线只返回一个信号
   bool EvaluateBestSignal(StrategyContext &ctx, RuntimeState &state, TradeSignal &best)
   {
      ResetSignal(best);

      if(state.lastEntryBarTime == ctx.lastClosedBarTime)
      {
         if(m_logger != NULL)
            m_logger.Info("Registry blocked: same closed bar already has an entry");
         return false;
      }

      CStrategyPullback pullback;
      TradeSignal pullbackSignal;
      ResetSignal(pullbackSignal);
      if(pullback.GenerateSignal(ctx, state, pullbackSignal) && pullbackSignal.valid)
      {
         best = pullbackSignal;
         if(m_logger != NULL)
            m_logger.Info(StringFormat("Registry selected: %s", pullbackSignal.comment));
         return true;
      }

      CStrategyTrendContinuation continuation;
      TradeSignal continuationSignal;
      ResetSignal(continuationSignal);
      if(continuation.GenerateSignal(ctx, state, continuationSignal) && continuationSignal.valid)
      {
         best = continuationSignal;
         if(m_logger != NULL)
            m_logger.Info(StringFormat("Registry selected: %s", continuationSignal.comment));
         return true;
      }

      return false;
   }
};

#endif
