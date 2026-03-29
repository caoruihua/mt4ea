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
input bool     EnableStrategyHealthReport = false; // 是否在初始化时输出策略健康报告
input bool     UseAtrStopBuffer = true;   // 是否使用ATR止损缓冲
input bool     EnableGlobalProfitLockStop = true; // 是否启用全局浮盈锁利止损
input double   GlobalProfitLockTriggerUsd = 5.0;  // 浮盈达到后触发锁利
input double   GlobalProfitLockOffsetUsd  = 0.5;  // 锁利止损相对开仓价偏移
input double   SL_Buffer_ATR_Multiplier = 0.30; // ATR止损缓冲倍数
input double   SL_Buffer_Fixed_USD = 1.50;      // 固定止损缓冲
input double   TakeProfit_R_Multiple = 2.0;     // 固定盈亏比
input double   DailyPriceDeltaTargetUsd = 40.0; // 日累计获利价格差达到后停止交易

// 价格差参数均为“图表价格差美元”（例如 XAUUSD 3000->3015 为 +15）
input double   Session1_3_SL_USD                  = 10.0; // Session1/3 固定止损
input double   Session1_3_TP_USD                  = 4.0;  // Session1/3 固定止盈（方案A）
input double   Session2_SL_USD                    = 10.0; // Session2 首K突破跟随止损
input double   Session2_TP_USD                    = 4.0;  // Session2 首K突破跟随止盈（方案A）
input double   Session4_MinRange_USD              = 8.0;  // Session4 区间最小宽度门槛
input double   Session4_EntryBuffer_USD           = 3.0;  // Session4 边界触发缓冲
input double   Session4_SL_Buffer_USD             = 5.0;  // Session4 SL放在区间外的缓冲
input double   Session4_TP_USD                    = 15.0; // Session4 固定止盈
input double   Session5_FakeBreakout_Trigger_USD  = 3.0;  // Session5 假突破触发阈值
input double   Session5_ValidBreakout_Trigger_USD = 5.0;  // Session5 真突破触发阈值
input double   Session5_SL_USD                    = 15.0; // Session5 止损
input double   Session5_TP_USD                    = 3.8;  // Session5 止盈（方案A）
input double   Session5_EMA_Tolerance_USD         = 2.0;  // Session5 EMA回踩容差
input double   Session6_MinBody_USD               = 4.5;  // Session6 动量实体最小阈值
input double   Session6_SL_USD                    = 20.0; // Session6 止损
input double   Session6_TP_USD                    = 3.5;  // Session6 止盈（方案A）

// 斜率通道策略参数（独立风控）
input int      Channel_Lookback_Bars              = 6;    // 斜率回看K线数
input double   Channel_MinSlope                   = 0.20; // 最小斜率阈值（每根K线）
input double   Channel_ParallelTolerance          = 0.20; // 上下轨斜率近似平行容差
input double   Channel_MaxWidth_USD               = 12.0; // 通道平均宽度上限
input double   Channel_EntryTolerance_USD         = 2.0;  // 贴近上下轨触发容差
input double   Channel_ADX_Min                    = 18.0; // ADX趋势强度最小阈值
input double   Channel_SL_USD                     = 4.0;  // 斜率通道策略独立止损
input double   Channel_TP_USD                     = 3.2;  // 斜率通道策略独立止盈（方案A）
input int      Channel_MaxTradesPerDay            = 2;    // 斜率通道日内最大交易次数

// 区间边界反转策略参数（独立信号）
input int      RangeEdge_Observation_Bars         = 30;   // 观察窗（结构识别）
input int      RangeEdge_Trading_Bars             = 20;   // 交易区间窗（HH/LL/Mid）
input double   RangeEdge_EntryTolerance_USD       = 1.0;  // 边界接近容差
input double   RangeEdge_SL_Buffer_USD            = 5.0;  // 区间外侧止损缓冲
input bool     RangeEdge_EnableProtection         = false;// 是否启用移动保护
input double   RangeEdge_Protection_Trigger_USD   = 2.0;  // 达到浮盈阈值触发保护
input double   RangeEdge_Protection_Lock_USD      = 0.1;  // 保护后锁定利润（或保本=0）

