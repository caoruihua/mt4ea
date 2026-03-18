//+------------------------------------------------------------------+
//|  DailyBreakoutEA_M5.mq4                                          |
//|  5分钟图 - 震荡区间明显突破策略                                   |
//|  盈利目标: 8 美元                                                |
//+------------------------------------------------------------------+
#property copyright "Monica EA - M5 Version"
#property version   "2.00"
#property strict

//==========================================================================
//  输入参数
//==========================================================================
input int    RangeStartHour   = 0;       // 区间统计开始时间（服务器时，默认0点）
input int    RangeEndHour     = 8;       // 区间统计结束时间（默认8点，亚盘结束）
input double BreakoutBuffer   = 15.0;    // 突破缓冲（点数），M5建议15~30
input int    ConfirmBars      = 2;       // 需要连续N根M5收盘在区间外才确认突破
input double ProfitTargetUSD  = 8.0;   // 盈利目标（美元）
input double StopLossUSD      = 6.0;   // 止损（美元）
input double LotSize          = 0.01;   // 手数：最小手数 0.01
input int    TradeEndHour     = 20;     // 每天最晚开单时间（超过不开单）
input int    MagicNumber      = 20250315;

//==========================================================================
//  全局变量
//==========================================================================
double g_rangeHigh     = 0;
double g_rangeLow      = 0;
bool   g_rangeReady    = false;
string g_lastRangeDate = "";

//==========================================================================
//  计算今日亚盘震荡区间
//==========================================================================
void CalcDailyRange()
{
   string today = TimeToString(TimeCurrent(), TIME_DATE);
   if(g_lastRangeDate == today && g_rangeReady) return;

   double high  = -1;
   double low   = 999999;
   int    count = 0;

   for(int i = 1; i < 500; i++)
   {
      datetime barTime = Time[i];
      string   barDate = TimeToString(barTime, TIME_DATE);
      int      barHour = TimeHour(barTime);

      if(barDate != today)                                     continue;
      if(barHour < RangeStartHour || barHour >= RangeEndHour) continue;

      if(High[i] > high) high = High[i];
      if(Low[i]  < low)  low  = Low[i];
      count++;
   }

   if(count >= 5 && high > 0 && low < 999999)
   {
      g_rangeHigh     = high;
      g_rangeLow      = low;
      g_rangeReady    = true;
      g_lastRangeDate = today;
      Print("📦 今日区间已更新 | High=", g_rangeHigh,
            " | Low=", g_rangeLow,
            " | 统计K线数=", count);
   }
}

//==========================================================================
//  确认突破（连续N根K线收盘在区间外）
//==========================================================================
bool ConfirmBreakoutUp()
{
   double threshold = g_rangeHigh + BreakoutBuffer * Point;
   for(int i = 1; i <= ConfirmBars; i++)
      if(Close[i] <= threshold) return false;
   return true;
}

bool ConfirmBreakoutDown()
{
   double threshold = g_rangeLow - BreakoutBuffer * Point;
   for(int i = 1; i <= ConfirmBars; i++)
      if(Close[i] >= threshold) return false;
   return true;
}

//==========================================================================
//  美元 → 价格点位换算（适配0.01手）
//==========================================================================
double USDtoPoints(double usd)
{
   double tickVal  = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tickVal <= 0 || tickSize <= 0) return 0;
   return usd / (tickVal * LotSize / tickSize);
}

double CalcTP(int type, double price)
{
   double pts = USDtoPoints(ProfitTargetUSD);
   return (type == OP_BUY) ? price + pts : price - pts;
}

double CalcSL(int type, double price)
{
   double pts = USDtoPoints(StopLossUSD);
   return (type == OP_BUY) ? price - pts : price + pts;
}

//==========================================================================
//  实时监控浮盈，达到40美元立即平仓
//==========================================================================
void MonitorProfit()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != MagicNumber)          continue;
      if(OrderSymbol()      != Symbol())             continue;

      double profit = OrderProfit() + OrderSwap() + OrderCommission();
      if(profit >= ProfitTargetUSD)
      {
         double closePrice = (OrderType() == OP_BUY) ? Bid : Ask;
         bool ok = OrderClose(OrderTicket(), OrderLots(), closePrice, 3, clrGold);
         if(ok)
            Print("✅ 盈利达到 $", DoubleToString(profit, 2), "，已平仓！");
         else
            Print("⚠️ 平仓失败，错误码:", GetLastError());
      }
   }
}

