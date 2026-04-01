#ifndef __CORE_RISK_MANAGER_MQH__
#define __CORE_RISK_MANAGER_MQH__

/*
 * 文件作用：
 * - 统一管理“日内风险锁定”逻辑
 * - 基于服务器日期日键做跨日重置（不依赖固定分钟）
 * - 从历史已平仓订单计算当日净收益（含 commission/swap）
 */

#include "Types.mqh"

class CRiskManager
{
private:
   // 仅保留日期（00:00:00），作为“服务器日键”
   datetime BuildServerDayKey(datetime serverTime)
   {
      if(serverTime <= 0)
         serverTime = TimeCurrent();
      return StringToTime(TimeToStr(serverTime, TIME_DATE));
   }

   // 统计当日已平仓净收益：OrderProfit + OrderSwap + OrderCommission
   // 说明：
   // - 只统计当前 symbol + magic 的历史单
   // - 只统计“本服务器日键”范围内已平仓订单
   // - 不计浮动盈亏，避免锁定状态随行情抖动
   double CalcTodayClosedNetProfit(const StrategyContext &ctx, datetime dayKey)
   {
      if(dayKey <= 0)
         return 0.0;

      datetime nextDayKey = dayKey + 86400;
      double total = 0.0;
      int totalHistory = OrdersHistoryTotal();

      for(int i = 0; i < totalHistory; i++)
      {
         if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
            continue;

         if(OrderSymbol() != ctx.symbol)
            continue;
         if(OrderMagicNumber() != ctx.magicNumber)
            continue;

         datetime closeTime = OrderCloseTime();
         if(closeTime < dayKey || closeTime >= nextDayKey)
            continue;

         total += (OrderProfit() + OrderSwap() + OrderCommission());
      }

      return total;
   }

public:
   // 对外保留旧接口名，避免当前主流程改动过大
   // 作用：更新日状态并判断是否需要阻止新开仓
   bool CheckCircuitBreaker(StrategyContext &ctx, RuntimeState &state)
   {
      datetime nowServer = TimeCurrent();
      datetime currentDayKey = BuildServerDayKey(nowServer);

      // 跨日时重置：不依赖固定分钟，第一笔tick即可生效
      if(state.dayKey != currentDayKey)
      {
         state.dayKey = currentDayKey;
         state.dailyLocked = false;
         state.dailyClosedProfit = 0.0;
         state.tradesToday = 0;
      }

      // 每个tick按历史已平仓单回算，保证重启后状态一致
      state.dailyClosedProfit = CalcTodayClosedNetProfit(ctx, state.dayKey);

      // 达到日收益目标即锁定：当天禁止新开仓
      if(state.dailyClosedProfit >= 50.0)
         state.dailyLocked = true;

      return state.dailyLocked;
   }

   // 兼容旧调用：保留函数，但语义改为“日键变化即重置”
   bool NeedDailyReset(datetime serverTime, RuntimeState &state)
   {
      datetime currentDayKey = BuildServerDayKey(serverTime);
      return (state.dayKey != currentDayKey);
   }

   // 兼容旧调用：仅重置 task2 允许的最小字段
   void DoDailyReset(datetime serverTime, RuntimeState &state)
   {
      state.dayKey = BuildServerDayKey(serverTime);
      state.dailyLocked = false;
      state.dailyClosedProfit = 0.0;
      state.tradesToday = 0;
   }

   // 兼容旧调用：内部复用同一日键重置逻辑
   void ResetDailyCounters(datetime serverTime, RuntimeState &state)
   {
      if(NeedDailyReset(serverTime, state))
         DoDailyReset(serverTime, state);
   }
};

#endif
