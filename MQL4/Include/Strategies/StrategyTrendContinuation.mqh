#ifndef __STRATEGY_TREND_CONTINUATION_MQH__
#define __STRATEGY_TREND_CONTINUATION_MQH__

#include "../Core/StrategyBase.mqh"

class CStrategyTrendContinuation : public IStrategy
{
private:
   int RecentLevelLookback(const StrategyContext &ctx) const { return MathMax(ctx.secondLegSwingLookbackBars, 5); }
   int HourlyLookbackBars() const { return 12; }

   bool IsLowVol(const StrategyContext &ctx)
   {
      double atrPoints = (Point > 0.0) ? (ctx.atr14 / Point) : 0.0;
      double spreadPoints = MathMax(ctx.spreadPoints, 0.0);
      double ratio = (spreadPoints > 0.0) ? (atrPoints / spreadPoints) : 9999.0;
      return (atrPoints < ctx.lowVolAtrPointsFloor || ratio < ctx.lowVolAtrSpreadRatioFloor);
   }

   void BuildInitialSLTP(int orderType, const StrategyContext &ctx, double atr, double &sl, double &tp)
   {
      double slDist = atr * 1.2;
      double tpDist = atr * 2.0;
      if(orderType == OP_BUY)
      {
         sl = NormalizeDouble(ctx.bid - slDist, ctx.digits);
         tp = NormalizeDouble(ctx.ask + tpDist, ctx.digits);
      }
      else
      {
         sl = NormalizeDouble(ctx.ask + slDist, ctx.digits);
         tp = NormalizeDouble(ctx.bid - tpDist, ctx.digits);
      }
   }

   void PromoteNearestAbove(double referencePrice, double candidate, double &nearest) const
   {
      if(candidate <= referencePrice)
         return;
      if(nearest <= 0.0 || candidate < nearest)
         nearest = candidate;
   }

   void PromoteNearestBelow(double referencePrice, double candidate, double &nearest) const
   {
      if(candidate >= referencePrice)
         return;
      if(nearest <= 0.0 || candidate > nearest)
         nearest = candidate;
   }

   double FindCurrentDayHighBeforeSignal() const
   {
      datetime dayStart = iTime(NULL, PERIOD_D1, 0);
      int dayShift = iBarShift(NULL, 0, dayStart, false);
      int count = dayShift - 1;
      if(count < 1)
         return 0.0;

      int highestIndex = iHighest(NULL, 0, MODE_HIGH, count, 2);
      return (highestIndex >= 0) ? High[highestIndex] : 0.0;
   }

   double FindCurrentDayLowBeforeSignal() const
   {
      datetime dayStart = iTime(NULL, PERIOD_D1, 0);
      int dayShift = iBarShift(NULL, 0, dayStart, false);
      int count = dayShift - 1;
      if(count < 1)
         return 0.0;

      int lowestIndex = iLowest(NULL, 0, MODE_LOW, count, 2);
      return (lowestIndex >= 0) ? Low[lowestIndex] : 0.0;
   }

   double FindNearestResistanceAbove(const StrategyContext &ctx, double referencePrice) const
   {
      double nearest = 0.0;

      int hourlyIndex = iHighest(NULL, 0, MODE_HIGH, HourlyLookbackBars(), 2);
      if(hourlyIndex >= 0)
         PromoteNearestAbove(referencePrice, High[hourlyIndex], nearest);

      double dayHigh = FindCurrentDayHighBeforeSignal();
      PromoteNearestAbove(referencePrice, dayHigh, nearest);

      int swingCount = MathMin(Bars - 2, RecentLevelLookback(ctx));
      if(swingCount > 0)
      {
         int swingIndex = iHighest(NULL, 0, MODE_HIGH, swingCount, 2);
         if(swingIndex >= 0)
            PromoteNearestAbove(referencePrice, High[swingIndex], nearest);
      }

      return nearest;
   }

   double FindNearestSupportBelow(const StrategyContext &ctx, double referencePrice) const
   {
      double nearest = 0.0;

      int hourlyIndex = iLowest(NULL, 0, MODE_LOW, HourlyLookbackBars(), 2);
      if(hourlyIndex >= 0)
         PromoteNearestBelow(referencePrice, Low[hourlyIndex], nearest);

      double dayLow = FindCurrentDayLowBeforeSignal();
      PromoteNearestBelow(referencePrice, dayLow, nearest);

      int swingCount = MathMin(Bars - 2, RecentLevelLookback(ctx));
      if(swingCount > 0)
      {
         int swingIndex = iLowest(NULL, 0, MODE_LOW, swingCount, 2);
         if(swingIndex >= 0)
            PromoteNearestBelow(referencePrice, Low[swingIndex], nearest);
      }

      return nearest;
   }

