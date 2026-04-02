#ifndef __STRATEGY_EXPANSION_FOLLOW_MQH__
#define __STRATEGY_EXPANSION_FOLLOW_MQH__

/*
 * 文件作用：
 * - 极端放量单边跟随策略（ExpansionFollow）
 * - 在已收盘K线上识别"实体异常放大 + 放量 + 结构突破"，立即顺势入场
 * - 初始止损：信号K线60%回撤位（做多：Low+Range*0.6；做空：High-Range*0.6）
 * - 初始止盈：2.0 * ATR
 * - 方向判定：不看大趋势，按当前爆发K线方向（阳线做多/阴线做空）
 */

#include "../Core/StrategyBase.mqh"

class CStrategyExpansionFollow : public IStrategy
{
private:
   bool IsLowVol(const StrategyContext &ctx)
   {
      double atrPoints = (Point > 0.0) ? (ctx.atr14 / Point) : 0.0;
      double spreadPoints = MathMax(ctx.spreadPoints, 0.0);
      double ratio = (spreadPoints > 0.0) ? (atrPoints / spreadPoints) : 9999.0;
      return (atrPoints < ctx.lowVolAtrPointsFloor || ratio < ctx.lowVolAtrSpreadRatioFloor);
   }

   double BodyAt(int shift)
   {
      return MathAbs(Close[shift] - Open[shift]);
   }

   double RangeAt(int shift)
   {
      return (High[shift] - Low[shift]);
   }

   bool CalcBodyMedian20(double &medianBody)
   {
      double bodies[];
      ArrayResize(bodies, 20);
      for(int i = 0; i < 20; i++)
      {
         int shift = i + 2;
         bodies[i] = BodyAt(shift);
      }
      ArraySort(bodies, WHOLE_ARRAY, 0, MODE_ASCEND);
      medianBody = (bodies[9] + bodies[10]) / 2.0;
      return (medianBody > 0.0);
   }

   bool CalcPrev3BodyMax(double &maxBody)
   {
      double b2 = BodyAt(2);
      double b3 = BodyAt(3);
      double b4 = BodyAt(4);
      maxBody = MathMax(b2, MathMax(b3, b4));
      return (maxBody > 0.0);
   }

   bool CalcVolumeRatio20(double &volRatio)
   {
      long tv1 = iVolume(Symbol(), PERIOD_M5, 1);
      if(tv1 <= 0) return false;
      double sum = 0.0;
      for(int i = 2; i <= 21; i++)
         sum += (double)iVolume(Symbol(), PERIOD_M5, i);
      double vma20 = sum / 20.0;
      if(vma20 <= 0.0) return false;
      volRatio = tv1 / vma20;
      return true;
   }

public:
   virtual string Name() { return "ExpansionFollow"; }

   bool EvaluateExpansionGate(
      double body,
      double atr,
      double bodyMed20,
      double prevBodyMax,
      double volRatio,
      double bodyRangeRatio,
      double rangeAtrRatio)
   {
      if(atr <= 0 || bodyMed20 <= 0 || prevBodyMax <= 0) return false;
      if(body / atr < 1.25) return false;
      if(body / bodyMed20 < 2.20) return false;
      if(body / prevBodyMax < 1.80) return false;
      if(volRatio < 1.90) return false;
      if(bodyRangeRatio < 0.65) return false;
      if(rangeAtrRatio > 3.20) return false;
      return true;
   }

   virtual bool CanTrade(StrategyContext &ctx, RuntimeState &state)
   {
      if(state.lastEntryBarTime == ctx.lastClosedBarTime) return false;
      if(IsLowVol(ctx)) return false;
      return true;
   }

   virtual bool GenerateSignal(StrategyContext &ctx, RuntimeState &state, TradeSignal &signal)
   {
      ResetSignal(signal);

      if(!CanTrade(ctx, state)) return false;
      if(Bars < 30 || ctx.atr14 <= 0)
      {
         signal.reason = "blocked: insufficient bars or invalid atr";
         return false;
      }

      double atr = ctx.atr14;
      double body1 = BodyAt(1);
      double range1 = RangeAt(1);
      if(body1 <= 0.0 || range1 <= 0.0)
      {
         signal.reason = "blocked: invalid body/range";
         return false;
      }

      double bodyMed20 = 0.0;
      if(!CalcBodyMedian20(bodyMed20))
      {
         signal.reason = "blocked: invalid body median";
         return false;
      }

      double prevBodyMax = 0.0;
      if(!CalcPrev3BodyMax(prevBodyMax))
      {
         signal.reason = "blocked: invalid prev body max";
         return false;
      }

      double volRatio = 0.0;
      if(!CalcVolumeRatio20(volRatio))
      {
         signal.reason = "blocked: invalid volume ratio";
         return false;
      }

      double bodyRangeRatio = body1 / range1;
      double rangeAtrRatio = range1 / atr;

      bool commonOk = EvaluateExpansionGate(body1, atr, bodyMed20, prevBodyMax, volRatio, bodyRangeRatio, rangeAtrRatio);
      if(!commonOk)
      {
         signal.reason = "blocked: expansion gate not met";
         return false;
      }

      double high20 = High[iHighest(NULL, 0, MODE_HIGH, 20, 2)];
      double low20 = Low[iLowest(NULL, 0, MODE_LOW, 20, 2)];

      double open1 = Open[1];
      double close1 = Close[1];
      double lowerWick = MathMin(open1, close1) - Low[1];
      double upperWick = High[1] - MathMax(open1, close1);

      bool bullishBar = (close1 > open1);
      bool bearishBar = (close1 < open1);
      bool bullishOppWickOk = ((lowerWick / range1) <= 0.25);
      bool bearishOppWickOk = ((upperWick / range1) <= 0.25);

      // 做多：阳线 + 突破上沿
      if(bullishBar && bullishOppWickOk && close1 > (high20 + atr * 0.10))
      {
         signal.valid = true;
         signal.strategyId = STRATEGY_EXPANSION_FOLLOW;
         signal.orderType = OP_BUY;
         signal.lots = ctx.fixedLots;
         
         // 止损：信号K线60%回撤位 = Low + Range*0.6
         signal.stopLoss = NormalizeDouble(Low[1] + range1 * 0.6, ctx.digits);
         // 止盈：2.0 * ATR
         signal.takeProfit = NormalizeDouble(ctx.ask + atr * 2.0, ctx.digits);
         
         signal.comment = "ExpansionFollow-Long";
         signal.reason = "bullish abnormal expansion with volume surge breakout";
         return true;
      }

      // 做空：阴线 + 突破下沿
      if(bearishBar && bearishOppWickOk && close1 < (low20 - atr * 0.10))
      {
         signal.valid = true;
         signal.strategyId = STRATEGY_EXPANSION_FOLLOW;
         signal.orderType = OP_SELL;
         signal.lots = ctx.fixedLots;
         
         // 止损：信号K线60%回撤位 = High - Range*0.6
         signal.stopLoss = NormalizeDouble(High[1] - range1 * 0.6, ctx.digits);
         // 止盈：2.0 * ATR
         signal.takeProfit = NormalizeDouble(ctx.bid - atr * 2.0, ctx.digits);
         
         signal.comment = "ExpansionFollow-Short";
         signal.reason = "bearish abnormal expansion with volume surge breakout";
         return true;
      }

      signal.reason = "blocked: direction or breakout condition not met";
      return false;
   }
};

#endif
