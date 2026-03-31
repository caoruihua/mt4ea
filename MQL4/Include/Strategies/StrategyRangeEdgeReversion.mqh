#ifndef __STRATEGY_RANGE_EDGE_REVERSION_MQH__
#define __STRATEGY_RANGE_EDGE_REVERSION_MQH__

/*
 * 文件作用：
 * - 震荡区间边界反转策略（独立文件实现）
 * - 30根观察窗 + 20根交易区间窗
 * - 上沿附近做空、下沿附近做多
 * - SL 放区间外侧，TP 取中轴
 * - 趋势过滤：连续新低/新高效 + EMA方向 + ADX强度
 */

#include "../Core/StrategyBase.mqh"

// 趋势过滤参数
input bool    InpEnableTrendFilter      = true;    // 启用趋势过滤
input int     InpTrendFilterWindow     = 5;        // 趋势过滤窗口（根K线）
input int     InpTrendFilterThreshold  = 3;        // 趋势过滤阈值（连续N根触发）
input bool    InpEnableEmaFilter       = true;     // 启用EMA方向过滤
input int     InpEmaFastPeriod         = 10;       // EMA快线周期
input int     InpEmaSlowPeriod         = 20;       // EMA慢线周期
input bool    InpEnableAdxFilter       = false;   // 启用ADX强度过滤（默认关闭）
input int     InpAdxPeriod             = 14;       // ADX周期
input double  InpAdxThreshold          = 25.0;     // ADX阈值（超过此值且逆势时禁止）

class CStrategyRangeEdgeReversion : public IStrategy
{
public:
   virtual string Name() { return "RangeEdgeReversion"; }

private:
   string SideToString(ENUM_ORDER_TYPE signalType)
   {
      if(signalType == OP_BUY)  return "BUY";
      if(signalType == OP_SELL) return "SELL";
      return "UNKNOWN";
   }

private:
   bool CheckPriceStructureFilter(ENUM_ORDER_TYPE signalType);
   bool CheckEmaFilter(ENUM_ORDER_TYPE signalType);
   bool CheckAdxFilter(ENUM_ORDER_TYPE signalType);

public:
   bool IsTrendFilterPass(ENUM_ORDER_TYPE signalType);

   virtual bool CanTrade(StrategyContext &ctx, RuntimeState &state)
   {
      if(ctx.regime != REGIME_RANGE)
         return false;

      // 突破候选/确认阶段禁用反向区间候选，避免噪声拦截
      int bs = state.breakoutSubstate;
      if(bs == BREAKOUT_CANDIDATE_UP   || bs == BREAKOUT_CANDIDATE_DOWN ||
         bs == BREAKOUT_CONFIRMED_UP   || bs == BREAKOUT_CONFIRMED_DOWN)
      {
         static datetime s_suppressLogTime = 0;
         if(TimeCurrent() - s_suppressLogTime >= 30)
         {
            Print(StringFormat("[RangeEdgeReversion] 突破阶段抑制 | breakoutSubstate=%d | regime=%d", bs, ctx.regime));
            s_suppressLogTime = TimeCurrent();
         }
         return false;
      }

      int obsBars = MathMax(ctx.range_edge_observation_bars, 30);
      int tradeBars = MathMax(ctx.range_edge_trading_bars, 20);
      if(Bars <= obsBars + 2 || Bars <= tradeBars + 2)
         return false;

      return true;
   }

