//+------------------------------------------------------------------+
//|                                    XAUUSD_Bollinger_ShortAndLong |
//|               黄金布林策略（做空+做多，简化版，MT4）              |
//+------------------------------------------------------------------+
#property strict
#property version   "3.0"
#property description "北京时间14:00-01:00，做空下破下轨，做多回踩中轨；多空各每天最多1单"

input string TradeSymbol            = "XAUUSD";    // 交易品种
input int    MagicNumber            = 20260320;    // 魔术号
input int    SlippagePoints         = 50;          // 允许滑点(points)
input bool   EnableDebugLogs        = true;        // 调试日志

input int    BollingerPeriod        = 30;          // 布林计算周期（收盘价）
input double BollingerStdFactor     = 1.5;         // 标准差倍数

input int    ServerToBjOffsetHrs    = 6;           // 服务器时间 +6小时 = 北京时间
input int    TradeStartHourBJ       = 14;          // 开始小时（北京时间）
input int    TradeEndHourBJ         = 1;           // 结束小时（北京时间，跨天）

// -------- 参数化交易配置（按你的要求不在主体逻辑写死） --------
input double LotsSell               = 0.02;        // 做空手数
input double SellStopLossUsd        = 40.0;        // 做空止损（价格美元）
input double SellTakeProfitUsd      = 70.0;        // 做空止盈（价格美元）

input double LotsBuy                = 0.02;        // 做多手数
input double BuyStopLossUsd         = 10.0;        // 做多止损（价格美元）
input double BuyTakeProfitUsd       = 20.0;        // 做多止盈（价格美元）

bool g_buyWasAboveMid = false;                     // 做多状态：是否已在中轨上方运行

void LogInfo(string msg)
{
   Print("[XAU-SIMPLE] ", msg);
}

void LogDebug(string msg)
{
   if(EnableDebugLogs)
      Print("[XAU-SIMPLE][DEBUG] ", msg);
}

double NormalizePrice(double price)
{
   return NormalizeDouble(price, Digits);
}

bool IsTradeEnvValid()
{
   if(Symbol() != TradeSymbol)
   {
      LogDebug("当前图表品种不是配置品种，当前=" + Symbol() + " 配置=" + TradeSymbol);
      return false;
   }

   if(Period() != PERIOD_M5)
   {
      LogDebug("当前图表周期不是M5，当前周期=" + IntegerToString(Period()));
      return false;
   }

   if(!IsTradeAllowed())
   {
      LogDebug("交易权限不可用，请检查终端自动交易开关与券商权限。");
      return false;
   }

   if(iBars(Symbol(), PERIOD_M5) <= BollingerPeriod + 5)
   {
      LogDebug("历史K线不足，无法计算布林带。");
      return false;
   }

   return true;
}

datetime GetBeijingNow()
{
   return (TimeCurrent() + ServerToBjOffsetHrs * 3600);
}

bool IsInTradeWindowByBeijing()
{
   datetime bjNow = GetBeijingNow();
   int h = TimeHour(bjNow);

   // 北京时间14:00到次日01:00（跨天）
   if(h >= TradeStartHourBJ || h < TradeEndHourBJ)
      return true;

   return false;
}

string GetBeijingDateString(datetime t)
{
   return TimeToString(t, TIME_DATE);
}

bool HasOpenedDirectionTodayByBeijing(int directionType)
{
   datetime bjNow = GetBeijingNow();
   string todayBj = GetBeijingDateString(bjNow);

   // 未平仓订单中是否已有今天开的该方向订单
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(OrderSymbol() != Symbol())
         continue;

      if(OrderMagicNumber() != MagicNumber)
         continue;

      if(OrderType() != directionType)
         continue;

      datetime openBj = OrderOpenTime() + ServerToBjOffsetHrs * 3600;
      if(GetBeijingDateString(openBj) == todayBj)
         return true;
   }

   // 历史订单中是否已有今天开的该方向订单
   for(int j = OrdersHistoryTotal() - 1; j >= 0; j--)
   {
      if(!OrderSelect(j, SELECT_BY_POS, MODE_HISTORY))
         continue;

      if(OrderSymbol() != Symbol())
         continue;

      if(OrderMagicNumber() != MagicNumber)
         continue;

      if(OrderType() != directionType)
         continue;

      datetime openBj2 = OrderOpenTime() + ServerToBjOffsetHrs * 3600;
      if(GetBeijingDateString(openBj2) == todayBj)
         return true;
   }

   return false;
}

bool HasOpenPositionByDirection(int directionType)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(OrderSymbol() != Symbol())
         continue;

      if(OrderMagicNumber() != MagicNumber)
         continue;

      if(OrderType() == directionType)
         return true;
   }

   return false;
}

bool GetBollingerBands(double &lowerBand, double &middleBand, double &upperBand)
{
   double sum = 0.0;
   for(int i = 1; i <= BollingerPeriod; i++)
      sum += iClose(Symbol(), PERIOD_M5, i);

   middleBand = sum / BollingerPeriod;
   double variance = 0.0;

   for(int j = 1; j <= BollingerPeriod; j++)
   {
      double d = iClose(Symbol(), PERIOD_M5, j) - middleBand;
      variance += d * d;
   }

   variance /= BollingerPeriod;
   double std = MathSqrt(variance);
   upperBand = middleBand + BollingerStdFactor * std;
   lowerBand = middleBand - BollingerStdFactor * std;
   return true;
}

