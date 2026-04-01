#ifndef __CORE_STATE_STORE_MQH__
#define __CORE_STATE_STORE_MQH__

/*
 * 文件作用：
 * - 将 RuntimeState 保存到 EA_State.txt
 * - EA 重启后读取状态，保证日内统计和持仓状态可续接
 * 
 * 持久化原则：
 * - 只保存无法安全重新计算的字段（日统计、入场状态、动态止损止盈状态）
 * - 可重新计算的字段（如市场结构、指标值）不保存
 */

#include "Types.mqh"

class CStateStore
{
public:
   // 初始化运行时状态为默认值
   void InitDefaults(RuntimeState &state)
   {
      state.dayKey = 0;
      state.dailyLocked = false;
      state.dailyClosedProfit = 0.0;
      state.tradesToday = 0;
      state.lastEntryBarTime = 0;
      state.entryPrice = 0.0;
      state.entryAtr = 0.0;
      state.highestCloseSinceEntry = 0.0;
      state.lowestCloseSinceEntry = 0.0;
      state.trailingActive = false;
   }

   // 保存运行时状态到文件
   bool Save(const RuntimeState &state)
   {
      int handle = FileOpen("EA_State.txt", FILE_WRITE | FILE_TXT);
      if(handle == INVALID_HANDLE)
         return false;

      // 日统计与风控状态（重启关键）
      FileWrite(handle, "DayKey=" + TimeToString(state.dayKey));
      FileWrite(handle, "DailyLocked=" + IntegerToString(state.dailyLocked ? 1 : 0));
      FileWrite(handle, "DailyClosedProfit=" + DoubleToString(state.dailyClosedProfit, 2));
      FileWrite(handle, "TradesToday=" + IntegerToString(state.tradesToday));
      
      // 入场状态（重启后需要恢复当前持仓管理）
      FileWrite(handle, "LastEntryBarTime=" + TimeToString(state.lastEntryBarTime));
      FileWrite(handle, "EntryPrice=" + DoubleToString(state.entryPrice, 5));
      FileWrite(handle, "EntryAtr=" + DoubleToString(state.entryAtr, 5));
      
      // 动态止损止盈跟踪状态（重启后需要续接追踪逻辑）
      FileWrite(handle, "HighestCloseSinceEntry=" + DoubleToString(state.highestCloseSinceEntry, 5));
      FileWrite(handle, "LowestCloseSinceEntry=" + DoubleToString(state.lowestCloseSinceEntry, 5));
      FileWrite(handle, "TrailingActive=" + IntegerToString(state.trailingActive ? 1 : 0));
      
      FileClose(handle);
      return true;
   }

   // 从文件加载运行时状态
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

         if(key == "DayKey") state.dayKey = StringToTime(value);
         else if(key == "DailyLocked") state.dailyLocked = (StringToInteger(value) != 0);
         else if(key == "DailyClosedProfit") state.dailyClosedProfit = StringToDouble(value);
         else if(key == "TradesToday") state.tradesToday = (int)StringToInteger(value);
         else if(key == "LastEntryBarTime") state.lastEntryBarTime = StringToTime(value);
         else if(key == "EntryPrice") state.entryPrice = StringToDouble(value);
         else if(key == "EntryAtr") state.entryAtr = StringToDouble(value);
         else if(key == "HighestCloseSinceEntry") state.highestCloseSinceEntry = StringToDouble(value);
         else if(key == "LowestCloseSinceEntry") state.lowestCloseSinceEntry = StringToDouble(value);
         else if(key == "TrailingActive") state.trailingActive = (StringToInteger(value) != 0);
      }

      FileClose(handle);
      return true;
   }
};

#endif