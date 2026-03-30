#ifndef __STRATEGY_SPIKE_MOMENTUM_MQH__
#define __STRATEGY_SPIKE_MOMENTUM_MQH__

#include "../Core/StrategyBase.mqh"
#include "../Core/Logger.mqh"

class CStrategySpikeMomentum : public IStrategy
{
private:
   CLogger *m_logger;
   static const int VERBOSE_EVALUATE_LOG_THROTTLE_SECONDS;

   void Info(const string message)
   {
      if(m_logger != NULL)
         m_logger.Info(message);
   }

   void Debug(const StrategyContext &ctx, const string message)
   {
      if(ctx.logLevel >= 2 && m_logger != NULL)
         m_logger.Debug(message);
   }

   bool ShouldLogVerboseEvaluate(const datetime nowServer)
   {
      static datetime s_lastVerboseEvaluateLogTime = 0;
      if(s_lastVerboseEvaluateLogTime > 0 && nowServer - s_lastVerboseEvaluateLogTime < VERBOSE_EVALUATE_LOG_THROTTLE_SECONDS)
         return false;

      s_lastVerboseEvaluateLogTime = nowServer;
      return true;
   }

   bool IsSpikeEventStillActive(const StrategyContext &ctx, const RuntimeState &state, const int direction, const double windowHigh, const double windowLow)
   {
      if(state.spikeLastDirection != direction)
         return false;
      if(state.spikeLastTriggerTime <= 0)
         return false;
      if(TimeCurrent() - state.spikeLastTriggerTime > ctx.spike_window_seconds)
         return false;

      double tolerance = MathMax(Point * 10.0, 0.10);
      if(MathAbs(state.spikeLastAnchorHigh - windowHigh) > tolerance)
         return false;
      if(MathAbs(state.spikeLastAnchorLow - windowLow) > tolerance)
         return false;

      return true;
   }

public:
   void Init(CLogger &logger) { m_logger = &logger; }

   virtual string Name() { return "SpikeMomentum"; }

   virtual bool CanTrade(StrategyContext &ctx, RuntimeState &state)
   {
      return ctx.spike_enable;
   }

