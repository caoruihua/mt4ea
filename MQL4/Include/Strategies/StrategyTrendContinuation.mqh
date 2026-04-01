#ifndef __STRATEGY_TREND_CONTINUATION_MQH__
#define __STRATEGY_TREND_CONTINUATION_MQH__

/*
 * 文件作用：
 * - 趋势延续策略（快/慢 EMA + ATR14）
 * - 仅在趋势有效且非低波动时，基于已收盘K线给出突破延续信号
 */

#include "../Core/StrategyBase.mqh"

class CStrategyTrendContinuation : public IStrategy
{
private:
   bool IsLowVol(const StrategyContext &ctx)
   {
      double atrPoints = (Point > 0.0) ? (ctx.atr14 / Point) : 0.0;
      double spreadPoints = MathMax(ctx.spreadPoints, 0.0);
      double ratio = (spreadPoints > 0.0) ? (atrPoints / spreadPoints) : 9999.0;
      return (atrPoints < 120.0 || ratio < 3.0);
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

public:
   virtual string Name() { return "TrendContinuation"; }

   virtual bool CanTrade(StrategyContext &ctx, RuntimeState &state)
   {
      // 中文说明：同一根K线只允许一次入场，且已有持仓时不重复入场
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

      if(Bars < 5)
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

      bool trendUp = (ctx.ema9 > ctx.ema21);
      bool trendDown = (ctx.ema9 < ctx.ema21);

      double body = MathAbs(Close[1] - Open[1]);
      double high2 = MathMax(High[2], High[3]);
      double low2 = MathMin(Low[2], Low[3]);

      // 中文说明：多头延续条件
      // 1) 快 EMA > 慢 EMA（默认 9/21）
      // 2) 已收盘K线向上突破前2根高点至少 0.20*ATR
      // 3) 实体 >= 0.35*ATR
      if(trendUp && Close[1] >= (high2 + atr * 0.20) && body >= atr * 0.35)
      {
         signal.valid = true;
         signal.strategyId = STRATEGY_TREND_CONTINUATION;
         signal.orderType = OP_BUY;
         signal.lots = ctx.fixedLots;
         BuildInitialSLTP(OP_BUY, ctx, atr, signal.stopLoss, signal.takeProfit);
         signal.comment = "TrendContinuation-Long";
         signal.reason = "trend-up breakout continuation";
         return true;
      }

      // 中文说明：空头延续条件（与多头镜像）
      if(trendDown && Close[1] <= (low2 - atr * 0.20) && body >= atr * 0.35)
      {
         signal.valid = true;
         signal.strategyId = STRATEGY_TREND_CONTINUATION;
         signal.orderType = OP_SELL;
         signal.lots = ctx.fixedLots;
         BuildInitialSLTP(OP_SELL, ctx, atr, signal.stopLoss, signal.takeProfit);
         signal.comment = "TrendContinuation-Short";
         signal.reason = "trend-down breakout continuation";
         return true;
      }

      signal.reason = "blocked: continuation condition not met";
      return false;
   }
};

#endif
