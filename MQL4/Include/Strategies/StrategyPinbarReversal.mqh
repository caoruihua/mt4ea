#ifndef __STRATEGY_PINBAR_REVERSAL_MQH__
#define __STRATEGY_PINBAR_REVERSAL_MQH__

/*
 * 文件作用：
 * - PinBar反转形态策略（纯价格行为）
 * - 前置条件：先有一波≥1.5×ATR的单向运动
 * - 触发条件：出现长影线拒绝PinBar（影线≥2×实体）
 * - 止盈：1.5×ATR
 * - 止损：拐点极值外侧3美元
 * - 优先级：最低（其他策略无信号时才考虑）
 */

#include "../Core/StrategyBase.mqh"

class CStrategyPinbarReversal : public IStrategy
{
private:
   // 参数配置
   int    m_prefetchBars;       // 前置波段检测K线数
   double m_prefetchAtrMult;    // 前置波段最小幅度（ATR倍数）
   double m_wickToBodyRatio;    // 影线与实体比例（≥此值为有效PinBar）
   double m_slOffsetUsd;        // 止损偏移（美元）
   double m_tpAtrMult;          // 止盈倍数（ATR）
   double m_maxOppositeWick;    // 对侧影线最大允许比例（过滤假PinBar）

   bool IsLowVol(const StrategyContext &ctx)
   {
      double atrPoints = (Point > 0.0) ? (ctx.atr14 / Point) : 0.0;
      double spreadPoints = MathMax(ctx.spreadPoints, 0.0);
      double ratio = (spreadPoints > 0.0) ? (atrPoints / spreadPoints) : 9999.0;
      return (atrPoints < ctx.lowVolAtrPointsFloor || ratio < ctx.lowVolAtrSpreadRatioFloor);
   }

    // 检查前置是否有强势下跌（用于多头PinBar）
    // 条件：最近4根K线的高低点距离 ≥ 当前PinBar整体长度的3倍
    bool HadStrongDeclineBefore()
    {
       // 找最近m_prefetchBars根（不含当前bar[1]）的最高点和最低点
       int highestBar = iHighest(NULL, 0, MODE_HIGH, m_prefetchBars, 2);
       int lowestBar = iLowest(NULL, 0, MODE_LOW, m_prefetchBars, 2);
       
       if(highestBar < 0 || lowestBar < 0) 
          return false;
       
       double range = High[highestBar] - Low[lowestBar];
       double pinbarRange = High[1] - Low[1];  // PinBar整体长度（最高到最低）
       
       if(pinbarRange <= 0)
          return false;
       
       // 条件1：4根K线的高低点距离 ≥ PinBar整体长度的3倍
       // 条件2：高点出现在低点之前（先跌后涨才是拐点）
       return (range >= pinbarRange * m_prefetchAtrMult && highestBar > lowestBar);
    }

    // 检查前置是否有强势上涨（用于空头PinBar）
    bool HadStrongRallyBefore()
    {
       int highestBar = iHighest(NULL, 0, MODE_HIGH, m_prefetchBars, 2);
       int lowestBar = iLowest(NULL, 0, MODE_LOW, m_prefetchBars, 2);
       
       if(highestBar < 0 || lowestBar < 0) 
          return false;
       
       double range = High[highestBar] - Low[lowestBar];
       double pinbarRange = High[1] - Low[1];  // PinBar整体长度
       
       if(pinbarRange <= 0)
          return false;
       
       // 低点出现在高点之前（先涨后跌才是拐点）
       return (range >= pinbarRange * m_prefetchAtrMult && lowestBar > highestBar);
    }

   // 多头PinBar：长下影线，收盘在高位
   bool IsBullishPinBar()
   {
      double open1 = Open[1];
      double close1 = Close[1];
      double high1 = High[1];
      double low1 = Low[1];
      
      double body = MathAbs(close1 - open1);
      if(body <= 0) 
         return false;
      
      double upperWick = high1 - MathMax(open1, close1);
      double lowerWick = MathMin(open1, close1) - low1;
      
      // 条件1：下影线 ≥ m_wickToBodyRatio × 实体（长下影）
      // 条件2：上影线 ≤ m_maxOppositeWick × 实体（短上影）
      // 条件3：收盘 > 开盘（阳线）
      return (lowerWick >= body * m_wickToBodyRatio && 
              upperWick <= body * m_maxOppositeWick && 
              close1 > open1);
   }

