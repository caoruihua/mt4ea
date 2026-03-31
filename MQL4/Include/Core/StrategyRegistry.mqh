#ifndef __CORE_STRATEGY_REGISTRY_MQH__
#define __CORE_STRATEGY_REGISTRY_MQH__

#include "StrategyBase.mqh"
#include "Logger.mqh"
#include "../Strategies/StrategyDailyExtremeEngulfing.mqh"
#include "../Strategies/StrategyRangeEdgeReversion.mqh"
#include "../Strategies/StrategySlopeChannel.mqh"
#include "../Strategies/StrategySpikeMomentum.mqh"

class CStrategyRegistry
{
private:
   CLogger *m_logger;

public:
   void Init(CLogger &logger) { m_logger = &logger; }

   int GetRegisteredStrategyCount() { return 8; }

   string GetStrategySummaryByIndex(int index)
   {
      switch(index)
      {
         case 0: return "TrendFollowLong | id=STRATEGY_LINEAR_TREND | priority=10";
         case 1: return "TrendFollowShort | id=STRATEGY_BREAKOUT | priority=10";
         case 2: return "BreakoutRetest | id=STRATEGY_REVERSAL | priority=12";
         case 3: return "SlopeChannel | id=STRATEGY_SLOPE_CHANNEL | priority=13";
         case 4: return "RangeEdgeReversion | id=STRATEGY_RANGE_EDGE_REVERSION | priority=14";
         case 5: return "WickRejection | id=STRATEGY_WICK_REJECTION | priority=13";
         case 6: return "SpikeMomentum | id=STRATEGY_SPIKE_MOMENTUM | priority=15";
         case 7: return "DailyExtremeEngulfing | id=STRATEGY_DAILY_EXTREME_ENGULFING | priority=configurable_default_15";
      }

      return "UnknownStrategy";
   }

   double GetStopBuffer(const StrategyContext &ctx)
   {
      if(ctx.useAtrStopBuffer && ctx.atr14 > 0)
         return MathMax(ctx.atr14 * ctx.slBufferAtrMultiplier, 0.1);
      return ctx.slBufferFixedUsd;
   }

   void BuildRiskRewardSignal(
      StrategyContext &ctx,
      RuntimeState &state,
      int orderType,
      StrategyId strategyId,
      double stopAnchor,
      string comment,
      string reason,
      int priority,
      TradeSignal &signal)
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

private:
   bool HasConsecutiveLowerLows(int window = 5, int threshold = 3)
   {
      if(window < 2 || threshold < 1)
         return false;
      if(Bars <= window + 1)
         return false;

      int count = 0;
      for(int i = 1; i <= window; i++)
      {
         if(i + 1 >= Bars)
            break;
         if(Low[i] < Low[i + 1])
            count++;
      }

      return count >= threshold;
   }

   bool HasConsecutiveHigherHighs(int window = 5, int threshold = 3)
   {
      if(window < 2 || threshold < 1)
         return false;
      if(Bars <= window + 1)
         return false;

      int count = 0;
      for(int i = 1; i <= window; i++)
      {
         if(i + 1 >= Bars)
            break;
         if(High[i] > High[i + 1])
            count++;
      }

      return count >= threshold;
   }

public:

   bool EvaluateBestSignal(StrategyContext &ctx, RuntimeState &state, TradeSignal &best)
   {
      ResetSignal(best);

      TradeSignal candidate;
      ResetSignal(candidate);

      if(ctx.regime == REGIME_TREND_UP)
      {
         // 突破确认上破：优先级更高的顺势追单
         if(state.breakoutSubstate == BREAKOUT_CONFIRMED_UP)
         {
            BuildRiskRewardSignal(ctx, state, OP_BUY, STRATEGY_BREAKOUT, Low[1], "BreakoutConfirmed-Long",
               "Directional breakout confirmed up", 15, candidate);
         }
         else if(!HasConsecutiveLowerLows(5, 3))
         {
            BuildRiskRewardSignal(ctx, state, OP_BUY, STRATEGY_LINEAR_TREND, Low[1], "TrendUp-Long",
               "Regime trend up confirmed", 10, candidate);
         }
      }
      else if(ctx.regime == REGIME_TREND_DOWN)
      {
         // 突破确认下破：优先级更高的顺势追单
         if(state.breakoutSubstate == BREAKOUT_CONFIRMED_DOWN)
         {
            BuildRiskRewardSignal(ctx, state, OP_SELL, STRATEGY_BREAKOUT, High[1], "BreakoutConfirmed-Short",
               "Directional breakout confirmed down", 15, candidate);
         }
         else if(!HasConsecutiveHigherHighs(5, 3))
         {
            BuildRiskRewardSignal(ctx, state, OP_SELL, STRATEGY_BREAKOUT, High[1], "TrendDown-Short",
               "Regime trend down confirmed", 10, candidate);
         }
      }
      else if(ctx.regime == REGIME_BREAKOUT_SETUP_UP && state.breakoutRetestActive && Low[1] <= state.breakoutLevel + GetStopBuffer(ctx))
      {
         BuildRiskRewardSignal(ctx, state, OP_BUY, STRATEGY_REVERSAL, MathMin(Low[1], state.breakoutLevel), "BreakoutRetest-Long", "Breakout retest holds above range", 12, candidate);
      }
      else if(ctx.regime == REGIME_BREAKOUT_SETUP_DOWN && state.breakoutRetestActive && High[1] >= state.breakoutLevel - GetStopBuffer(ctx))
      {
         BuildRiskRewardSignal(ctx, state, OP_SELL, STRATEGY_REVERSAL, MathMax(High[1], state.breakoutLevel), "BreakoutRetest-Short", "Breakout retest holds below range", 12, candidate);
      }

      ConsiderSignal(best, candidate);

      ResetSignal(candidate);
      CStrategySlopeChannel slopeChannel;
      slopeChannel.Init(*m_logger);
      if(slopeChannel.CanTrade(ctx, state))
         slopeChannel.GenerateSignal(ctx, state, candidate);
      ConsiderSignal(best, candidate);

      ResetSignal(candidate);
      CStrategyRangeEdgeReversion rangeEdge;
      if(rangeEdge.CanTrade(ctx, state))
         rangeEdge.GenerateSignal(ctx, state, candidate);
      ConsiderSignal(best, candidate);

      ResetSignal(candidate);
      CStrategyDailyExtremeEngulfing engulfing;
      engulfing.Init(*m_logger);
      if(engulfing.CanTrade(ctx, state))
         engulfing.GenerateSignal(ctx, state, candidate);
      ConsiderSignal(best, candidate);

      ResetSignal(candidate);
      TryBuildWickRejectionSignal(ctx, candidate);
      ConsiderSignal(best, candidate);

      ResetSignal(candidate);
      CStrategySpikeMomentum spikeMomentum;
      spikeMomentum.Init(*m_logger);
      if(spikeMomentum.CanTrade(ctx, state))
         spikeMomentum.GenerateSignal(ctx, state, candidate);
      ConsiderSignal(best, candidate);

      return best.valid;
   }
};

#endif