//==========================================================================
//  画区间线
//==========================================================================
void DrawRangeLines()
{
   if(!g_rangeReady) return;

   string nameH = "EA_RangeHigh";
   string nameL = "EA_RangeLow";

   if(ObjectFind(nameH) < 0)
      ObjectCreate(nameH, OBJ_HLINE, 0, 0, g_rangeHigh);
   else
      ObjectMove(nameH, 0, 0, g_rangeHigh);
   ObjectSet(nameH, OBJPROP_COLOR, clrDodgerBlue);
   ObjectSet(nameH, OBJPROP_STYLE, STYLE_DASH);
   ObjectSet(nameH, OBJPROP_WIDTH, 2);

   if(ObjectFind(nameL) < 0)
      ObjectCreate(nameL, OBJ_HLINE, 0, 0, g_rangeLow);
   else
      ObjectMove(nameL, 0, 0, g_rangeLow);
   ObjectSet(nameL, OBJPROP_COLOR, clrOrangeRed);
   ObjectSet(nameL, OBJPROP_STYLE, STYLE_DASH);
   ObjectSet(nameL, OBJPROP_WIDTH, 2);

   ChartRedraw();
}

//==========================================================================
//  OnTick 主逻辑
//==========================================================================
void OnTick()
{
   // ① 先监控浮盈
   MonitorProfit();

   // ② 硬性约束：有持仓则直接退出，空仓才能继续往下走
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != MagicNumber)          continue;
      if(OrderSymbol()      != Symbol())             continue;
      return; // 有持仓，直接退出
   }

   // ③ 超过最晚开单时间，不开单
   int curHour = TimeHour(TimeCurrent());
   if(curHour >= TradeEndHour) return;

   // ④ 区间统计时段结束后才开始计算区间
   if(curHour >= RangeEndHour)
      CalcDailyRange();

   if(!g_rangeReady) return;

   DrawRangeLines();

   // ⑤ 每根新K线只判断一次，防止同一根K线重复触发
   static datetime lastBarTime = 0;
   if(Time[0] == lastBarTime) return;
   lastBarTime = Time[0];

   // ⑥ 向上突破 → 开多
   if(ConfirmBreakoutUp())
   {
      double openPrice = Ask;
      double tp = CalcTP(OP_BUY, openPrice);
      double sl = CalcSL(OP_BUY, openPrice);

      int ticket = OrderSend(Symbol(), OP_BUY, LotSize,
                             openPrice, 3, sl, tp,
                             "M5 Breakout BUY", MagicNumber, 0, clrBlue);
      if(ticket > 0)
         Print("🔵 [BUY 0.01手] 向上突破 | Price=", openPrice,
               " | TP=", DoubleToString(tp, 5),
               " | SL=", DoubleToString(sl, 5));
      else
         Print("❌ BUY 开单失败，错误码:", GetLastError());
      return;
   }

   // ⑦ 向下突破 → 开空
   if(ConfirmBreakoutDown())
   {
      double openPrice = Bid;
      double tp = CalcTP(OP_SELL, openPrice);
      double sl = CalcSL(OP_SELL, openPrice);

      int ticket = OrderSend(Symbol(), OP_SELL, LotSize,
                             openPrice, 3, sl, tp,
                             "M5 Breakout SELL", MagicNumber, 0, clrRed);
      if(ticket > 0)
         Print("🔴 [SELL 0.01手] 向下突破 | Price=", openPrice,
               " | TP=", DoubleToString(tp, 5),
               " | SL=", DoubleToString(sl, 5));
      else
         Print("❌ SELL 开单失败，错误码:", GetLastError());
   }
}

//==========================================================================
//  OnInit
//==========================================================================
int OnInit()
{
   Print("======================================");
   Print("  DailyBreakoutEA M5 v2.0 启动");
   Print("  手数: ", LotSize, " (0.01最小手数)");
   Print("  区间时段: ", RangeStartHour, ":00 ~ ", RangeEndHour, ":00");
   Print("  盈利目标: $", ProfitTargetUSD);
   Print("  止损: $", StopLossUSD);
   Print("  硬性约束: 空仓才能开新单");
   Print("======================================");
   g_rangeReady = false;
   return(INIT_SUCCEEDED);
}

//==========================================================================
//  OnDeinit
//==========================================================================
void OnDeinit(const int reason)
{
   ObjectDelete("EA_RangeHigh");
   ObjectDelete("EA_RangeLow");
   Print("=== DailyBreakoutEA M5 已卸载 ===");
}//+------------------------------------------------------------------+
//|                                      XAUUSD_ThreeBarMomentum_EA  |
//|                    M5 momentum follow-through EA for XAUUSD      |
//+------------------------------------------------------------------+
#property strict
#property version   "1.0"
#property description "伦敦金M5三连动量EA"

