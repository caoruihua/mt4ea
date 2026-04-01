#ifndef __STRATEGY_PULLBACK_MQH__
#define __STRATEGY_PULLBACK_MQH__

/*
 * 文件作用：
 * - 回踩策略（EMA15 回踩 + 拒绝K线）
 * - 仅在趋势有效且非低波动时，基于已收盘K线给出回踩入场信号
 */

#include "../Core/StrategyBase.mqh"

class CStrategyPullback : public IStrategy
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

   bool IsBullishPullbackReject(const StrategyContext &ctx)
   {
      double atr = ctx.atr14;
      if(atr <= 0)
         return false;

      double low1 = Low[1];
      double close1 = Close[1];
      double open1 = Open[1];
      double body = MathAbs(close1 - open1);
      if(body <= 0)
         return false;

      double zoneTolerance = atr * 0.15;
      bool touchZone = (MathAbs(low1 - ctx.ema15) <= zoneTolerance || low1 <= ctx.ema15 + zoneTolerance);
      bool closeBack = (close1 > ctx.ema15 && close1 > open1);
      double lowerWick = MathMin(open1, close1) - low1;
      bool wickReject = (lowerWick >= body * 0.50);
      return (touchZone && closeBack && wickReject);
   }

   bool IsBearishPullbackReject(const StrategyContext &ctx)
   {
      double atr = ctx.atr14;
      if(atr <= 0)
         return false;

      double high1 = High[1];
      double close1 = Close[1];
      double open1 = Open[1];
      double body = MathAbs(close1 - open1);
      if(body <= 0)
         return false;

      double zoneTolerance = atr * 0.15;
      bool touchZone = (MathAbs(high1 - ctx.ema15) <= zoneTolerance || high1 >= ctx.ema15 - zoneTolerance);
      bool closeBack = (close1 < ctx.ema15 && close1 < open1);
      double upperWick = high1 - MathMax(open1, close1);
      bool wickReject = (upperWick >= body * 0.50);
      return (touchZone && closeBack && wickReject);
   }

public:
   virtual string Name() { return "Pullback"; }

   virtual bool CanTrade(StrategyContext &ctx, RuntimeState &state)
   {
      // 中文说明：同一收盘K线只允许一次新信号，避免同bar重复开仓。
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
      if(Bars < 5 || ctx.atr14 <= 0)
      {
         signal.reason = "blocked: invalid snapshot";
         return false;
      }

      bool trendUp = (ctx.ema15 > ctx.ema30);
      bool trendDown = (ctx.ema15 < ctx.ema30);

      // 中文说明：多头回踩条件
      // 1) EMA15 > EMA30
      // 2) bar[1] 回踩 EMA15 区域（±0.15*ATR）
      // 3) 收盘重新站回 EMA15 且收阳
      // 4) 下影线 >= 实体 50%
      if(trendUp && IsBullishPullbackReject(ctx))
      {
         signal.valid = true;
         signal.strategyId = STRATEGY_PULLBACK;
         signal.orderType = OP_BUY;
         signal.lots = ctx.fixedLots;
         BuildInitialSLTP(OP_BUY, ctx, ctx.atr14, signal.stopLoss, signal.takeProfit);
         signal.comment = "Pullback-Long";
         signal.reason = "bullish ema15 pullback rejection";
         return true;
      }

      // 中文说明：空头回踩条件（多头镜像）
      if(trendDown && IsBearishPullbackReject(ctx))
      {
         signal.valid = true;
         signal.strategyId = STRATEGY_PULLBACK;
         signal.orderType = OP_SELL;
         signal.lots = ctx.fixedLots;
         BuildInitialSLTP(OP_SELL, ctx, ctx.atr14, signal.stopLoss, signal.takeProfit);
         signal.comment = "Pullback-Short";
         signal.reason = "bearish ema15 pullback rejection";
         return true;
      }

      signal.reason = "blocked: pullback condition not met";
      return false;
   }
};

#endif
