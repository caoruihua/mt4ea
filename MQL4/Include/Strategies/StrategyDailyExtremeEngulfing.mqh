#ifndef __STRATEGY_DAILY_EXTREME_ENGULFING_MQH__
#define __STRATEGY_DAILY_EXTREME_ENGULFING_MQH__

#include "../Core/StrategyBase.mqh"
#include "../Core/Logger.mqh"

class CStrategyDailyExtremeEngulfing : public IStrategy
{
private:
   CLogger *m_logger;

   datetime DateOnly(const datetime t)
   {
      return StringToTime(TimeToStr(t, TIME_DATE));
   }

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

   bool UpdateDayExtremes(const StrategyContext &ctx, RuntimeState &state)
   {
      datetime currentDate = DateOnly(ctx.beijingTime);
      if(state.dayExtremeDate != currentDate || state.dayHigh <= 0.0 || state.dayLow <= 0.0)
      {
         state.dayExtremeDate = currentDate;
         state.dayHigh = High[0];
         state.dayLow = Low[0];
      }
      else
      {
         if(High[0] > state.dayHigh)
            state.dayHigh = High[0];
         if(Low[0] < state.dayLow)
            state.dayLow = Low[0];
      }

      return state.dayHigh > 0.0 && state.dayLow > 0.0 && state.dayHigh >= state.dayLow;
   }

   double BodyHigh(const int shift) { return MathMax(Open[shift], Close[shift]); }
   double BodyLow(const int shift) { return MathMin(Open[shift], Close[shift]); }
   double BodySize(const int shift) { return MathAbs(Close[shift] - Open[shift]); }

   bool IsBullishEngulfing(const StrategyContext &ctx)
   {
      if(Close[2] >= Open[2] || Close[1] <= Open[1])
         return false;
      if(BodySize(1) < ctx.engulfing_min_body_usd)
         return false;
      return BodyHigh(1) >= BodyHigh(2) && BodyLow(1) <= BodyLow(2);
   }

   bool IsBearishEngulfing(const StrategyContext &ctx)
   {
      if(Close[2] <= Open[2] || Close[1] >= Open[1])
         return false;
      if(BodySize(1) < ctx.engulfing_min_body_usd)
         return false;
      return BodyHigh(1) >= BodyHigh(2) && BodyLow(1) <= BodyLow(2);
   }

   void LogReject(const StrategyContext &ctx, const RuntimeState &state, const string reason, const string side)
   {
      Debug(ctx, StringFormat(
         "DailyExtremeEngulfing | reject=%s | side=%s | beijing=%s | dayHigh=%.5f | dayLow=%.5f | body1=%.2f | high1=%.5f | low1=%.5f | high2=%.5f | low2=%.5f",
         reason,
         side,
         TimeToStr(ctx.beijingTime, TIME_DATE|TIME_SECONDS),
         state.dayHigh,
         state.dayLow,
         BodySize(1),
         High[1],
         Low[1],
         High[2],
         Low[2]
      ));
   }

public:
   void Init(CLogger &logger) { m_logger = &logger; }

   virtual string Name() { return "DailyExtremeEngulfing"; }

   virtual bool CanTrade(StrategyContext &ctx, RuntimeState &state)
   {
      if(!ctx.engulfing_enable)
         return false;
      if(Bars <= 3)
         return false;
      return UpdateDayExtremes(ctx, state);
   }

   virtual bool GenerateSignal(StrategyContext &ctx, RuntimeState &state, TradeSignal &signal)
   {
      ResetSignal(signal);

      if(!CanTrade(ctx, state))
         return false;

      double proximity = MathMax(ctx.engulfing_extreme_proximity_usd, 0.1);
      double stopBuffer = MathMax(ctx.engulfing_stop_buffer_usd, 0.1);
      double maxStop = MathMax(ctx.engulfing_max_stop_loss_usd, stopBuffer);
      double bodySize = BodySize(1);

      bool bullish = IsBullishEngulfing(ctx);
      bool bearish = IsBearishEngulfing(ctx);
      if(!bullish && !bearish)
      {
         LogReject(ctx, state, "pattern_not_engulfing", "NONE");
         return false;
      }

      if(bullish)
      {
         double patternLow = MathMin(Low[1], Low[2]);
         double proximityLow = patternLow - state.dayLow;
         if(proximityLow > proximity)
         {
            LogReject(ctx, state, "not_near_day_low", "BUY");
            return false;
         }

         double sl = NormalizeDouble(MathMin(state.dayLow, patternLow) - stopBuffer, ctx.digits);
         double risk = ctx.ask - sl;
         if(risk <= 0.0)
         {
            LogReject(ctx, state, "invalid_long_risk", "BUY");
            return false;
         }
         if(risk > maxStop)
         {
            LogReject(ctx, state, "long_stop_distance_exceeded", "BUY");
            return false;
         }

         signal.valid = true;
         signal.strategyId = STRATEGY_DAILY_EXTREME_ENGULFING;
         signal.orderType = OP_BUY;
         signal.lots = ctx.fixedLots;
         signal.stopLoss = sl;
         signal.takeProfit = 0.0;
         signal.comment = "DailyExtremeEngulfing-Long";
         signal.reason = StringFormat("Bullish engulfing near day low | body=%.2f | proximity=%.2f", bodySize, proximityLow);
         signal.priority = ctx.engulfing_priority;

         Info(StringFormat(
            "DailyExtremeEngulfing | trigger=BUY | beijing=%s | dayHigh=%.5f | dayLow=%.5f | body=%.2f | patternLow=%.5f | proximity=%.2f | entry=%.5f | sl=%.5f",
            TimeToStr(ctx.beijingTime, TIME_DATE|TIME_SECONDS),
            state.dayHigh,
            state.dayLow,
            bodySize,
            patternLow,
            proximityLow,
            ctx.ask,
            sl
         ));
         return true;
      }

      double patternHigh = MathMax(High[1], High[2]);
      double proximityHigh = state.dayHigh - patternHigh;
      if(proximityHigh > proximity)
      {
         LogReject(ctx, state, "not_near_day_high", "SELL");
         return false;
      }

      double sl = NormalizeDouble(MathMax(state.dayHigh, patternHigh) + stopBuffer, ctx.digits);
      double risk = sl - ctx.bid;
      if(risk <= 0.0)
      {
         LogReject(ctx, state, "invalid_short_risk", "SELL");
         return false;
      }
      if(risk > maxStop)
      {
         LogReject(ctx, state, "short_stop_distance_exceeded", "SELL");
         return false;
      }

      signal.valid = true;
      signal.strategyId = STRATEGY_DAILY_EXTREME_ENGULFING;
      signal.orderType = OP_SELL;
      signal.lots = ctx.fixedLots;
      signal.stopLoss = sl;
      signal.takeProfit = 0.0;
      signal.comment = "DailyExtremeEngulfing-Short";
      signal.reason = StringFormat("Bearish engulfing near day high | body=%.2f | proximity=%.2f", bodySize, proximityHigh);
      signal.priority = ctx.engulfing_priority;

      Info(StringFormat(
         "DailyExtremeEngulfing | trigger=SELL | beijing=%s | dayHigh=%.5f | dayLow=%.5f | body=%.2f | patternHigh=%.5f | proximity=%.2f | entry=%.5f | sl=%.5f",
         TimeToStr(ctx.beijingTime, TIME_DATE|TIME_SECONDS),
         state.dayHigh,
         state.dayLow,
         bodySize,
         patternHigh,
         proximityHigh,
         ctx.bid,
         sl
      ));
      return true;
   }
};

#endif