   virtual bool GenerateSignal(StrategyContext &ctx, RuntimeState &state, TradeSignal &signal)
   {
      ResetSignal(signal);
      if(!CanTrade(ctx, state))
         return false;

      int obsBars = MathMax(ctx.range_edge_observation_bars, 30);
      int tradeBars = MathMax(ctx.range_edge_trading_bars, 20);
      double tolerance = MathMax(ctx.range_edge_entry_tolerance_usd, 0.1);
      double slBuffer = MathMax(ctx.range_edge_sl_buffer_usd, 0.1);

      double obsHigh = High[1];
      double obsLow = Low[1];
      for(int i = 2; i <= obsBars; i++)
      {
         if(High[i] > obsHigh) obsHigh = High[i];
         if(Low[i] < obsLow) obsLow = Low[i];
      }

      double tradeHigh = High[1];
      double tradeLow = Low[1];
      for(int j = 2; j <= tradeBars; j++)
      {
         if(High[j] > tradeHigh) tradeHigh = High[j];
         if(Low[j] < tradeLow) tradeLow = Low[j];
      }

      double tradeWidth = tradeHigh - tradeLow;
      if(tradeWidth < tolerance * 2.0)
         return false;

      if((obsHigh - obsLow) < tradeWidth * 0.8)
         return false;

      double mid = (tradeHigh + tradeLow) * 0.5;
      double edgeBandEscapeMult = 2.0;

      bool nearUpperEdge = (ctx.bid >= tradeHigh - tolerance && ctx.bid <= tradeHigh + tolerance);
      bool nearLowerEdge = (ctx.ask <= tradeLow + tolerance && ctx.ask >= tradeLow - tolerance);

      // 价格已明显脱离区间边缘带，直接拒绝区间反转候选，避免“已突破却还按震荡做反向”。
      if(ctx.bid > tradeHigh + tolerance * edgeBandEscapeMult)
      {
         Print(StringFormat(
            "[RangeEdgeReversion] 信号拒绝 | phase=edge-band | decision=REJECT | reason=outside_range_edge_band_up | bid=%.5f | tradeHigh=%.5f | tolerance=%.2f | escapeMult=%.1f",
            ctx.bid,
            tradeHigh,
            tolerance,
            edgeBandEscapeMult
         ));
         return false;
      }

      if(ctx.ask < tradeLow - tolerance * edgeBandEscapeMult)
      {
         Print(StringFormat(
            "[RangeEdgeReversion] 信号拒绝 | phase=edge-band | decision=REJECT | reason=outside_range_edge_band_down | ask=%.5f | tradeLow=%.5f | tolerance=%.2f | escapeMult=%.1f",
            ctx.ask,
            tradeLow,
            tolerance,
            edgeBandEscapeMult
         ));
         return false;
      }

      // ---- 区间上沿做空 ----
      if(nearUpperEdge)
      {
         Print(StringFormat(
            "[RangeEdgeReversion] 候选信号 | side=SELL | phase=edge-check | regime=%d | bid=%.5f | ask=%.5f | tradeHigh=%.5f | tradeLow=%.5f | mid=%.5f | tolerance=%.2f | slBuffer=%.2f | obsBars=%d | tradeBars=%d",
            ctx.regime,
            ctx.bid,
            ctx.ask,
            tradeHigh,
            tradeLow,
            mid,
            tolerance,
            slBuffer,
            obsBars,
            tradeBars
         ));

         // 趋势过滤：做空前检查
         if(!IsTrendFilterPass(OP_SELL))
         {
            Print(StringFormat(
               "[RangeEdgeReversion] 信号拒绝 | side=SELL | phase=trend-filter | decision=REJECT | reason=TrendFilterBlocked | regime=%d | bid=%.5f | ask=%.5f | tradeHigh=%.5f | tradeLow=%.5f | tolerance=%.2f",
               ctx.regime,
               ctx.bid,
               ctx.ask,
               tradeHigh,
               tradeLow,
               tolerance
            ));
            return false;
         }

         signal.valid = true;
         signal.strategyId = STRATEGY_RANGE_EDGE_REVERSION;
         signal.orderType = OP_SELL;
         signal.lots = ctx.fixedLots;
         signal.stopLoss = NormalizeDouble(tradeHigh + slBuffer, ctx.digits);
         signal.takeProfit = NormalizeDouble(mid, ctx.digits);
         signal.comment = "RangeEdgeReversion-Short";
         signal.reason = StringFormat("Near HH%d edge within %.2f", tradeBars, tolerance);
         signal.priority = 14;
         return true;
      }

      // ---- 区间下沿做多 ----
      if(nearLowerEdge)
      {
         Print(StringFormat(
            "[RangeEdgeReversion] 候选信号 | side=BUY | phase=edge-check | regime=%d | bid=%.5f | ask=%.5f | tradeHigh=%.5f | tradeLow=%.5f | mid=%.5f | tolerance=%.2f | slBuffer=%.2f | obsBars=%d | tradeBars=%d",
            ctx.regime,
            ctx.bid,
            ctx.ask,
            tradeHigh,
            tradeLow,
            mid,
            tolerance,
            slBuffer,
            obsBars,
            tradeBars
         ));

         // 趋势过滤：做多前检查
         if(!IsTrendFilterPass(OP_BUY))
         {
            Print(StringFormat(
               "[RangeEdgeReversion] 信号拒绝 | side=BUY | phase=trend-filter | decision=REJECT | reason=TrendFilterBlocked | regime=%d | bid=%.5f | ask=%.5f | tradeHigh=%.5f | tradeLow=%.5f | tolerance=%.2f",
               ctx.regime,
               ctx.bid,
               ctx.ask,
               tradeHigh,
               tradeLow,
               tolerance
            ));
            return false;
         }

         signal.valid = true;
         signal.strategyId = STRATEGY_RANGE_EDGE_REVERSION;
         signal.orderType = OP_BUY;
         signal.lots = ctx.fixedLots;
         signal.stopLoss = NormalizeDouble(tradeLow - slBuffer, ctx.digits);
         signal.takeProfit = NormalizeDouble(mid, ctx.digits);
         signal.comment = "RangeEdgeReversion-Long";
         signal.reason = StringFormat("Near LL%d edge within %.2f", tradeBars, tolerance);
         signal.priority = 14;
         return true;
      }

      return false;
   }
};

