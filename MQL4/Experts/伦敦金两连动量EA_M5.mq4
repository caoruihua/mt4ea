//+------------------------------------------------------------------+
//|                                      XAUUSD_TwoBarMomentum_EA    |
//|                    M5 momentum follow-through EA for XAUUSD      |
//| 版本 1.6 本次修改说明：                                          |
//| 1. 新增最大止损距离限制，若结构止损距离 > MaxStopLossUsd 则禁止下单    |
//| 2. 新增最低盈亏比限制，初始止盈至少满足 MinRiskRewardRatio 倍风险      |
//| 3. 新增动态风控：浮盈达到 BreakEvenTriggerR 后移到保本               |
//| 4. 浮盈达到 TrailStartR 后，按最近 TrailLookbackBars 根K线做跟踪止损 |
//| 5. 保留原有二次确认逻辑，并与新的风控/出场逻辑整合                   |
//+------------------------------------------------------------------+
#property strict
#property version   "1.6"
#property description "伦敦金M5二连动量EA（精简版）"

input double FixedLots            = 0.01;      // 单次下单手数，同时也作为最大总持仓上限；默认最多持仓 0.01 手。
input int    MagicNumber          = 20260317;  // EA 订单唯一标识
input int    SlippagePoints       = 50;        // 市价下单最大滑点（points）
input double TakeProfitUsd        = 8.0;       // 固定止盈价格距离（XAUUSD价格单位，不是账户盈亏美元）
input double MinTwoBarMoveUsd     = 5.0;       // 最近2根已收盘K线的最小净涨跌幅（XAUUSD价格单位）
input double StopBufferUsd        = 0.5;       // 结构止损额外缓冲距离（XAUUSD价格单位，不是固定止损美元）
input double MaxStopLossUsd       = 10.0;      // 实际止损距离大于该值时，禁止下单
input double MinRiskRewardRatio   = 1.5;       // 最低盈亏比要求；实际止盈距离至少为风险的该倍数
input double DailyPriceTargetUsd  = 40.0;      // 北京时间日内累计净价格差达到该值后，停止当日开新仓（XAUUSD价格单位）
input double DailyPriceLossLimitUsd = 30.0;    // 北京时间日内累计净价格差 <= -该值后，停止当日开新仓（XAUUSD价格单位）
input int    ServerToBeijingHours = 6;         // 服务器时间+该值=北京时间（常见：GMT+2券商填6，GMT+3填5，GMT+0填8）
input bool   EnableDailySummaryLog = true;     // 是否在北京时间跨日时输出"昨日汇总（价格差+美元净盈亏）"
input bool   EnablePerBarDailyStats = true;    // 是否每根新K线输出"今日累计价格差+今日美元净盈亏"（调试期建议开启）
input string TradeSymbol          = "XAUUSD";  // 允许交易品种
input bool   EnableDebugLogs      = true;      // 是否输出调试日志（建议实盘可关闭）
input int    EntryObserveSeconds  = 2;         // 下单前观察秒数；若实时价格方向与前两根动量一致才下单
input double EntryObserveMinMoveUsd = 0.30;   // 观察期内至少同向净移动这么多价格，才允许下单
input int    EntryObserveSampleMs = 200;       // 观察期采样间隔（毫秒）
input double EntryObserveMinDirectionalRatio = 0.60; // 观察期内同向步数占比至少达到该阈值才允许下单
input bool   EnableDynamicExit    = true;      // 是否启用动态止盈止损管理
input double BreakEvenTriggerR    = 1.0;       // 浮盈达到多少R后，将止损移动到保本
input double BreakEvenLockUsd     = 0.0;       // 保本后额外锁定的价格差；多单加到开仓价上方，空单减到开仓价下方
input double TrailStartR          = 1.5;       // 浮盈达到多少R后，启动结构跟踪止损
input int    TrailLookbackBars    = 2;         // 跟踪止损参考最近多少根已收盘K线
input double TrailBufferUsd       = 0.3;       // 跟踪止损额外缓冲距离

datetime g_lastBarTime = 0;
bool g_loggedWrongSymbol   = false;
bool g_loggedWrongPeriod   = false;
bool g_loggedTradeNotAllow = false;
bool g_loggedBarsNotEnough = false;
bool g_loggedDailyTargetReached = false;
bool g_loggedDailyLossLimitReached = false;
int  g_lastBeijingDayKey = -1;
int  g_loggedDayWindowKey = -1;

void LogInfo(string msg)
{
   Print("[TBM] ", msg);
}

void LogDebug(string msg)
{
   if(EnableDebugLogs)
      Print("[TBM][DEBUG] ", msg);
}

