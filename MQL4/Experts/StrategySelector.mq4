//+------------------------------------------------------------------+
//|                                              StrategySelector.mq4 |
//|                  Gold Two-Strategy Minimal Kernel (Task8)         |
//+------------------------------------------------------------------+
#property strict
#property version   "2.0"
#property description "XAUUSD minimal two-strategy kernel (configurable EMA + ATR14)"

#include "../Include/Core/Types.mqh"
#include "../Include/Core/Logger.mqh"
#include "../Include/Core/SessionClock.mqh"
#include "../Include/Core/SignalEngine.mqh"
#include "../Include/Core/StateStore.mqh"
#include "../Include/Core/MarketState.mqh"
#include "../Include/Core/RiskManager.mqh"
#include "../Include/Core/TradeExecutor.mqh"
#include "../Include/Core/StrategyRegistry.mqh"

input int      MagicNumber               = 20260313;
input int      LogLevel                  = 1;
input int      MaxTradesPerDay           = 30;
input double   DailyProfitStopUsd        = 50.0;
input double   DailyLossStopUsd          = 40.0;
input double   FixedLots                 = 0.01;
input int      EMAFastPeriod             = 9;
input int      EMASlowPeriod             = 21;
input double   LowVolAtrPointsFloor      = 300.0;
input double   LowVolAtrSpreadRatioFloor = 3.0;
input bool     EnableSecondLegLongFilter = true;
input bool     EnableSecondLegShortFilter = true;
input double   SecondLegMinSpaceAtr      = 1.0;
input double   SecondLegPullbackMinAtr   = 0.3;
input int      SecondLegMinPullbackBars  = 2;
input int      SecondLegBaseMinBars      = 2;
input double   SecondLegBaseMaxRangeAtr  = 1.2;
input double   SecondLegReclaimRatio     = 0.5;
input int      SecondLegSwingLookbackBars = 20;
input int      Slippage                  = 30;
input int      MaxRetries                = 6;

CLogger            g_logger;
CSessionClock      g_clock;
CSignalEngine      g_signalEngine;
CStateStore        g_stateStore;
CMarketStateEngine g_marketState;
CRiskManager       g_risk;
CTradeExecutor     g_executor;
CStrategyRegistry  g_registry;

StrategyContext    g_ctx;
RuntimeState       g_state;

datetime           g_lastProcessedClosedBar = 0;
datetime           g_lastHeartbeatMinute = 0;

bool FillContext()
{
   double emaFast, emaSlow, atr14, spreadPoints;
   datetime barTime;
   if(!g_signalEngine.BuildCoreSnapshot(emaFast, emaSlow, atr14, spreadPoints, barTime, EMAFastPeriod, EMASlowPeriod))
      return false;

   g_ctx.symbol = Symbol();
   g_ctx.timeframe = PERIOD_M5;
   g_ctx.digits = Digits;
   g_ctx.magicNumber = MagicNumber;
   g_ctx.logLevel = LogLevel;

   g_ctx.bid = Bid;
   g_ctx.ask = Ask;
   g_ctx.emaFastPeriod = EMAFastPeriod;
   g_ctx.emaSlowPeriod = EMASlowPeriod;
   g_ctx.emaFast = emaFast;
   g_ctx.emaSlow = emaSlow;
   g_ctx.atr14 = atr14;
   g_ctx.spreadPoints = spreadPoints;
   g_ctx.lowVolAtrPointsFloor = LowVolAtrPointsFloor;
   g_ctx.lowVolAtrSpreadRatioFloor = LowVolAtrSpreadRatioFloor;

   g_ctx.enableSecondLegLongFilter = EnableSecondLegLongFilter;
   g_ctx.enableSecondLegShortFilter = EnableSecondLegShortFilter;
   g_ctx.secondLegMinSpaceAtr = SecondLegMinSpaceAtr;
   g_ctx.secondLegPullbackMinAtr = SecondLegPullbackMinAtr;
   g_ctx.secondLegMinPullbackBars = SecondLegMinPullbackBars;
   g_ctx.secondLegBaseMinBars = SecondLegBaseMinBars;
   g_ctx.secondLegBaseMaxRangeAtr = SecondLegBaseMaxRangeAtr;
   g_ctx.secondLegReclaimRatio = SecondLegReclaimRatio;
   g_ctx.secondLegSwingLookbackBars = SecondLegSwingLookbackBars;

   g_ctx.fixedLots = FixedLots;
   g_ctx.slippage = Slippage;
   g_ctx.maxRetries = MaxRetries;

   g_ctx.currentTime = TimeCurrent();
   g_ctx.lastClosedBarTime = barTime;
   return true;
}

void PrintHeartbeat()
{
   datetime now = TimeLocal();
   datetime currentMinute = now - (now % 60);

   if(currentMinute == g_lastHeartbeatMinute)
      return;

   g_lastHeartbeatMinute = currentMinute;

   int ticket = g_executor.GetCurrentPosition(g_ctx);
   string posInfo = (ticket >= 0) ? StringFormat("持仓票据=%d", ticket) : "无持仓";

   g_logger.Info(StringFormat(
      "[心跳] 品种=%s 时间=%s 点差=%.1f EMA9=%.2f EMA21=%.2f ATR14=%.2f 今日交易=%d 日锁定=%s %s",
      g_ctx.symbol,
      TimeToStr(now, TIME_DATE|TIME_SECONDS),
      g_ctx.spreadPoints,
      g_ctx.emaFast,
      g_ctx.emaSlow,
      g_ctx.atr14,
      g_state.tradesToday,
      g_state.dailyLocked ? "是" : "否",
      posInfo
   ));
}

