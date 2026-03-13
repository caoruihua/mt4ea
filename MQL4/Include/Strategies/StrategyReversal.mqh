#ifndef __STRATEGY_REVERSAL_MQH__
#define __STRATEGY_REVERSAL_MQH__

/*
 * 文件作用：
 * - 反转策略（映射旧EA Session5 的假突破与EMA回踩）
 * - 假突破信号优先级高于 EMA 回踩信号
 */

#include "../Core/StrategyBase.mqh"

class CStrategyReversal : public IStrategy
{
public:
   virtual string Name() { return "Reversal"; }

   virtual bool CanTrade(StrategyContext &ctx, RuntimeState &state)
   {
      if(ctx.sessionId != 5) return false;
      if(state.session5Trades >= 2) return false;
      if(state.asianHigh <= 0 && state.asianLow <= 0) return false;
      return true;
   }

   virtual bool GenerateSignal(StrategyContext &ctx, RuntimeState &state, TradeSignal &signal)
   {
      ResetSignal(signal);
      if(ctx.sessionId != 5)
         return false;

      double currentPrice = Bid;

      // Fake breakout below low then close back above
      if(state.asianLow > 0 && currentPrice < state.asianLow - ctx.session5_fakeBreakout_trigger_usd)
      {
         if(state.fakeBreakoutLow == 0 || Low[0] < state.fakeBreakoutLow)
            state.fakeBreakoutLow = Low[0];
      }
      if(state.fakeBreakoutLow > 0 && Close[1] > state.asianLow)
      {
         signal.valid = true;
         signal.strategyId = STRATEGY_REVERSAL;
         signal.orderType = OP_BUY;
         signal.lots = ctx.fixedLots;
         signal.stopLoss = NormalizeDouble(state.fakeBreakoutLow - ctx.session5_sl_usd, ctx.digits);
         signal.takeProfit = NormalizeDouble(Ask + ctx.session5_tp_usd, ctx.digits);
         signal.comment = "Session5-FakeBreakout-Long";
         signal.reason = "Fake breakout below Asian low";
         signal.priority = 15;
         return true;
      }

      // Fake breakout above high then close back below
      if(state.asianHigh > 0 && currentPrice > state.asianHigh + ctx.session5_fakeBreakout_trigger_usd)
      {
         if(state.fakeBreakoutHigh == 0 || High[0] > state.fakeBreakoutHigh)
            state.fakeBreakoutHigh = High[0];
      }
      if(state.fakeBreakoutHigh > 0 && Close[1] < state.asianHigh)
      {
         signal.valid = true;
         signal.strategyId = STRATEGY_REVERSAL;
         signal.orderType = OP_SELL;
         signal.lots = ctx.fixedLots;
         signal.stopLoss = NormalizeDouble(state.fakeBreakoutHigh + ctx.session5_sl_usd, ctx.digits);
         signal.takeProfit = NormalizeDouble(Bid - ctx.session5_tp_usd, ctx.digits);
         signal.comment = "Session5-FakeBreakout-Short";
         signal.reason = "Fake breakout above Asian high";
         signal.priority = 15;
         return true;
      }

      // EMA pullback fallback
      if(ctx.ema20 > ctx.ema50 && MathAbs(Close[1] - ctx.ema20) <= ctx.session5_emaTolerance_usd && Close[1] > ctx.ema20 && ctx.rsi > 45 && ctx.rsi < 65)
      {
         signal.valid = true;
         signal.strategyId = STRATEGY_REVERSAL;
         signal.orderType = OP_BUY;
         signal.lots = ctx.fixedLots;
         signal.stopLoss = NormalizeDouble(Bid - ctx.session5_sl_usd, ctx.digits);
         signal.takeProfit = NormalizeDouble(Ask + ctx.session5_tp_usd, ctx.digits);
         signal.comment = "Session5-EMAPullback-Long";
         signal.reason = "EMA pullback long";
         signal.priority = 7;
         return true;
      }

      if(ctx.ema20 < ctx.ema50 && MathAbs(Close[1] - ctx.ema20) <= ctx.session5_emaTolerance_usd && Close[1] < ctx.ema20 && ctx.rsi > 35 && ctx.rsi < 55)
      {
         signal.valid = true;
         signal.strategyId = STRATEGY_REVERSAL;
         signal.orderType = OP_SELL;
         signal.lots = ctx.fixedLots;
         signal.stopLoss = NormalizeDouble(Ask + ctx.session5_sl_usd, ctx.digits);
         signal.takeProfit = NormalizeDouble(Bid - ctx.session5_tp_usd, ctx.digits);
         signal.comment = "Session5-EMAPullback-Short";
         signal.reason = "EMA pullback short";
         signal.priority = 7;
         return true;
      }

      return false;
   }
};

#endif