   // 空头PinBar：长上影线，收盘在低位
   bool IsBearishPinBar()
   {
      double open1 = Open[1];
      double close1 = Close[1];
      double high1 = High[1];
      double low1 = Low[1];
      
      double body = MathAbs(close1 - open1);
      if(body <= 0) 
         return false;
      
      double upperWick = high1 - MathMax(open1, close1);
      double lowerWick = MathMin(open1, close1) - low1;
      
      // 条件1：上影线 ≥ m_wickToBodyRatio × 实体（长上影）
      // 条件2：下影线 ≤ m_maxOppositeWick × 实体（短下影）
      // 条件3：收盘 < 开盘（阴线）
      return (upperWick >= body * m_wickToBodyRatio && 
              lowerWick <= body * m_maxOppositeWick && 
              close1 < open1);
   }

   void BuildInitialSLTP(int orderType, const StrategyContext &ctx, double atr, double &sl, double &tp)
   {
      double slOffset = m_slOffsetUsd;  // 3美元偏移
      double tpDist = atr * m_tpAtrMult;  // 1.5×ATR止盈
      
      if(orderType == OP_BUY)
      {
         // 多头止损：PinBar最低点 - 3美元
         double slPrice = Low[1] - slOffset;
         sl = NormalizeDouble(slPrice, ctx.digits);
         tp = NormalizeDouble(ctx.ask + tpDist, ctx.digits);
      }
      else
      {
         // 空头止损：PinBar最高点 + 3美元
         double slPrice = High[1] + slOffset;
         sl = NormalizeDouble(slPrice, ctx.digits);
         tp = NormalizeDouble(ctx.bid - tpDist, ctx.digits);
      }
   }

public:
   // 构造函数：设置默认参数
   CStrategyPinbarReversal()
   {
      m_prefetchBars = 4;           // 前置4根K线
       m_prefetchAtrMult = 2.0;      // 前置波段≥PinBar整体长度2倍
      m_wickToBodyRatio = 2.0;      // 影线≥2倍实体
      m_slOffsetUsd = 3.0;          // 止损外侧3美元
      m_tpAtrMult = 1.5;            // 止盈1.5×ATR
      m_maxOppositeWick = 0.5;      // 对侧影线≤0.5倍实体
   }

   virtual string Name() { return "PinbarReversal"; }

   virtual bool CanTrade(StrategyContext &ctx, RuntimeState &state)
   {
      // 中文说明：同一根K线只允许一次入场，且已有持仓时不重复入场
      if(state.lastEntryBarTime == ctx.lastClosedBarTime)
         return false;
      if(IsLowVol(ctx))
         return false;
      return true;
   }

   virtual bool GenerateSignal(StrategyContext &ctx, RuntimeState &state, TradeSignal &signal)
   {
      ResetSignal(signal);

      if(!CanTrade(ctx, state))
         return false;

      if(Bars < m_prefetchBars + 2)
      {
         signal.reason = "blocked: insufficient bars";
         return false;
      }

      double atr = ctx.atr14;
      if(atr <= 0)
      {
         signal.reason = "blocked: invalid atr";
         return false;
      }

      // 中文说明：多头PinBar反转条件
      // 1) 前置波段：最近4根K线的高低点距离 ≥ 当前K线实体的3倍
      // 2) 当前K线：长下影线PinBar（影线≥2倍实体），收盘在高位
      // 3) 止损：PinBar最低点 - 3美元
      // 4) 止盈：1.5×ATR
      if(HadStrongDeclineBefore() && IsBullishPinBar())
      {
         signal.valid = true;
         signal.strategyId = STRATEGY_PINBAR_REVERSAL;
         signal.orderType = OP_BUY;
         signal.lots = ctx.fixedLots;
         signal.priority = 1;  // 最低优先级
         BuildInitialSLTP(OP_BUY, ctx, atr, signal.stopLoss, signal.takeProfit);
         signal.comment = "PinbarReversal-Long";
         signal.reason = "bullish pinbar after strong decline";
         return true;
      }

      // 中文说明：空头PinBar反转条件（与多头镜像）
      // 1) 前置波段：最近4根K线的高低点距离 ≥ 当前K线实体的3倍
      // 2) 当前K线：长上影线PinBar（影线≥2倍实体），收盘在低位
      if(HadStrongRallyBefore() && IsBearishPinBar())
      {
         signal.valid = true;
         signal.strategyId = STRATEGY_PINBAR_REVERSAL;
         signal.orderType = OP_SELL;
         signal.lots = ctx.fixedLots;
         signal.priority = 1;  // 最低优先级
         BuildInitialSLTP(OP_SELL, ctx, atr, signal.stopLoss, signal.takeProfit);
         signal.comment = "PinbarReversal-Short";
         signal.reason = "bearish pinbar after strong rally";
         return true;
      }

      signal.reason = "blocked: no valid pinbar setup";
      return false;
   }
};

#endif