   bool HasLoosePause(const StrategyContext &ctx, int pauseExtremeIndex, bool bullish, double &baseRange, int &pauseBars) const
   {
      baseRange = 0.0;
      pauseBars = 0;

      if(pauseExtremeIndex < 2)
         return false;

      int count = pauseExtremeIndex - 1;
      if(count < 1)
         return false;

      int highestIndex = iHighest(NULL, 0, MODE_HIGH, count, 2);
      int lowestIndex = iLowest(NULL, 0, MODE_LOW, count, 2);
      if(highestIndex < 0 || lowestIndex < 0)
         return false;

      baseRange = High[highestIndex] - Low[lowestIndex];
      pauseBars = count;

      bool enoughBars = (pauseBars >= ctx.secondLegBaseMinBars);
      bool compactRange = (baseRange <= ctx.atr14 * ctx.secondLegBaseMaxRangeAtr);
      bool slowdownBar = ((High[2] - Low[2]) <= ctx.atr14 * 0.60);
      bool directionalPause = bullish ? (Close[2] >= Open[2]) : (Close[2] <= Open[2]);

      return (enoughBars || compactRange || (slowdownBar && directionalPause));
   }

   bool EvaluateBullishAntiChase(const StrategyContext &ctx, string &reason) const
   {
      if(!ctx.enableSecondLegLongFilter)
         return true;

      double referencePrice = Close[1];
      double nearestResistance = FindNearestResistanceAbove(ctx, referencePrice);
      if(nearestResistance > referencePrice)
      {
         double space = nearestResistance - referencePrice;
         double requiredSpace = ctx.atr14 * ctx.secondLegMinSpaceAtr;
         if(space < requiredSpace)
         {
            reason = StringFormat("blocked: anti-chase long space %.2f < %.2f (resistance %.2f)", space, requiredSpace, nearestResistance);
            return false;
         }
      }

      int searchCount = MathMin(Bars - 3, RecentLevelLookback(ctx));
      if(searchCount < (ctx.secondLegMinPullbackBars + 2))
      {
         reason = "blocked: anti-chase long insufficient bars";
         return false;
      }

      int impulseHighIndex = iHighest(NULL, 0, MODE_HIGH, searchCount, 2);
      if(impulseHighIndex < 3)
      {
         reason = "blocked: anti-chase long waiting for impulse high";
         return false;
      }

      int pullbackSearchCount = impulseHighIndex - 2;
      if(pullbackSearchCount < 1)
      {
         reason = "blocked: anti-chase long waiting for pullback";
         return false;
      }

      int pullbackLowIndex = iLowest(NULL, 0, MODE_LOW, pullbackSearchCount, 2);
      if(pullbackLowIndex < 2 || pullbackLowIndex >= impulseHighIndex)
      {
         reason = "blocked: anti-chase long reset on invalid pullback ordering";
         return false;
      }

      double impulseHigh = High[impulseHighIndex];
      double pullbackLow = Low[pullbackLowIndex];
      double pullbackDepth = impulseHigh - pullbackLow;
      double minDepth = ctx.atr14 * ctx.secondLegPullbackMinAtr;
      if(pullbackDepth < minDepth)
      {
         reason = StringFormat("blocked: anti-chase long pullback %.2f < %.2f", pullbackDepth, minDepth);
         return false;
      }

      int pullbackBars = impulseHighIndex - pullbackLowIndex;
      if(pullbackBars < ctx.secondLegMinPullbackBars)
      {
         reason = StringFormat("blocked: anti-chase long pullback bars %d < %d", pullbackBars, ctx.secondLegMinPullbackBars);
         return false;
      }

      double reclaimLevel = pullbackLow + pullbackDepth * ctx.secondLegReclaimRatio;
      if(Close[1] < reclaimLevel)
      {
         reason = StringFormat("blocked: anti-chase long reclaim %.2f < %.2f", Close[1], reclaimLevel);
         return false;
      }

      double baseRange = 0.0;
      int pauseBars = 0;
      if(!HasLoosePause(ctx, pullbackLowIndex, true, baseRange, pauseBars))
      {
         reason = StringFormat("blocked: anti-chase long no loose pause (bars=%d range=%.2f)", pauseBars, baseRange);
         return false;
      }

      reason = StringFormat(
         "anti-chase long passed: resistance=%.2f reclaim=%.2f pullback=%.2f pauseBars=%d baseRange=%.2f",
         nearestResistance,
         reclaimLevel,
         pullbackDepth,
         pauseBars,
         baseRange);
      return true;
   }