//==============================================================================
// 趋势过滤三层实现
//==============================================================================

bool CStrategyRangeEdgeReversion::IsTrendFilterPass(ENUM_ORDER_TYPE signalType)
{
   if(!InpEnableTrendFilter)
      return true;

   if(!CheckPriceStructureFilter(signalType))
      return false;

   if(!CheckEmaFilter(signalType))
      return false;

   if(!CheckAdxFilter(signalType))
      return false;

   return true;
}

//------------------------------------------------------------------------------
// 第一层：价格结构过滤
// 做多：最近N根K线持续创新低 → 禁止
// 做空：最近N根K线持续创新高 → 禁止
//------------------------------------------------------------------------------
bool CStrategyRangeEdgeReversion::CheckPriceStructureFilter(ENUM_ORDER_TYPE signalType)
{
   int window = MathMax(InpTrendFilterWindow, 3);
   int threshold = MathMin(InpTrendFilterThreshold, window - 1);
   if(threshold < 1) threshold = 1;

   int consecutiveCount = 0;

   if(signalType == OP_BUY)
   {
      for(int i = 1; i <= window; i++)
      {
         if(i + 1 > Bars) break;
         if(Low[i] < Low[i + 1])
            consecutiveCount++;
      }

      if(consecutiveCount >= threshold)
      {
         Print(StringFormat(
            "[RangeEdgeReversion] 趋势过滤 | filter=PriceStructure | side=%s | decision=REJECT | consecutiveLow=%d | window=%d | threshold=%d",
            SideToString(signalType),
            consecutiveCount,
            window,
            threshold
         ));
         return false;
      }
   }
   else if(signalType == OP_SELL)
   {
      for(int i = 1; i <= window; i++)
      {
         if(i + 1 > Bars) break;
         if(High[i] > High[i + 1])
            consecutiveCount++;
      }

      if(consecutiveCount >= threshold)
      {
         Print(StringFormat(
            "[RangeEdgeReversion] 趋势过滤 | filter=PriceStructure | side=%s | decision=REJECT | consecutiveHigh=%d | window=%d | threshold=%d",
            SideToString(signalType),
            consecutiveCount,
            window,
            threshold
         ));
         return false;
      }
   }

   return true;
}

