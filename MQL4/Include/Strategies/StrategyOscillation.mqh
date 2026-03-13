#ifndef __STRATEGY_OSCILLATION_MQH__
#define __STRATEGY_OSCILLATION_MQH__

/*
 * 文件作用：
 * - 震荡策略（映射旧EA Session4）
 * - 在亚盘区间上沿/下沿附近做反转单
 */

#include "../Core/StrategyBase.mqh"

class CStrategyOscillation : public IStrategy
{
public:
   virtual string Name() { return "Oscillation"; }

   virtual bool CanTrade(StrategyContext &ctx, RuntimeState &state)
   {
      // 仅在 10:00-15:00 执行区间高低点策略
      if(ctx.sessionId != 4)
         return false;

      int h = TimeHour(ctx.beijingTime);
      if(h < 10 || h >= 15)
         return false;

      if(state.asianHigh <= 0 || state.asianLow <= 0)
         return false;
      return true;
   }

   virtual bool GenerateSignal(StrategyContext &ctx, RuntimeState &state, TradeSignal &signal)
   {
      ResetSignal(signal);
      if(ctx.sessionId != 4) return false;

      double rangeWidth = state.asianHigh - state.asianLow;
      if(rangeWidth < ctx.session4_minRange_usd)
         return false;

      double currentPrice = Bid;

      if(currentPrice >= state.asianHigh - ctx.session4_entryBuffer_usd)
      {
         signal.valid = true;
         signal.strategyId = STRATEGY_OSCILLATION;
         signal.orderType = OP_SELL;
         signal.lots = ctx.fixedLots;
         signal.stopLoss = NormalizeDouble(state.asianHigh + ctx.session4_slBuffer_usd, ctx.digits);
         signal.takeProfit = NormalizeDouble(Bid - ctx.session4_tp_usd, ctx.digits);
         signal.comment = "Session4-Short";
         signal.reason = "Near Asian high, mean reversion short";
         signal.priority = 20; // 10:00-15:00 触及高低点时优先级高于斜率策略
         return true;
      }

      if(currentPrice <= state.asianLow + ctx.session4_entryBuffer_usd)
      {
         signal.valid = true;
         signal.strategyId = STRATEGY_OSCILLATION;
         signal.orderType = OP_BUY;
         signal.lots = ctx.fixedLots;
         signal.stopLoss = NormalizeDouble(state.asianLow - ctx.session4_slBuffer_usd, ctx.digits);
         signal.takeProfit = NormalizeDouble(Ask + ctx.session4_tp_usd, ctx.digits);
         signal.comment = "Session4-Long";
         signal.reason = "Near Asian low, mean reversion long";
         signal.priority = 20; // 10:00-15:00 触及高低点时优先级高于斜率策略
         return true;
      }

      return false;
   }
};

#endif
