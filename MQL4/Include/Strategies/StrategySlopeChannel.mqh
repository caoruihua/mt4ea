#ifndef __STRATEGY_SLOPE_CHANNEL_MQH__
#define __STRATEGY_SLOPE_CHANNEL_MQH__

#include "../Core/StrategyBase.mqh"
#include "../Core/Logger.mqh"

class CStrategySlopeChannel : public IStrategy
{
private:
   CLogger *m_logger;

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

   string StageToString(const int stage)
   {
      switch(stage)
      {
         case PULLBACK_BASE_STAGE_PULLBACK: return "pullback";
         case PULLBACK_BASE_STAGE_BASE:     return "base";
         case PULLBACK_BASE_STAGE_ARMED:    return "armed";
         default:                           return "idle";
      }
   }

   void ResetPullbackState(RuntimeState &state)
   {
      state.channelPullbackStage = PULLBACK_BASE_STAGE_IDLE;
      state.channelSetupTime = 0;
      state.channelPullbackHigh = 0.0;
      state.channelSupportLevel = 0.0;
      state.channelFailedBreakdownCount = 0;
      state.channelBaseBarCount = 0;
      state.channelBaseCloseAverage = 0.0;
      state.channelRecoveryLevel = 0.0;
      state.channelLastBaseBarTime = 0;
   }

   void ResetPullbackState(RuntimeState &state, const string reason, const StrategyContext &ctx)
   {
      if(state.channelPullbackStage != PULLBACK_BASE_STAGE_IDLE)
      {
         Info(StringFormat(
            "SlopeChannel | reset | reason=%s | stage=%s | pullbackHigh=%.5f | support=%.5f | baseAvg=%.5f | recovery=%.5f",
            reason,
            StageToString(state.channelPullbackStage),
            state.channelPullbackHigh,
            state.channelSupportLevel,
            state.channelBaseCloseAverage,
            state.channelRecoveryLevel
         ));
      }
      ResetPullbackState(state);
   }

   double LinearSlopeClose(const int lookback, const int shiftStart)
   {
      double sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumXX = 0.0;
      for(int i = 0; i < lookback; i++)
      {
         double x = i;
         double y = Close[shiftStart + i];
         sumX += x;
         sumY += y;
         sumXY += x * y;
         sumXX += x * x;
      }

      double n = lookback;
      double den = (n * sumXX - sumX * sumX);
      if(MathAbs(den) < 1e-10)
         return 0.0;

      return (n * sumXY - sumX * sumY) / den;
   }

   double LinearSlopeHigh(const int lookback, const int shiftStart)
   {
      double sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumXX = 0.0;
      for(int i = 0; i < lookback; i++)
      {
         double x = i;
         double y = High[shiftStart + i];
         sumX += x;
         sumY += y;
         sumXY += x * y;
         sumXX += x * x;
      }

      double n = lookback;
      double den = (n * sumXX - sumX * sumX);
      if(MathAbs(den) < 1e-10)
         return 0.0;

      return (n * sumXY - sumX * sumY) / den;
   }

   double LinearSlopeLow(const int lookback, const int shiftStart)
   {
      double sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumXX = 0.0;
      for(int i = 0; i < lookback; i++)
      {
         double x = i;
         double y = Low[shiftStart + i];
         sumX += x;
         sumY += y;
         sumXY += x * y;
         sumXX += x * x;
      }

      double n = lookback;
      double den = (n * sumXX - sumX * sumX);
      if(MathAbs(den) < 1e-10)
         return 0.0;

      return (n * sumXY - sumX * sumY) / den;
   }

   double AverageWidth(const int lookback, const int shiftStart)
   {
      double sum = 0.0;
      for(int i = 0; i < lookback; i++)
         sum += (High[shiftStart + i] - Low[shiftStart + i]);
      return sum / lookback;
   }