   virtual bool GenerateSignal(StrategyContext &ctx, RuntimeState &state, TradeSignal &signal)
   {
      ResetSignal(signal);

      if(!ctx.spike_enable)
         return false;

      int windowSeconds = MathMax(ctx.spike_window_seconds, 60);
      int barsM1 = iBars(ctx.symbol, PERIOD_M1);
      if(barsM1 <= 0)
      {
         Info("SpikeMomentum | skip=no_m1_data");
         return false;
      }

      datetime nowServer = TimeCurrent();
      datetime windowStart = nowServer - windowSeconds;
      double windowHigh = -DBL_MAX;
      double windowLow = DBL_MAX;
      datetime highTime = 0;
      datetime lowTime = 0;
      int barsUsed = 0;

      for(int shift = 0; shift < barsM1; shift++)
      {
         datetime barTime = iTime(ctx.symbol, PERIOD_M1, shift);
         if(barTime <= 0)
            break;
         if(barTime < windowStart && shift > 0)
            break;

         double barHigh = iHigh(ctx.symbol, PERIOD_M1, shift);
         double barLow = iLow(ctx.symbol, PERIOD_M1, shift);

         if(barHigh > windowHigh)
         {
            windowHigh = barHigh;
            highTime = barTime;
         }
         if(barLow < windowLow)
         {
            windowLow = barLow;
            lowTime = barTime;
         }
         barsUsed++;
      }

      if(barsUsed <= 0 || windowHigh <= windowLow)
      {
         Info("SpikeMomentum | skip=invalid_window");
         return false;
      }

      double impulse = windowHigh - windowLow;
      double currentBuyPrice = ctx.ask;
      double currentSellPrice = ctx.bid;
      double buyPullback = windowHigh - currentBuyPrice;
      double sellPullback = currentSellPrice - windowLow;
      double buyPullbackRatio = impulse > 0 ? buyPullback / impulse : 999.0;
      double sellPullbackRatio = impulse > 0 ? sellPullback / impulse : 999.0;
      bool highAfterLow = (highTime >= lowTime);
      bool lowAfterHigh = (lowTime >= highTime);

      if(ctx.spike_log_verbose && ShouldLogVerboseEvaluate(nowServer))
      {
         Info(StringFormat(
            "SpikeMomentum | evaluate | server=%s | beijing=%s | session=%d | regime=%d | bars=%d | start=%s | end=%s | high=%.2f@%s | low=%.2f@%s | ask=%.2f | bid=%.2f | impulse=%.2f | trigger=%.2f | buyPullback=%.2f | buyRatio=%.4f | sellPullback=%.2f | sellRatio=%.4f",
            TimeToStr(nowServer, TIME_DATE|TIME_SECONDS),
            TimeToStr(ctx.beijingTime, TIME_DATE|TIME_SECONDS),
            ctx.sessionId,
            ctx.regime,
            barsUsed,
            TimeToStr(windowStart, TIME_DATE|TIME_SECONDS),
            TimeToStr(nowServer, TIME_DATE|TIME_SECONDS),
            windowHigh,
            TimeToStr(highTime, TIME_DATE|TIME_SECONDS),
            windowLow,
            TimeToStr(lowTime, TIME_DATE|TIME_SECONDS),
            currentBuyPrice,
            currentSellPrice,
            impulse,
            ctx.spike_trigger_usd,
            buyPullback,
            buyPullbackRatio,
            sellPullback,
            sellPullbackRatio
         ));
      }

      if(impulse < ctx.spike_trigger_usd)
      {
         Debug(ctx, StringFormat("SpikeMomentum | reject=trigger_not_met | impulse=%.2f | required=%.2f", impulse, ctx.spike_trigger_usd));
         return false;
      }

      int direction = 0;
      int orderType = -1;
      double pullback = 0.0;
      double pullbackRatio = 0.0;
      double entry = 0.0;
      string comment = "";
      string reason = "";

      if(highAfterLow && buyPullback >= 0 && buyPullbackRatio <= ctx.spike_max_pullback_ratio)
      {
         direction = 1;
         orderType = OP_BUY;
         pullback = buyPullback;
         pullbackRatio = buyPullbackRatio;
         entry = currentBuyPrice;
         comment = "SpikeMomentum-Buy";
         reason = StringFormat("5m spike buy | impulse=%.2f | pullback=%.2f | ratio=%.4f", impulse, pullback, pullbackRatio);
      }
      else if(lowAfterHigh && sellPullback >= 0 && sellPullbackRatio <= ctx.spike_max_pullback_ratio)
      {
         direction = -1;
         orderType = OP_SELL;
         pullback = sellPullback;
         pullbackRatio = sellPullbackRatio;
         entry = currentSellPrice;
         comment = "SpikeMomentum-Sell";
         reason = StringFormat("5m spike sell | impulse=%.2f | pullback=%.2f | ratio=%.4f", impulse, pullback, pullbackRatio);
      }
      else
      {
         string rejectReason = "structure_invalid";
         if(highAfterLow && buyPullbackRatio > ctx.spike_max_pullback_ratio)
            rejectReason = StringFormat("buy_pullback_exceeded | ratio=%.4f | max=%.4f", buyPullbackRatio, ctx.spike_max_pullback_ratio);
         else if(lowAfterHigh && sellPullbackRatio > ctx.spike_max_pullback_ratio)
            rejectReason = StringFormat("sell_pullback_exceeded | ratio=%.4f | max=%.4f", sellPullbackRatio, ctx.spike_max_pullback_ratio);
         else if(!highAfterLow && !lowAfterHigh)
            rejectReason = "extreme_order_invalid";

         Info("SpikeMomentum | reject=" + rejectReason);
         return false;
      }

      if(IsSpikeEventStillActive(ctx, state, direction, windowHigh, windowLow))
      {
         Info(StringFormat("SpikeMomentum | reject=duplicate_event | direction=%d | lastTrigger=%s", direction, TimeToStr(state.spikeLastTriggerTime, TIME_DATE|TIME_SECONDS)));
         return false;
      }

      signal.valid = true;
      signal.strategyId = STRATEGY_SPIKE_MOMENTUM;
      signal.orderType = orderType;
      signal.lots = ctx.fixedLots;
      signal.stopLoss = (orderType == OP_BUY)
         ? NormalizeDouble(entry - ctx.spike_sl_usd, ctx.digits)
         : NormalizeDouble(entry + ctx.spike_sl_usd, ctx.digits);
      signal.takeProfit = (orderType == OP_BUY)
         ? NormalizeDouble(entry + ctx.spike_tp_usd, ctx.digits)
         : NormalizeDouble(entry - ctx.spike_tp_usd, ctx.digits);
      signal.comment = comment;
      signal.reason = reason;
      signal.priority = 15;

      state.spikeLastDirection = direction;
      state.spikeLastTriggerTime = nowServer;
      state.spikeLastAnchorHigh = windowHigh;
      state.spikeLastAnchorLow = windowLow;

      Info(StringFormat(
         "SpikeMomentum | signal=ready | direction=%s | impulse=%.2f | pullback=%.2f | ratio=%.4f | entry=%.2f | sl=%.2f | tp=%.2f | priority=%d",
         (orderType == OP_BUY ? "BUY" : "SELL"),
         impulse,
         pullback,
         pullbackRatio,
         entry,
         signal.stopLoss,
         signal.takeProfit,
         signal.priority
      ));

      return true;
   }
};

const int CStrategySpikeMomentum::VERBOSE_EVALUATE_LOG_THROTTLE_SECONDS = 20;

#endif
