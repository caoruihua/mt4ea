#ifndef __STRATEGY_LINEAR_TREND_MQH__
#define __STRATEGY_LINEAR_TREND_MQH__

/*
 * 文件作用：
 * - 线性趋势策略（映射旧EA Session1 / Session3）
 * - 条件：EMA20/EMA50 + RSI区间 + MACD 同向确认
 */

#include "../Core/StrategyBase.mqh"

class CStrategyLinearTrend : public IStrategy
{
private:
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
   virtual string Name() { return "LinearTrend"; }

   virtual bool CanTrade(StrategyContext &ctx, RuntimeState &state)
   {
      if(ctx.sessionId == 1 && state.session1Trades < 2) return true;
      if(ctx.sessionId == 3 && state.session3Trades < 1) return true;
      return false;
   }

   virtual bool GenerateSignal(StrategyContext &ctx, RuntimeState &state, TradeSignal &signal)
   {
      ResetSignal(signal);

      if(!(ctx.sessionId == 1 || ctx.sessionId == 3))
         return false;

      double close1 = Close[1];

      if(close1 > ctx.ema20 && ctx.ema20 > ctx.ema50 && ctx.rsi > 55 && ctx.rsi < 70 && ctx.macd > 0)
      {
         signal.valid = true;
         signal.strategyId = STRATEGY_LINEAR_TREND;
         signal.orderType = OP_BUY;
         signal.lots = ctx.fixedLots;
         BuildSLTP(OP_BUY, ctx.session1_3_sl_usd, ctx.session1_3_tp_usd, ctx.digits, signal.stopLoss, signal.takeProfit);
         signal.comment = (ctx.sessionId == 1) ? "Session1-Long" : "Session3-Long";
         signal.reason = "EMA+RSI+MACD trend long";
         signal.priority = 10;
         return true;
      }

      if(close1 < ctx.ema20 && ctx.ema20 < ctx.ema50 && ctx.rsi > 30 && ctx.rsi < 45 && ctx.macd < 0)
      {
         signal.valid = true;
         signal.strategyId = STRATEGY_LINEAR_TREND;
         signal.orderType = OP_SELL;
         signal.lots = ctx.fixedLots;
         BuildSLTP(OP_SELL, ctx.session1_3_sl_usd, ctx.session1_3_tp_usd, ctx.digits, signal.stopLoss, signal.takeProfit);
         signal.comment = (ctx.sessionId == 1) ? "Session1-Short" : "Session3-Short";
         signal.reason = "EMA+RSI+MACD trend short";
         signal.priority = 10;
         return true;
      }

      return false;
   }
};

#endif