   double ChannelLowerRef(const int lookback, const int shiftStart)
   {
      double v = Low[shiftStart];
      for(int i = 1; i < lookback; i++)
      {
         if(Low[shiftStart + i] < v)
            v = Low[shiftStart + i];
      }
      return v;
   }

   double ChannelUpperRef(const int lookback, const int shiftStart)
   {
      double v = High[shiftStart];
      for(int i = 1; i < lookback; i++)
      {
         if(High[shiftStart + i] > v)
            v = High[shiftStart + i];
      }
      return v;
   }

   void BuildSLTP(const int orderType, const double slUsd, const double tpUsd, const int digits, double &sl, double &tp)
   {
      if(orderType == OP_BUY)
      {
         sl = NormalizeDouble(Bid - slUsd, digits);
         tp = NormalizeDouble(Ask + tpUsd, digits);
      }
      else
      {
         sl = NormalizeDouble(Ask + slUsd, digits);
         tp = NormalizeDouble(Bid - tpUsd, digits);
      }
   }

   bool IsBullishChannel(const StrategyContext &ctx, const double slopeH, const double slopeL, const double slopeC)
   {
      return (slopeH > ctx.channel_min_slope && slopeL > ctx.channel_min_slope && slopeC > 0.0);
   }

   bool IsBearishChannel(const StrategyContext &ctx, const double slopeH, const double slopeL, const double slopeC)
   {
      return (slopeH < -ctx.channel_min_slope && slopeL < -ctx.channel_min_slope && slopeC < 0.0);
   }

   bool EvaluateBullishStallFilter(
      StrategyContext &ctx,
      RuntimeState &state,
      double &highProgress,
      double &closeBand,
      double &recentRange,
      int &matchedConditions)
   {
      highProgress = 0.0;
      closeBand = 0.0;
      recentRange = 0.0;
      matchedConditions = 0;

      if(!ctx.channel_enable_stall_filter)
         return false;

      int lookback = MathMax(ctx.channel_stall_lookback_bars, 6);
      if(Bars <= lookback + 2)
         return false;

      int recentHalf = MathMax(lookback / 2, 2);
      int olderStart = recentHalf + 1;

      double recentHigh = High[1];
      double olderHigh = High[olderStart];
      double highestClose = Close[1];
      double lowestClose = Close[1];
      double highestHigh = High[1];
      double lowestLow = Low[1];

      for(int i = 1; i <= lookback; i++)
      {
         if(i <= recentHalf && High[i] > recentHigh)
            recentHigh = High[i];

         if(i >= olderStart && High[i] > olderHigh)
            olderHigh = High[i];

         if(Close[i] > highestClose)
            highestClose = Close[i];
         if(Close[i] < lowestClose)
            lowestClose = Close[i];
         if(High[i] > highestHigh)
            highestHigh = High[i];
         if(Low[i] < lowestLow)
            lowestLow = Low[i];
      }

      highProgress = recentHigh - olderHigh;
      closeBand = highestClose - lowestClose;
      recentRange = highestHigh - lowestLow;

      double pullbackSpan = MathMax(state.channelPullbackHigh - state.channelSupportLevel, ctx.channel_pullback_min_drop_usd);
      double compressionThreshold = MathMax(pullbackSpan * ctx.channel_stall_compression_ratio,
                                            ctx.channel_stall_close_band_max_usd * 1.5);

      bool weakProgress = (highProgress <= ctx.channel_stall_max_high_progress_usd);
      bool clusteredCloses = (closeBand <= ctx.channel_stall_close_band_max_usd);
      bool compressedRange = (recentRange <= compressionThreshold);

      if(weakProgress)
         matchedConditions++;
      if(clusteredCloses)
         matchedConditions++;
      if(compressedRange)
         matchedConditions++;

      Info(StringFormat(
         "SlopeChannel | stall_check | lookback=%d | highProgress=%.5f/%.5f | closeBand=%.5f/%.5f | recentRange=%.5f/%.5f | hits=%d/%d",
         lookback,
         highProgress,
         ctx.channel_stall_max_high_progress_usd,
         closeBand,
         ctx.channel_stall_close_band_max_usd,
         recentRange,
         compressionThreshold,
         matchedConditions,
         MathMax(ctx.channel_stall_min_conditions, 1)
      ));

      return (matchedConditions >= MathMax(ctx.channel_stall_min_conditions, 1));
   }

