//+------------------------------------------------------------------+
//|                                              StrategySelector.mq4 |
//|                 Engineering Modular EA (keep legacy file intact)  |
//+------------------------------------------------------------------+
//| 版本号：v1.1 (2026-03-31)                                         |
//| 更新内容：                                                         |
//|   - 新增方向突破状态机（BreakoutSubstate）                          |
//|   - 区间边界冻结 + 2根K线站稳确认突破                               |
//|   - 突破确认后直接放行顺势信号（优先级15）                           |
//|   - 突破阶段禁用 RangeEdgeReversion 反向候选                        |
//|   - 绕过 stabilizer 延迟，突破确认后即时触发                         |
//|   - 增加状态诊断日志（rawRegime/stableRegime/breakoutSubstate）     |
//+------------------------------------------------------------------+
#property strict
#property version   "1.1"
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

input int      TimeZoneOffset = 6;
input int      MagicNumber    = 20260313;
input int      LogLevel       = 1;
input bool     EnableStrategyHealthReport = false;
input bool     UseAtrStopBuffer = true;
input bool     EnableGlobalProfitLockStop = true;
input double   GlobalProfitLockTriggerUsd = 5.0;
input double   GlobalProfitLockOffsetUsd  = 0.5;
input double   SL_Buffer_ATR_Multiplier = 0.30;
input double   SL_Buffer_Fixed_USD = 1.50;
input double   TakeProfit_R_Multiple = 2.0;
input double   DailyPriceDeltaTargetUsd = 40.0;

input double   Session1_3_SL_USD                  = 10.0;
input double   Session1_3_TP_USD                  = 4.0;
input double   Session2_SL_USD                    = 10.0;
input double   Session2_TP_USD                    = 4.0;
input double   Session4_MinRange_USD              = 8.0;
input double   Session4_EntryBuffer_USD           = 3.0;
input double   Session4_SL_Buffer_USD             = 5.0;
input double   Session4_TP_USD                    = 15.0;
input double   Session5_FakeBreakout_Trigger_USD  = 3.0;
input double   Session5_ValidBreakout_Trigger_USD = 5.0;
input double   Session5_SL_USD                    = 15.0;
input double   Session5_TP_USD                    = 3.8;
input double   Session5_EMA_Tolerance_USD         = 2.0;
input double   Session6_MinBody_USD               = 4.5;
input double   Session6_SL_USD                    = 20.0;
input double   Session6_TP_USD                    = 3.5;

input int      Channel_Lookback_Bars              = 6;
input double   Channel_MinSlope                   = 0.20;
input double   Channel_ParallelTolerance          = 0.20;
input double   Channel_MaxWidth_USD               = 12.0;
input double   Channel_EntryTolerance_USD         = 2.0;
input double   Channel_ADX_Min                    = 18.0;
input double   Channel_SL_USD                     = 4.0;
input double   Channel_TP_USD                     = 3.2;
input int      Channel_MaxTradesPerDay            = 2;
input double   Channel_Pullback_MinDrop_USD       = 6.0;
input double   Channel_SupportTestTolerance_USD   = 1.2;
input double   Channel_BreakdownCloseTolerance_USD= 0.5;
input int      Channel_Base_MinTests              = 2;
input int      Channel_Base_MaxBars               = 5;
input double   Channel_Recovery_Trigger_Ratio     = 0.70;
input bool     Channel_Enable_Stall_Filter        = true;
input int      Channel_Stall_Lookback_Bars        = 10;
input double   Channel_Stall_Max_High_Progress_USD= 1.5;
input double   Channel_Stall_Close_Band_Max_USD   = 4.0;
input double   Channel_Stall_Compression_Ratio    = 0.60;
input int      Channel_Stall_Min_Conditions       = 2;

input int      RangeEdge_Observation_Bars         = 30;
input int      RangeEdge_Trading_Bars             = 20;
input double   RangeEdge_EntryTolerance_USD       = 1.0;
input double   RangeEdge_SL_Buffer_USD            = 5.0;
input bool     RangeEdge_EnableProtection         = false;
input double   RangeEdge_Protection_Trigger_USD   = 2.0;
input double   RangeEdge_Protection_Lock_USD      = 0.1;

input int      Wick_Window_Bars                   = 8;
input double   Wick_Min_Upper_Ratio               = 0.45;
input double   Wick_Min_Lower_Ratio               = 0.45;
input double   Wick_Min_Length_USD                = 1.0;
input int      Wick_Min_Count                     = 3;
input double   Wick_Break_Tolerance_USD           = 0.3;
input double   Wick_SL_USD                        = 6.0;
input double   Wick_TP_USD                        = 4.0;

