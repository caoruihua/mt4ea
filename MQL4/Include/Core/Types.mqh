#ifndef __CORE_TYPES_MQH__
#define __CORE_TYPES_MQH__

/*
 * 文件作用：
 * - 定义模块间共享的枚举、上下文结构、运行态结构、交易信号结构
 * - 统一字段命名，避免策略之间参数含义不一致
 */

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
   STRATEGY_SPIKE_MOMENTUM
};

struct StrategyContext
{
   string   symbol;         // 交易品种，例如 XAUUSD
   int      timeframe;      // 当前周期，通常 M5
   int      digits;         // 报价精度
   int      magicNumber;    // 魔术号
   int      logLevel;       // 日志级别
   int      timeZoneOffset; // 时区偏移（服务器 -> 北京）

   double   bid;            // 当前买价
   double   ask;            // 当前卖价

   double   ema20;          // EMA20
   double   ema50;          // EMA50
   double   rsi;            // RSI(14)
   double   macd;           // MACD主线
   double   atr14;          // ATR(14)
   double   adx14;          // ADX(14)

   datetime beijingTime;    // 北京时间
   int      sessionId;      // 会话ID（1~6）
   MarketRegime regime;     // 市场状态

   double   fixedLots;            // 固定手数
   double   profitThresholdUsd;   // 日盈利熔断阈值
   double   lossThresholdPercent; // 日亏损熔断阈值（百分比）
   double   dailyPriceDeltaTarget;// 当日累计获利价格差停手阈值
   int      slippage;             // 允许滑点
   int      maxRetries;           // 重试次数
   bool     useAtrStopBuffer;     // 是否使用ATR缓冲
   double   slBufferAtrMultiplier;// 止损ATR缓冲倍数
   double   slBufferFixedUsd;     // 固定止损缓冲
   double   riskRewardRatio;      // 固定盈亏比
   bool     enable_global_profit_lock;      // 是否启用全局浮盈锁利止损
   double   global_profit_lock_trigger_usd; // 触发锁利的最小浮盈
   double   global_profit_lock_offset_usd;  // 锁利止损相对开仓价偏移

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
   double   dailyProfit;          // 当日已实现盈利
   double   dailyLoss;            // 当日已实现亏损
   double   dailyPriceDelta;      // 当日累计获利价格差（仅累计正向已实现价格差）
   bool     circuitBreakerActive; // 熔断开关
   double   rangeHigh;            // 当前震荡区间高点
   double   rangeLow;             // 当前震荡区间低点
   double   breakoutLevel;        // 突破参考线
   int      breakoutDirection;    // 突破方向：1上破/-1下破/0无
   bool     breakoutRetestActive; // 是否处于回踩确认阶段
   double   asianHigh;            // 亚盘高点
   double   asianLow;             // 亚盘低点
   int      euroBreakoutState;    // 欧盘突破方向：0无/1多/2空
   datetime lastResetDate;        // 上次日重置日期

   int      session1Trades;
   int      session3Trades;
   bool     session2Traded;
   int      session5Trades;
   int      channelTrades;

   double   fakeBreakoutLow;
   double   fakeBreakoutHigh;
   datetime countersResetDate;
   datetime asianRangeDate;
   datetime lastEntryBarTime;        // 最近一次成功开仓所在K线时间
   datetime lastEntryAttemptBarTime; // 最近一次尝试开仓所在K线时间（成功/失败都记录）
   int      spikeLastDirection;
   datetime spikeLastTriggerTime;
   double   spikeLastAnchorHigh;
   double   spikeLastAnchorLow;
};

struct TradeSignal
{
   bool     valid;            // 信号有效标记
   StrategyId strategyId;     // 来源策略ID
   int      orderType;        // OP_BUY/OP_SELL
   double   lots;             // 下单手数
   double   stopLoss;         // 止损价
   double   takeProfit;       // 止盈价
   string   comment;          // 订单注释
   string   reason;           // 信号原因
   int      priority;         // 优先级（越大越优先）
};

#endif
