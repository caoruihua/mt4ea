//+------------------------------------------------------------------+
//|                                              StrategySelector.mq4 |
//|                 Engineering Modular EA (keep legacy file intact)  |
//+------------------------------------------------------------------+
/*
 * 文件作用：
 * 1) 主EA入口（OnInit/OnTick/OnDeinit）
 * 2) 组装 Core 模块：状态识别、状态稳定、风控、执行、策略注册
 * 3) 将输入参数写入 StrategyContext，交给策略模块生成信号
 * 4) 不改动旧版 XAUUSD_MultiSession_Strategy.mq4，作为并行新架构
 */
#property strict
#property version   "1.0"
#property description "Modular Strategy Selector EA"

#include "../Include/Core/Types.mqh"
#include "../Include/Core/Logger.mqh"
#include "../Include/Core/SessionClock.mqh"
#include "../Include/Core/SignalEngine.mqh"
#include "../Include/Core/StateStore.mqh"
#include "../Include/Core/StateStabilizer.mqh"
#include "../Include/Core/MarketState.mqh"
#include "../Include/Core/RiskManager.mqh"
#include "../Include/Core/TradeExecutor.mqh"
#include "../Include/Core/StrategyRegistry.mqh"

//--- Inputs（与旧EA语义保持一致）
input int      TimeZoneOffset = 6;        // 时区偏移：服务器时间 + offset = 北京时间
input int      MagicNumber    = 20260313; // 订单魔术号：用于区分本EA订单
input int      LogLevel       = 1;        // 日志级别：0=少量，1=信息，2=调试

// 价格差参数均为“图表价格差美元”（例如 XAUUSD 3000->3015 为 +15）
input double   Session1_3_SL_USD                  = 10.0; // Session1/3 固定止损
input double   Session1_3_TP_USD                  = 15.0; // Session1/3 固定止盈
input double   Session2_SL_USD                    = 10.0; // Session2 首K突破跟随止损
input double   Session2_TP_USD                    = 15.0; // Session2 首K突破跟随止盈
input double   Session4_MinRange_USD              = 8.0;  // Session4 区间最小宽度门槛
input double   Session4_EntryBuffer_USD           = 3.0;  // Session4 边界触发缓冲
input double   Session4_SL_Buffer_USD             = 5.0;  // Session4 SL放在区间外的缓冲
input double   Session4_TP_USD                    = 15.0; // Session4 固定止盈
input double   Session5_FakeBreakout_Trigger_USD  = 3.0;  // Session5 假突破触发阈值
input double   Session5_ValidBreakout_Trigger_USD = 5.0;  // Session5 真突破触发阈值
input double   Session5_SL_USD                    = 15.0; // Session5 止损
input double   Session5_TP_USD                    = 30.0; // Session5 止盈
input double   Session5_EMA_Tolerance_USD         = 2.0;  // Session5 EMA回踩容差
input double   Session6_MinBody_USD               = 5.0;  // Session6 动量实体最小阈值
input double   Session6_SL_USD                    = 20.0; // Session6 止损
input double   Session6_TP_USD                    = 45.0; // Session6 止盈

const double   FIXED_LOTS             = 0.01; // 固定手数（后续可改动态仓位）
const double   PROFIT_THRESHOLD_USD   = 50.0; // 日盈利熔断阈值
const double   LOSS_THRESHOLD_PERCENT = 3.0;  // 日亏损熔断阈值（余额百分比）
const int      SLIPPAGE               = 30;   // 允许滑点
const int      MAX_RETRIES            = 3;    // 下单/平仓最大重试次数

//--- Modules
CLogger            g_logger;
CSessionClock      g_clock;
CSignalEngine      g_signalEngine;
CStateStore        g_stateStore;
CStateStabilizer   g_stabilizer;
CMarketStateEngine g_marketState;
CRiskManager       g_risk;
CTradeExecutor     g_executor;
CStrategyRegistry  g_registry;

StrategyContext    g_ctx;
RuntimeState       g_state;

void FillContext()
{
   // 将运行环境与参数统一写入上下文，供策略模块无状态读取
   g_ctx.symbol = Symbol();
   g_ctx.timeframe = Period();
   g_ctx.digits = Digits;
   g_ctx.magicNumber = MagicNumber;
   g_ctx.logLevel = LogLevel;
   g_ctx.timeZoneOffset = TimeZoneOffset;

   g_ctx.bid = Bid;
   g_ctx.ask = Ask;

   g_ctx.ema20 = g_signalEngine.GetEMA(20, 1);
   g_ctx.ema50 = g_signalEngine.GetEMA(50, 1);
   g_ctx.rsi = g_signalEngine.GetRSI(1);
   g_ctx.macd = g_signalEngine.GetMACD(1);

   g_ctx.beijingTime = g_clock.GetBeijingTime(TimeZoneOffset);
   g_ctx.sessionId = g_clock.GetCurrentSession(g_ctx.beijingTime);
   g_ctx.regime = REGIME_UNKNOWN;

   g_ctx.fixedLots = FIXED_LOTS;
   g_ctx.profitThresholdUsd = PROFIT_THRESHOLD_USD;
   g_ctx.lossThresholdPercent = LOSS_THRESHOLD_PERCENT;
   g_ctx.slippage = SLIPPAGE;
   g_ctx.maxRetries = MAX_RETRIES;

   g_ctx.session1_3_sl_usd = Session1_3_SL_USD;
   g_ctx.session1_3_tp_usd = Session1_3_TP_USD;
   g_ctx.session2_sl_usd = Session2_SL_USD;
   g_ctx.session2_tp_usd = Session2_TP_USD;
   g_ctx.session4_minRange_usd = Session4_MinRange_USD;
   g_ctx.session4_entryBuffer_usd = Session4_EntryBuffer_USD;
   g_ctx.session4_slBuffer_usd = Session4_SL_Buffer_USD;
   g_ctx.session4_tp_usd = Session4_TP_USD;
   g_ctx.session5_fakeBreakout_trigger_usd = Session5_FakeBreakout_Trigger_USD;
   g_ctx.session5_validBreakout_trigger_usd = Session5_ValidBreakout_Trigger_USD;
   g_ctx.session5_sl_usd = Session5_SL_USD;
   g_ctx.session5_tp_usd = Session5_TP_USD;
   g_ctx.session5_emaTolerance_usd = Session5_EMA_Tolerance_USD;
   g_ctx.session6_minBody_usd = Session6_MinBody_USD;
   g_ctx.session6_sl_usd = Session6_SL_USD;
   g_ctx.session6_tp_usd = Session6_TP_USD;
}

