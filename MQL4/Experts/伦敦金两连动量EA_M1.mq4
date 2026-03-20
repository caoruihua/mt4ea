//+------------------------------------------------------------------+
//|                                      XAUUSD_TwoBarMomentum_EA    |
//|                    M1 momentum follow-through EA for XAUUSD      |
//+------------------------------------------------------------------+
#property strict
#property version   "1.4"
#property description "伦敦金M1两连动量EA（精简版）"

input double FixedLots            = 0.01;      // 单次下单手数，同时也作为最大总持仓上限；默认最多持仓 0.01 手。
input int    MagicNumber          = 20260317;  // EA 订单唯一标识
input int    SlippagePoints       = 50;        // 市价下单最大滑点（points）
input double TakeProfitUsd        = 3.0;       // 固定止盈价格距离（XAUUSD价格单位，不是账户盈亏美元）
input double MinThreeBarMoveUsd   = 5.0;       // 最近2根已收盘K线的最小净涨跌幅（XAUUSD价格单位）
input double StopBufferUsd        = 0.5;       // 结构止损额外缓冲距离（XAUUSD价格单位，不是固定止损美元）
input string TradeSymbol          = "XAUUSD";  // 允许交易品种
input bool   EnableDebugLogs      = true;      // 是否输出调试日志（建议实盘可关闭）

datetime g_lastBarTime = 0;
bool g_loggedWrongSymbol   = false;
bool g_loggedWrongPeriod   = false;
bool g_loggedTradeNotAllow = false;
bool g_loggedBarsNotEnough = false;

void LogInfo(string msg)
{
   Print("[TBM] ", msg);
}

void LogDebug(string msg)
{
   if(EnableDebugLogs)
      Print("[TBM][DEBUG] ", msg);
}

// 检测是否出现新的 M1 K线，保证每根新K线只判断一次信号。
bool IsNewBar()
{
   datetime currentBarTime = iTime(Symbol(), PERIOD_M1, 0);
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
   return(iBars(Symbol(), PERIOD_M1) > 10);
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
   double open2 = iOpen(Symbol(), PERIOD_M1, 2);
   double open1 = iOpen(Symbol(), PERIOD_M1, 1);
   double close2 = iClose(Symbol(), PERIOD_M1, 2);
   double close1 = iClose(Symbol(), PERIOD_M1, 1);
   double high2 = iHigh(Symbol(), PERIOD_M1, 2);
   double high1 = iHigh(Symbol(), PERIOD_M1, 1);

   if(!(close2 > open2 && close1 > open1))
      return(false);

   if(!(high1 > high2))
      return(false);

   if(!(close1 > close2))
      return(false);

   return((close1 - open2) >= MinThreeBarMoveUsd);
}

// 判断是否满足两连阴动量条件：
// 1. 最近 2 根已收盘K线全部收阴
// 2. Low 逐根降低
// 3. Close 逐根降低
// 4. 从第2根信号K线开盘价到第1根信号K线收盘价的净跌幅至少达到设定阈值
bool IsBearishMomentumSetup()
{
   double open2 = iOpen(Symbol(), PERIOD_M1, 2);
   double open1 = iOpen(Symbol(), PERIOD_M1, 1);
   double close2 = iClose(Symbol(), PERIOD_M1, 2);
   double close1 = iClose(Symbol(), PERIOD_M1, 1);
   double low2 = iLow(Symbol(), PERIOD_M1, 2);
   double low1 = iLow(Symbol(), PERIOD_M1, 1);

   if(!(close2 < open2 && close1 < open1))
      return(false);

   if(!(low1 < low2))
      return(false);

   if(!(close1 < close2))
      return(false);

   return((open2 - close1) >= MinThreeBarMoveUsd);
}

// 取最近 2 根信号K线“最高点与最低点的平均价”，用于多单结构止损基准。
double LowestSignalLow()
{
   double high1 = iHigh(Symbol(), PERIOD_M1, 1);
   double high2 = iHigh(Symbol(), PERIOD_M1, 2);
   double low1 = iLow(Symbol(), PERIOD_M1, 1);
   double low2 = iLow(Symbol(), PERIOD_M1, 2);
   double highest = MathMax(high1, high2);
   double lowest = MathMin(low1, low2);
   return((highest + lowest) / 2.0);
}