// 检测是否出现新的 M5 K线，保证每根新K线只判断一次信号。
bool IsNewBar()
{
   datetime currentBarTime = iTime(Symbol(), PERIOD_M5, 0);
   if(currentBarTime == 0)
      return(false);

   if(g_lastBarTime == 0)
   {
      g_lastBarTime = currentBarTime;
      return(false);
   }

   if(currentBarTime == g_lastBarTime)
      return(false);

   g_lastBarTime = currentBarTime;
   return(true);
}

// 基础历史数据保护，避免 EA 刚挂上图表时读取到不完整的K线数据。
bool HasEnoughBars()
{
   return(iBars(Symbol(), PERIOD_M5) > 10);
}

// 获取"北京时间日期键"，格式：YYYYMMDD。
// 传入的 t 必须已经是北京时间坐标。
int GetBeijingDayKey(datetime t)
{
   MqlDateTime dt;
   TimeToStruct(t, dt);
   return(dt.year * 10000 + dt.mon * 100 + dt.day);
}

// 获取当前"北京时间日期键"。
// 不依赖 TimeGMT()，直接用 TimeCurrent() + 用户配置的偏移。
// 公式：北京时间 = 服务器时间 + ServerToBeijingHours 小时
int GetCurrentBeijingDayKey()
{
   datetime beijingNow = TimeCurrent() + ServerToBeijingHours * 3600;
   return(GetBeijingDayKey(beijingNow));
}

// 按"北京时间日期键（YYYYMMDD）"计算固定日窗口，并换算到服务器时间：
// [dayStartServer, dayEndServer)
// 不依赖 TimeGMT()，直接用 ServerToBeijingHours 偏移。
// 公式：服务器时间 = 北京时间 - ServerToBeijingHours 小时
void GetBeijingDayWindowByKeyInServerTime(int dayKey, datetime &dayStartServer, datetime &dayEndServer)
{
   int year  = dayKey / 10000;
   int month = (dayKey / 100) % 100;
   int day   = dayKey % 100;

   MqlDateTime bj;
   bj.year = year;
   bj.mon  = month;
   bj.day  = day;
   bj.hour = 0;
   bj.min  = 0;
   bj.sec  = 0;
   bj.day_of_week = 0;
   bj.day_of_year = 0;

   // beijingDayStart = 该日北京时间 00:00:00 的 datetime 数值
   datetime beijingDayStart = StructToTime(bj);

   // 服务器时间 = 北京时间 - 偏移
   dayStartServer = beijingDayStart - ServerToBeijingHours * 3600;
   dayEndServer   = dayStartServer + 24 * 3600;
}

// 统计指定"北京时间日期键（YYYYMMDD）"已平仓订单的累计净价格差（仅本EA、当前品种）。
// Buy: Close-Open；Sell: Open-Close。亏损会抵消盈利，属于净累计。
double GetNetPriceMoveByBeijingDayKey(int dayKey)
{
   datetime dayStartServer = 0;
   datetime dayEndServer = 0;
   GetBeijingDayWindowByKeyInServerTime(dayKey, dayStartServer, dayEndServer);

   double totalMove = 0.0;

   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;

      if(OrderSymbol() != Symbol())
         continue;

      if(OrderMagicNumber() != MagicNumber)
         continue;

      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL)
         continue;

      datetime closeTime = OrderCloseTime();
      if(closeTime <= 0)
         continue;

      if(closeTime < dayStartServer || closeTime >= dayEndServer)
         continue;

      if(type == OP_BUY)
         totalMove += (OrderClosePrice() - OrderOpenPrice());
      else
         totalMove += (OrderOpenPrice() - OrderClosePrice());
   }

   return(totalMove);
}

// 统计指定"北京时间日期键（YYYYMMDD）"已平仓订单的美元净盈亏（仅本EA、当前品种）。
// 口径：OrderProfit + OrderSwap + OrderCommission。
double GetNetUsdByBeijingDayKey(int dayKey)
{
   datetime dayStartServer = 0;
   datetime dayEndServer = 0;
   GetBeijingDayWindowByKeyInServerTime(dayKey, dayStartServer, dayEndServer);

   double totalUsd = 0.0;

   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;

      if(OrderSymbol() != Symbol())
         continue;

      if(OrderMagicNumber() != MagicNumber)
         continue;

      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL)
         continue;

      datetime closeTime = OrderCloseTime();
      if(closeTime <= 0)
         continue;

      if(closeTime < dayStartServer || closeTime >= dayEndServer)
         continue;

      totalUsd += (OrderProfit() + OrderSwap() + OrderCommission());
   }

   return(totalUsd);
}

// 统计当前图表品种上，本 EA 已开仓订单的总手数。
double GetManagedOpenLots()
{
   double lots = 0.0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(OrderSymbol() != Symbol())
         continue;

      if(OrderMagicNumber() != MagicNumber)
         continue;

      if(OrderType() == OP_BUY || OrderType() == OP_SELL)
         lots += OrderLots();
   }

   return(lots);
}

