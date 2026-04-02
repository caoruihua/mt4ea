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
input int      MaxTradesPerDay        = 30;       // 日内最多开仓次数（上限）
input double   DailyProfitStopUsd     = 50.0;     // 日净收益达到该值后锁定
input int      EMAFastPeriod          = 9;        // 快 EMA 周期
input int      EMASlowPeriod          = 21;       // 慢 EMA 周期
input int      Slippage               = 30;       // 下单滑点
input int      MaxRetries             = 6;        // 执行重试次数

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

// 记录"上一根已处理收盘bar时间"，保证新开仓只在新bar评估
datetime           g_lastProcessedClosedBar = 0;

// 心跳日志：记录上一次打印心跳的分钟时间（按本地时间），用于每分钟打印一次心跳
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

   g_ctx.fixedLots = FIXED_LOTS;
   g_ctx.slippage = Slippage;
   g_ctx.maxRetries = MaxRetries;

   g_ctx.currentTime = TimeCurrent();
   g_ctx.lastClosedBarTime = barTime;
   return true;
}

// 打印心跳日志：每分钟最多打印一次，包含详版运行状态
void PrintHeartbeat()
{
   datetime now = TimeLocal();
   // 取当前时间的分钟部分（去掉秒），用于判重
   datetime currentMinute = now - (now % 60);
   
   if(currentMinute == g_lastHeartbeatMinute)
      return; // 同一分钟内已经打印过
   
   g_lastHeartbeatMinute = currentMinute;
   
   // 获取持仓信息
   int ticket = g_executor.GetCurrentPosition(g_ctx);
   string posInfo = (ticket >= 0) ? StringFormat("持仓票据=%d", ticket) : "无持仓";
   
   // 打印详版心跳日志
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
   
   // 心跳日志：每分钟打印一次详版运行状态
   PrintHeartbeat();

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

   // 6) 市场过滤（低波动全局阻断；趋势有效性由各策略自行判断）
   MarketFilterResult filter;
   if(!g_marketState.EvaluateFilter(g_ctx, filter))
      return;
   if(filter.isLowVol)
   {
      if(StringLen(filter.blockReason) > 0)
         g_logger.Info(filter.blockReason);
      return;
   }

   // 7) 三策略调度（ExpansionFollow -> Pullback -> TrendContinuation）
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