// 取最近 2 根信号K线“最高点与最低点的平均价”，用于空单结构止损基准。
double HighestSignalHigh()
{
   double high1 = iHigh(Symbol(), PERIOD_M1, 1);
   double high2 = iHigh(Symbol(), PERIOD_M1, 2);
   double low1 = iLow(Symbol(), PERIOD_M1, 1);
   double low2 = iLow(Symbol(), PERIOD_M1, 2);
   double highest = MathMax(high1, high2);
   double lowest = MathMin(low1, low2);
   return((highest + lowest) / 2.0);
}

// 按券商报价精度标准化价格，避免下单价格小数位不合法。
double NormalizePrice(double price)
{
   return(NormalizeDouble(price, Digits));
}

// 检查运行环境是否满足要求：
// 1. 品种必须是配置中的交易品种
// 2. 周期必须是 M1
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

   if(Period() != PERIOD_M1)
   {
      if(!g_loggedWrongPeriod)
      {
         LogInfo("EA 只能运行在 M1 周期，当前周期=" + IntegerToString(Period()) + "，暂停交易。");
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

// 按检测到的动量方向执行市价下单，并自动带上“结构止损 + 缓冲距离”以及“固定价格距离止盈”。
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
      LogInfo("本次下单跳过：止损/止盈距离过近。入场=" + DoubleToString(entryPrice, Digits) +
              " 止损=" + DoubleToString(stopLoss, Digits) +
              " 止盈=" + DoubleToString(takeProfit, Digits));
      return;
   }

   LogInfo("准备发送订单。方向=" + string(orderType == OP_BUY ? "多" : "空") +
           " 入场=" + DoubleToString(entryPrice, Digits) +
           " 止损=" + DoubleToString(stopLoss, Digits) +
           " 止盈=" + DoubleToString(takeProfit, Digits) +
           " 手数=" + DoubleToString(FixedLots, 2) +
           " 滑点=" + IntegerToString(SlippagePoints));

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

   if(ticket < 0)
   {
      LogInfo("OrderSend 下单失败。错误码=" + IntegerToString(GetLastError()) +
              " 方向=" + string(orderType == OP_BUY ? "多" : "空") +
              " 入场=" + DoubleToString(entryPrice, Digits) +
              " 止损=" + DoubleToString(stopLoss, Digits) +
              " 止盈=" + DoubleToString(takeProfit, Digits));
      return;
   }

   LogInfo("订单开仓成功。Ticket=" + IntegerToString(ticket) +
           " 方向=" + string(orderType == OP_BUY ? "多" : "空") +
           " 入场=" + DoubleToString(entryPrice, Digits) +
           " 止损=" + DoubleToString(stopLoss, Digits) +
           " 止盈=" + DoubleToString(takeProfit, Digits));
}

int OnInit()
{
   LogInfo("EA 初始化。品种=" + Symbol() +
           " 周期=" + IntegerToString(Period()) +
           " 魔术号=" + IntegerToString(MagicNumber) +
           " 固定手数=" + DoubleToString(FixedLots, 2) +
           " 止盈=" + DoubleToString(TakeProfitUsd, 2) +
           " 两K最小波动=" + DoubleToString(MinThreeBarMoveUsd, 2) +
           " 止损缓冲=" + DoubleToString(StopBufferUsd, 2) +
           " 滑点=" + IntegerToString(SlippagePoints));

   if(Period() != PERIOD_M1)
      LogInfo("请把 EA 挂到 M1 图表。");

   if(Symbol() != TradeSymbol)
      LogInfo("请把 EA 挂到 " + TradeSymbol + " 图表。当前图表品种=" + Symbol());

   return(INIT_SUCCEEDED);
}

void OnTick()
{
   if(!CheckTradeEnvironment())
      return;

   if(!HasEnoughBars())
   {
      if(!g_loggedBarsNotEnough)
      {
         LogInfo("本次不判断信号：历史 M1 K线数量不足。");
         g_loggedBarsNotEnough = true;
      }
      return;
   }
   g_loggedBarsNotEnough = false;

   if(!IsNewBar())
      return;

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
      LogInfo("检测到两连阳动量信号，准备执行多单。");
      SendMomentumOrder(OP_BUY);
      return;
   }

   if(IsBearishMomentumSetup())
   {
      LogInfo("检测到两连阴动量信号，准备执行空单。");
      SendMomentumOrder(OP_SELL);
      return;
   }

   LogDebug("最近 2 根已收盘 M1 K线未形成有效两连动量信号。");
}