// 判断是否满足两连阳动量条件：
// 1. 最近 2 根已收盘K线全部收阳
// 2. High 逐根抬高
// 3. Close 逐根抬高
// 4. 从第2根信号K线开盘价到第1根信号K线收盘价的净涨幅至少达到设定阈值
bool IsBullishMomentumSetup()
{
   double open2 = iOpen(Symbol(), PERIOD_M5, 2);
   double open1 = iOpen(Symbol(), PERIOD_M5, 1);
   double close2 = iClose(Symbol(), PERIOD_M5, 2);
   double close1 = iClose(Symbol(), PERIOD_M5, 1);
   double high2 = iHigh(Symbol(), PERIOD_M5, 2);
   double high1 = iHigh(Symbol(), PERIOD_M5, 1);

   if(!(close2 > open2 && close1 > open1))
      return(false);

   if(!(high1 > high2))
      return(false);

   if(!(close1 > close2))
      return(false);

   return((close1 - open2) >= MinTwoBarMoveUsd);
}

// 判断是否满足两连阴动量条件：
// 1. 最近 2 根已收盘K线全部收阴
// 2. Low 逐根降低
// 3. Close 逐根降低
// 4. 从第2根信号K线开盘价到第1根信号K线收盘价的净跌幅至少达到设定阈值
bool IsBearishMomentumSetup()
{
   double open2 = iOpen(Symbol(), PERIOD_M5, 2);
   double open1 = iOpen(Symbol(), PERIOD_M5, 1);
   double close2 = iClose(Symbol(), PERIOD_M5, 2);
   double close1 = iClose(Symbol(), PERIOD_M5, 1);
   double low2 = iLow(Symbol(), PERIOD_M5, 2);
   double low1 = iLow(Symbol(), PERIOD_M5, 1);

   if(!(close2 < open2 && close1 < open1))
      return(false);

   if(!(low1 < low2))
      return(false);

   if(!(close1 < close2))
      return(false);

   return((open2 - close1) >= MinTwoBarMoveUsd);
}

// 取最近 2 根信号K线最低点，用于多单结构止损基准。
double LowestSignalLow()
{
   double low1 = iLow(Symbol(), PERIOD_M5, 1);
   double low2 = iLow(Symbol(), PERIOD_M5, 2);

   return(MathMin(low1, low2));
}

// 取最近 2 根信号K线最高点，用于空单结构止损基准。
double HighestSignalHigh()
{
   double high1 = iHigh(Symbol(), PERIOD_M5, 1);
   double high2 = iHigh(Symbol(), PERIOD_M5, 2);

   return(MathMax(high1, high2));
}

// 按券商报价精度标准化价格，避免下单价格小数位不合法。
double NormalizePrice(double price)
{
   return(NormalizeDouble(price, Digits));
}

double GetRiskDistance(int orderType, double entryPrice, double stopLoss)
{
   if(orderType == OP_BUY)
      return(entryPrice - stopLoss);

   if(orderType == OP_SELL)
      return(stopLoss - entryPrice);

   return(0.0);
}

double GetRewardDistance(int orderType, double entryPrice, double takeProfit)
{
   if(orderType == OP_BUY)
      return(takeProfit - entryPrice);

   if(orderType == OP_SELL)
      return(entryPrice - takeProfit);

   return(0.0);
}

double GetRecentLowestLow(int lookbackBars)
{
   int barsToCheck = MathMax(1, lookbackBars);
   double lowest = iLow(Symbol(), PERIOD_M5, 1);

   for(int i = 2; i <= barsToCheck; i++)
      lowest = MathMin(lowest, iLow(Symbol(), PERIOD_M5, i));

   return(lowest);
}

double GetRecentHighestHigh(int lookbackBars)
{
   int barsToCheck = MathMax(1, lookbackBars);
   double highest = iHigh(Symbol(), PERIOD_M5, 1);

   for(int i = 2; i <= barsToCheck; i++)
      highest = MathMax(highest, iHigh(Symbol(), PERIOD_M5, i));

   return(highest);
}

bool IsBetterStopLoss(int orderType, double currentStopLoss, double candidateStopLoss)
{
   if(currentStopLoss <= 0.0)
      return(true);

   if(orderType == OP_BUY)
      return(candidateStopLoss > currentStopLoss);

   if(orderType == OP_SELL)
      return(candidateStopLoss < currentStopLoss);

   return(false);
}

