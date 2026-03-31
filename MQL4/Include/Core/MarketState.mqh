#ifndef __CORE_MARKET_STATE_MQH__
#define __CORE_MARKET_STATE_MQH__

/*
 * 文件作用：
 * - 市场状态识别引擎
 * - 基于价格结构 + EMA/RSI/MACD 将市场划分为：
 *   趋势/震荡/突破/反转
 * - v2: 新增解耦后的方向突破子状态机（breakoutSubstate）
 *   区间边界在 candidate 开始时冻结，2 根 closed bar 站稳即确认。
 * - v2.1: [fix] lookback 30→12（M5 回看窗口收窄到 1 小时）
 *         [fix] EMA 斜率基准 bar[3]→bar[2]（相邻两根，更敏感）
 *         [fix] EMA 斜率归一化（除以 ATR，消除品种差异）
 */

#include "Types.mqh"

class CMarketStateEngine
{
public:
   MarketRegime Detect(StrategyContext &ctx, RuntimeState &state)
   {
      // ── 1. 样本保护 ─────────────────────────────────────────
      // [fix v2.1] lookback: 30 → 12
      // M5 × 12根 = 60分钟，短线回看 1 小时更合理
      // 原来 30根 = 150分钟，高低点太陈旧，容易把正常短线突破淹没在大区间里
      int lookback = 12;
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
      double atr = MathMax(ctx.atr14, 0.0001);  // [fix] 防止除零，最小值改为 0.0001

      // ── 3. EMA 斜率 ──────────────────────────────────────────
      // [fix v2.1] 基准从 bar[3] 改为 bar[2]：
      //   原来：ema20Slope = bar[1]值 - bar[3]值，跨越 10 分钟，斜率太钝
      //   现在：ema20Slope = bar[1]值 - bar[2]值，只差 5 分钟，更敏感
      double ema12Prev  = iMA(Symbol(), PERIOD_M5, 12, 0, MODE_EMA, PRICE_CLOSE, 2);
      double ema20Prev  = iMA(Symbol(), PERIOD_M5, 20, 0, MODE_EMA, PRICE_CLOSE, 2);

      double ema12SlopeRaw = ctx.ema12 - ema12Prev;
      double ema20SlopeRaw = ctx.ema20 - ema20Prev;

      // [fix v2.1] 斜率归一化：除以 ATR，消除品种价格量纲差异
      //   例：黄金 ATR=2.0，斜率 0.3 → 归一化 0.15（15% ATR/bar）
      //       日元 ATR=0.5，斜率 0.3 → 归一化 0.60（60% ATR/bar，明显更陡）
      //   归一化后阈值在不同品种上含义一致
      double ema12Slope = ema12SlopeRaw / atr;
      double ema20Slope = ema20SlopeRaw / atr;

      // [fix v2.1] 斜率阈值改为归一化比例
      //   原来 regime_slope_flip_threshold 是绝对价格值，品种间不可移植
      //   现在含义：EMA 每根 bar 移动量 >= X% 的 ATR 才算有效斜率
      //   建议 ctx.regime_slope_flip_threshold 设置为 0.03～0.08
      double slopeThreshold = MathMax(ctx.regime_slope_flip_threshold, 0.0);

      double invalidationMoveThreshold = atr * MathMax(ctx.regime_trend_invalidation_atr_mult, 0.0);
      double trendAdxThreshold = MathMax(18.0, ctx.regime_adx_weak_threshold);
      bool   weakAdx = (ctx.adx14 > 0 && ctx.adx14 < ctx.regime_adx_weak_threshold);

      // ── 4. 旧趋势失效快线（优先级最高） ─────────────────────
      // 注意：slopeThreshold 现在是归一化值，ema20Slope 也是归一化值，量纲一致
      bool upTrendStrongInvalidated =
         (close1 < ctx.ema12) &&
         (ema12Slope < -slopeThreshold) &&
         ((highest - close1) >= invalidationMoveThreshold);

      bool downTrendStrongInvalidated =
         (close1 > ctx.ema12) &&
         (ema12Slope > slopeThreshold) &&
         ((close1 - lowest) >= invalidationMoveThreshold);

      if(upTrendStrongInvalidated || downTrendStrongInvalidated)
      {
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

      if(sub == BREAKOUT_CANDIDATE_UP)
      {
         if(close1 > state.breakoutFrozenHigh + breakoutBuffer)
         {
            state.breakoutHoldBars++;
            if(state.breakoutHoldBars >= 2)
            {
               state.breakoutSubstate = BREAKOUT_CONFIRMED_UP;
               return REGIME_TREND_UP;
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
      else if(sub == BREAKOUT_CANDIDATE_DOWN)
      {
         if(close1 < state.breakoutFrozenLow - breakoutBuffer)
         {
            state.breakoutHoldBars++;
            if(state.breakoutHoldBars >= 2)
            {
               state.breakoutSubstate = BREAKOUT_CONFIRMED_DOWN;
               return REGIME_TREND_DOWN;
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
      else if(sub == BREAKOUT_CONFIRMED_UP)
         return REGIME_TREND_UP;
      else if(sub == BREAKOUT_CONFIRMED_DOWN)
         return REGIME_TREND_DOWN;

      // 5c. NONE / FAILED → 检测新的突破候选/确认
      double upperBreakLevel = highest + breakoutBuffer;
      double lowerBreakLevel = lowest  - breakoutBuffer;
      static datetime s_breakoutDiagLogTime = 0;
      bool allowDiagLog = (TimeCurrent() - s_breakoutDiagLogTime >= 15);

      if(close1 > upperBreakLevel && close2 > upperBreakLevel)
      {
         if(allowDiagLog)
         {
            Print(StringFormat(
               "[MarketState] breakout confirm up | close1=%.5f | close2=%.5f | upperLevel=%.5f | highest=%.5f | buffer=%.5f",
               close1, close2, upperBreakLevel, highest, breakoutBuffer
            ));
            s_breakoutDiagLogTime = TimeCurrent();
         }
         state.breakoutSubstate         = BREAKOUT_CONFIRMED_UP;
         state.breakoutFrozenHigh       = highest;
         state.breakoutFrozenLow        = lowest;
         state.breakoutCandidateBarTime = Time[1];
         state.breakoutHoldBars         = 2;
         return REGIME_TREND_UP;
      }

      if(close1 < lowerBreakLevel && close2 < lowerBreakLevel)
      {
         if(allowDiagLog)
         {
            Print(StringFormat(
               "[MarketState] breakout confirm down | close1=%.5f | close2=%.5f | lowerLevel=%.5f | lowest=%.5f | buffer=%.5f",
               close1, close2, lowerBreakLevel, lowest, breakoutBuffer
            ));
            s_breakoutDiagLogTime = TimeCurrent();
         }
         state.breakoutSubstate         = BREAKOUT_CONFIRMED_DOWN;
         state.breakoutFrozenHigh       = highest;
         state.breakoutFrozenLow        = lowest;
         state.breakoutCandidateBarTime = Time[1];
         state.breakoutHoldBars         = 2;
         return REGIME_TREND_DOWN;
      }

      if(close1 > upperBreakLevel)
      {
         if(allowDiagLog)
         {
            Print(StringFormat(
               "[MarketState] breakout candidate up | close1=%.5f | close2=%.5f | upperLevel=%.5f | highest=%.5f | buffer=%.5f",
               close1, close2, upperBreakLevel, highest, breakoutBuffer
            ));
            s_breakoutDiagLogTime = TimeCurrent();
         }
         state.breakoutSubstate         = BREAKOUT_CANDIDATE_UP;
         state.breakoutFrozenHigh       = highest;
         state.breakoutFrozenLow        = lowest;
         state.breakoutCandidateBarTime = Time[1];
         state.breakoutHoldBars         = 1;
         return REGIME_RANGE;
      }
      if(close1 < lowerBreakLevel)
      {
         if(allowDiagLog)
         {
            Print(StringFormat(
               "[MarketState] breakout candidate down | close1=%.5f | close2=%.5f | lowerLevel=%.5f | lowest=%.5f | buffer=%.5f",
               close1, close2, lowerBreakLevel, lowest, breakoutBuffer
            ));
            s_breakoutDiagLogTime = TimeCurrent();
         }
         state.breakoutSubstate         = BREAKOUT_CANDIDATE_DOWN;
         state.breakoutFrozenHigh       = highest;
         state.breakoutFrozenLow        = lowest;
         state.breakoutCandidateBarTime = Time[1];
         state.breakoutHoldBars         = 1;
         return REGIME_RANGE;
      }

      // ── 6. 旧版回踩跟踪（保留兼容） ─────────────────────────
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
            if(Low[1] <= state.breakoutLevel + buffer && close1 > state.breakoutLevel + buffer && ctx.ema12 > ctx.ema20)
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
            if(High[1] >= state.breakoutLevel - buffer && close1 < state.breakoutLevel - buffer && ctx.ema12 < ctx.ema20)
            {
               state.breakoutRetestActive = false;
               return REGIME_TREND_DOWN;
            }
            return REGIME_BREAKOUT_SETUP_DOWN;
         }
      }

      // ── 7. 震荡候选门控 ──────────────────────────────────────
      bool rangeCandidate = (ctx.adx14 > 0 && ctx.adx14 < 18.0 && atr > 0 && rangeWidth <= atr * 3.5);
      if(rangeCandidate)
         return REGIME_RANGE;

      // ── 8. 趋势识别（价格结构 + EMA + ADX） ─────────────────
      // 注意：ema12Slope / ema20Slope 现在是归一化值
      //   > 0 表示向上，< 0 表示向下，与原逻辑符号含义完全一致，无需改动判断方向
      // 放宽结构条件：只需价格在EMA上方/下方 + EMA排列即可
      bool risingStructure  = (Close[1] > ctx.ema12 && ctx.ema12 > ctx.ema20);
      bool fallingStructure = (Close[1] < ctx.ema12 && ctx.ema12 < ctx.ema20);

      if(!weakAdx && risingStructure && ctx.ema12 > ctx.ema20 && ema12Slope > 0 && ema20Slope >= 0 && ctx.adx14 >= trendAdxThreshold)
         return REGIME_TREND_UP;

      if(!weakAdx && fallingStructure && ctx.ema12 < ctx.ema20 && ema12Slope < 0 && ema20Slope <= 0 && ctx.adx14 >= trendAdxThreshold)
         return REGIME_TREND_DOWN;

      // ── 9. 强趋势兜底识别 ────────────────────────────────────
      if(!weakAdx && ctx.adx14 >= trendAdxThreshold)
      {
         if(ctx.ema12 > ctx.ema20 && ema12Slope > 0 && ema20Slope >= 0 && close1 >= ctx.ema12 - atr * 0.10)
            return REGIME_TREND_UP;

         if(ctx.ema12 < ctx.ema20 && ema12Slope < 0 && ema20Slope <= 0 && close1 <= ctx.ema12 + atr * 0.10)
            return REGIME_TREND_DOWN;
      }

      return REGIME_RANGE;
   }
};

#endif