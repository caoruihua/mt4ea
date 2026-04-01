#ifndef __CORE_MARKET_STATE_MQH__
#define __CORE_MARKET_STATE_MQH__

/*
 * 文件作用：
 * - 提供“两策略内核”的最小市场过滤器
 * - 仅输出：趋势方向、趋势有效性、低波动拦截结果
 *
 * 设计约束：
 * - 决策只基于已收盘 M5 K线
 * - 不再维护突破子状态机、区间状态机、防抖状态机
 */

#include "Types.mqh"

class CMarketStateEngine
{
private:
   // 将 ATR 价格差转换为 points，便于与点差做同量纲比较
   double PriceToPoints(double priceDelta)
   {
      if(Point <= 0.0)
         return 0.0;
      return priceDelta / Point;
   }

public:
   // 计算最小市场过滤结果
   bool EvaluateFilter(const StrategyContext &ctx, MarketFilterResult &out)
   {
      out.trendDirection = TREND_NONE;
      out.isTrendValid = false;
      out.isLowVol = false;
      out.barTime = ctx.lastClosedBarTime;
      out.blockReason = "";

      if(ctx.emaFast <= 0 || ctx.emaSlow <= 0 || ctx.atr14 <= 0)
      {
         out.isLowVol = true;
         out.blockReason = "blocked: invalid indicator snapshot";
         return false;
      }

      double atrPoints = PriceToPoints(ctx.atr14);
      double spreadPoints = MathMax(ctx.spreadPoints, 0.0);
      double atrSpreadRatio = (spreadPoints > 0.0) ? (atrPoints / spreadPoints) : 9999.0;

      // 低波动门控：
      // 1) ATR(14) >= 120 points
      // 2) ATR points / spread points >= 3.0
      // 任一条件不满足，禁止新开仓（但不影响已有持仓管理）
      if(atrPoints < 120.0 || atrSpreadRatio < 3.0)
      {
         out.isLowVol = true;
         out.blockReason = StringFormat("blocked: low volatility | atrPts=%.2f spreadPts=%.2f ratio=%.2f", atrPoints, spreadPoints, atrSpreadRatio);
         return true;
      }

      // 趋势判定（快/慢 EMA，默认 9/21）：
      // - 多头：快 EMA > 慢 EMA 且两者相对3根已收盘K线前都在上行
      // - 空头：快 EMA < 慢 EMA 且两者相对3根已收盘K线前都在下行
      double emaFastPrev3 = iMA(ctx.symbol, PERIOD_M5, ctx.emaFastPeriod, 0, MODE_EMA, PRICE_CLOSE, 3);
      double emaSlowPrev3 = iMA(ctx.symbol, PERIOD_M5, ctx.emaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE, 3);

      bool upTrend = (ctx.emaFast > ctx.emaSlow && ctx.emaFast > emaFastPrev3 && ctx.emaSlow > emaSlowPrev3);
      bool downTrend = (ctx.emaFast < ctx.emaSlow && ctx.emaFast < emaFastPrev3 && ctx.emaSlow < emaSlowPrev3);

      if(upTrend)
      {
         out.trendDirection = TREND_UP;
         out.isTrendValid = true;
         return true;
      }

      if(downTrend)
      {
         out.trendDirection = TREND_DOWN;
         out.isTrendValid = true;
         return true;
      }

      out.trendDirection = TREND_NONE;
      out.isTrendValid = false;
      out.blockReason = "blocked: no valid trend";
      return true;
   }
};

#endif
