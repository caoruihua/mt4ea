#ifndef __STRATEGY_SLOPE_CHANNEL_MQH__
#define __STRATEGY_SLOPE_CHANNEL_MQH__

/*
 * 文件作用：
 * - 斜率通道策略（Slope Channel）
 * - 识别“上下轨近似平行且同向倾斜”的通道
 * - 上行通道：回踩下轨附近做多；下行通道：反弹上轨附近做空
 * - 使用独立 SL/TP 参数（channel_sl_usd / channel_tp_usd）
 */

#include "../Core/StrategyBase.mqh"

class CStrategySlopeChannel : public IStrategy
{
private:
   double LinearSlopeClose(int lookback, int shiftStart)
   {
      // y = a + b*x，返回 b（每根K线的价格斜率）
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
      if(MathAbs(den) < 1e-10) return 0.0;
      return (n * sumXY - sumX * sumY) / den;
   }

   double LinearSlopeHigh(int lookback, int shiftStart)
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
      if(MathAbs(den) < 1e-10) return 0.0;
      return (n * sumXY - sumX * sumY) / den;
   }

   double LinearSlopeLow(int lookback, int shiftStart)
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
      if(MathAbs(den) < 1e-10) return 0.0;
      return (n * sumXY - sumX * sumY) / den;
   }

   double AverageWidth(int lookback, int shiftStart)
   {
      double sum = 0.0;
      for(int i = 0; i < lookback; i++)
         sum += (High[shiftStart + i] - Low[shiftStart + i]);
      return sum / lookback;
   }

   double ChannelLowerRef(int lookback, int shiftStart)
   {
      double v = Low[shiftStart];
      for(int i = 1; i < lookback; i++) if(Low[shiftStart + i] < v) v = Low[shiftStart + i];
      return v;
   }

   double ChannelUpperRef(int lookback, int shiftStart)
   {
      double v = High[shiftStart];
      for(int i = 1; i < lookback; i++) if(High[shiftStart + i] > v) v = High[shiftStart + i];
      return v;
   }

   void BuildSLTP(int orderType, double slUsd, double tpUsd, int digits, double &sl, double &tp)
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

public:
   virtual string Name() { return "SlopeChannel"; }

   virtual bool CanTrade(StrategyContext &ctx, RuntimeState &state)
   {
      if(state.channelTrades >= ctx.channel_max_trades_per_day)
         return false;

      int h = TimeHour(ctx.beijingTime);
      // 按你的要求：8:00-15:00 执行斜率策略（10:00-15:00若触及高低点由区间策略优先）
      if(h < 8 || h >= 15)
         return false;

      return true;
   }

   virtual bool GenerateSignal(StrategyContext &ctx, RuntimeState &state, TradeSignal &signal)
   {
      ResetSignal(signal);

      int n = ctx.channel_lookback_bars;
      if(n < 10) n = 10;

      double adx = iADX(Symbol(), PERIOD_M5, 14, PRICE_CLOSE, MODE_MAIN, 1);
      if(adx < ctx.channel_adx_min)
         return false;

      double slopeH = LinearSlopeHigh(n, 1);
      double slopeL = LinearSlopeLow(n, 1);
      double slopeC = LinearSlopeClose(n, 1);

      if(MathAbs(slopeH - slopeL) > ctx.channel_parallel_tolerance)
         return false;

      double width = AverageWidth(n, 1);
      if(width > ctx.channel_max_width_usd)
         return false;

      double lowerRef = ChannelLowerRef(n, 1);
      double upperRef = ChannelUpperRef(n, 1);
      double c1 = Close[1];

      // 上行平行通道：回踩下轨附近 + close斜率向上
      if(slopeH > ctx.channel_min_slope && slopeL > ctx.channel_min_slope && slopeC > 0)
      {
         if(c1 <= lowerRef + ctx.channel_entry_tolerance_usd)
         {
            signal.valid = true;
            signal.strategyId = STRATEGY_SLOPE_CHANNEL;
            signal.orderType = OP_BUY;
            signal.lots = ctx.fixedLots;
            BuildSLTP(OP_BUY, ctx.channel_sl_usd, ctx.channel_tp_usd, ctx.digits, signal.stopLoss, signal.takeProfit);
            signal.comment = "SlopeChannel-Long";
            signal.reason = "Up slope channel pullback long";
            signal.priority = 13;
            return true;
         }
      }

      // 下行平行通道：反弹上轨附近 + close斜率向下
      if(slopeH < -ctx.channel_min_slope && slopeL < -ctx.channel_min_slope && slopeC < 0)
      {
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
