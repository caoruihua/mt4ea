#ifndef __CORE_STRATEGY_REGISTRY_MQH__
#define __CORE_STRATEGY_REGISTRY_MQH__

/*
 * 文件作用：
 * - 注册并持有所有策略实例
 * - 汇总策略信号并按 priority 选择最佳信号
 */

#include "StrategyBase.mqh"
#include "../Strategies/StrategyRangeEdgeReversion.mqh"

class CStrategyRegistry
{
public:
   int GetRegisteredStrategyCount() { return 5; }

   string GetStrategySummaryByIndex(int index)
   {
      switch(index)
      {
         case 0: return "TrendFollowLong | id=STRATEGY_LINEAR_TREND | priority=10";
         case 1: return "TrendFollowShort | id=STRATEGY_BREAKOUT | priority=10";
         case 2: return "BreakoutRetest | id=STRATEGY_REVERSAL | priority=12";
         case 3: return "RangeEdgeReversion | id=STRATEGY_RANGE_EDGE_REVERSION | priority=14";
         case 4: return "WickRejection | id=STRATEGY_WICK_REJECTION | priority=13";
      }

      return "UnknownStrategy";
   }

   double GetStopBuffer(const StrategyContext &ctx)
   {
      if(ctx.useAtrStopBuffer && ctx.atr14 > 0)
         return MathMax(ctx.atr14 * ctx.slBufferAtrMultiplier, 0.1);
      return ctx.slBufferFixedUsd;
   }

   void BuildRiskRewardSignal(StrategyContext &ctx, RuntimeState &state, int orderType, StrategyId strategyId, double stopAnchor, string comment, string reason, int priority, TradeSignal &signal)
   {
      double buffer = GetStopBuffer(ctx);
      double entry = (orderType == OP_BUY) ? ctx.ask : ctx.bid;
      double stopLoss = 0.0;
      double risk = 0.0;
      double takeProfit = 0.0;

      if(orderType == OP_BUY)
      {
         stopLoss = NormalizeDouble(stopAnchor - buffer, ctx.digits);
         risk = entry - stopLoss;
         takeProfit = NormalizeDouble(entry + risk * ctx.riskRewardRatio, ctx.digits);
      }
      else
      {
         stopLoss = NormalizeDouble(stopAnchor + buffer, ctx.digits);
         risk = stopLoss - entry;
         takeProfit = NormalizeDouble(entry - risk * ctx.riskRewardRatio, ctx.digits);
      }

      if(risk <= 0)
         return;

      signal.valid = true;
      signal.strategyId = strategyId;
      signal.orderType = orderType;
      signal.lots = ctx.fixedLots;
      signal.stopLoss = stopLoss;
      signal.takeProfit = takeProfit;
      signal.comment = comment;
      signal.reason = reason;
      signal.priority = priority;
   }

   void ConsiderSignal(TradeSignal &best, const TradeSignal &candidate)
   {
      if(!candidate.valid)
         return;

      if(!best.valid || candidate.priority > best.priority)
         best = candidate;
   }

   bool IsLongUpperWick(const int shift, const StrategyContext &ctx)
   {
      double high = High[shift];
      double low = Low[shift];
      double open = Open[shift];
      double close = Close[shift];
      double range = high - low;
      if(range <= 0)
         return false;

      double bodyHigh = MathMax(open, close);
      double upperWick = high - bodyHigh;
      if(upperWick < ctx.wick_min_length_usd)
         return false;

      double upperRatio = upperWick / range;
      return upperRatio >= ctx.wick_min_upper_ratio;
   }

   bool IsLongLowerWick(const int shift, const StrategyContext &ctx)
   {
      double high = High[shift];
      double low = Low[shift];
      double open = Open[shift];
      double close = Close[shift];
      double range = high - low;
      if(range <= 0)
         return false;

      double bodyLow = MathMin(open, close);
      double lowerWick = bodyLow - low;
      if(lowerWick < ctx.wick_min_length_usd)
         return false;

      double lowerRatio = lowerWick / range;
      return lowerRatio >= ctx.wick_min_lower_ratio;
   }

