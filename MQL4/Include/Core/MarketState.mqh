#ifndef __CORE_MARKET_STATE_MQH__
#define __CORE_MARKET_STATE_MQH__

/*
 * 文件作用：
 * - 市场状态识别引擎
 * - 基于价格结构 + EMA/RSI/MACD 将市场划分为：
 *   趋势/震荡/突破/反转
 */

#include "Types.mqh"

class CMarketStateEngine
{
public:
   MarketRegime Detect(StrategyContext &ctx)
   {
      double c1 = Close[1];
      double h2 = High[2];
      double l2 = Low[2];

      if(c1 > h2 + 2.0 || c1 < l2 - 2.0)
         return REGIME_BREAKOUT;

      if(ctx.ema20 > ctx.ema50 && ctx.rsi > 52 && ctx.macd > 0)
         return REGIME_TREND_UP;

      if(ctx.ema20 < ctx.ema50 && ctx.rsi < 48 && ctx.macd < 0)
         return REGIME_TREND_DOWN;

      if((ctx.rsi > 70 && ctx.macd < 0) || (ctx.rsi < 30 && ctx.macd > 0))
         return REGIME_REVERSAL;

      return REGIME_RANGE;
   }
};

#endif