input bool     Engulfing_Enable                   = true;
input double   Engulfing_Extreme_Proximity_USD    = 3.0;
input double   Engulfing_Min_Body_USD             = 2.0;
input double   Engulfing_Stop_Buffer_USD          = 3.0;
input double   Engulfing_Max_Stop_Loss_USD        = 8.0;
input int      Engulfing_Priority                 = 15;

input bool     Spike_Enable                       = true;
input int      Spike_Window_Seconds               = 120;
input double   Spike_Trigger_USD                  = 20.0;
input double   Spike_Max_Pullback_Ratio           = 0.40;
input double   Spike_SL_USD                       = 20.0;
input double   Spike_TP_USD                       = 35.0;
input bool     Spike_Log_Verbose                  = true;

// Regime 灵敏度参数：
// - Promote: 从非趋势升级到趋势所需确认K线数（大一点更稳）
// - Demote : 趋势失效降级所需确认K线数（小一点更敏锐）
// - InvalidationAtrMult: 趋势失效幅度阈值（按ATR倍数）
// - SlopeFlipThreshold : EMA20 斜率翻转阈值（过滤微小波动）
// - AdxWeakThreshold   : ADX弱趋势闸门（弱势时优先回到RANGE）
input int      RegimePromoteConfirmBars           = 1;
input int      RegimeDemoteConfirmBars            = 1;
input double   RegimeTrendInvalidationAtrMult     = 0.9;
input double   RegimeSlopeFlipThreshold           = 0.0;
input double   RegimeAdxWeakThreshold             = 16.0;

const double   FIXED_LOTS             = 0.01;
const double   PROFIT_THRESHOLD_USD   = 50.0;
const double   LOSS_THRESHOLD_PERCENT = 3.0;
const int      SLIPPAGE               = 30;
const int      MAX_RETRIES            = 3;

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

string StrategyIdToString(StrategyId id)
{
   switch(id)
   {
      case STRATEGY_LINEAR_TREND:          return "STRATEGY_LINEAR_TREND";
      case STRATEGY_OSCILLATION:           return "STRATEGY_OSCILLATION";
      case STRATEGY_BREAKOUT:              return "STRATEGY_BREAKOUT";
      case STRATEGY_REVERSAL:              return "STRATEGY_REVERSAL";
      case STRATEGY_SLOPE_CHANNEL:         return "STRATEGY_SLOPE_CHANNEL";
      case STRATEGY_RANGE_EDGE_REVERSION:  return "STRATEGY_RANGE_EDGE_REVERSION";
      case STRATEGY_WICK_REJECTION:        return "STRATEGY_WICK_REJECTION";
      case STRATEGY_SPIKE_MOMENTUM:        return "STRATEGY_SPIKE_MOMENTUM";
      case STRATEGY_DAILY_EXTREME_ENGULFING:return "STRATEGY_DAILY_EXTREME_ENGULFING";
      default:                             return "STRATEGY_NONE";
   }
}

string OrderTypeToString(int orderType)
{
   if(orderType == OP_BUY)
      return "BUY";
   if(orderType == OP_SELL)
      return "SELL";
   return "UNKNOWN";
}

void LogStrategyHealthReport()
{
   if(!EnableStrategyHealthReport)
      return;

   g_logger.Info("=== Strategy Health Report ===");
   g_logger.Info(StringFormat(
      "Runtime identity | symbol=%s | timeframe=%d | magic=%d | logLevel=%d | tzOffset=%d",
      Symbol(),
      Period(),
      MagicNumber,
      LogLevel,
      TimeZoneOffset
   ));

   int strategyCount = g_registry.GetRegisteredStrategyCount();
   g_logger.Info(StringFormat("Registered strategies: %d", strategyCount));
   for(int i = 0; i < strategyCount; i++)
      g_logger.Info(StringFormat("Strategy[%d] %s", i + 1, g_registry.GetStrategySummaryByIndex(i)));
}