   bool TryBuildWickRejectionSignal(StrategyContext &ctx, TradeSignal &signal)
   {
      ResetSignal(signal);

      int n = MathMax(ctx.wick_window_bars, 3);
      int minCount = MathMax(ctx.wick_min_count, 1);
      if(Bars <= n + 2)
         return false;

      double windowHigh = High[1];
      double windowLow = Low[1];
      for(int i = 2; i <= n; i++)
      {
         if(High[i] > windowHigh) windowHigh = High[i];
         if(Low[i] < windowLow) windowLow = Low[i];
      }

      int upperRejectCount = 0;
      int lowerRejectCount = 0;
      for(int j = 1; j <= n; j++)
      {
         bool nearTop = (High[j] >= windowHigh - ctx.wick_break_tolerance_usd);
         bool noBreakUp = (Close[j] <= windowHigh - ctx.wick_break_tolerance_usd);
         if(nearTop && noBreakUp && IsLongUpperWick(j, ctx))
            upperRejectCount++;

         bool nearBottom = (Low[j] <= windowLow + ctx.wick_break_tolerance_usd);
         bool noBreakDown = (Close[j] >= windowLow + ctx.wick_break_tolerance_usd);
         if(nearBottom && noBreakDown && IsLongLowerWick(j, ctx))
            lowerRejectCount++;
      }

      if(upperRejectCount >= minCount)
      {
         signal.valid = true;
         signal.strategyId = STRATEGY_WICK_REJECTION;
         signal.orderType = OP_SELL;
         signal.lots = ctx.fixedLots;
         signal.stopLoss = NormalizeDouble(ctx.bid + ctx.wick_sl_usd, ctx.digits);
         signal.takeProfit = NormalizeDouble(ctx.bid - ctx.wick_tp_usd, ctx.digits);
         signal.comment = "WickRejection-Short";
         signal.reason = StringFormat("Upper wick rejection count=%d/%d", upperRejectCount, n);
         signal.priority = 13;
         return true;
      }

      if(lowerRejectCount >= minCount)
      {
         signal.valid = true;
         signal.strategyId = STRATEGY_WICK_REJECTION;
         signal.orderType = OP_BUY;
         signal.lots = ctx.fixedLots;
         signal.stopLoss = NormalizeDouble(ctx.ask - ctx.wick_sl_usd, ctx.digits);
         signal.takeProfit = NormalizeDouble(ctx.ask + ctx.wick_tp_usd, ctx.digits);
         signal.comment = "WickRejection-Long";
         signal.reason = StringFormat("Lower wick rejection count=%d/%d", lowerRejectCount, n);
         signal.priority = 13;
         return true;
      }

      return false;
   }

   bool EvaluateBestSignal(StrategyContext &ctx, RuntimeState &state, TradeSignal &best)
   {
      ResetSignal(best);

      TradeSignal candidate;
      ResetSignal(candidate);

      // 按策略自有条件评估：去掉“RANGE 全局禁开仓”硬编码
      if(ctx.regime == REGIME_TREND_UP)
         BuildRiskRewardSignal(ctx, state, OP_BUY, STRATEGY_LINEAR_TREND, Low[1], "TrendUp-Long", "Regime trend up confirmed", 10, candidate);
      else if(ctx.regime == REGIME_TREND_DOWN)
         BuildRiskRewardSignal(ctx, state, OP_SELL, STRATEGY_BREAKOUT, High[1], "TrendDown-Short", "Regime trend down confirmed", 10, candidate);
      else if(ctx.regime == REGIME_BREAKOUT_SETUP_UP && state.breakoutRetestActive && Low[1] <= state.breakoutLevel + GetStopBuffer(ctx))
         BuildRiskRewardSignal(ctx, state, OP_BUY, STRATEGY_REVERSAL, MathMin(Low[1], state.breakoutLevel), "BreakoutRetest-Long", "Breakout retest holds above range", 12, candidate);
      else if(ctx.regime == REGIME_BREAKOUT_SETUP_DOWN && state.breakoutRetestActive && High[1] >= state.breakoutLevel - GetStopBuffer(ctx))
         BuildRiskRewardSignal(ctx, state, OP_SELL, STRATEGY_REVERSAL, MathMax(High[1], state.breakoutLevel), "BreakoutRetest-Short", "Breakout retest holds below range", 12, candidate);

      ConsiderSignal(best, candidate);

      // 额外叠加“影线拒绝突破”独立候选信号（不覆盖原逻辑，只参与优先级竞争）
      ResetSignal(candidate);
      CStrategyRangeEdgeReversion rangeEdge;
      if(rangeEdge.CanTrade(ctx, state))
         rangeEdge.GenerateSignal(ctx, state, candidate);
      ConsiderSignal(best, candidate);

      // 额外叠加“影线拒绝突破”独立候选信号（不覆盖原逻辑，只参与优先级竞争）
      ResetSignal(candidate);
      TryBuildWickRejectionSignal(ctx, candidate);
      ConsiderSignal(best, candidate);

      return best.valid;
   }
};

#endif
