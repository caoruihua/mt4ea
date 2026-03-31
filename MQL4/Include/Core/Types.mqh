#ifndef __CORE_TYPES_MQH__
#define __CORE_TYPES_MQH__

/*
 * 文件作用：
 * - 定义系统内所有“通用类型”：市场状态、策略ID、上下文、运行时状态、交易信号。
 * - 这是各模块共享的数据契约（MarketState / StrategyRegistry / Risk / Executor 等都会引用）。
 *
 * 维护建议：
 * - 新增字段时，优先放在语义相近的分组下，并补充注释，避免“只知道能跑，不知道含义”。
 * - StrategyContext 偏“当前tick输入快照”；RuntimeState 偏“跨tick持久状态”。
 */

enum MarketRegime
{
   REGIME_UNKNOWN = 0,         // 未知/样本不足
   REGIME_RANGE,               // 震荡区间
   REGIME_BREAKOUT_SETUP_UP,   // 向上突破后的回踩准备阶段
   REGIME_BREAKOUT_SETUP_DOWN, // 向下突破后的回踩准备阶段
   REGIME_TREND_UP,            // 上升趋势
   REGIME_TREND_DOWN           // 下降趋势
};

// 策略唯一标识：用于日志、优先级选择、统计归因
enum StrategyId
{
   STRATEGY_NONE = 0,               // 无策略/占位
   STRATEGY_LINEAR_TREND,           // 线性趋势
   STRATEGY_OSCILLATION,            // 震荡
   STRATEGY_BREAKOUT,               // 突破顺势
   STRATEGY_REVERSAL,               // 反转/回踩确认
   STRATEGY_SLOPE_CHANNEL,          // 斜率通道
   STRATEGY_RANGE_EDGE_REVERSION,   // 区间边缘反转
   STRATEGY_WICK_REJECTION,         // 长影线拒绝
   STRATEGY_SPIKE_MOMENTUM,         // 脉冲动量
   STRATEGY_DAILY_EXTREME_ENGULFING // 日内极值吞没
};

// 突破子状态：用于识别震荡区间突破的方向与进度
enum BreakoutSubstate
{
   BREAKOUT_NONE           = 0, // 无突破（震荡状态）
   BREAKOUT_CANDIDATE_UP   = 1, // 上破候选（首根收盘突破区间上沿）
   BREAKOUT_CANDIDATE_DOWN = 2, // 下破候选（首根收盘突破区���下沿）
   BREAKOUT_CONFIRMED_UP   = 3, // 上破确认（连续 2 根收盘站稳区间外）
   BREAKOUT_CONFIRMED_DOWN = 4, // 下破确认（连续 2 根收盘站稳区间外）
   BREAKOUT_FAILED         = 5  // 突破失败（已回区间内）
};

// 斜率通道策略内部状态机阶段
enum PullbackBaseStage
{
   PULLBACK_BASE_STAGE_IDLE = 0, // 空闲，尚未进入形态跟踪
   PULLBACK_BASE_STAGE_PULLBACK, // 回撤阶段
   PULLBACK_BASE_STAGE_BASE,     // 筑底/盘整阶段
   PULLBACK_BASE_STAGE_ARMED     // 已满足触发条件，等待执行
};

// 策略上下文：当前 tick 的“输入快照”
struct StrategyContext
{
   // ---- 运行标识 ----
   string   symbol;          // 交易品种
   int      timeframe;       // 当前周期（如 PERIOD_M5）
   int      digits;          // 报价小数位
   int      magicNumber;     // 订单魔术号
   int      logLevel;        // 日志等级
   int      timeZoneOffset;  // 时区偏移（用于会话换算）

   // ---- 当前报价 ----
   double   bid;             // 卖价
   double   ask;             // 买价

   // ---- 指标快照（通常取上一根已收盘K线） ----
   double   ema12;
   double   ema20;
   double   rsi;
   double   macd;
   double   atr14;
   double   adx14;

   // ---- Regime（市场状态）切换灵敏度参数 ----
   int      regime_promote_confirm_bars;         // 非趋势 -> 趋势 升级确认条数（大=更稳）
   int      regime_demote_confirm_bars;          // 趋势 -> 非趋势 降级确认条数（小=更敏锐）
   double   regime_trend_invalidation_atr_mult;  // 趋势失效幅度阈值（ATR倍数）
   double   regime_slope_flip_threshold;         // EMA20 斜率翻转阈值（过滤微小噪声）
   double   regime_adx_weak_threshold;           // ADX 弱势闸门

   // ---- 时间与会话 ----
   datetime beijingTime;     // 换算后的北京时间
   int      sessionId;       // 当前交易时段ID
   MarketRegime regime;      // 稳定后的市场状态

   // ---- 全局风控与执行参数 ----
   double   fixedLots;                      // 固定手数
   double   profitThresholdUsd;             // 日利润阈值
   double   lossThresholdPercent;           // 日亏损百分比阈值
   double   dailyPriceDeltaTarget;          // 日波动目标
   int      slippage;                       // 允许滑点
   int      maxRetries;                     // 下单重试次数
   bool     useAtrStopBuffer;               // 是否启用 ATR 止损缓冲
   double   slBufferAtrMultiplier;          // ATR 止损缓冲倍数
   double   slBufferFixedUsd;               // 固定止损缓冲
   double   riskRewardRatio;                // 风险收益比（R）
   bool     enable_global_profit_lock;      // 是否启用全局锁盈
   double   global_profit_lock_trigger_usd; // 触发锁盈的浮盈阈值
   double   global_profit_lock_offset_usd;  // 锁盈偏移

