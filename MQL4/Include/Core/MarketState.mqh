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
   MarketRegime Detect(StrategyContext &ctx, RuntimeState &state)
   {
      int lookback = 30;
      if(Bars <= lookback + 5)
         return REGIME_UNKNOWN;

      double highest = High[1];
      double lowest = Low[1];
      for(int i = 2; i <= lookback; i++)
      {
         if(High[i] > highest) highest = High[i];
         if(Low[i] < lowest) lowest = Low[i];
      }

      state.rangeHigh = highest;
      state.rangeLow = lowest;

      double rangeWidth = highest - lowest;
      double close1 = Close[1];
      double close2 = Close[2];
      double ema20Prev = iMA(Symbol(), PERIOD_M5, 20, 0, MODE_EMA, PRICE_CLOSE, 3);
      double ema50Prev = iMA(Symbol(), PERIOD_M5, 50, 0, MODE_EMA, PRICE_CLOSE, 3);
      double ema20Slope = ctx.ema20 - ema20Prev;
      double ema50Slope = ctx.ema50 - ema50Prev;

      double atr = MathMax(ctx.atr14, 0.0);
      double invalidationMoveThreshold = atr * MathMax(ctx.regime_trend_invalidation_atr_mult, 0.0);
      double trendAdxThreshold = MathMax(18.0, ctx.regime_adx_weak_threshold);

      bool weakAdx = (ctx.adx14 > 0 && ctx.adx14 < ctx.regime_adx_weak_threshold);

      bool upTrendStrongInvalidated =
         (atr > 0) &&
         (close1 < ctx.ema20) &&
         (ema20Slope < -ctx.regime_slope_flip_threshold) &&
         ((highest - close1) >= invalidationMoveThreshold);

      bool downTrendStrongInvalidated =
         (atr > 0) &&
         (close1 > ctx.ema20) &&
         (ema20Slope > ctx.regime_slope_flip_threshold) &&
         ((close1 - lowest) >= invalidationMoveThreshold);

      bool risingStructure = (High[1] > High[2] && High[2] > High[3] && Low[1] > Low[2] && Low[2] > Low[3]);
      bool fallingStructure = (High[1] < High[2] && High[2] < High[3] && Low[1] < Low[2] && Low[2] < Low[3]);
      bool rangeCandidate = (ctx.adx14 > 0 && ctx.adx14 < 18.0 && atr > 0 && rangeWidth <= atr * 3.5);

      // 趋势失效快线：先快速撤销旧趋势，优先回到 RANGE，避免“过山车后仍维持旧方向”。
      if(upTrendStrongInvalidated || downTrendStrongInvalidated)
         return REGIME_RANGE;

      if(state.breakoutRetestActive)
      {
         double buffer = MathMax(atr * 0.15, 0.5);

         if(state.breakoutDirection > 0)
         {
            if(close1 < state.breakoutLevel - buffer)
            {
               state.breakoutRetestActive = false;
               state.breakoutDirection = 0;
               state.breakoutLevel = 0.0;
               return REGIME_RANGE;
            }

            if(Low[1] <= state.breakoutLevel + buffer && close1 > state.breakoutLevel + buffer && ctx.ema20 > ctx.ema50)
            {
               state.breakoutRetestActive = false;
               return REGIME_TREND_UP;
            }

            return REGIME_BREAKOUT_SETUP_UP;
         }

         if(state.breakoutDirection < 0)
         {
            if(close1 > state.breakoutLevel + buffer)
            {
               state.breakoutRetestActive = false;
               state.breakoutDirection = 0;
               state.breakoutLevel = 0.0;
               return REGIME_RANGE;
            }

            if(High[1] >= state.breakoutLevel - buffer && close1 < state.breakoutLevel - buffer && ctx.ema20 < ctx.ema50)
            {
               state.breakoutRetestActive = false;
               return REGIME_TREND_DOWN;
            }

            return REGIME_BREAKOUT_SETUP_DOWN;
         }
      }

      if(rangeCandidate)
      {
         double breakoutBuffer = MathMax(atr * 0.25, 1.0);
         if(close1 > highest + breakoutBuffer && close2 <= highest + breakoutBuffer)
         {
            state.breakoutRetestActive = true;
            state.breakoutDirection = 1;
            state.breakoutLevel = highest;
            return REGIME_BREAKOUT_SETUP_UP;
         }

         if(close1 < lowest - breakoutBuffer && close2 >= lowest - breakoutBuffer)
         {
            state.breakoutRetestActive = true;
            state.breakoutDirection = -1;
            state.breakoutLevel = lowest;
            return REGIME_BREAKOUT_SETUP_DOWN;
         }

         return REGIME_RANGE;
      }

      if(!weakAdx && risingStructure && ctx.ema20 > ctx.ema50 && ema20Slope > 0 && ema50Slope >= 0 && ctx.adx14 >= trendAdxThreshold)
         return REGIME_TREND_UP;

      if(!weakAdx && fallingStructure && ctx.ema20 < ctx.ema50 && ema20Slope < 0 && ema50Slope <= 0 && ctx.adx14 >= trendAdxThreshold)
         return REGIME_TREND_DOWN;

      return REGIME_RANGE;
   }
};

#endif
