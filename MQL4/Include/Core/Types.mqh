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
   REGIME_TREND_UP,
   REGIME_TREND_DOWN,
   REGIME_RANGE,
   REGIME_BREAKOUT,
   REGIME_REVERSAL
};

enum StrategyId
{
   STRATEGY_NONE = 0,
   STRATEGY_LINEAR_TREND,
   STRATEGY_OSCILLATION,
   STRATEGY_BREAKOUT,
   STRATEGY_REVERSAL,
   STRATEGY_SLOPE_CHANNEL
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

   datetime beijingTime;    // 北京时间
   int      sessionId;      // 会话ID（1~6）
   MarketRegime regime;     // 市场状态

   double   fixedLots;            // 固定手数
   double   profitThresholdUsd;   // 日盈利熔断阈值
   double   lossThresholdPercent; // 日亏损熔断阈值（百分比）
   int      slippage;             // 允许滑点
   int      maxRetries;           // 重试次数

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
};

struct RuntimeState
{
   double   dailyProfit;          // 当日已实现盈利
   double   dailyLoss;            // 当日已实现亏损
   bool     circuitBreakerActive; // 熔断开关
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