//------------------------------------------------------------------------------
// 第二层：EMA方向过滤
// EMA20 < EMA50 → 空头排列，禁止做多
// EMA20 > EMA50 → 多头排列，禁止做空
//------------------------------------------------------------------------------
bool CStrategyRangeEdgeReversion::CheckEmaFilter(ENUM_ORDER_TYPE signalType)
{
   if(!InpEnableEmaFilter)
      return true;

   double emaFast = iMA(NULL, 0, InpEmaFastPeriod, 0, MODE_EMA, PRICE_CLOSE, 0);
   double emaSlow = iMA(NULL, 0, InpEmaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE, 0);

   if(emaFast <= 0 || emaSlow <= 0)
      return true;

   if(signalType == OP_BUY)
   {
      if(emaFast < emaSlow)
      {
         Print(StringFormat(
            "[RangeEdgeReversion] 趋势过滤 | filter=EMA | side=%s | decision=REJECT | emaFastPeriod=%d | emaSlowPeriod=%d | emaFast=%.5f | emaSlow=%.5f | relation=emaFast<emaSlow",
            SideToString(signalType),
            InpEmaFastPeriod,
            InpEmaSlowPeriod,
            emaFast,
            emaSlow
         ));
         return false;
      }
   }
   else if(signalType == OP_SELL)
   {
      if(emaFast > emaSlow)
      {
         Print(StringFormat(
            "[RangeEdgeReversion] 趋势过滤 | filter=EMA | side=%s | decision=REJECT | emaFastPeriod=%d | emaSlowPeriod=%d | emaFast=%.5f | emaSlow=%.5f | relation=emaFast>emaSlow",
            SideToString(signalType),
            InpEmaFastPeriod,
            InpEmaSlowPeriod,
            emaFast,
            emaSlow
         ));
         return false;
      }
   }

   return true;
}

//------------------------------------------------------------------------------
// 第三层：ADX强度过滤（可选，默认关闭）
// ADX > 阈值 + 趋势方向与入场方向相反 → 禁止逆势入场
//------------------------------------------------------------------------------
bool CStrategyRangeEdgeReversion::CheckAdxFilter(ENUM_ORDER_TYPE signalType)
{
   if(!InpEnableAdxFilter)
      return true;

   double adx = iADX(NULL, 0, InpAdxPeriod, PRICE_CLOSE, MODE_MAIN, 0);
   if(adx <= 0)
      return true;

   if(adx <= InpAdxThreshold)
      return true;

   double emaFast = iMA(NULL, 0, InpEmaFastPeriod, 0, MODE_EMA, PRICE_CLOSE, 0);
   double emaSlow = iMA(NULL, 0, InpEmaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE, 0);
   if(emaFast <= 0 || emaSlow <= 0)
      return true;

   bool emaBullish = (emaFast > emaSlow);
   bool emaBearish = (emaFast < emaSlow);

   if(signalType == OP_BUY)
   {
      if(emaBearish)
      {
         Print(StringFormat(
            "[RangeEdgeReversion] 趋势过滤 | filter=ADX | side=%s | decision=REJECT | adx=%.2f | adxThreshold=%.2f | emaFast=%.5f | emaSlow=%.5f | relation=emaBearish",
            SideToString(signalType),
            adx,
            InpAdxThreshold,
            emaFast,
            emaSlow
         ));
         return false;
      }
   }
   else if(signalType == OP_SELL)
   {
      if(emaBullish)
      {
         Print(StringFormat(
            "[RangeEdgeReversion] 趋势过滤 | filter=ADX | side=%s | decision=REJECT | adx=%.2f | adxThreshold=%.2f | emaFast=%.5f | emaSlow=%.5f | relation=emaBullish",
            SideToString(signalType),
            adx,
            InpAdxThreshold,
            emaFast,
            emaSlow
         ));
         return false;
      }
   }

   return true;
}

#endif