   bool UpdateBullishPullbackState(
      StrategyContext &ctx,
      RuntimeState &state,
      const double upperRef,
      const double lowerRef,
      const double currentBid,
      TradeSignal &signal)
   {
      double minDrop = MathMax(ctx.channel_pullback_min_drop_usd, 0.1);
      double supportTol = MathMax(ctx.channel_support_test_tolerance_usd, 0.1);
      double breakdownTol = MathMax(ctx.channel_breakdown_close_tolerance_usd, 0.1);
      int minTests = MathMax(ctx.channel_base_min_tests, 2);
      int maxBars = MathMax(ctx.channel_base_max_bars, minTests);
      double triggerRatio = ctx.channel_recovery_trigger_ratio;
      if(triggerRatio <= 0.0)
         triggerRatio = 0.7;
      if(triggerRatio > 1.0)
         triggerRatio = 1.0;

      double drop = upperRef - currentBid;
      double supportZoneUpper = lowerRef + supportTol;

      // If a newer swing high forms while an old setup is still being tracked,
      // the old pullback origin is no longer the right reference for the new
      // continuation leg. Reset and allow the setup to rebuild from scratch.
      if(state.channelPullbackStage != PULLBACK_BASE_STAGE_IDLE &&
         upperRef > state.channelPullbackHigh + supportTol &&
         currentBid > state.channelSupportLevel + supportTol)
      {
         ResetPullbackState(state, "new_pullback_origin_superseded_active_setup", ctx);
      }

      if(state.channelPullbackStage == PULLBACK_BASE_STAGE_IDLE && drop >= minDrop)
      {
         state.channelPullbackStage = PULLBACK_BASE_STAGE_PULLBACK;
         state.channelSetupTime = Time[0];
         state.channelPullbackHigh = upperRef;
         state.channelSupportLevel = lowerRef;
         Info(StringFormat(
            "SlopeChannel | stage=pullback | high=%.5f | support=%.5f | drop=%.5f | minDrop=%.5f",
            state.channelPullbackHigh,
            state.channelSupportLevel,
            drop,
            minDrop
         ));
      }

      if(state.channelPullbackStage == PULLBACK_BASE_STAGE_PULLBACK && currentBid <= supportZoneUpper)
      {
         state.channelPullbackStage = PULLBACK_BASE_STAGE_BASE;
         state.channelSupportLevel = lowerRef;
         state.channelSetupTime = Time[0];
         Info(StringFormat(
            "SlopeChannel | stage=base | pullbackHigh=%.5f | support=%.5f | currentBid=%.5f",
            state.channelPullbackHigh,
            state.channelSupportLevel,
            currentBid
         ));
      }

      if(state.channelPullbackStage != PULLBACK_BASE_STAGE_BASE &&
         state.channelPullbackStage != PULLBACK_BASE_STAGE_ARMED)
      {
         return false;
      }

      // Once we start judging the base, accepted closes below support mean the
      // market did break down. That invalidates the setup immediately.
      if(Close[1] < state.channelSupportLevel - breakdownTol)
      {
         ResetPullbackState(state, "accepted_close_below_support", ctx);
         return false;
      }

      int supportTests = 0;
      double closeSum = 0.0;
      datetime newestQualifiedBar = 0;

      // The base is intentionally measured from several recent closed candles.
      // Each qualified candle must probe the support area while still closing
      // back above the accepted-breakdown boundary. This is how the strategy
      // distinguishes "support is being defended" from "support merely got hit".
      for(int i = 1; i <= maxBars; i++)
      {
         bool testedSupport = (Low[i] <= state.channelSupportLevel + supportTol);
         bool closeHeld = (Close[i] >= state.channelSupportLevel - breakdownTol);
         if(testedSupport && closeHeld)
         {
            supportTests++;
            closeSum += Close[i];
            if(newestQualifiedBar == 0 || Time[i] > newestQualifiedBar)
               newestQualifiedBar = Time[i];
         }
      }

      if(state.channelFailedBreakdownCount != supportTests ||
         state.channelBaseBarCount != supportTests)
      {
         Info(StringFormat(
            "SlopeChannel | waiting_base | stage=%s | support=%.5f | tests=%d/%d | latestClose=%.5f | latestLow=%.5f",
            StageToString(state.channelPullbackStage),
            state.channelSupportLevel,
            supportTests,
            minTests,
            Close[1],
            Low[1]
         ));
      }

      state.channelFailedBreakdownCount = supportTests;
      state.channelBaseBarCount = supportTests;
      state.channelLastBaseBarTime = newestQualifiedBar;

      if(supportTests < minTests)
      {
         state.channelBaseCloseAverage = 0.0;
         state.channelRecoveryLevel = 0.0;
         state.channelPullbackStage = PULLBACK_BASE_STAGE_BASE;
         return false;
      }

      double baseAverage = closeSum / supportTests;
      double recoveryLevel = baseAverage + (state.channelPullbackHigh - baseAverage) * triggerRatio;

      state.channelBaseCloseAverage = baseAverage;
      state.channelRecoveryLevel = recoveryLevel;

      if(state.channelPullbackStage != PULLBACK_BASE_STAGE_ARMED)
      {
         Info(StringFormat(
            "SlopeChannel | stage=armed | pullbackHigh=%.5f | support=%.5f | baseAvg=%.5f | recovery=%.5f | tests=%d",
            state.channelPullbackHigh,
            state.channelSupportLevel,
            state.channelBaseCloseAverage,
            state.channelRecoveryLevel,
            state.channelFailedBreakdownCount
         ));
      }

      state.channelPullbackStage = PULLBACK_BASE_STAGE_ARMED;

      if(ctx.ask < state.channelRecoveryLevel)
      {
         Debug(ctx, StringFormat(
            "SlopeChannel | waiting_recovery | ask=%.5f | recovery=%.5f | baseAvg=%.5f | support=%.5f",
            ctx.ask,
            state.channelRecoveryLevel,
            state.channelBaseCloseAverage,
            state.channelSupportLevel
         ));
         return false;
      }

      double stallHighProgress = 0.0;
      double stallCloseBand = 0.0;
      double stallRecentRange = 0.0;
      int stallHits = 0;
      if(EvaluateBullishStallFilter(ctx, state, stallHighProgress, stallCloseBand, stallRecentRange, stallHits))
      {
         Info(StringFormat(
            "SlopeChannel | reject=stall_filter | high=%.5f | support=%.5f | recovery=%.5f | ask=%.5f | highProgress=%.5f | closeBand=%.5f | recentRange=%.5f | hits=%d",
            state.channelPullbackHigh,
            state.channelSupportLevel,
            state.channelRecoveryLevel,
            ctx.ask,
            stallHighProgress,
            stallCloseBand,
            stallRecentRange,
            stallHits
         ));
         ResetPullbackState(state, "stall_filter_veto", ctx);
         return false;
      }

      signal.valid = true;
      signal.strategyId = STRATEGY_SLOPE_CHANNEL;
      signal.orderType = OP_BUY;
      signal.lots = ctx.fixedLots;
      BuildSLTP(OP_BUY, ctx.channel_sl_usd, ctx.channel_tp_usd, ctx.digits, signal.stopLoss, signal.takeProfit);
      signal.comment = "SlopeChannel-Long";
      signal.reason = StringFormat(
         "Pullback base breakout long | high=%.5f | support=%.5f | baseAvg=%.5f | recovery=%.5f | ask=%.5f | tests=%d",
         state.channelPullbackHigh,
         state.channelSupportLevel,
         state.channelBaseCloseAverage,
         state.channelRecoveryLevel,
         ctx.ask,
         state.channelFailedBreakdownCount
      );
      signal.priority = 13;

      Info(StringFormat(
         "SlopeChannel | trigger=long | high=%.5f | support=%.5f | baseAvg=%.5f | recovery=%.5f | ask=%.5f | tests=%d",
         state.channelPullbackHigh,
         state.channelSupportLevel,
         state.channelBaseCloseAverage,
         state.channelRecoveryLevel,
         ctx.ask,
         state.channelFailedBreakdownCount
      ));

      return true;
   }

public:
   void Init(CLogger &logger) { m_logger = &logger; }