int OnInit()
{
   g_logger.Init(LogLevel);

   if(FixedLots <= 0.0)
   {
      g_logger.Error(StringFormat("Invalid fixed lots: %.2f | require > 0", FixedLots));
      return(INIT_FAILED);
   }

   if(EMAFastPeriod <= 0 || EMASlowPeriod <= 0 || EMAFastPeriod >= EMASlowPeriod)
   {
      g_logger.Error(StringFormat("Invalid EMA settings: fast=%d slow=%d | require fast>0, slow>0, fast<slow", EMAFastPeriod, EMASlowPeriod));
      return(INIT_FAILED);
   }

   if(SecondLegMinSpaceAtr < 0.0 || SecondLegPullbackMinAtr < 0.0 ||
      SecondLegMinPullbackBars < 1 || SecondLegBaseMinBars < 1 ||
      SecondLegBaseMaxRangeAtr <= 0.0 || SecondLegReclaimRatio <= 0.0 ||
      SecondLegReclaimRatio >= 1.0 || SecondLegSwingLookbackBars < 5)
   {
      g_logger.Error(StringFormat(
         "Invalid second-leg filter settings: minSpaceAtr=%.2f pullbackMinAtr=%.2f minPullbackBars=%d baseMinBars=%d baseMaxRangeAtr=%.2f reclaimRatio=%.2f swingLookback=%d",
         SecondLegMinSpaceAtr,
         SecondLegPullbackMinAtr,
         SecondLegMinPullbackBars,
         SecondLegBaseMinBars,
         SecondLegBaseMaxRangeAtr,
         SecondLegReclaimRatio,
         SecondLegSwingLookbackBars));
      return(INIT_FAILED);
   }

   g_executor.Init(g_logger);
   g_registry.Init(g_logger);

   g_stateStore.InitDefaults(g_state);
   g_stateStore.Load(g_state);

   g_logger.Info("=== StrategySelector v2.0 initialized ===");
   g_logger.Info(StringFormat("symbol=%s timeframe=%d magic=%d emaFast=%d emaSlow=%d", Symbol(), PERIOD_M5, MagicNumber, EMAFastPeriod, EMASlowPeriod));
   int strategyCount = g_registry.GetRegisteredStrategyCount();
   for(int i = 0; i < strategyCount; i++)
      g_logger.Info(StringFormat("strategy[%d]=%s", i, g_registry.GetStrategySummaryByIndex(i)));
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   g_stateStore.Save(g_state);
}

void OnTick()
{
   if(!FillContext())
      return;

   PrintHeartbeat();

   bool dailyLocked = g_risk.CheckCircuitBreaker(g_ctx, g_state, DailyProfitStopUsd, DailyLossStopUsd);

   g_executor.ApplyGlobalProfitLockIfNeeded(g_ctx);
   bool closedByProtection = g_executor.CheckStopLossTakeProfit(g_ctx, g_state);
   if(closedByProtection)
      g_stateStore.Save(g_state);

   bool closedByServer = g_executor.DetectServerClosedPosition(g_ctx, g_state, g_state.lastTicket);
   if(closedByServer)
      g_stateStore.Save(g_state);

   if(g_lastProcessedClosedBar == g_ctx.lastClosedBarTime)
      return;
   g_lastProcessedClosedBar = g_ctx.lastClosedBarTime;

   if(dailyLocked)
   {
      g_state.dailyLocked = true;
      g_logger.Info(StringFormat("[风控] 日风控触发（盈亏锁定），禁止新开仓 | 已平仓=%.2f", g_state.dailyClosedProfit));
      g_stateStore.Save(g_state);
      return;
   }
   if(g_state.tradesToday >= MaxTradesPerDay)
   {
      g_logger.Info(StringFormat("Entry blocked: tradesToday=%d reached cap=%d", g_state.tradesToday, MaxTradesPerDay));
      return;
   }

   int existingTicket = g_executor.GetCurrentPosition(g_ctx);
   g_state.lastTicket = existingTicket;
   if(existingTicket >= 0)
      return;

   MarketFilterResult filter;
   if(!g_marketState.EvaluateFilter(g_ctx, filter))
      return;
   if(filter.isLowVol)
   {
      if(StringLen(filter.blockReason) > 0)
         g_logger.Info(filter.blockReason);
      return;
   }

   TradeSignal best;
   if(!g_registry.EvaluateBestSignal(g_ctx, g_state, best) || !best.valid)
      return;

   int ticket = g_executor.OpenOrder(g_ctx, best);
   if(ticket > 0)
   {
      g_state.tradesToday++;
      g_state.lastEntryBarTime = g_ctx.lastClosedBarTime;
      g_state.entryAtr = g_ctx.atr14;
      g_state.trailingActive = false;
      g_state.highestCloseSinceEntry = Close[1];
      g_state.lowestCloseSinceEntry = Close[1];
      g_state.lastTicket = ticket;

      if(OrderSelect(ticket, SELECT_BY_TICKET))
         g_state.entryPrice = OrderOpenPrice();

      g_stateStore.Save(g_state);
   }
}