   // ---- 分时段策略参数（价格距离，单位：图表价格USD） ----
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

   // ---- 斜率通道策略参数 ----
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

   // ---- 区间边缘反转策略参数 ----
   int    range_edge_observation_bars;
   int    range_edge_trading_bars;
   double range_edge_entry_tolerance_usd;
   double range_edge_sl_buffer_usd;
   bool   range_edge_enable_protection;
   double range_edge_protection_trigger_usd;
   double range_edge_protection_lock_usd;

   // ---- 长影线拒绝策略参数 ----
   int    wick_window_bars;
   double wick_min_upper_ratio;
   double wick_min_lower_ratio;
   double wick_min_length_usd;
   int    wick_min_count;
   double wick_break_tolerance_usd;
   double wick_sl_usd;
   double wick_tp_usd;

   // ---- 日内极值吞没策略参数 ----
   bool   engulfing_enable;
   double engulfing_extreme_proximity_usd;
   double engulfing_min_body_usd;
   double engulfing_stop_buffer_usd;
   double engulfing_max_stop_loss_usd;
   int    engulfing_priority;

   // ---- 脉冲动量策略参数 ----
   bool   spike_enable;
   int    spike_window_seconds;
   double spike_trigger_usd;
   double spike_max_pullback_ratio;
   double spike_sl_usd;
   double spike_tp_usd;
   bool   spike_log_verbose;
};

// 运行时状态：跨 tick / 跨天持久化的“系统记忆”
struct RuntimeState
{
   // ---- 日内统计 / 风控状态 ----
   double   dailyProfit;          // 当日累计盈利
   double   dailyLoss;            // 当日累计亏损
   double   dailyPriceDelta;      // 当日价格变动统计
   bool     circuitBreakerActive; // 熔断开关

   // ---- 市场结构缓存 ----
   double   rangeHigh;            // 近期区间高点
   double   rangeLow;             // 近期区间低点
   double   breakoutLevel;        // 突破关键位
   int      breakoutDirection;    // 突破方向（1/-1）
   bool     breakoutRetestActive; // 是否处于突破回踩跟踪中

   // ---- 时段辅助状态 ----
   double   asianHigh;            // 亚洲时段高点缓存
   double   asianLow;             // 亚洲时段低点缓存
   int      euroBreakoutState;    // 欧盘突破状态机
   datetime lastResetDate;        // 最近一次日重置日期

   // ---- 分时段交易计数 ----
   int      session1Trades;
   int      session3Trades;
   bool     session2Traded;
   int      session5Trades;
   int      channelTrades;

   // ---- 其他策略共享缓存 ----
   double   fakeBreakoutLow;      // 假突破低点缓存
   double   fakeBreakoutHigh;     // 假突破高点缓存
   datetime dayExtremeDate;       // 当日极值对应日期
   double   dayHigh;              // 当日最高价
   double   dayLow;               // 当日最低价
   datetime countersResetDate;    // 计数器最近重置日期
   datetime asianRangeDate;       // 亚洲区间所属日期
   datetime lastEntryBarTime;        // 最近成功入场K线时间
   datetime lastEntryAttemptBarTime; // 最近尝试入场K线时间（用于同K线限频）

   // 斜率通道“回撤-筑底-恢复”形态跟踪状态：
   // 跨 tick 保存，避免每个 tick 从头识别，确保形态识别连贯。
   // 生命周期示例：回撤下跌 -> 多次跌破失败 -> 价格恢复到阈值。
   int      channelPullbackStage;
   datetime channelSetupTime;
   double   channelPullbackHigh;
   double   channelSupportLevel;
   int      channelFailedBreakdownCount;
   int      channelBaseBarCount;
   double   channelBaseCloseAverage;
   double   channelRecoveryLevel;
   datetime channelLastBaseBarTime;

   // ---- 脉冲动量策略状态 ----
   int      spikeLastDirection;
   datetime spikeLastTriggerTime;
   double   spikeLastAnchorHigh;
   double   spikeLastAnchorLow;

   // ---- 突破子状态机（方向突破识别） ----
   int      breakoutSubstate;          // BreakoutSubstate 枚举值
   double   breakoutFrozenHigh;        // 突破候选开始时冻结的区间上沿
   double   breakoutFrozenLow;         // 突破候选开始时冻结的区间下沿
   datetime breakoutCandidateBarTime;  // 首次突破候选所在 K 线时间
   int      breakoutHoldBars;          // 已连续站稳区间外的 K 线计数
};

// 交易信号：策略评估后的统一下单意图
struct TradeSignal
{
   bool     valid;       // 信号是否有效
   StrategyId strategyId; // 来源策略
   int      orderType;   // OP_BUY / OP_SELL
   double   lots;        // 手数
   double   stopLoss;    // 止损价
   double   takeProfit;  // 止盈价
   string   comment;     // 订单注释
   string   reason;      // 触发原因（日志可读）
   int      priority;    // 优先级（数值越大优先）
};

#endif