bool IsStopLossPriceValidForModify(int orderType, double candidateStopLoss)
{
   double stopLevelPoints = MarketInfo(Symbol(), MODE_STOPLEVEL);
   double minDistance = stopLevelPoints * Point;
   RefreshRates();

   if(orderType == OP_BUY)
      return((Bid - candidateStopLoss) >= minDistance);

   if(orderType == OP_SELL)
      return((candidateStopLoss - Ask) >= minDistance);

   return(false);
}

bool CalculateOrderPrices(int orderType,
                          double entryPrice,
                          double &stopLoss,
                          double &takeProfit,
                          double &riskDistance,
                          double &rewardDistance,
                          double &riskRewardRatio)
{
   if(orderType == OP_BUY)
      stopLoss = LowestSignalLow() - StopBufferUsd;
   else if(orderType == OP_SELL)
      stopLoss = HighestSignalHigh() + StopBufferUsd;
   else
      return(false);

   stopLoss = NormalizePrice(stopLoss);
   riskDistance = GetRiskDistance(orderType, entryPrice, stopLoss);

   if(riskDistance <= 0.0)
      return(false);

   if(MaxStopLossUsd > 0.0 && riskDistance > MaxStopLossUsd)
   {
      LogInfo("本次信号放弃：止损距离过大。方向=" + string(orderType == OP_BUY ? "多" : "空") +
              " 入场=" + DoubleToString(entryPrice, Digits) +
              " 止损=" + DoubleToString(stopLoss, Digits) +
              " 风险距离=" + DoubleToString(riskDistance, 2) +
              " 上限=" + DoubleToString(MaxStopLossUsd, 2));
      return(false);
   }

   rewardDistance = MathMax(TakeProfitUsd, riskDistance * MinRiskRewardRatio);
   if(orderType == OP_BUY)
      takeProfit = entryPrice + rewardDistance;
   else
      takeProfit = entryPrice - rewardDistance;

   takeProfit = NormalizePrice(takeProfit);
   rewardDistance = GetRewardDistance(orderType, entryPrice, takeProfit);

   if(riskDistance <= 0.0)
      return(false);

   riskRewardRatio = rewardDistance / riskDistance;
   if(riskRewardRatio < MinRiskRewardRatio)
   {
      LogInfo("本次信号放弃：盈亏比不足。方向=" + string(orderType == OP_BUY ? "多" : "空") +
              " 风险距离=" + DoubleToString(riskDistance, 2) +
              " 止盈距离=" + DoubleToString(rewardDistance, 2) +
              " 实际RR=" + DoubleToString(riskRewardRatio, 2) +
              " 最低RR=" + DoubleToString(MinRiskRewardRatio, 2));
      return(false);
   }

   return(true);
}

// 检查运行环境是否满足要求：
// 1. 品种必须是配置中的交易品种
// 2. 周期必须是 M5
// 3. 终端和券商必须允许交易
bool CheckTradeEnvironment()
{
   if(Symbol() != TradeSymbol)
   {
      if(!g_loggedWrongSymbol)
      {
         LogInfo("EA 配置品种=" + TradeSymbol + "，当前图表=" + Symbol() + "，暂停交易。");
         g_loggedWrongSymbol = true;
      }
      return(false);
   }
   g_loggedWrongSymbol = false;

   if(Period() != PERIOD_M5)
   {
      if(!g_loggedWrongPeriod)
      {
         LogInfo("EA 只能运行在 M5 周期，当前周期=" + IntegerToString(Period()) + "，暂停交易。");
         g_loggedWrongPeriod = true;
      }
      return(false);
   }
   g_loggedWrongPeriod = false;

   if(!IsTradeAllowed())
   {
      if(!g_loggedTradeNotAllow)
      {
         LogInfo("当前终端或券商设置不允许交易，暂停交易。");
         g_loggedTradeNotAllow = true;
      }
      return(false);
   }
   g_loggedTradeNotAllow = false;

   return(true);
}

// 检查止损止盈是否满足券商最小止损距离限制。
bool ValidateStops(int orderType, double entryPrice, double stopLoss, double takeProfit)
{
   double stopLevelPoints = MarketInfo(Symbol(), MODE_STOPLEVEL);
   double minDistance = stopLevelPoints * Point;

   if(orderType == OP_BUY)
   {
      if((entryPrice - stopLoss) < minDistance || (takeProfit - entryPrice) < minDistance)
         return(false);
   }
   else if(orderType == OP_SELL)
   {
      if((stopLoss - entryPrice) < minDistance || (entryPrice - takeProfit) < minDistance)
         return(false);
   }

   return(true);
}

// 用于短时间方向确认：
// 多单看 Ask，空单看 Bid，避免方向判断与真实成交侧脱节。
double GetObservationPrice(int orderType)
{
   RefreshRates();

   if(orderType == OP_BUY)
      return(Ask);

   return(Bid);
}

