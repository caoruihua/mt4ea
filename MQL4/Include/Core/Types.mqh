#ifndef __CORE_TYPES_MQH__
#define __CORE_TYPES_MQH__

enum MarketRegime
{
   REGIME_UNKNOWN = 0,
   REGIME_RANGE,
   REGIME_BREAKOUT_SETUP_UP,
   REGIME_BREAKOUT_SETUP_DOWN,
   REGIME_TREND_UP,
   REGIME_TREND_DOWN
};

enum StrategyId
{
   STRATEGY_NONE = 0,
   STRATEGY_LINEAR_TREND,
   STRATEGY_OSCILLATION,
   STRATEGY_BREAKOUT,
   STRATEGY_REVERSAL,
   STRATEGY_SLOPE_CHANNEL,
   STRATEGY_RANGE_EDGE_REVERSION,
   STRATEGY_WICK_REJECTION,
   STRATEGY_SPIKE_MOMENTUM,
   STRATEGY_DAILY_EXTREME_ENGULFING
};

enum PullbackBaseStage
{
   PULLBACK_BASE_STAGE_IDLE = 0,
   PULLBACK_BASE_STAGE_PULLBACK,
   PULLBACK_BASE_STAGE_BASE,
   PULLBACK_BASE_STAGE_ARMED
};

struct StrategyContext
{
   string   symbol;
   int      timeframe;
   int      digits;
   int      magicNumber;
   int      logLevel;
   int      timeZoneOffset;

   double   bid;
   double   ask;

   double   ema20;
   double   ema50;
   double   rsi;
   double   macd;
   double   atr14;
   double   adx14;

   datetime beijingTime;
   int      sessionId;
   MarketRegime regime;

   double   fixedLots;
   double   profitThresholdUsd;
   double   lossThresholdPercent;
   double   dailyPriceDeltaTarget;
   int      slippage;
   int      maxRetries;
   bool     useAtrStopBuffer;
   double   slBufferAtrMultiplier;
   double   slBufferFixedUsd;
   double   riskRewardRatio;
   bool     enable_global_profit_lock;
   double   global_profit_lock_trigger_usd;
   double   global_profit_lock_offset_usd;

   // Price-distance params (USD on chart price)
   double session1_3_sl_usd;
   double session1_3_tp_usd;
   double session2_sl_usd;
   double session2_tp_usd;
   double session4_minRange_usd;
   double session4_entryBuffer_usd;
   double session4_slBuffer_usd;
   double session4_tp_usd;
   double session5_fakeBreakout_trigger_usd;
   double session5_validBreakout_trigger_usd;
   double session5_sl_usd;
   double session5_tp_usd;
   double session5_emaTolerance_usd;
   double session6_minBody_usd;
   double session6_sl_usd;
   double session6_tp_usd;

   // Slope channel strategy params
   int    channel_lookback_bars;
   double channel_min_slope;
   double channel_parallel_tolerance;
   double channel_max_width_usd;
   double channel_entry_tolerance_usd;
   double channel_adx_min;
   double channel_sl_usd;
   double channel_tp_usd;
   int    channel_max_trades_per_day;
   double channel_pullback_min_drop_usd;
   double channel_support_test_tolerance_usd;
   double channel_breakdown_close_tolerance_usd;
   int    channel_base_min_tests;
   int    channel_base_max_bars;
   double channel_recovery_trigger_ratio;
   bool   channel_enable_stall_filter;
   int    channel_stall_lookback_bars;
   double channel_stall_max_high_progress_usd;
   double channel_stall_close_band_max_usd;
   double channel_stall_compression_ratio;
   int    channel_stall_min_conditions;

   // Range-edge reversion strategy params
   int    range_edge_observation_bars;
   int    range_edge_trading_bars;
   double range_edge_entry_tolerance_usd;
   double range_edge_sl_buffer_usd;
   bool   range_edge_enable_protection;
   double range_edge_protection_trigger_usd;
   double range_edge_protection_lock_usd;

   // Wick rejection strategy params
   int    wick_window_bars;
   double wick_min_upper_ratio;
   double wick_min_lower_ratio;
   double wick_min_length_usd;
   int    wick_min_count;
   double wick_break_tolerance_usd;
   double wick_sl_usd;
   double wick_tp_usd;

   // Daily extreme engulfing strategy params
   bool   engulfing_enable;
   double engulfing_extreme_proximity_usd;
   double engulfing_min_body_usd;
   double engulfing_stop_buffer_usd;
   double engulfing_max_stop_loss_usd;
   int    engulfing_priority;

   // Spike momentum strategy params
   bool   spike_enable;
   int    spike_window_seconds;
   double spike_trigger_usd;
   double spike_max_pullback_ratio;
   double spike_sl_usd;
   double spike_tp_usd;
   bool   spike_log_verbose;
};

struct RuntimeState
{
   double   dailyProfit;
   double   dailyLoss;
   double   dailyPriceDelta;
   bool     circuitBreakerActive;
   double   rangeHigh;
   double   rangeLow;
   double   breakoutLevel;
   int      breakoutDirection;
   bool     breakoutRetestActive;
   double   asianHigh;
   double   asianLow;
   int      euroBreakoutState;
   datetime lastResetDate;

   int      session1Trades;
   int      session3Trades;
   bool     session2Traded;
   int      session5Trades;
   int      channelTrades;

   double   fakeBreakoutLow;
   double   fakeBreakoutHigh;
   datetime dayExtremeDate;
   double   dayHigh;
   double   dayLow;
   datetime countersResetDate;
   datetime asianRangeDate;
   datetime lastEntryBarTime;
   datetime lastEntryAttemptBarTime;

   // The pullback-base-breakout setup is tracked across ticks so the strategy
   // can wait through the whole "selloff -> failed breakdowns -> 70% recovery"
   // lifecycle instead of re-evaluating from scratch each tick.
   int      channelPullbackStage;
   datetime channelSetupTime;
   double   channelPullbackHigh;
   double   channelSupportLevel;
   int      channelFailedBreakdownCount;
   int      channelBaseBarCount;
   double   channelBaseCloseAverage;
   double   channelRecoveryLevel;
   datetime channelLastBaseBarTime;

   int      spikeLastDirection;
   datetime spikeLastTriggerTime;
   double   spikeLastAnchorHigh;
   double   spikeLastAnchorLow;
};

struct TradeSignal
{
   bool     valid;
   StrategyId strategyId;
   int      orderType;
   double   lots;
   double   stopLoss;
   double   takeProfit;
   string   comment;
   string   reason;
   int      priority;
};

#endif
