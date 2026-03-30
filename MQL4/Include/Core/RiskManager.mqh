#ifndef __CORE_RISK_MANAGER_MQH__
#define __CORE_RISK_MANAGER_MQH__

/*
 * 文件作用：
 * - 统一风控：日盈利/日亏损熔断
 * - 日切重置（01:00 北京时间）
 * - 各会话计数器日内重置
 */

#include "Types.mqh"

class CRiskManager
{
public:
   bool CheckCircuitBreaker(StrategyContext &ctx, RuntimeState &state)
   {
      if(state.dailyPriceDelta >= ctx.dailyPriceDeltaTarget)
      {
         state.circuitBreakerActive = true;
         return true;
      }

      if(state.dailyProfit >= ctx.profitThresholdUsd)
      {
         state.circuitBreakerActive = true;
         return true;
      }

      double lossThreshold = AccountBalance() * ctx.lossThresholdPercent / 100.0;
      if(state.dailyLoss >= lossThreshold)
      {
         state.circuitBreakerActive = true;
         return true;
      }

      return false;
   }

   datetime DateOnly(datetime t)
   {
      return StringToTime(TimeToStr(t, TIME_DATE));
   }

   bool NeedDailyReset(datetime bjTime, RuntimeState &state)
   {
      int h = TimeHour(bjTime);
      int m = TimeMinute(bjTime);
      if(h != 1 || m != 0)
         return false;

      datetime currentDate = DateOnly(bjTime);
      return state.lastResetDate != currentDate;
   }

   void DoDailyReset(datetime bjTime, RuntimeState &state)
   {
      datetime currentDate = DateOnly(bjTime);
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
      state.lastResetDate = currentDate;
      state.dayExtremeDate = currentDate;
      state.dayHigh = 0.0;
      state.dayLow = 0.0;
      state.channelPullbackStage = PULLBACK_BASE_STAGE_IDLE;
      state.channelSetupTime = 0;
      state.channelPullbackHigh = 0.0;
      state.channelSupportLevel = 0.0;
      state.channelFailedBreakdownCount = 0;
      state.channelBaseBarCount = 0;
      state.channelBaseCloseAverage = 0.0;
      state.channelRecoveryLevel = 0.0;
      state.channelLastBaseBarTime = 0;
   }

   void ResetDailyCounters(datetime bjTime, RuntimeState &state)
   {
      datetime currentDate = DateOnly(bjTime);
      if(state.countersResetDate == currentDate)
         return;

      state.session1Trades = 0;
      state.session3Trades = 0;
      state.session2Traded = false;
      state.session5Trades = 0;
      state.channelTrades = 0;
      state.fakeBreakoutLow = 0.0;
      state.fakeBreakoutHigh = 0.0;
      state.dayExtremeDate = currentDate;
      state.dayHigh = 0.0;
      state.dayLow = 0.0;
      state.rangeHigh = 0.0;
      state.rangeLow = 0.0;
      state.breakoutLevel = 0.0;
      state.breakoutDirection = 0;
      state.breakoutRetestActive = false;
      state.asianRangeDate = 0;
      state.channelPullbackStage = PULLBACK_BASE_STAGE_IDLE;
      state.channelSetupTime = 0;
      state.channelPullbackHigh = 0.0;
      state.channelSupportLevel = 0.0;
      state.channelFailedBreakdownCount = 0;
      state.channelBaseBarCount = 0;
      state.channelBaseCloseAverage = 0.0;
      state.channelRecoveryLevel = 0.0;
      state.channelLastBaseBarTime = 0;
      state.countersResetDate = currentDate;
   }
};

#endif
