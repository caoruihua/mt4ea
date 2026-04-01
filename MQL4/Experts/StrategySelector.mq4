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

// ======================== 最小参数面板（中文说明） ========================
input int      MagicNumber            = 20260313; // 订单魔术号
input int      LogLevel               = 1;        // 日志等级
input int      MaxTradesPerDay        = 8;        // 日内最多开仓次数（上限）
input double   DailyProfitStopUsd     = 50.0;     // 日净收益达到该值后锁定
input int      EMAFastPeriod          = 9;        // 快 EMA 周期
input int      EMASlowPeriod          = 21;       // 慢 EMA 周期
input int      Slippage               = 30;       // 下单滑点
input int      MaxRetries             = 3;        // 执行重试次数

const double   FIXED_LOTS             = 0.01;

// ======================== 全局对象 ========================
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

// 记录“上一根已处理收盘bar时间”，保证新开仓只在新bar评估
datetime           g_lastProcessedClosedBar = 0;

bool FillContext()
{
   double ema9, ema21, atr14, spreadPoints;
   datetime barTime;
   if(!g_signalEngine.BuildCoreSnapshot(ema9, ema21, atr14, spreadPoints, barTime, EMAFastPeriod, EMASlowPeriod))
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
   g_ctx.ema9 = ema9;
   g_ctx.ema21 = ema21;
   g_ctx.atr14 = atr14;
   g_ctx.spreadPoints = spreadPoints;

   g_ctx.fixedLots = FIXED_LOTS;
   g_ctx.slippage = Slippage;
   g_ctx.maxRetries = MaxRetries;

   g_ctx.currentTime = TimeCurrent();
   g_ctx.lastClosedBarTime = barTime;
   return true;
}

int OnInit()
{
   g_logger.Init(LogLevel);

   if(EMAFastPeriod <= 0 || EMASlowPeriod <= 0 || EMAFastPeriod >= EMASlowPeriod)
   {
      g_logger.Error(StringFormat("Invalid EMA settings: fast=%d slow=%d | require fast>0, slow>0, fast<slow", EMAFastPeriod, EMASlowPeriod));
      return(INIT_FAILED);
   }

   g_executor.Init(g_logger);
   g_registry.Init(g_logger);

   g_stateStore.InitDefaults(g_state);
   g_stateStore.Load(g_state);

   g_logger.Info("=== StrategySelector v2.0 initialized ===");
   g_logger.Info(StringFormat("symbol=%s timeframe=%d magic=%d emaFast=%d emaSlow=%d", Symbol(), PERIOD_M5, MagicNumber, EMAFastPeriod, EMASlowPeriod));
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

   // 1) 每tick先同步日风险状态（跨日重置 + 日净收益锁定）
   bool dailyLocked = g_risk.CheckCircuitBreaker(g_ctx, g_state, DailyProfitStopUsd);

   // 2) 每tick都允许持仓保护/平仓检查，不受新开仓锁定影响
   g_executor.ApplyGlobalProfitLockIfNeeded(g_ctx);
   bool closedByProtection = g_executor.CheckStopLossTakeProfit(g_ctx, g_state);
   if(closedByProtection)
      g_stateStore.Save(g_state);

   // 3) 新开仓仅在“新收盘bar”触发一次
   if(g_lastProcessedClosedBar == g_ctx.lastClosedBarTime)
      return;
   g_lastProcessedClosedBar = g_ctx.lastClosedBarTime;

   // 4) 锁定或日内上限达到后，禁止新开仓
   if(dailyLocked)
   {
      g_state.dailyLocked = true;
      g_logger.Info(StringFormat("Entry blocked: daily lock active | closedProfit=%.2f", g_state.dailyClosedProfit));
      g_stateStore.Save(g_state);
      return;
   }
   if(g_state.tradesToday >= MaxTradesPerDay)
   {
      g_logger.Info(StringFormat("Entry blocked: tradesToday=%d reached cap=%d", g_state.tradesToday, MaxTradesPerDay));
      return;
   }

   // 5) 已有持仓则不重复开仓（symbol+magic 单持仓）
   int existingTicket = g_executor.GetCurrentPosition(g_ctx);
   if(existingTicket >= 0)
      return;

   // 6) 市场过滤（趋势/低波动）
   MarketFilterResult filter;
   if(!g_marketState.EvaluateFilter(g_ctx, filter))
      return;
   if(filter.isLowVol || !filter.isTrendValid)
   {
      if(StringLen(filter.blockReason) > 0)
         g_logger.Info(filter.blockReason);
      return;
   }

   // 7) 两策略调度（Pullback 优先）
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

      if(OrderSelect(ticket, SELECT_BY_TICKET))
         g_state.entryPrice = OrderOpenPrice();

      g_stateStore.Save(g_state);
   }
}