// 影线拒绝突破策略参数（独立信号，不改动现有策略逻辑）
input int      Wick_Window_Bars                   = 8;    // 影线统计窗口
input double   Wick_Min_Upper_Ratio               = 0.45; // 长上影最小占比（上影/总长）
input double   Wick_Min_Lower_Ratio               = 0.45; // 长下影最小占比（下影/总长）
input double   Wick_Min_Length_USD                = 1.0;  // 影线最小绝对长度
input int      Wick_Min_Count                     = 3;    // 窗口内最少有效影线次数（>=3入场）
input double   Wick_Break_Tolerance_USD           = 0.3;  // 突破/跌破判定容差
input double   Wick_SL_USD                        = 6.0;  // 影线策略独立止损
input double   Wick_TP_USD                        = 4.0;  // 影线策略独立止盈

input bool     Spike_Enable                       = true; // 是否启用 5 分钟脉冲动量策略
input int      Spike_Window_Seconds               = 300;  // 滚动窗口秒数
input double   Spike_Trigger_USD                  = 40.0; // 脉冲最小价格差
input double   Spike_Max_Pullback_Ratio           = 0.20; // 最大允许回吐比例
input double   Spike_SL_USD                       = 20.0; // 固定止损价格差
input double   Spike_TP_USD                       = 35.0; // 固定止盈价格差
input bool     Spike_Log_Verbose                  = true; // 是否输出完整脉冲日志

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

string StrategyIdToString(StrategyId id)
{
   switch(id)
   {
      case STRATEGY_LINEAR_TREND:   return "STRATEGY_LINEAR_TREND";
      case STRATEGY_OSCILLATION:    return "STRATEGY_OSCILLATION";
      case STRATEGY_BREAKOUT:       return "STRATEGY_BREAKOUT";
      case STRATEGY_REVERSAL:       return "STRATEGY_REVERSAL";
      case STRATEGY_SLOPE_CHANNEL:  return "STRATEGY_SLOPE_CHANNEL";
      case STRATEGY_RANGE_EDGE_REVERSION: return "STRATEGY_RANGE_EDGE_REVERSION";
      case STRATEGY_WICK_REJECTION: return "STRATEGY_WICK_REJECTION";
      case STRATEGY_SPIKE_MOMENTUM: return "STRATEGY_SPIKE_MOMENTUM";
      default:                      return "STRATEGY_NONE";
   }
}

string OrderTypeToString(int orderType)
{
   if(orderType == OP_BUY)  return "BUY";
   if(orderType == OP_SELL) return "SELL";
   return "UNKNOWN";
}

