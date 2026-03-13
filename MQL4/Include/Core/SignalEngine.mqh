#ifndef __CORE_SIGNAL_ENGINE_MQH__
#define __CORE_SIGNAL_ENGINE_MQH__

/*
 * 文件作用：
 * - 封装常用指标读取：EMA/RSI/MACD
 * - 封装统一 SL/TP 构建逻辑（按价格差美元）
 */

class CSignalEngine
{
public:
   double GetEMA(int period, int shift)
   {
      ResetLastError();
      double val = iMA(Symbol(), PERIOD_M5, period, 0, MODE_EMA, PRICE_CLOSE, shift);
      if(GetLastError() != 0)
         return -1.0;
      return val;
   }

   double GetRSI(int shift)
   {
      ResetLastError();
      double val = iRSI(Symbol(), PERIOD_M5, 14, PRICE_CLOSE, shift);
      if(GetLastError() != 0)
         return -1.0;
      return val;
   }

   double GetMACD(int shift)
   {
      ResetLastError();
      double val = iMACD(Symbol(), PERIOD_M5, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, shift);
      if(GetLastError() != 0)
         return -1.0;
      return val;
   }

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