   bool EvaluateBearishAntiChase(const StrategyContext &ctx, string &reason) const
   {
      if(!ctx.enableSecondLegShortFilter)
         return true;

      double referencePrice = Close[1];
      double nearestSupport = FindNearestSupportBelow(ctx, referencePrice);
      if(nearestSupport > 0.0 && nearestSupport < referencePrice)
      {
         double space = referencePrice - nearestSupport;
         double requiredSpace = ctx.atr14 * ctx.secondLegMinSpaceAtr;
         if(space < requiredSpace)
         {
            reason = StringFormat("blocked: anti-chase short space %.2f < %.2f (support %.2f)", space, requiredSpace, nearestSupport);
            return false;
         }
      }

      int searchCount = MathMin(Bars - 3, RecentLevelLookback(ctx));
      if(searchCount < (ctx.secondLegMinPullbackBars + 2))
      {
         reason = "blocked: anti-chase short insufficient bars";
         return false;
      }

      int impulseLowIndex = iLowest(NULL, 0, MODE_LOW, searchCount, 2);
      if(impulseLowIndex < 3)
      {
         reason = "blocked: anti-chase short waiting for impulse low";
         return false;
      }

      int reboundSearchCount = impulseLowIndex - 2;
      if(reboundSearchCount < 1)
      {
         reason = "blocked: anti-chase short waiting for rebound";
         return false;
      }

      int reboundHighIndex = iHighest(NULL, 0, MODE_HIGH, reboundSearchCount, 2);
      if(reboundHighIndex < 2 || reboundHighIndex >= impulseLowIndex)
      {
         reason = "blocked: anti-chase short reset on invalid rebound ordering";
         return false;
      }

      double impulseLow = Low[impulseLowIndex];
      double reboundHigh = High[reboundHighIndex];
      double reboundDepth = reboundHigh - impulseLow;
      double minDepth = ctx.atr14 * ctx.secondLegPullbackMinAtr;
      if(reboundDepth < minDepth)
      {
         reason = StringFormat("blocked: anti-chase short rebound %.2f < %.2f", reboundDepth, minDepth);
         return false;
      }

      int reboundBars = impulseLowIndex - reboundHighIndex;
      if(reboundBars < ctx.secondLegMinPullbackBars)
      {
         reason = StringFormat("blocked: anti-chase short rebound bars %d < %d", reboundBars, ctx.secondLegMinPullbackBars);
         return false;
      }

      double reclaimLevel = reboundHigh - reboundDepth * ctx.secondLegReclaimRatio;
      if(Close[1] > reclaimLevel)
      {
         reason = StringFormat("blocked: anti-chase short reclaim %.2f > %.2f", Close[1], reclaimLevel);
         return false;
      }

      double baseRange = 0.0;
      int pauseBars = 0;
      if(!HasLoosePause(ctx, reboundHighIndex, false, baseRange, pauseBars))
      {
         reason = StringFormat("blocked: anti-chase short no loose pause (bars=%d range=%.2f)", pauseBars, baseRange);
         return false;
      }

      reason = StringFormat(
         "anti-chase short passed: support=%.2f reclaim=%.2f rebound=%.2f pauseBars=%d baseRange=%.2f",
         nearestSupport,
         reclaimLevel,
         reboundDepth,
         pauseBars,
         baseRange);
      return true;
   }

public:
   virtual string Name() { return "TrendContinuation"; }

   virtual bool CanTrade(StrategyContext &ctx, RuntimeState &state)
   {
      if(state.lastEntryBarTime == ctx.lastClosedBarTime)
         return false;
      if(IsLowVol(ctx))
         return false;
      return true;
   }

   virtual bool GenerateSignal(StrategyContext &ctx, RuntimeState &state, TradeSignal &signal)
   {
      ResetSignal(signal);

      if(!CanTrade(ctx, state))
         return false;

      if(Bars < 25)
      {
         signal.reason = "blocked: insufficient bars";
         return false;
      }

      double atr = ctx.atr14;
      if(atr <= 0)
      {
         signal.reason = "blocked: invalid atr";
         return false;
      }

      bool trendUp = (ctx.emaFast > ctx.emaSlow);
      bool trendDown = (ctx.emaFast < ctx.emaSlow);

      double body = MathAbs(Close[1] - Open[1]);
      double high2 = MathMax(High[2], High[3]);
      double low2 = MathMin(Low[2], Low[3]);

      if(trendUp && Close[1] >= (high2 + atr * 0.20) && body >= atr * 0.35)
      {
         string longReason = "";
         if(!EvaluateBullishAntiChase(ctx, longReason))
         {
            signal.reason = longReason;
            return false;
         }

         signal.valid = true;
         signal.strategyId = STRATEGY_TREND_CONTINUATION;
         signal.orderType = OP_BUY;
         signal.lots = ctx.fixedLots;
         BuildInitialSLTP(OP_BUY, ctx, atr, signal.stopLoss, signal.takeProfit);
         signal.comment = "TrendContinuation-Long";
         signal.reason = longReason;
         return true;
      }

      if(trendDown && Close[1] <= (low2 - atr * 0.20) && body >= atr * 0.35)
      {
         string shortReason = "";
         if(!EvaluateBearishAntiChase(ctx, shortReason))
         {
            signal.reason = shortReason;
            return false;
         }

         signal.valid = true;
         signal.strategyId = STRATEGY_TREND_CONTINUATION;
         signal.orderType = OP_SELL;
         signal.lots = ctx.fixedLots;
         BuildInitialSLTP(OP_SELL, ctx, atr, signal.stopLoss, signal.takeProfit);
         signal.comment = "TrendContinuation-Short";
         signal.reason = shortReason;
         return true;
      }

      signal.reason = "blocked: continuation condition not met";
      return false;
   }
};

#endif