bool IsBreakoutSellSignal()
{
   double lower = 0.0, middle = 0.0, upper = 0.0;
   if(!GetBollingerBands(lower, middle, upper))
      return false;

   // 做空信号：当前Bid跌破布林下轨
   return (Bid < lower);
}

bool IsPullbackMidlineBuySignal()
{
   double lower = 0.0, middle = 0.0, upper = 0.0;
   if(!GetBollingerBands(lower, middle, upper))
      return false;

   // 先在中轨上方运行
   if(Bid > middle)
   {
      g_buyWasAboveMid = true;
      return false;
   }

   // 然后回踩到中轨或以下，触发做多
   if(g_buyWasAboveMid && Bid <= middle)
   {
      g_buyWasAboveMid = false;
      return true;
   }

   return false;
}

bool ValidateStops(int orderType, double entry, double sl, double tp)
{
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

   if(orderType == OP_SELL)
   {
      if((sl - entry) < stopLevel)
         return false;
      if((entry - tp) < stopLevel)
         return false;
   }
   else if(orderType == OP_BUY)
   {
      if((entry - sl) < stopLevel)
         return false;
      if((tp - entry) < stopLevel)
         return false;
   }
   else
   {
      return false;
   }

   return true;
}

bool OpenSingleSellOrder()
{
   RefreshRates();

   double entry = NormalizePrice(Bid);
   double sl    = NormalizePrice(entry + SellStopLossUsd);
   double tp    = NormalizePrice(entry - SellTakeProfitUsd);

   if(!ValidateStops(OP_SELL, entry, sl, tp))
   {
      LogInfo("下单取消：止损/止盈距离不满足券商最小距离。");
      return false;
   }

   ResetLastError();
   int ticket = OrderSend(Symbol(), OP_SELL, LotsSell, entry, SlippagePoints,
                          sl, tp, "BollingerSell", MagicNumber, 0, clrTomato);
   if(ticket < 0)
   {
      LogInfo("OrderSend失败，错误码=" + IntegerToString(GetLastError()));
      return false;
   }

   LogInfo("开仓成功：Ticket=" + IntegerToString(ticket) +
           "，方向=SELL" +
           "，Lots=" + DoubleToString(LotsSell, 2) +
           "，SL=" + DoubleToString(sl, Digits) +
           "，TP=" + DoubleToString(tp, Digits));
   return true;
}

bool OpenSingleBuyOrder()
{
   RefreshRates();

   double entry = NormalizePrice(Ask);
   double sl    = NormalizePrice(entry - BuyStopLossUsd);
   double tp    = NormalizePrice(entry + BuyTakeProfitUsd);

   if(!ValidateStops(OP_BUY, entry, sl, tp))
   {
      LogInfo("做多下单取消：止损/止盈距离不满足券商最小距离。");
      return false;
   }

   ResetLastError();
   int ticket = OrderSend(Symbol(), OP_BUY, LotsBuy, entry, SlippagePoints,
                          sl, tp, "BollingerBuy", MagicNumber, 0, clrDodgerBlue);
   if(ticket < 0)
   {
      LogInfo("Buy OrderSend失败，错误码=" + IntegerToString(GetLastError()));
      return false;
   }

   LogInfo("开仓成功：Ticket=" + IntegerToString(ticket) +
           "，方向=BUY" +
           "，Lots=" + DoubleToString(LotsBuy, 2) +
           "，SL=" + DoubleToString(sl, Digits) +
           "，TP=" + DoubleToString(tp, Digits));
   return true;
}

int OnInit()
{
   LogInfo("EA初始化完成。Symbol=" + Symbol() +
           " Period=" + IntegerToString(Period()) +
           " Magic=" + IntegerToString(MagicNumber));

   LogInfo("参数：SELL(Lots=" + DoubleToString(LotsSell,2) +
           ",SL=" + DoubleToString(SellStopLossUsd,2) +
           ",TP=" + DoubleToString(SellTakeProfitUsd,2) +
           ") BUY(Lots=" + DoubleToString(LotsBuy,2) +
           ",SL=" + DoubleToString(BuyStopLossUsd,2) +
           ",TP=" + DoubleToString(BuyTakeProfitUsd,2) +
           ") 时段=北京时间" + IntegerToString(TradeStartHourBJ) + ":00-" + IntegerToString(TradeEndHourBJ) + ":00"
           + " 时差=+" + IntegerToString(ServerToBjOffsetHrs));

   g_buyWasAboveMid = false;

   return INIT_SUCCEEDED;
}

void OnTick()
{
   RefreshRates();

   if(!IsTradeEnvValid())
      return;

   // 仅在北京时间14:00-01:00交易
   if(!IsInTradeWindowByBeijing())
      return;

   // 做空：下破下轨；每天最多1单（按北京时间）；同方向有持仓不重复开
   if(!HasOpenedDirectionTodayByBeijing(OP_SELL) &&
      !HasOpenPositionByDirection(OP_SELL) &&
      IsBreakoutSellSignal())
   {
      OpenSingleSellOrder();
   }

   // 做多：先上方运行后回踩中轨；每天最多1单（按北京时间）；同方向有持仓不重复开
   if(!HasOpenedDirectionTodayByBeijing(OP_BUY) &&
      !HasOpenPositionByDirection(OP_BUY) &&
      IsPullbackMidlineBuySignal())
   {
      OpenSingleBuyOrder();
   }
}
