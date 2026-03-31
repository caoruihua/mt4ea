#ifndef __CORE_MARKET_STATE_MQH__
#define __CORE_MARKET_STATE_MQH__

/*
 * 文件作用：
 * - 市场状态识别引擎
 * - 基于价格结构 + EMA/RSI/MACD 将市场划分为：
 *   趋势/震荡/突破/反转
 * - v2: 新增解耦后的方向突破子状态机（breakoutSubstate）
 *   区间边界在 candidate 开始时冻结，2 根 closed bar 站稳即确认。
 */

#include "Types.mqh"

class CMarketStateEngine
{
public:
   MarketRegime Detect(StrategyContext &ctx, RuntimeState &state)
   {
      // ── 1. 样本保护 ─────────────────────────────────────────
      int lookback = 30;
      if(Bars <= lookback + 5)
         return REGIME_UNKNOWN;

      double close1 = Close[1];
      double close2 = Close[2];

      // ── 2. 区间高低点（排除 bar[1] 本身，避免突破 bar 自身抬高 highest） ──
      double highest = High[2];
      double lowest  = Low[2];
      for(int i = 3; i <= lookback; i++)
      {
         if(High[i] > highest) highest = High[i];
         if(Low[i]  < lowest)  lowest  = Low[i];
      }

      state.rangeHigh = highest;
      state.rangeLow  = lowest;

      double rangeWidth = highest - lowest;
      double atr = MathMax(ctx.atr14, 0.0);

      // ── 3. EMA 斜率（与旧逻辑一致） ──────────────────────────
      double ema20Prev  = iMA(Symbol(), PERIOD_M5, 20, 0, MODE_EMA, PRICE_CLOSE, 3);
      double ema50Prev  = iMA(Symbol(), PERIOD_M5, 50, 0, MODE_EMA, PRICE_CLOSE, 3);
      double ema20Slope = ctx.ema20 - ema20Prev;
      double ema50Slope = ctx.ema50 - ema50Prev;

      double invalidationMoveThreshold = atr * MathMax(ctx.regime_trend_invalidation_atr_mult, 0.0);
      double trendAdxThreshold = MathMax(18.0, ctx.regime_adx_weak_threshold);
      bool   weakAdx = (ctx.adx14 > 0 && ctx.adx14 < ctx.regime_adx_weak_threshold);

      // ── 4. 旧趋势失效快线（优先级最高） ─────────────────────
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

      if(upTrendStrongInvalidated || downTrendStrongInvalidated)
      {
         // 旧趋势失效时同步重置突破子状态
         state.breakoutSubstate         = BREAKOUT_NONE;
         state.breakoutFrozenHigh       = 0.0;
         state.breakoutFrozenLow        = 0.0;
         state.breakoutCandidateBarTime = 0;
         state.breakoutHoldBars         = 0;
         return REGIME_RANGE;
      }

      // ── 5. 方向突破子状态机（独立于 rangeCandidate 门控） ────
      double breakoutBuffer = MathMax(atr * 0.25, 1.0);

      int    sub = state.breakoutSubstate;

      // 5a. 当前为候选阶段 → 判断是否确认或失败
      if(sub == BREAKOUT_CANDIDATE_UP)
      {
         if(close1 > state.breakoutFrozenHigh + breakoutBuffer)
         {
            state.breakoutHoldBars++;
            if(state.breakoutHoldBars >= 2)
            {
               state.breakoutSubstate = BREAKOUT_CONFIRMED_UP;
               return REGIME_TREND_UP; // 确认上破 → 立即追多
            }
            // 还未满 2 根，保持候选
            return REGIME_RANGE;
         }
         else
         {
            // 收盘回到区间内 → 突破失败
            state.breakoutSubstate         = BREAKOUT_FAILED;
            state.breakoutFrozenHigh       = 0.0;
            state.breakoutFrozenLow        = 0.0;
            state.breakoutCandidateBarTime = 0;
            state.breakoutHoldBars         = 0;
            // 失败后回退到 RANGE；下面继续执行结构判断
         }
      }
      else if(sub == BREAKOUT_CANDIDATE_DOWN)
      {
         if(close1 < state.breakoutFrozenLow - breakoutBuffer)
         {
            state.breakoutHoldBars++;
            if(state.breakoutHoldBars >= 2)
            {
               state.breakoutSubstate = BREAKOUT_CONFIRMED_DOWN;
               return REGIME_TREND_DOWN; // 确认下破 → 立即追空
            }
            return REGIME_RANGE;
         }
         else
         {
            state.breakoutSubstate         = BREAKOUT_FAILED;
            state.breakoutFrozenHigh       = 0.0;
            state.breakoutFrozenLow        = 0.0;
            state.breakoutCandidateBarTime = 0;
            state.breakoutHoldBars         = 0;
         }
      }
      // 5b. 已确认阶段 → 维持直到旧趋势失效（已在上方处理）
      else if(sub == BREAKOUT_CONFIRMED_UP)
         return REGIME_TREND_UP;
      else if(sub == BREAKOUT_CONFIRMED_DOWN)
         return REGIME_TREND_DOWN;

      // 5c. NONE / FAILED → 检测新的突破候选
      // 使用冻结边界（计算时已排除 bar[1]）
      if(close1 > highest + breakoutBuffer && close2 <= highest + breakoutBuffer)
      {
         state.breakoutSubstate         = BREAKOUT_CANDIDATE_UP;
         state.breakoutFrozenHigh       = highest;
         state.breakoutFrozenLow        = lowest;
         state.breakoutCandidateBarTime = Time[1];
         state.breakoutHoldBars         = 1; // 首根已站稳
         return REGIME_RANGE;
      }
      if(close1 < lowest - breakoutBuffer && close2 >= lowest - breakoutBuffer)
      {
         state.breakoutSubstate         = BREAKOUT_CANDIDATE_DOWN;
         state.breakoutFrozenHigh       = highest;
         state.breakoutFrozenLow        = lowest;
         state.breakoutCandidateBarTime = Time[1];
         state.breakoutHoldBars         = 1;
         return REGIME_RANGE;
      }

      // ── 6. 旧版回踩跟踪（保留兼容，breakoutRetestActive 路径） ─
      if(state.breakoutRetestActive)
      {
         double buffer = MathMax(atr * 0.15, 0.5);

         if(state.breakoutDirection > 0)
         {
            if(close1 < state.breakoutLevel - buffer)
            {
               state.breakoutRetestActive = false;
               state.breakoutDirection    = 0;
               state.breakoutLevel        = 0.0;
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
               state.breakoutDirection    = 0;
               state.breakoutLevel        = 0.0;
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

      // ── 7. 震荡候选门控（保留旧逻辑） ───────────────────────
      bool rangeCandidate = (ctx.adx14 > 0 && ctx.adx14 < 18.0 && atr > 0 && rangeWidth <= atr * 3.5);
      if(rangeCandidate)
         return REGIME_RANGE;

      // ── 8. 趋势识别（价格结构 + EMA + ADX） ─────────────────
      bool risingStructure  = (High[1] > High[2] && High[2] > High[3] && Low[1] > Low[2] && Low[2] > Low[3]);
      bool fallingStructure = (High[1] < High[2] && High[2] < High[3] && Low[1] < Low[2] && Low[2] < Low[3]);

      if(!weakAdx && risingStructure && ctx.ema20 > ctx.ema50 && ema20Slope > 0 && ema50Slope >= 0 && ctx.adx14 >= trendAdxThreshold)
         return REGIME_TREND_UP;

      if(!weakAdx && fallingStructure && ctx.ema20 < ctx.ema50 && ema20Slope < 0 && ema50Slope <= 0 && ctx.adx14 >= trendAdxThreshold)
         return REGIME_TREND_DOWN;

      return REGIME_RANGE;
   }
};

#endif