// 检测到两连动量后，不立刻下单，先观察当前这根 M5 K线开端 2 秒钟的实时价格方向。
// 不只比较起点和终点，而是做多次采样，综合判断：
// 1. 净位移是否足够
// 2. 同向小步数是否明显多于反向
// 3. 同向步数占比是否达标
bool ConfirmMomentumDirectionBeforeEntry(int orderType)
{
   if(EntryObserveSeconds <= 0)
      return(true);

   int sampleMs = MathMax(50, EntryObserveSampleMs);
   int totalObserveMs = EntryObserveSeconds * 1000;
   int sampleCount = MathMax(1, totalObserveMs / sampleMs);
   datetime observedBarTime = iTime(Symbol(), PERIOD_M5, 0);
   double startPrice = GetObservationPrice(orderType);
   double previousPrice = startPrice;
   double endPrice = startPrice;
   int sameDirSteps = 0;
   int oppositeSteps = 0;
   int flatSteps = 0;

   LogInfo("检测到信号后先观察" + IntegerToString(EntryObserveSeconds) +
           "秒。方向=" + string(orderType == OP_BUY ? "多" : "空") +
           " 起始价=" + DoubleToString(startPrice, Digits) +
           " 最小净位移=" + DoubleToString(EntryObserveMinMoveUsd, 2) +
           " 采样间隔=" + IntegerToString(sampleMs) + "ms");

   for(int i = 0; i < sampleCount; i++)
   {
      Sleep(sampleMs);

      if(IsStopped())
         return(false);

      datetime currentBarTime = iTime(Symbol(), PERIOD_M5, 0);
      if(currentBarTime != observedBarTime)
      {
         LogInfo("观察期间已切换到新K线，放弃本次信号。");
         return(false);
      }

      endPrice = GetObservationPrice(orderType);
      double stepDelta = endPrice - previousPrice;

      if(stepDelta == 0.0)
      {
         flatSteps++;
      }
      else if(orderType == OP_BUY)
      {
         if(stepDelta > 0.0)
            sameDirSteps++;
         else
            oppositeSteps++;
      }
      else
      {
         if(stepDelta < 0.0)
            sameDirSteps++;
         else
            oppositeSteps++;
      }

      previousPrice = endPrice;
   }

   double delta = endPrice - startPrice;
   double directionalMove = (orderType == OP_BUY) ? delta : (-delta);
   int activeSteps = sameDirSteps + oppositeSteps;
   double directionalRatio = 0.0;
   if(activeSteps > 0)
      directionalRatio = (double)sameDirSteps / activeSteps;

   bool sameDirection = (directionalMove >= EntryObserveMinMoveUsd &&
                         sameDirSteps > oppositeSteps &&
                         directionalRatio >= EntryObserveMinDirectionalRatio);

   LogInfo("观察结束。方向=" + string(orderType == OP_BUY ? "多" : "空") +
           " 起始价=" + DoubleToString(startPrice, Digits) +
           " 结束价=" + DoubleToString(endPrice, Digits) +
           " 净变化=" + DoubleToString(delta, Digits) +
           " 同向步数=" + IntegerToString(sameDirSteps) +
           " 反向步数=" + IntegerToString(oppositeSteps) +
           " 平步数=" + IntegerToString(flatSteps) +
           " 同向占比=" + DoubleToString(directionalRatio, 2) +
           " 结果=" + string(sameDirection ? "同向，允许下单" : "不同向，取消下单"));

   return(sameDirection);
}