void FillContext()
{
   // 每个 tick 统一构建一次上下文，保证所有策略读取同一份行情与风控数据，
   // 避免“同一时刻不同策略看到的数据不一致”。
   g_ctx.symbol = Symbol();
   g_ctx.timeframe = Period();
   g_ctx.digits = Digits;
   g_ctx.magicNumber = MagicNumber;
   g_ctx.logLevel = LogLevel;
   g_ctx.timeZoneOffset = TimeZoneOffset;

   g_ctx.bid = Bid;
   g_ctx.ask = Ask;

   g_ctx.ema12 = g_signalEngine.GetEMA(12, 1);
   g_ctx.ema20 = g_signalEngine.GetEMA(20, 1);
   g_ctx.rsi = g_signalEngine.GetRSI(1);
   g_ctx.macd = g_signalEngine.GetMACD(1);
   g_ctx.atr14 = g_signalEngine.GetATR(1);
   g_ctx.adx14 = g_signalEngine.GetADX(1);

   // 将输入参数注入上下文，供 MarketState / Stabilizer 使用。
   // 这样无需在各模块重复读 input，便于统一调参与回测对比。
   g_ctx.regime_promote_confirm_bars = RegimePromoteConfirmBars;
   g_ctx.regime_demote_confirm_bars = RegimeDemoteConfirmBars;
   g_ctx.regime_trend_invalidation_atr_mult = RegimeTrendInvalidationAtrMult;
   g_ctx.regime_slope_flip_threshold = RegimeSlopeFlipThreshold;
   g_ctx.regime_adx_weak_threshold = RegimeAdxWeakThreshold;

   g_ctx.beijingTime = g_clock.GetBeijingTime(TimeZoneOffset);
   g_ctx.sessionId = g_clock.GetCurrentSession(g_ctx.beijingTime);
   g_ctx.regime = REGIME_UNKNOWN;

   g_ctx.fixedLots = FIXED_LOTS;
   g_ctx.profitThresholdUsd = PROFIT_THRESHOLD_USD;
   g_ctx.lossThresholdPercent = LOSS_THRESHOLD_PERCENT;
   g_ctx.dailyPriceDeltaTarget = DailyPriceDeltaTargetUsd;
   g_ctx.slippage = SLIPPAGE;
   g_ctx.maxRetries = MAX_RETRIES;
   g_ctx.useAtrStopBuffer = UseAtrStopBuffer;
   g_ctx.slBufferAtrMultiplier = SL_Buffer_ATR_Multiplier;
   g_ctx.slBufferFixedUsd = SL_Buffer_Fixed_USD;
   g_ctx.riskRewardRatio = TakeProfit_R_Multiple;
   g_ctx.enable_global_profit_lock = EnableGlobalProfitLockStop;
   g_ctx.global_profit_lock_trigger_usd = GlobalProfitLockTriggerUsd;
   g_ctx.global_profit_lock_offset_usd = GlobalProfitLockOffsetUsd;

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

   g_ctx.channel_lookback_bars = Channel_Lookback_Bars;
   g_ctx.channel_min_slope = Channel_MinSlope;
   g_ctx.channel_parallel_tolerance = Channel_ParallelTolerance;
   g_ctx.channel_max_width_usd = Channel_MaxWidth_USD;
   g_ctx.channel_entry_tolerance_usd = Channel_EntryTolerance_USD;
   g_ctx.channel_adx_min = Channel_ADX_Min;
   g_ctx.channel_sl_usd = Channel_SL_USD;
   g_ctx.channel_tp_usd = Channel_TP_USD;
   g_ctx.channel_max_trades_per_day = Channel_MaxTradesPerDay;
   g_ctx.channel_pullback_min_drop_usd = Channel_Pullback_MinDrop_USD;
   g_ctx.channel_support_test_tolerance_usd = Channel_SupportTestTolerance_USD;
   g_ctx.channel_breakdown_close_tolerance_usd = Channel_BreakdownCloseTolerance_USD;
   g_ctx.channel_base_min_tests = Channel_Base_MinTests;
   g_ctx.channel_base_max_bars = Channel_Base_MaxBars;
   g_ctx.channel_recovery_trigger_ratio = Channel_Recovery_Trigger_Ratio;
   g_ctx.channel_enable_stall_filter = Channel_Enable_Stall_Filter;
   g_ctx.channel_stall_lookback_bars = Channel_Stall_Lookback_Bars;
   g_ctx.channel_stall_max_high_progress_usd = Channel_Stall_Max_High_Progress_USD;
   g_ctx.channel_stall_close_band_max_usd = Channel_Stall_Close_Band_Max_USD;
   g_ctx.channel_stall_compression_ratio = Channel_Stall_Compression_Ratio;
   g_ctx.channel_stall_min_conditions = Channel_Stall_Min_Conditions;

   g_ctx.range_edge_observation_bars = RangeEdge_Observation_Bars;
   g_ctx.range_edge_trading_bars = RangeEdge_Trading_Bars;
   g_ctx.range_edge_entry_tolerance_usd = RangeEdge_EntryTolerance_USD;
   g_ctx.range_edge_sl_buffer_usd = RangeEdge_SL_Buffer_USD;
   g_ctx.range_edge_enable_protection = RangeEdge_EnableProtection;
   g_ctx.range_edge_protection_trigger_usd = RangeEdge_Protection_Trigger_USD;
   g_ctx.range_edge_protection_lock_usd = RangeEdge_Protection_Lock_USD;

   g_ctx.wick_window_bars = Wick_Window_Bars;
   g_ctx.wick_min_upper_ratio = Wick_Min_Upper_Ratio;
   g_ctx.wick_min_lower_ratio = Wick_Min_Lower_Ratio;
   g_ctx.wick_min_length_usd = Wick_Min_Length_USD;
   g_ctx.wick_min_count = Wick_Min_Count;
   g_ctx.wick_break_tolerance_usd = Wick_Break_Tolerance_USD;
   g_ctx.wick_sl_usd = Wick_SL_USD;
   g_ctx.wick_tp_usd = Wick_TP_USD;

   g_ctx.engulfing_enable = Engulfing_Enable;
   g_ctx.engulfing_extreme_proximity_usd = Engulfing_Extreme_Proximity_USD;
   g_ctx.engulfing_min_body_usd = Engulfing_Min_Body_USD;
   g_ctx.engulfing_stop_buffer_usd = Engulfing_Stop_Buffer_USD;
   g_ctx.engulfing_max_stop_loss_usd = Engulfing_Max_Stop_Loss_USD;
   g_ctx.engulfing_priority = Engulfing_Priority;

   g_ctx.spike_enable = Spike_Enable;
   g_ctx.spike_window_seconds = Spike_Window_Seconds;
   g_ctx.spike_trigger_usd = Spike_Trigger_USD;
   g_ctx.spike_max_pullback_ratio = Spike_Max_Pullback_Ratio;
   g_ctx.spike_sl_usd = Spike_SL_USD;
   g_ctx.spike_tp_usd = Spike_TP_USD;
   g_ctx.spike_log_verbose = Spike_Log_Verbose;
}

