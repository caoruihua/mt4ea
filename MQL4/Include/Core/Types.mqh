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

enum TrendDirection
{
   TREND_NONE = 0,
   TREND_UP,
   TREND_DOWN
};

enum StrategyId
{
   STRATEGY_NONE = 0,
   STRATEGY_TREND_CONTINUATION,
   STRATEGY_PULLBACK,
   STRATEGY_EXPANSION_FOLLOW,
   STRATEGY_PINBAR_REVERSAL
};

struct StrategyContext
{
   // ---- 运行标识 ----
   string   symbol;
   int      timeframe;
   int      digits;
   int      magicNumber;
   int      logLevel;

   // ---- 当前报价 ----
   double   bid;
   double   ask;

   // ---- 指标快照（取上一根已收盘K线） ----
   int      emaFastPeriod;
   int      emaSlowPeriod;
   double   emaFast;
   double   emaSlow;
   double   atr14;
   double   spreadPoints;
   double   lowVolAtrPointsFloor;
   double   lowVolAtrSpreadRatioFloor;

   // ---- 第二波防追过滤参数（统一由主入口文件下发） ----
   bool     enableSecondLegLongFilter;
   bool     enableSecondLegShortFilter;
   double   secondLegMinSpaceAtr;
   double   secondLegPullbackMinAtr;
   int      secondLegMinPullbackBars;
   int      secondLegBaseMinBars;
   double   secondLegBaseMaxRangeAtr;
   double   secondLegReclaimRatio;
   int      secondLegSwingLookbackBars;

   // ---- 全局风控与执行参数 ----
   double   fixedLots;
   int      slippage;
   int      maxRetries;

   // ---- 时间 ----
   datetime currentTime;
   datetime lastClosedBarTime;
};

struct RuntimeState
{
   datetime dayKey;
   bool     dailyLocked;
   double   dailyClosedProfit;
   int      tradesToday;

   datetime lastEntryBarTime;
   double   entryPrice;
   double   entryAtr;

   double   highestCloseSinceEntry;
   double   lowestCloseSinceEntry;
   bool     trailingActive;

   int      lastTicket;
};

struct MarketFilterResult
{
   TrendDirection trendDirection;
   bool           isTrendValid;
   bool           isLowVol;
   datetime       barTime;
   string         blockReason;
};

struct TradeSignal
{
   bool       valid;
   StrategyId strategyId;
   int        orderType;
   int        priority;
   double     lots;
   double     stopLoss;
   double     takeProfit;
   string     comment;
   string     reason;
};

#endif