void ManageOpenOrders()
{
   if(!EnableDynamicExit)
      return;

   if(iBars(Symbol(), PERIOD_M5) <= TrailLookbackBars + 2)
      return;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(OrderSymbol() != Symbol())
         continue;

      if(OrderMagicNumber() != MagicNumber)
         continue;

      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL)
         continue;

      double entryPrice = OrderOpenPrice();
      double currentStopLoss = OrderStopLoss();
      double currentTakeProfit = OrderTakeProfit();
      double initialRisk = GetRiskDistance(type, entryPrice, currentStopLoss);
      if(initialRisk <= 0.0)
         continue;

      RefreshRates();
      double currentPrice = (type == OP_BUY) ? Bid : Ask;
      double profitDistance = (type == OP_BUY) ? (currentPrice - entryPrice) : (entryPrice - currentPrice);
      if(profitDistance <= 0.0)
         continue;

      double candidateStopLoss = currentStopLoss;
      bool shouldModify = false;

      if(BreakEvenTriggerR > 0.0 && profitDistance >= initialRisk * BreakEvenTriggerR)
      {
         double breakEvenStop = (type == OP_BUY) ? (entryPrice + BreakEvenLockUsd) : (entryPrice - BreakEvenLockUsd);
         breakEvenStop = NormalizePrice(breakEvenStop);

         if(IsBetterStopLoss(type, candidateStopLoss, breakEvenStop))
         {
            candidateStopLoss = breakEvenStop;
            shouldModify = true;
         }
      }

      if(TrailStartR > 0.0 && profitDistance >= initialRisk * TrailStartR)
      {
         double trailStop = 0.0;
         if(type == OP_BUY)
            trailStop = GetRecentLowestLow(TrailLookbackBars) - TrailBufferUsd;
         else
            trailStop = GetRecentHighestHigh(TrailLookbackBars) + TrailBufferUsd;

         trailStop = NormalizePrice(trailStop);
         if(IsBetterStopLoss(type, candidateStopLoss, trailStop))
         {
            candidateStopLoss = trailStop;
            shouldModify = true;
         }
      }

      candidateStopLoss = NormalizePrice(candidateStopLoss);
      if(!shouldModify)
         continue;

      if(!IsStopLossPriceValidForModify(type, candidateStopLoss))
         continue;

      if(MathAbs(candidateStopLoss - currentStopLoss) < Point)
         continue;

      ResetLastError();
      if(OrderModify(OrderTicket(), OrderOpenPrice(), candidateStopLoss, currentTakeProfit, 0, clrNONE))
      {
         LogDebug("订单动态风控更新成功。Ticket=" + IntegerToString(OrderTicket()) +
                  " 方向=" + string(type == OP_BUY ? "多" : "空") +
                  " 原止损=" + DoubleToString(currentStopLoss, Digits) +
                  " 新止损=" + DoubleToString(candidateStopLoss, Digits) +
                  " 当前浮盈距离=" + DoubleToString(profitDistance, 2) +
                  " 初始风险=" + DoubleToString(initialRisk, 2));
      }
      else
      {
         LogInfo("订单动态风控更新失败。Ticket=" + IntegerToString(OrderTicket()) +
                 " 错误码=" + IntegerToString(GetLastError()) +
                 " 方向=" + string(type == OP_BUY ? "多" : "空") +
                 " 候选止损=" + DoubleToString(candidateStopLoss, Digits));
      }
   }
}

// 按检测到的动量方向执行市价下单，并自动带上"结构止损 + 缓冲距离"以及"固定价格距离止盈"。
void SendMomentumOrder(int orderType)
{
   double entryPrice = 0.0;
   double stopLoss = 0.0;
   double takeProfit = 0.0;
   double riskDistance = 0.0;
   double rewardDistance = 0.0;
   double riskRewardRatio = 0.0;
   color orderColor = (orderType == OP_BUY) ? clrDodgerBlue : clrTomato;
   int maxRetries = 3;

   for(int attempt = 1; attempt <= maxRetries; attempt++)
   {
      RefreshRates();

      entryPrice = (orderType == OP_BUY) ? Ask : Bid;
      entryPrice = NormalizePrice(entryPrice);

      if(!CalculateOrderPrices(orderType, entryPrice, stopLoss, takeProfit, riskDistance, rewardDistance, riskRewardRatio))
         return;

      if(!ValidateStops(orderType, entryPrice, stopLoss, takeProfit))
      {
         LogInfo("第" + IntegerToString(attempt) + "/" + IntegerToString(maxRetries) +
                 "次下单跳过：止损/止盈距离过近。方向=" + string(orderType == OP_BUY ? "多" : "空") +
                 " 入场=" + DoubleToString(entryPrice, Digits) +
                 " 止损=" + DoubleToString(stopLoss, Digits) +
                 " 止盈=" + DoubleToString(takeProfit, Digits));

         if(attempt < maxRetries)
            Sleep(300);

         continue;
      }

      LogInfo("准备发送订单（第" + IntegerToString(attempt) + "/" + IntegerToString(maxRetries) + "次）。方向=" +
              string(orderType == OP_BUY ? "多" : "空") +
              " 入场=" + DoubleToString(entryPrice, Digits) +
              " 止损=" + DoubleToString(stopLoss, Digits) +
              " 止盈=" + DoubleToString(takeProfit, Digits) +
              " 风险距离=" + DoubleToString(riskDistance, 2) +
              " 止盈距离=" + DoubleToString(rewardDistance, 2) +
              " RR=" + DoubleToString(riskRewardRatio, 2) +
              " 手数=" + DoubleToString(FixedLots, 2) +
              " 滑点=" + IntegerToString(SlippagePoints));

      ResetLastError();
      int ticket = OrderSend(
         Symbol(),
         orderType,
         FixedLots,
         entryPrice,
         SlippagePoints,
         stopLoss,
         takeProfit,
         "两连动量",
         MagicNumber,
         0,
         orderColor
      );

      if(ticket >= 0)
      {
         LogInfo("订单开仓成功。Ticket=" + IntegerToString(ticket) +
                 " 尝试次数=" + IntegerToString(attempt) +
                 " 方向=" + string(orderType == OP_BUY ? "多" : "空") +
                 " 入场=" + DoubleToString(entryPrice, Digits) +
                 " 止损=" + DoubleToString(stopLoss, Digits) +
                 " 止盈=" + DoubleToString(takeProfit, Digits) +
                 " RR=" + DoubleToString(riskRewardRatio, 2));
         return;
      }

      int err = GetLastError();
      LogInfo("OrderSend 第" + IntegerToString(attempt) + "/" + IntegerToString(maxRetries) +
              "次下单失败。错误码=" + IntegerToString(err) +
              " 方向=" + string(orderType == OP_BUY ? "多" : "空") +
              " 入场=" + DoubleToString(entryPrice, Digits) +
              " 止损=" + DoubleToString(stopLoss, Digits) +
              " 止盈=" + DoubleToString(takeProfit, Digits));

      if(attempt < maxRetries)
         Sleep(300);
   }

   LogInfo("OrderSend 重试" + IntegerToString(maxRetries) +
           "次后仍失败，放弃本次信号。方向=" + string(orderType == OP_BUY ? "多" : "空"));
}