int OnInit()
{
   g_logger.Init(LogLevel);
   g_executor.Init(g_logger);
   g_registry.Init(g_logger);

   // 不对称防抖初始化：
   // - Promote(升级趋势)通常更保守
   // - Demote(趋势失效)可更敏锐
   g_stabilizer.Init(RegimePromoteConfirmBars, RegimeDemoteConfirmBars);

   g_stateStore.InitDefaults(g_state);
   g_stateStore.Load(g_state);

   g_logger.Info("=== Modular Strategy Selector EA initialized ===");
   g_logger.Info(StringFormat("symbol=%s timeframe=%d magic=%d", Symbol(), Period(), MagicNumber));

   datetime serverNow = TimeCurrent();
   datetime localNow = TimeLocal();
   datetime beijingNow = g_clock.GetBeijingTime(TimeZoneOffset);
   int initSession = g_clock.GetCurrentSession(beijingNow);
   g_logger.Info(StringFormat(
      "Clock snapshot | server=%s | local=%s | beijing=%s | tzOffset=%d | session=%d(%s)",
      TimeToStr(serverNow, TIME_DATE|TIME_SECONDS),
      TimeToStr(localNow, TIME_DATE|TIME_SECONDS),
      TimeToStr(beijingNow, TIME_DATE|TIME_SECONDS),
      TimeZoneOffset,
      initSession,
      g_clock.GetSessionName(initSession)
   ));

   LogStrategyHealthReport();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   g_stateStore.Save(g_state);
}

