#ifndef __STRATEGY_BREAKOUT_MQH__
#define __STRATEGY_BREAKOUT_MQH__

/*
 * 文件作用：
 * - 突破/动量策略
 * - 映射旧EA：Session2 首K线跟随、Session5 真突破、Session6 动量跟随
 */

#include "../Core/StrategyBase.mqh"

class CStrategyBreakout : public IStrategy
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
   virtual string Name() { return "Breakout"; }

   virtual bool CanTrade(StrategyContext &ctx, RuntimeState &state)
   {
      if(ctx.sessionId == 2 && !state.session2Traded) return true;
      if(ctx.sessionId == 5 && state.session5Trades < 2) return true;
      if(ctx.sessionId == 6) return true;
      return false;
   }

   virtual bool GenerateSignal(StrategyContext &ctx, RuntimeState &state, TradeSignal &signal)
   {
      ResetSignal(signal);

      // Session2: first 5-min candle follow @07:05
      if(ctx.sessionId == 2)
      {
         int h = TimeHour(ctx.beijingTime);
         int m = TimeMinute(ctx.beijingTime);
         if(h == 7 && m == 5)
         {
            double o1 = Open[1], c1 = Close[1];
            if(c1 > o1)
            {
               signal.valid = true;
               signal.strategyId = STRATEGY_BREAKOUT;
               signal.orderType = OP_BUY;
               signal.lots = ctx.fixedLots;
               BuildSLTP(OP_BUY, ctx.session2_sl_usd, ctx.session2_tp_usd, ctx.digits, signal.stopLoss, signal.takeProfit);
               signal.comment = "Session2-Long";
               signal.reason = "First 5m candle bullish";
               signal.priority = 12;
               return true;
            }
            if(c1 < o1)
            {
               signal.valid = true;
               signal.strategyId = STRATEGY_BREAKOUT;
               signal.orderType = OP_SELL;
               signal.lots = ctx.fixedLots;
               BuildSLTP(OP_SELL, ctx.session2_sl_usd, ctx.session2_tp_usd, ctx.digits, signal.stopLoss, signal.takeProfit);
               signal.comment = "Session2-Short";
               signal.reason = "First 5m candle bearish";
               signal.priority = 12;
               return true;
            }
         }
      }

      // Session5: valid breakout
      if(ctx.sessionId == 5)
      {
         if(state.asianHigh > 0 && Close[1] > state.asianHigh + ctx.session5_validBreakout_trigger_usd && Close[2] > state.asianHigh)
         {
            signal.valid = true;
            signal.strategyId = STRATEGY_BREAKOUT;
            signal.orderType = OP_BUY;
            signal.lots = ctx.fixedLots;
            BuildSLTP(OP_BUY, ctx.session5_sl_usd, ctx.session5_tp_usd, ctx.digits, signal.stopLoss, signal.takeProfit);
            signal.comment = "Session5-ValidBreakout-Long";
            signal.reason = "Valid breakout above Asian high";
            signal.priority = 11;
            return true;
         }
         if(state.asianLow > 0 && Close[1] < state.asianLow - ctx.session5_validBreakout_trigger_usd && Close[2] < state.asianLow)
         {
            signal.valid = true;
            signal.strategyId = STRATEGY_BREAKOUT;
            signal.orderType = OP_SELL;
            signal.lots = ctx.fixedLots;
            BuildSLTP(OP_SELL, ctx.session5_sl_usd, ctx.session5_tp_usd, ctx.digits, signal.stopLoss, signal.takeProfit);
            signal.comment = "Session5-ValidBreakout-Short";
            signal.reason = "Valid breakout below Asian low";
            signal.priority = 11;
            return true;
         }
      }

      // Session6: momentum
      if(ctx.sessionId == 6)
      {
         double o1 = Open[1], c1 = Close[1], o2 = Open[2], c2 = Close[2];
         bool bullish1 = c1 > o1, bullish2 = c2 > o2;
         bool bearish1 = c1 < o1, bearish2 = c2 < o2;
         double body1 = MathAbs(c1 - o1), body2 = MathAbs(c2 - o2);

         if(body1 >= ctx.session6_minBody_usd || body2 >= ctx.session6_minBody_usd)
         {
            if(bullish1 && bullish2 && Close[0] > ctx.ema20)
            {
               signal.valid = true;
               signal.strategyId = STRATEGY_BREAKOUT;
               signal.orderType = OP_BUY;
               signal.lots = ctx.fixedLots;
               BuildSLTP(OP_BUY, ctx.session6_sl_usd, ctx.session6_tp_usd, ctx.digits, signal.stopLoss, signal.takeProfit);
               signal.comment = "Session6-Long";
               signal.reason = "Momentum long with EMA filter";
               signal.priority = 9;
               return true;
            }
            if(bearish1 && bearish2 && Close[0] < ctx.ema20)
            {
               signal.valid = true;
               signal.strategyId = STRATEGY_BREAKOUT;
               signal.orderType = OP_SELL;
               signal.lots = ctx.fixedLots;
               BuildSLTP(OP_SELL, ctx.session6_sl_usd, ctx.session6_tp_usd, ctx.digits, signal.stopLoss, signal.takeProfit);
               signal.comment = "Session6-Short";
               signal.reason = "Momentum short with EMA filter";
               signal.priority = 9;
               return true;
            }
         }
      }

      return false;
   }
};

#endif
