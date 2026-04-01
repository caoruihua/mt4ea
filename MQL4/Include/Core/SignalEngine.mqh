#ifndef __CORE_SIGNAL_ENGINE_MQH__
#define __CORE_SIGNAL_ENGINE_MQH__

/*
 * 文件作用：
 * - 统一提供两策略内核需要的最小指标输入
    * - 只保留快/慢 EMA、ATR14、点差、已收盘K线时间
 *
 * 说明：
 * - 指标统一基于 M5 和已收盘K线（默认 shift=1）
 * - 不在这里做策略判断，只做“数据采集与标准化”
 */

class CSignalEngine
{
public:
   double GetEMA(int period, int shift)
   {
      ResetLastError();
      double v = iMA(Symbol(), PERIOD_M5, period, 0, MODE_EMA, PRICE_CLOSE, shift);
      if(GetLastError() != 0)
         return -1.0;
      return v;
   }

   double GetATR(int shift)
   {
      ResetLastError();
      double v = iATR(Symbol(), PERIOD_M5, 14, shift);
      if(GetLastError() != 0)
         return -1.0;
      return v;
   }

   // 读取两策略内核的最小指标快照（基于已收盘K线）
   bool BuildCoreSnapshot(double &emaFast, double &emaSlow, double &atr14, double &spreadPoints, datetime &barTime, int emaFastPeriod, int emaSlowPeriod)
   {
      emaFast = GetEMA(emaFastPeriod, 1);
      emaSlow = GetEMA(emaSlowPeriod, 1);
      atr14 = GetATR(1);
      spreadPoints = (Ask - Bid) / Point;
      barTime = iTime(Symbol(), PERIOD_M5, 1);

      if(emaFast <= 0 || emaSlow <= 0 || atr14 <= 0 || spreadPoints < 0 || barTime <= 0)
         return false;
      return true;
   }

   // 兼容旧接口（后续任务会删除旧调用）
   double GetRSI(int shift) { return iRSI(Symbol(), PERIOD_M5, 14, PRICE_CLOSE, shift); }
   double GetMACD(int shift) { return iMACD(Symbol(), PERIOD_M5, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, shift); }
   double GetADX(int shift) { return iADX(Symbol(), PERIOD_M5, 14, PRICE_CLOSE, MODE_MAIN, shift); }

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
};

#endif