   virtual string Name() { return "SlopeChannel"; }

   virtual bool CanTrade(StrategyContext &ctx, RuntimeState &state)
   {
      if(state.channelTrades >= ctx.channel_max_trades_per_day)
         return false;

      // 放宽时段限制：亚盘和欧盘都允许，更敏感
      int h = TimeHour(ctx.beijingTime);
      if(h < 6 || h >= 21)
         return false;

      return true;
   }

   virtual bool GenerateSignal(StrategyContext &ctx, RuntimeState &state, TradeSignal &signal)
   {
      ResetSignal(signal);

      int n = ctx.channel_lookback_bars;
      if(n < 10)
         n = 10;

      if(Bars <= n + MathMax(ctx.channel_base_max_bars, 5) + 2)
         return false;

      double adx = iADX(Symbol(), PERIOD_M5, 14, PRICE_CLOSE, MODE_MAIN, 1);
      if(adx < ctx.channel_adx_min)
      {
         ResetPullbackState(state, "adx_below_threshold", ctx);
         return false;
      }

      double slopeH = LinearSlopeHigh(n, 1);
      double slopeL = LinearSlopeLow(n, 1);
      double slopeC = LinearSlopeClose(n, 1);

      if(MathAbs(slopeH - slopeL) > ctx.channel_parallel_tolerance)
      {
         ResetPullbackState(state, "channel_not_parallel", ctx);
         return false;
      }

      double width = AverageWidth(n, 1);
      if(width > ctx.channel_max_width_usd)
      {
         ResetPullbackState(state, "channel_width_too_large", ctx);
         return false;
      }

      double lowerRef = ChannelLowerRef(n, 1);
      double upperRef = ChannelUpperRef(n, 1);
      bool bullishChannel = IsBullishChannel(ctx, slopeH, slopeL, slopeC);
      bool bearishChannel = IsBearishChannel(ctx, slopeH, slopeL, slopeC);

      if(bullishChannel)
      {
         if(UpdateBullishPullbackState(ctx, state, upperRef, lowerRef, ctx.bid, signal))
            return true;
      }
      else
      {
         ResetPullbackState(state, "bullish_channel_context_lost", ctx);
      }

      // The bearish side keeps the legacy behavior for now. This change is
      // intentionally scoped to the bullish "sharp selloff then recover" case
      // discussed in the OpenSpec change.
      if(bearishChannel)
      {
         double c1 = Close[1];
         if(c1 >= upperRef - ctx.channel_entry_tolerance_usd)
         {
            signal.valid = true;
            signal.strategyId = STRATEGY_SLOPE_CHANNEL;
            signal.orderType = OP_SELL;
            signal.lots = ctx.fixedLots;
            BuildSLTP(OP_SELL, ctx.channel_sl_usd, ctx.channel_tp_usd, ctx.digits, signal.stopLoss, signal.takeProfit);
            signal.comment = "SlopeChannel-Short";
            signal.reason = "Down slope channel rebound short";
            signal.priority = 13;
            return true;
         }
      }

      return false;
   }
};

#endif