void UpdateAsianRange()
{
   // Session4（08:00-15:00）更新亚洲区间高低点
   if(g_ctx.sessionId != 4)
      return;

   datetime currentDate = StringToTime(TimeToStr(g_ctx.beijingTime, TIME_DATE));
   int hour = TimeHour(g_ctx.beijingTime);

   if(hour == 8 && g_state.asianRangeDate != currentDate)
   {
      g_state.asianHigh = High[0];
      g_state.asianLow = Low[0];
      g_state.asianRangeDate = currentDate;
   }

   if(hour >= 8 && hour < 15)
   {
      if(High[0] > g_state.asianHigh) g_state.asianHigh = High[0];
      if(Low[0] < g_state.asianLow)  g_state.asianLow = Low[0];
   }
}

void UpdateCountersAfterOpen(const TradeSignal &sig)
{
   // 统一更新日内策略计数，避免每个策略重复维护计数逻辑
   if(g_ctx.sessionId == 1 && sig.strategyId == STRATEGY_LINEAR_TREND)
      g_state.session1Trades++;
   else if(g_ctx.sessionId == 3 && sig.strategyId == STRATEGY_LINEAR_TREND)
      g_state.session3Trades++;
   else if(g_ctx.sessionId == 2 && sig.strategyId == STRATEGY_BREAKOUT)
      g_state.session2Traded = true;
   else if(g_ctx.sessionId == 5 && (sig.strategyId == STRATEGY_BREAKOUT || sig.strategyId == STRATEGY_REVERSAL))
      g_state.session5Trades++;

   if(g_ctx.sessionId == 5)
   {
      if(sig.orderType == OP_BUY) g_state.euroBreakoutState = 1;
      if(sig.orderType == OP_SELL) g_state.euroBreakoutState = 2;
   }
}

void SessionTimeRules()
{
   // 会话级时间规则（目前保留 Session2 在 07:15 强平）
   int h = TimeHour(g_ctx.beijingTime);
   int m = TimeMinute(g_ctx.beijingTime);

   // Force close at 07:15 for Session2
   if(h == 7 && m == 15)
   {
      int ticket = g_executor.GetCurrentPosition(g_ctx);
      if(ticket > 0)
         g_executor.CloseOrder(g_ctx, ticket, g_state, "Session2 Force Close 07:15");
   }
}

int OnInit()
{
   // 初始化模块并加载状态文件
   g_logger.Init(LogLevel);
   g_executor.Init(g_logger);
   g_stabilizer.Init(2);

   g_stateStore.InitDefaults(g_state);
   g_stateStore.Load(g_state);

   g_logger.Info("=== StrategySelector Modular EA initialized ===");
   g_logger.Info(StringFormat("Symbol=%s TF=%d Magic=%d", Symbol(), Period(), MagicNumber));
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   g_stateStore.Save(g_state);
}

void OnTick()
{
   // 主流程：填充上下文 -> 风控检查 -> 状态识别 -> 策略选择 -> 执行下单
   FillContext();

   g_risk.ResetDailyCounters(g_ctx.beijingTime, g_state);

   if(g_risk.NeedDailyReset(g_ctx.beijingTime, g_state))
   {
      int t = g_executor.GetCurrentPosition(g_ctx);
      if(t > 0)
         g_executor.CloseOrder(g_ctx, t, g_state, "Daily Reset - 01:00");

      g_risk.DoDailyReset(g_ctx.beijingTime, g_state);
      g_stateStore.Save(g_state);
   }

   g_executor.CheckStopLossTakeProfit(g_ctx, g_state);
   SessionTimeRules();
   UpdateAsianRange();

   if(g_risk.CheckCircuitBreaker(g_ctx, g_state))
   {
      int ticket = g_executor.GetCurrentPosition(g_ctx);
      if(ticket > 0)
         g_executor.CloseOrder(g_ctx, ticket, g_state, "Circuit Breaker");
      g_stateStore.Save(g_state);
      return;
   }

   if(g_state.circuitBreakerActive)
      return;

   if(g_executor.GetCurrentPosition(g_ctx) >= 0)
      return;

   if(g_ctx.ema20 < 0 || g_ctx.ema50 < 0 || g_ctx.rsi < 0 || g_ctx.macd == -1.0)
      return;

   MarketRegime raw = g_marketState.Detect(g_ctx);
   g_ctx.regime = g_stabilizer.Stabilize(raw);

   TradeSignal best;
   if(g_registry.EvaluateBestSignal(g_ctx, g_state, best) && best.valid)
   {
      int ticket2 = g_executor.OpenOrder(g_ctx, best);
      if(ticket2 > 0)
      {
         UpdateCountersAfterOpen(best);
         g_stateStore.Save(g_state);
      }
   }
}