void OnTick()
{
   // 1) 构建统一上下文
   FillContext();

   // 2) 日级计数与重置逻辑（先处理风控与状态清理）
   g_risk.ResetDailyCounters(g_ctx.beijingTime, g_state);

   if(g_risk.NeedDailyReset(g_ctx.beijingTime, g_state))
   {
      int t = g_executor.GetCurrentPosition(g_ctx);
      if(t > 0)
      {
         g_executor.CloseOrder(g_ctx, t, g_state, "Daily reset 01:00");
         g_state.lastEntryAttemptBarTime = Time[0];
      }

      g_risk.DoDailyReset(g_ctx.beijingTime, g_state);
      g_stateStore.Save(g_state);
      if(t > 0)
         return;
   }

   bool closedBySlTp = g_executor.CheckStopLossTakeProfit(g_ctx, g_state);
   if(closedBySlTp)
   {
      g_state.lastEntryAttemptBarTime = Time[0];
      g_stateStore.Save(g_state);
      return;
   }

   if(g_risk.CheckCircuitBreaker(g_ctx, g_state))
   {
      int ticket = g_executor.GetCurrentPosition(g_ctx);
      if(ticket > 0)
         g_executor.CloseOrder(g_ctx, ticket, g_state, "Circuit breaker active");
      g_stateStore.Save(g_state);
      return;
   }

   if(g_state.circuitBreakerActive)
      return;

   // 3) 持仓保护逻辑（全局锁盈 / 保护性移动）
   g_executor.ApplyGlobalProfitLockIfNeeded(g_ctx);
   g_executor.ApplyProtectionIfNeeded(g_ctx);

   if(g_state.lastEntryAttemptBarTime == Time[0])
      return;

   if(g_ctx.ema12 < 0 || g_ctx.ema20 < 0 || g_ctx.rsi < 0 || g_ctx.macd == -1.0 || g_ctx.atr14 < 0 || g_ctx.adx14 < 0)
      return;

   // 4) 先做市场状态识别，再做防抖稳定：
   // raw 更敏锐，stable 用于最终策略决策，减少噪声抖动。
   MarketRegime raw = g_marketState.Detect(g_ctx, g_state);
   g_ctx.regime = g_stabilizer.Stabilize(raw);

   // 突破确认快速通道：当 breakoutSubstate 为 CONFIRMED_UP/DOWN 时，
   // 直接覆盖 stable regime 为对应趋势，绕过 stabilizer 的 promote 延迟，
   // 确保 2 根 K 线站稳后立即触发顺势信号。
   if(g_state.breakoutSubstate == BREAKOUT_CONFIRMED_UP)
      g_ctx.regime = REGIME_TREND_UP;
   else if(g_state.breakoutSubstate == BREAKOUT_CONFIRMED_DOWN)
      g_ctx.regime = REGIME_TREND_DOWN;

   // 诊断日志：输出 raw/stable regime 与 breakout 子状态，便于追踪状态转换
   static datetime s_diagLogTime = 0;
   if(TimeCurrent() - s_diagLogTime >= 60)
   {
      g_logger.Info(StringFormat(
         "RegimeDiag | rawRegime=%d | stableRegime=%d | breakoutSubstate=%d | frozenHigh=%.5f | frozenLow=%.5f | holdBars=%d | ema12=%.5f | ema20=%.5f | adx14=%.2f",
         (int)raw,
         (int)g_ctx.regime,
         g_state.breakoutSubstate,
         g_state.breakoutFrozenHigh,
         g_state.breakoutFrozenLow,
         g_state.breakoutHoldBars,
         g_ctx.ema12,
         g_ctx.ema20,
         g_ctx.adx14
      ));
      s_diagLogTime = TimeCurrent();
   }

   int existingTicket = g_executor.GetCurrentPosition(g_ctx);

   TradeSignal best;
   if(g_registry.EvaluateBestSignal(g_ctx, g_state, best) && best.valid)
   {
      // 5) 有持仓则不重复开仓，避免同向/反向信号互相踩踏。
      if(existingTicket >= 0)
      {
         g_logger.Info(StringFormat(
            "Signal blocked by existing position | strategyId=%s | comment=%s | ticket=%d | regime=%d | session=%d",
            StrategyIdToString(best.strategyId),
            best.comment,
            existingTicket,
            g_ctx.regime,
            g_ctx.sessionId
         ));
         return;
      }

      double entry = (best.orderType == OP_BUY) ? g_ctx.ask : g_ctx.bid;
       g_logger.Info(StringFormat(
          "Strategy triggered order | strategyId=%s | comment=%s | orderType=%s | priority=%d | reason=%s | entry=%.5f | sl=%.5f | tp=%.5f | regime=%d | breakoutSubstate=%d | session=%d",
          StrategyIdToString(best.strategyId),
          best.comment,
          OrderTypeToString(best.orderType),
          best.priority,
          best.reason,
          entry,
          best.stopLoss,
          best.takeProfit,
          g_ctx.regime,
          g_state.breakoutSubstate,
          g_ctx.sessionId
       ));

      // 6) 记录入场并执行下单。
      g_state.lastEntryAttemptBarTime = Time[0];
      int ticket2 = g_executor.OpenOrder(g_ctx, best);
      if(ticket2 > 0)
      {
         g_state.lastEntryBarTime = Time[0];
         g_stateStore.Save(g_state);
      }
   }
}