input double FixedLots            = 0.01;      // 固定下单手数。当前策略限制为最多只持有 1 笔 0.01 手。
input int    MagicNumber          = 20260317;  // EA 订单唯一标识，只管理本 EA 自己的订单。
input int    SlippagePoints       = 50;        // 市价下单允许的最大滑点，单位为券商 points。
input double TakeProfitUsd        = 5.0;       // 固定止盈距离，按伦敦金价格单位计算，例如 3000.0 到 3005.0。
input double MinThreeBarMoveUsd   = 5.0;       // 最近 3 根信号K线的最小累计波动，达到后才算暴涨或暴跌。
input double StopBufferUsd        = 0.5;       // 结构止损外再额外留出的缓冲距离。
input string TradeSymbol          = "XAUUSD";  // 允许交易的图表品种，默认只做伦敦金。

datetime g_lastBarTime = 0;

// 判断当前图表品种上，是否已经存在本 EA 管理中的持仓订单。
bool IsManagedOpenPosition()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(OrderSymbol() != Symbol())
         continue;

      if(OrderMagicNumber() != MagicNumber)
         continue;

      if(OrderType() == OP_BUY || OrderType() == OP_SELL)
         return(true);
   }

   return(false);
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

// 判断是否满足三连阳动量条件：
// 1. 最近 3 根已收盘K线全部收阳
// 2. High 逐根抬高
// 3. Close 逐根抬高
// 4. 三根K线累计涨幅至少达到设定阈值
bool IsBullishMomentumSetup()
{
   double open3 = iOpen(Symbol(), PERIOD_M5, 3);
   double open2 = iOpen(Symbol(), PERIOD_M5, 2);
   double open1 = iOpen(Symbol(), PERIOD_M5, 1);
   double close3 = iClose(Symbol(), PERIOD_M5, 3);
   double close2 = iClose(Symbol(), PERIOD_M5, 2);
   double close1 = iClose(Symbol(), PERIOD_M5, 1);
   double high3 = iHigh(Symbol(), PERIOD_M5, 3);
   double high2 = iHigh(Symbol(), PERIOD_M5, 2);
   double high1 = iHigh(Symbol(), PERIOD_M5, 1);

   if(!(close3 > open3 && close2 > open2 && close1 > open1))
      return(false);

   if(!(high2 > high3 && high1 > high2))
      return(false);

   if(!(close2 > close3 && close1 > close2))
      return(false);

   return((close1 - open3) >= MinThreeBarMoveUsd);
}

// 判断是否满足三连阴动量条件：
// 1. 最近 3 根已收盘K线全部收阴
// 2. Low 逐根降低
// 3. Close 逐根降低
// 4. 三根K线累计跌幅至少达到设定阈值
bool IsBearishMomentumSetup()
{
   double open3 = iOpen(Symbol(), PERIOD_M5, 3);
   double open2 = iOpen(Symbol(), PERIOD_M5, 2);
   double open1 = iOpen(Symbol(), PERIOD_M5, 1);
   double close3 = iClose(Symbol(), PERIOD_M5, 3);
   double close2 = iClose(Symbol(), PERIOD_M5, 2);
   double close1 = iClose(Symbol(), PERIOD_M5, 1);
   double low3 = iLow(Symbol(), PERIOD_M5, 3);
   double low2 = iLow(Symbol(), PERIOD_M5, 2);
   double low1 = iLow(Symbol(), PERIOD_M5, 1);

   if(!(close3 < open3 && close2 < open2 && close1 < open1))
      return(false);

   if(!(low2 < low3 && low1 < low2))
      return(false);

   if(!(close2 < close3 && close1 < close2))
      return(false);

   return((open3 - close1) >= MinThreeBarMoveUsd);
}

// 取最近 3 根信号K线中的最低点，用于多单结构止损。
double LowestSignalLow()
{
   double low1 = iLow(Symbol(), PERIOD_M5, 1);
   double low2 = iLow(Symbol(), PERIOD_M5, 2);
   double low3 = iLow(Symbol(), PERIOD_M5, 3);
   return(MathMin(low1, MathMin(low2, low3)));
}

// 取最近 3 根信号K线中的最高点，用于空单结构止损。
double HighestSignalHigh()
{
   double high1 = iHigh(Symbol(), PERIOD_M5, 1);
   double high2 = iHigh(Symbol(), PERIOD_M5, 2);
   double high3 = iHigh(Symbol(), PERIOD_M5, 3);
   return(MathMax(high1, MathMax(high2, high3)));
}

// 按券商报价精度标准化价格，避免下单价格小数位不合法。
double NormalizePrice(double price)
{
   return(NormalizeDouble(price, Digits));
}

