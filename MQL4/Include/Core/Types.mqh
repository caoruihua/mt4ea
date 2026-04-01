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

// 市场状态趋势方向：用于趋势过滤和入场方向判断
enum TrendDirection
{
   TREND_NONE = 0,      // 无趋势或趋势不明确
   TREND_UP,           // 上升趋势
   TREND_DOWN          // 下降趋势
};

// 策略唯一标识：用于日志、统计归因和策略选择
enum StrategyId
{
   STRATEGY_NONE = 0,          // 无策略/占位
   STRATEGY_TREND_CONTINUATION, // 趋势延续策略
   STRATEGY_PULLBACK           // 回踩策略
};

// 策略上下文：当前 tick 的“输入快照”
struct StrategyContext
{
   // ---- 运行标识 ----
   string   symbol;          // 交易品种（固定为XAUUSD）
   int      timeframe;       // 当前周期（固定为PERIOD_M5）
   int      digits;          // 报价小数位
   int      magicNumber;     // 订单魔术号
   int      logLevel;        // 日志等级
   
   // ---- 当前报价 ----
   double   bid;             // 卖价
   double   ask;             // 买价
   
   // ---- 指标快照（取上一根已收盘K线） ----
   double   ema15;           // EMA(15) 用于趋势判断
   double   ema30;           // EMA(30) 用于趋势判断  
   double   atr14;           // ATR(14) 用于波动率过滤和止损止盈计算
   double   spreadPoints;    // 当前点差（点数）
   
   // ---- 全局风控与执行参数 ----
   double   fixedLots;       // 固定手数（固定为0.01）
   int      slippage;        // 允许滑点
   int      maxRetries;      // 下单重试次数
   
   // ---- 时间与会话 ----
   datetime currentTime;     // 当前服务器时间
   datetime lastClosedBarTime; // 上一根已收盘K线时间
};

// 运行时状态：跨 tick / 跨天持久化的“系统记忆”
struct RuntimeState
{
   // ---- 日内统计 / 风控状态 ----
   datetime dayKey;              // 服务器日键（用于日重置判断，基于TimeCurrent()日期）
   bool     dailyLocked;         // 日盈利锁定标志（当日累计净盈利达到+$50后锁定）
   double   dailyClosedProfit;   // 当日累计已平仓净盈利（美元）
   int      tradesToday;         // 当日已开仓次数
   
   // ---- 入场状态缓存（用于重启后恢复） ----
   datetime lastEntryBarTime;    // 最近成功入场K线时间（用于同K线限频）
   double   entryPrice;          // 当前持仓入场价格（重启后需要恢复）
   double   entryAtr;            // 入场时的ATR值（用于动态SL/TP计算）
   
   // ---- 动态止损止盈跟踪状态 ----
   double   highestCloseSinceEntry;  // 入场后最高收盘价（用于多头追踪）
   double   lowestCloseSinceEntry;   // 入场后最低收盘价（用于空头追踪）
   bool     trailingActive;          // 追踪止损是否已激活
};

// 市场过滤结果：仅服务于两策略内核
struct MarketFilterResult
{
   TrendDirection trendDirection; // 趋势方向：上/下/无
   bool           isTrendValid;   // 趋势是否有效（EMA排列+斜率）
   bool           isLowVol;       // 是否低波动（ATR/点差过滤失败）
   datetime       barTime;        // 参与决策的已收盘K线时间（M5）
   string         blockReason;    // 当次被拦截原因（日志直接可读）
};

// 交易信号：策略评估后的统一下单意图
struct TradeSignal
{
   bool       valid;          // 信号是否有效
   StrategyId strategyId;     // 来源策略
   int        orderType;      // OP_BUY / OP_SELL
   int        priority;       // 策略优先级（值越大越优先）
   double     lots;           // 手数（固定为0.01）
   double     stopLoss;       // 止损价
   double     takeProfit;     // 止盈价
   string     comment;        // 订单注释
   string     reason;         // 触发原因（日志可读）
};

#endif
