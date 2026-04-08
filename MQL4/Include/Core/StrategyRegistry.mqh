#ifndef __CORE_STRATEGY_REGISTRY_MQH__
#define __CORE_STRATEGY_REGISTRY_MQH__

/*
 * 文件作用：
 * - 四策略调度器
 * - 固定调度顺序：ExpansionFollow -> Pullback -> TrendContinuation -> PinbarReversal
 * - 同一根已收盘K线最多只返回一个可执行信号
 */

#include "StrategyBase.mqh"
#include "Logger.mqh"
#include "../Strategies/StrategyExpansionFollow.mqh"
#include "../Strategies/StrategyPullback.mqh"
#include "../Strategies/StrategyTrendContinuation.mqh"
#include "../Strategies/StrategyPinbarReversal.mqh"

class CStrategyRegistry
{
private:
   CLogger *m_logger;

public:
   void Init(CLogger &logger) { m_logger = &logger; }

   int GetRegisteredStrategyCount() { return 4; }

   string GetStrategySummaryByIndex(int index)
   {
      switch(index)
      {
         case 0: return "ExpansionFollow | id=STRATEGY_EXPANSION_FOLLOW | priority=first";
         case 1: return "Pullback | id=STRATEGY_PULLBACK | priority=second";
         case 2: return "TrendContinuation | id=STRATEGY_TREND_CONTINUATION | priority=third";
         case 3: return "PinbarReversal | id=STRATEGY_PINBAR_REVERSAL | priority=last";
      }
      return "UnknownStrategy";
   }

   // 中文说明：
   // 1) 先评估 ExpansionFollow（爆发行情优先）
   // 2) ExpansionFollow 无信号时，再评估 Pullback
   // 3) Pullback 无信号时，再评估 TrendContinuation
   // 4) TrendContinuation 无信号时，最后评估 PinbarReversal（形态信号兜底）
   // 5) 同一根已收盘K线只返回一个信号
   bool EvaluateBestSignal(StrategyContext &ctx, RuntimeState &state, TradeSignal &best)
   {
      ResetSignal(best);

      if(state.lastEntryBarTime == ctx.lastClosedBarTime)
      {
         if(m_logger != NULL)
            m_logger.Info("Registry blocked: same closed bar already has an entry");
         return false;
      }

      CStrategyExpansionFollow expansion;
      TradeSignal expansionSignal;
      ResetSignal(expansionSignal);
      if(expansion.GenerateSignal(ctx, state, expansionSignal) && expansionSignal.valid)
      {
         best = expansionSignal;
         if(m_logger != NULL)
            m_logger.Info(StringFormat("Registry selected: %s", expansionSignal.comment));
         return true;
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
            m_logger.Info(StringFormat("Registry selected: %s | %s", continuationSignal.comment, continuationSignal.reason));
         return true;
      }
      if(m_logger != NULL && StringLen(continuationSignal.reason) > 0 &&
         StringFind(continuationSignal.reason, "anti-chase") >= 0)
      {
         m_logger.Info(StringFormat("Registry blocked TrendContinuation: %s", continuationSignal.reason));
      }

      CStrategyPinbarReversal pinbar;
      TradeSignal pinbarSignal;
      ResetSignal(pinbarSignal);
      if(pinbar.GenerateSignal(ctx, state, pinbarSignal) && pinbarSignal.valid)
      {
         best = pinbarSignal;
         if(m_logger != NULL)
            m_logger.Info(StringFormat("Registry selected: %s", pinbarSignal.comment));
         return true;
      }

      return false;
   }
};

#endif