int OnInit()
{
   g_lastBeijingDayKey = GetCurrentBeijingDayKey();

   // 输出初始化时的统计窗口，方便验证偏移是否配对
   datetime initDayStart = 0;
   datetime initDayEnd = 0;
   GetBeijingDayWindowByKeyInServerTime(g_lastBeijingDayKey, initDayStart, initDayEnd);

   LogInfo("EA 初始化。品种=" + Symbol() +
           " 周期=" + IntegerToString(Period()) +
           " 魔术号=" + IntegerToString(MagicNumber) +
           " 固定手数=" + DoubleToString(FixedLots, 2) +
           " 止盈=" + DoubleToString(TakeProfitUsd, 2) +
           " 最大止损=" + DoubleToString(MaxStopLossUsd, 2) +
           " 最低RR=" + DoubleToString(MinRiskRewardRatio, 2) +
           " 两K最小波动=" + DoubleToString(MinTwoBarMoveUsd, 2) +
           " 日封顶净价格差=" + DoubleToString(DailyPriceTargetUsd, 2) +
           " 日亏损停机净价格差=" + DoubleToString(DailyPriceLossLimitUsd, 2) +
           " 服务器→北京偏移=" + IntegerToString(ServerToBeijingHours) + "h" +
           " 跨日日志=" + string(EnableDailySummaryLog ? "开" : "关") +
           " K线统计日志=" + string(EnablePerBarDailyStats ? "开" : "关") +
           " 入场观察秒数=" + IntegerToString(EntryObserveSeconds) +
           " 入场最小净位移=" + DoubleToString(EntryObserveMinMoveUsd, 2) +
           " 入场采样间隔=" + IntegerToString(EntryObserveSampleMs) + "ms" +
           " 入场同向占比阈值=" + DoubleToString(EntryObserveMinDirectionalRatio, 2) +
           " 动态出场=" + string(EnableDynamicExit ? "开" : "关") +
           " 保本触发R=" + DoubleToString(BreakEvenTriggerR, 2) +
           " 保本锁盈=" + DoubleToString(BreakEvenLockUsd, 2) +
           " 跟踪启动R=" + DoubleToString(TrailStartR, 2) +
           " 跟踪K线数=" + IntegerToString(TrailLookbackBars) +
           " 跟踪缓冲=" + DoubleToString(TrailBufferUsd, 2) +
           " 止损缓冲=" + DoubleToString(StopBufferUsd, 2) +
           " 滑点=" + IntegerToString(SlippagePoints));

   LogInfo("初始统计窗口：北京日期=" + IntegerToString(g_lastBeijingDayKey) +
           " 服务器时间=" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) +
           " 窗口开始=" + TimeToString(initDayStart, TIME_DATE|TIME_SECONDS) +
           " 窗口结束=" + TimeToString(initDayEnd, TIME_DATE|TIME_SECONDS));

   if(Period() != PERIOD_M5)
      LogInfo("请把 EA 挂到 M5 图表。");

   if(Symbol() != TradeSymbol)
      LogInfo("请把 EA 挂到 " + TradeSymbol + " 图表。当前图表品种=" + Symbol());

   return(INIT_SUCCEEDED);
}