void LogStrategyHealthReport()
{
   if(!EnableStrategyHealthReport)
      return;

   g_logger.Info("=== 策略健康报告 ===");
   g_logger.Info(StringFormat(
      "运行环境 | 品种=%s | 周期=%d | 魔术号=%d | 日志级别=%d | 时区偏移=%d",
      Symbol(),
      Period(),
      MagicNumber,
      LogLevel,
      TimeZoneOffset
   ));

   int strategyCount = g_registry.GetRegisteredStrategyCount();
   g_logger.Info(StringFormat("已注册策略数: %d", strategyCount));

   for(int i = 0; i < strategyCount; i++)
      g_logger.Info(StringFormat("策略[%d] %s", i + 1, g_registry.GetStrategySummaryByIndex(i)));

   g_logger.Info("健康报告模式为只读：不会改变任何交易逻辑。");
}

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
   g_ctx.atr14 = g_signalEngine.GetATR(1);
   g_ctx.adx14 = g_signalEngine.GetADX(1);

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
   // 初始化模块并加载状态文件
   g_logger.Init(LogLevel);
   g_executor.Init(g_logger);
   g_registry.Init(g_logger);
   g_stabilizer.Init(2);

   g_stateStore.InitDefaults(g_state);
   g_stateStore.Load(g_state);

   g_logger.Info("=== 策略选择器模块化EA已初始化 ===");
   g_logger.Info(StringFormat("品种=%s 周期=%d 魔术号=%d", Symbol(), Period(), MagicNumber));

   // 启动时打印时区转换结果，便于核对"服务器时间 -> 北京时间"是否正确
   datetime serverNow = TimeCurrent();
   datetime localNow = TimeLocal();
   datetime beijingNow = g_clock.GetBeijingTime(TimeZoneOffset);
   int initSession = g_clock.GetCurrentSession(beijingNow);
   g_logger.Info(StringFormat(
      "时区检查 OnInit | 服务器时间=%s | 本地时间=%s | 北京时间=%s | 偏移=%d | 会话=%d(%s)",
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
   // 主流程：填充上下文 -> 风控检查 -> 状态识别 -> 策略选择 -> 执行下单
   FillContext();

   g_risk.ResetDailyCounters(g_ctx.beijingTime, g_state);

   if(g_risk.NeedDailyReset(g_ctx.beijingTime, g_state))
   {
      int t = g_executor.GetCurrentPosition(g_ctx);
      if(t > 0)
      {
         g_executor.CloseOrder(g_ctx, t, g_state, "日重置 - 01:00");
         g_state.lastEntryAttemptBarTime = Time[0];
      }

      g_risk.DoDailyReset(g_ctx.beijingTime, g_state);
      g_stateStore.Save(g_state);
      if(t > 0)
         return; // 平仓后本tick不再开仓，防止同tick反复扫单
   }

   bool closedBySlTp = g_executor.CheckStopLossTakeProfit(g_ctx, g_state);
   if(closedBySlTp)
   {
      g_state.lastEntryAttemptBarTime = Time[0];
      g_stateStore.Save(g_state);
      return; // 平仓后本tick不再开仓
   }

   if(g_risk.CheckCircuitBreaker(g_ctx, g_state))
   {
      int ticket = g_executor.GetCurrentPosition(g_ctx);
      if(ticket > 0)
         g_executor.CloseOrder(g_ctx, ticket, g_state, "熔断触发");
      g_stateStore.Save(g_state);
      return;
   }

   if(g_state.circuitBreakerActive)
      return;

   g_executor.ApplyGlobalProfitLockIfNeeded(g_ctx);

   g_executor.ApplyProtectionIfNeeded(g_ctx);

   // 同一根K线上仅允许一次开仓尝试（无论上次成功还是失败）
   if(g_state.lastEntryAttemptBarTime == Time[0])
      return;

   if(g_ctx.ema20 < 0 || g_ctx.ema50 < 0 || g_ctx.rsi < 0 || g_ctx.macd == -1.0 || g_ctx.atr14 < 0 || g_ctx.adx14 < 0)
      return;

   MarketRegime raw = g_marketState.Detect(g_ctx, g_state);
   g_ctx.regime = g_stabilizer.Stabilize(raw);

   int existingTicket = g_executor.GetCurrentPosition(g_ctx);

   TradeSignal best;
   if(g_registry.EvaluateBestSignal(g_ctx, g_state, best) && best.valid)
   {
      if(existingTicket >= 0)
      {
         g_logger.Info(StringFormat(
            "信号被持仓阻止 | strategyId=%s | comment=%s | ticket=%d | regime=%d | session=%d",
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
         "策略触发下单 | strategyId=%s | comment=%s | orderType=%s | priority=%d | reason=%s | entry=%.5f | sl=%.5f | tp=%.5f | regime=%d | session=%d",
         StrategyIdToString(best.strategyId),
         best.comment,
         OrderTypeToString(best.orderType),
         best.priority,
         best.reason,
         entry,
         best.stopLoss,
         best.takeProfit,
         g_ctx.regime,
         g_ctx.sessionId
      ));

      g_state.lastEntryAttemptBarTime = Time[0];
      int ticket2 = g_executor.OpenOrder(g_ctx, best);
      if(ticket2 > 0)
      {
         g_state.lastEntryBarTime = Time[0];
         g_stateStore.Save(g_state);
      }
   }
}