// 检查运行环境是否满足要求：
// 1. 品种必须是配置中的交易品种
// 2. 周期必须是 M5
// 3. 终端和券商必须允许交易
bool CheckTradeEnvironment()
{
   if(Symbol() != TradeSymbol)
   {
      Print("EA 配置的交易品种是 ", TradeSymbol, "，当前图表品种是 ", Symbol());
      return(false);
   }

   if(Period() != PERIOD_M5)
   {
      Print("EA 只能运行在 M5 周期。");
      return(false);
   }

   if(!IsTradeAllowed())
   {
      Print("当前终端或券商设置不允许交易。");
      return(false);
   }

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

// 按检测到的动量方向执行市价下单，并自动带上结构止损和固定止盈。
void SendMomentumOrder(int orderType)
{
   double entryPrice = (orderType == OP_BUY) ? Ask : Bid;
   double stopLoss = 0.0;
   double takeProfit = 0.0;
   color orderColor = (orderType == OP_BUY) ? clrDodgerBlue : clrTomato;

   if(orderType == OP_BUY)
   {
      stopLoss = LowestSignalLow() - StopBufferUsd;
      takeProfit = entryPrice + TakeProfitUsd;
   }
   else
   {
      stopLoss = HighestSignalHigh() + StopBufferUsd;
      takeProfit = entryPrice - TakeProfitUsd;
   }

   entryPrice = NormalizePrice(entryPrice);
   stopLoss = NormalizePrice(stopLoss);
   takeProfit = NormalizePrice(takeProfit);

   if(!ValidateStops(orderType, entryPrice, stopLoss, takeProfit))
   {
      Print("本次下单跳过，原因是止损或止盈距离当前价格过近。入场=", entryPrice,
            " 止损=", stopLoss, " 止盈=", takeProfit);
      return;
   }

   Print("准备发送订单。方向=", (orderType == OP_BUY ? "多" : "空"),
         " 入场=", entryPrice,
         " 止损=", stopLoss,
         " 止盈=", takeProfit,
         " 手数=", FixedLots,
         " 滑点=", SlippagePoints);

   int ticket = OrderSend(
      Symbol(),
      orderType,
      FixedLots,
      entryPrice,
      SlippagePoints,
      stopLoss,
      takeProfit,
      "三连动量",
      MagicNumber,
      0,
      orderColor
   );

   if(ticket < 0)
   {
      Print("OrderSend 下单失败。错误码=", GetLastError(),
            " 方向=", (orderType == OP_BUY ? "多" : "空"),
            " 入场=", entryPrice,
            " 止损=", stopLoss,
            " 止盈=", takeProfit);
      return;
   }

   Print("订单开仓成功。Ticket=", ticket,
         " 方向=", (orderType == OP_BUY ? "多" : "空"),
         " 入场=", entryPrice,
         " 止损=", stopLoss,
         " 止盈=", takeProfit);
}

int OnInit()
{
   Print("EA 初始化。品种=", Symbol(),
         " 周期=", Period(),
         " 魔术号=", MagicNumber,
         " 固定手数=", FixedLots,
         " 止盈=", TakeProfitUsd,
         " 三K最小波动=", MinThreeBarMoveUsd,
         " 止损缓冲=", StopBufferUsd,
         " 滑点=", SlippagePoints);

   if(Period() != PERIOD_M5)
      Print("请把 EA 挂到 M5 图表。");

   if(Symbol() != TradeSymbol)
      Print("请把 EA 挂到 ", TradeSymbol, " 图表。当前图表品种=", Symbol());

   return(INIT_SUCCEEDED);
}

void OnTick()
{
   if(!CheckTradeEnvironment())
      return;

   if(!HasEnoughBars())
   {
      Print("本次不判断信号，原因是历史 M5 K线数量不足。");
      return;
   }

   if(!IsNewBar())
      return;

   if(IsManagedOpenPosition())
   {
      Print("本次不再开新仓，原因是当前已经有本 EA 的持仓。");
      return;
   }

   if(GetManagedOpenLots() >= FixedLots)
   {
      Print("本次不再开新仓，原因是本 EA 已开仓总手数达到上限。当前手数=", GetManagedOpenLots());
      return;
   }

   RefreshRates();

   if(IsBullishMomentumSetup())
   {
      Print("检测到三连阳动量信号，准备执行多单。");
      SendMomentumOrder(OP_BUY);
      return;
   }

   if(IsBearishMomentumSetup())
   {
      Print("检测到三连阴动量信号，准备执行空单。");
      SendMomentumOrder(OP_SELL);
      return;
   }

   Print("最近 3 根已收盘 M5 K线未形成有效三连动量信号。");
}