void OnTick()
{
   if(!CheckTradeEnvironment())
      return;

    ManageOpenOrders();

   if(!HasEnoughBars())
   {
      if(!g_loggedBarsNotEnough)
      {
         LogInfo("本次不判断信号：历史 M5 K线数量不足。");
         g_loggedBarsNotEnough = true;
      }
      return;
   }
   g_loggedBarsNotEnough = false;

   if(!IsNewBar())
      return;

   int currentBeijingDayKey = GetCurrentBeijingDayKey();
   if(currentBeijingDayKey != g_lastBeijingDayKey)
   {
      if(EnableDailySummaryLog && g_lastBeijingDayKey > 0)
      {
         double prevNetMove = GetNetPriceMoveByBeijingDayKey(g_lastBeijingDayKey);
         double prevNetUsd = GetNetUsdByBeijingDayKey(g_lastBeijingDayKey);
         LogInfo("北京时间跨日汇总。日期=" + IntegerToString(g_lastBeijingDayKey) +
                 " 净价格差=" + DoubleToString(prevNetMove, 2) +
                 " 美元净盈亏=" + DoubleToString(prevNetUsd, 2));
      }

      g_lastBeijingDayKey = currentBeijingDayKey;
      g_loggedDailyTargetReached = false;
      g_loggedDailyLossLimitReached = false;
      g_loggedDayWindowKey = -1;
   }

   if(EnableDebugLogs && g_loggedDayWindowKey != currentBeijingDayKey)
   {
      datetime dayStartServer = 0;
      datetime dayEndServer = 0;
      GetBeijingDayWindowByKeyInServerTime(currentBeijingDayKey, dayStartServer, dayEndServer);

      LogDebug("北京时间固定统计窗口：日期=" + IntegerToString(currentBeijingDayKey) +
               " 服务器当前=" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) +
               " 窗口开始=" + TimeToString(dayStartServer, TIME_DATE|TIME_SECONDS) +
               " 窗口结束=" + TimeToString(dayEndServer, TIME_DATE|TIME_SECONDS));
      g_loggedDayWindowKey = currentBeijingDayKey;
   }

   double todayNetMove = GetNetPriceMoveByBeijingDayKey(currentBeijingDayKey);
   double todayNetUsd = GetNetUsdByBeijingDayKey(currentBeijingDayKey);

   if(EnablePerBarDailyStats)
   {
      LogDebug("北京时间今日统计：净价格差=" + DoubleToString(todayNetMove, 2) +
               " 美元净盈亏=" + DoubleToString(todayNetUsd, 2) +
               " 盈利目标=" + DoubleToString(DailyPriceTargetUsd, 2) +
               " 亏损停机=" + DoubleToString(DailyPriceLossLimitUsd, 2));
   }

   if(todayNetMove >= DailyPriceTargetUsd)
   {
      if(!g_loggedDailyTargetReached)
      {
         LogInfo("北京时间今日累计净价格差已达封顶，停止当日开新仓。当前=" +
                 DoubleToString(todayNetMove, 2) +
                 " 美元净盈亏=" + DoubleToString(todayNetUsd, 2) +
                 " 目标=" + DoubleToString(DailyPriceTargetUsd, 2));
         g_loggedDailyTargetReached = true;
      }
      return;
   }

   if(DailyPriceLossLimitUsd > 0.0 && todayNetMove <= (-DailyPriceLossLimitUsd))
   {
      if(!g_loggedDailyLossLimitReached)
      {
         LogInfo("北京时间今日累计净价格差触及亏损停机，停止当日开新仓。当前=" +
                 DoubleToString(todayNetMove, 2) +
                 " 美元净盈亏=" + DoubleToString(todayNetUsd, 2) +
                 " 停机阈值=" + DoubleToString(-DailyPriceLossLimitUsd, 2));
         g_loggedDailyLossLimitReached = true;
      }
      return;
   }

   // 最大总持仓上限 = FixedLots；默认 FixedLots=0.01，因此默认最多持仓 0.01 手。
   double managedLots = GetManagedOpenLots();
   if(managedLots >= FixedLots)
   {
      LogDebug("本次不再开新仓：已达总手数上限。当前=" + DoubleToString(managedLots, 2) +
               " 上限=" + DoubleToString(FixedLots, 2));
      return;
   }

   RefreshRates();

   if(IsBullishMomentumSetup())
   {
      LogInfo("检测到两连阳动量信号，开始多单二次确认。");
      if(!ConfirmMomentumDirectionBeforeEntry(OP_BUY))
      {
         LogInfo("多单二次确认未通过，本次不下单。");
         return;
      }

      SendMomentumOrder(OP_BUY);
      return;
   }

   if(IsBearishMomentumSetup())
   {
      LogInfo("检测到两连阴动量信号，开始空单二次确认。");
      if(!ConfirmMomentumDirectionBeforeEntry(OP_SELL))
      {
         LogInfo("空单二次确认未通过，本次不下单。");
         return;
      }

      SendMomentumOrder(OP_SELL);
      return;
   }

   LogDebug("最近 2 根已收盘 M5 K线未形成有效两连动量信号。");
}
