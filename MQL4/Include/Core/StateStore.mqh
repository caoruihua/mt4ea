#ifndef __CORE_STATE_STORE_MQH__
#define __CORE_STATE_STORE_MQH__

/*
 * 文件作用：
 * - 将 RuntimeState 保存到 EA_State.txt
 * - EA 重启后读取状态，保证日内统计可续接
 */

#include "Types.mqh"

class CStateStore
{
public:
   void InitDefaults(RuntimeState &state)
   {
      state.dailyProfit = 0.0;
      state.dailyLoss = 0.0;
      state.dailyPriceDelta = 0.0;
      state.circuitBreakerActive = false;
      state.rangeHigh = 0.0;
      state.rangeLow = 0.0;
      state.breakoutLevel = 0.0;
      state.breakoutDirection = 0;
      state.breakoutRetestActive = false;
      state.asianHigh = 0.0;
      state.asianLow = 0.0;
      state.euroBreakoutState = 0;
      state.lastResetDate = 0;
      state.session1Trades = 0;
      state.session3Trades = 0;
      state.session2Traded = false;
      state.session5Trades = 0;
      state.channelTrades = 0;
      state.fakeBreakoutLow = 0.0;
      state.fakeBreakoutHigh = 0.0;
      state.countersResetDate = 0;
      state.asianRangeDate = 0;
      state.lastEntryBarTime = 0;
      state.lastEntryAttemptBarTime = 0;
   }

   bool Save(const RuntimeState &state)
   {
      int handle = FileOpen("EA_State.txt", FILE_WRITE | FILE_TXT);
      if(handle == INVALID_HANDLE)
         return false;

      FileWrite(handle, "DailyProfit=" + DoubleToString(state.dailyProfit, 2));
      FileWrite(handle, "DailyLoss=" + DoubleToString(state.dailyLoss, 2));
      FileWrite(handle, "DailyPriceDelta=" + DoubleToString(state.dailyPriceDelta, 2));
      FileWrite(handle, "CircuitBreakerActive=" + IntegerToString(state.circuitBreakerActive ? 1 : 0));
      FileWrite(handle, "RangeHigh=" + DoubleToString(state.rangeHigh, Digits));
      FileWrite(handle, "RangeLow=" + DoubleToString(state.rangeLow, Digits));
      FileWrite(handle, "BreakoutLevel=" + DoubleToString(state.breakoutLevel, Digits));
      FileWrite(handle, "BreakoutDirection=" + IntegerToString(state.breakoutDirection));
      FileWrite(handle, "BreakoutRetestActive=" + IntegerToString(state.breakoutRetestActive ? 1 : 0));
      FileWrite(handle, "AsianHigh=" + DoubleToString(state.asianHigh, Digits));
      FileWrite(handle, "AsianLow=" + DoubleToString(state.asianLow, Digits));
      FileWrite(handle, "EuroBreakoutState=" + IntegerToString(state.euroBreakoutState));
      FileWrite(handle, "LastResetDate=" + TimeToString(state.lastResetDate));
      FileWrite(handle, "Session1Trades=" + IntegerToString(state.session1Trades));
      FileWrite(handle, "Session3Trades=" + IntegerToString(state.session3Trades));
      FileWrite(handle, "Session2Traded=" + IntegerToString(state.session2Traded ? 1 : 0));
      FileWrite(handle, "Session5Trades=" + IntegerToString(state.session5Trades));
      FileWrite(handle, "ChannelTrades=" + IntegerToString(state.channelTrades));
      FileWrite(handle, "FakeBreakoutLow=" + DoubleToString(state.fakeBreakoutLow, Digits));
      FileWrite(handle, "FakeBreakoutHigh=" + DoubleToString(state.fakeBreakoutHigh, Digits));
      FileWrite(handle, "CountersResetDate=" + TimeToString(state.countersResetDate));
      FileWrite(handle, "AsianRangeDate=" + TimeToString(state.asianRangeDate));
      FileWrite(handle, "LastEntryBarTime=" + TimeToString(state.lastEntryBarTime));
      FileWrite(handle, "LastEntryAttemptBarTime=" + TimeToString(state.lastEntryAttemptBarTime));
      FileClose(handle);
      return true;
   }

   bool Load(RuntimeState &state)
   {
      int handle = FileOpen("EA_State.txt", FILE_READ | FILE_TXT);
      if(handle == INVALID_HANDLE)
         return false;

      while(!FileIsEnding(handle))
      {
         string line = FileReadString(handle);
         if(line == "")
            continue;

         int pos = StringFind(line, "=");
         if(pos <= 0)
            continue;

         string key = StringSubstr(line, 0, pos);
         string value = StringSubstr(line, pos + 1);

         if(key == "DailyProfit") state.dailyProfit = StringToDouble(value);
         else if(key == "DailyLoss") state.dailyLoss = StringToDouble(value);
         else if(key == "DailyPriceDelta") state.dailyPriceDelta = StringToDouble(value);
         else if(key == "CircuitBreakerActive") state.circuitBreakerActive = (StringToInteger(value) != 0);
         else if(key == "RangeHigh") state.rangeHigh = StringToDouble(value);
         else if(key == "RangeLow") state.rangeLow = StringToDouble(value);
         else if(key == "BreakoutLevel") state.breakoutLevel = StringToDouble(value);
         else if(key == "BreakoutDirection") state.breakoutDirection = (int)StringToInteger(value);
         else if(key == "BreakoutRetestActive") state.breakoutRetestActive = (StringToInteger(value) != 0);
         else if(key == "AsianHigh") state.asianHigh = StringToDouble(value);
         else if(key == "AsianLow") state.asianLow = StringToDouble(value);
         else if(key == "EuroBreakoutState") state.euroBreakoutState = (int)StringToInteger(value);
         else if(key == "LastResetDate") state.lastResetDate = StringToTime(value);
         else if(key == "Session1Trades") state.session1Trades = (int)StringToInteger(value);
         else if(key == "Session3Trades") state.session3Trades = (int)StringToInteger(value);
         else if(key == "Session2Traded") state.session2Traded = (StringToInteger(value) != 0);
         else if(key == "Session5Trades") state.session5Trades = (int)StringToInteger(value);
         else if(key == "ChannelTrades") state.channelTrades = (int)StringToInteger(value);
         else if(key == "FakeBreakoutLow") state.fakeBreakoutLow = StringToDouble(value);
         else if(key == "FakeBreakoutHigh") state.fakeBreakoutHigh = StringToDouble(value);
         else if(key == "CountersResetDate") state.countersResetDate = StringToTime(value);
         else if(key == "AsianRangeDate") state.asianRangeDate = StringToTime(value);
         else if(key == "LastEntryBarTime") state.lastEntryBarTime = StringToTime(value);
         else if(key == "LastEntryAttemptBarTime") state.lastEntryAttemptBarTime = StringToTime(value);
      }

      FileClose(handle);
      return true;
   }
};

#endif
