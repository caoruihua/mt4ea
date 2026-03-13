//+------------------------------------------------------------------+
//|                                XAUUSD_MultiSession_Strategy.mq4 |
//|                                  Copyright 2026, Antigravity     |
//|                                             https://github.com/ |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Antigravity"
#property link      "https://github.com/"
#property version   "1.6"
#property description "XAUUSD Multi-Session Breakout Strategy"
#property strict

/**
 * Strategy Description:
 * This EA implements a multi-session breakout strategy for XAUUSD on M5 timeframe.
 * It monitors Asian session range and trades European session breakouts.
 * 
 * Core Rules:
 * - Maximum 1 open position at a time.
 * - Fixed lot size: 0.01.
 * - Circuit Breaker: Stop trading if daily profit > $50 or daily loss > 3% of balance.
 */

//--- Input Parameters
input int      TimeZoneOffset = 6;        // Time zone offset (GMT+2 + 6 = Beijing)
input int      MagicNumber    = 20260313; // Magic Number
input int      LogLevel       = 1;        // Log Level (0: Error, 1: Info, 2: Debug)

//--- Configurable price-distance parameters (USD on chart price)
// 说明：以下 *_USD 都是“图表价格差”，例如 XAUUSD 从 3000 到 3015 即 +15 美元价格差
input double   Session1_3_SL_USD                  = 10.0; // Session1/3 固定止损距离（价格差美元）
input double   Session1_3_TP_USD                  = 15.0; // Session1/3 固定止盈距离（价格差美元）
input double   Session2_SL_USD                    = 10.0; // Session2(07:05突破跟随)止损距离，越大越抗噪但单笔风险更高
input double   Session2_TP_USD                    = 15.0; // Session2 止盈距离，建议与 SL 搭配保持稳定盈亏比
input double   Session4_MinRange_USD              = 8.0;  // Session4 启动门槛：亚洲区间宽度至少达到该值才允许交易
input double   Session4_EntryBuffer_USD           = 3.0;  // Session4 入场缓冲：价格接近区间高/低点多少美元内触发
input double   Session4_SL_Buffer_USD             = 5.0;  // Session4 边界外保护：SL 放在区间边界外再偏移该距离
input double   Session4_TP_USD                    = 15.0; // Session4 固定止盈距离（价格差美元）
input double   Session5_FakeBreakout_Trigger_USD  = 3.0;  // Session5 假突破判定：刺穿亚洲高/低点至少该距离才认定“假突破候选”
input double   Session5_ValidBreakout_Trigger_USD = 5.0;  // Session5 真突破判定：收盘有效越界至少该距离
input double   Session5_SL_USD                    = 15.0; // Session5 止损距离/缓冲（用于真突破、EMA回踩及假突破边界外保护）
input double   Session5_TP_USD                    = 30.0; // Session5 止盈距离（趋势段通常可设得比 SL 更大）
input double   Session5_EMA_Tolerance_USD         = 2.0;  // Session5 EMA回踩容差：价格距离 EMA20 在该范围内才算“回踩到位”
input double   Session6_MinBody_USD               = 5.0;  // Session6 动量过滤：至少一根K线实体 >= 该值才允许动量入场
input double   Session6_SL_USD                    = 20.0; // Session6 止损距离（夜盘波动快，通常大于白天会话）
input double   Session6_TP_USD                    = 45.0; // Session6 止盈距离（配合动量延续，目标通常设置更远）

//--- Constants
const double   FIXED_LOTS             = 0.01;
const double   PROFIT_THRESHOLD_USD   = 50.0;
const double   LOSS_THRESHOLD_PERCENT = 3.0;
const int      SLIPPAGE               = 30;
const int      MAX_RETRIES            = 3;

//--- Global Variables
double         g_dailyProfit          = 0.0;
double         g_dailyLoss            = 0.0;
bool           g_circuitBreakerActive = false;
double         g_asianHigh            = 0.0;
double         g_asianLow             = 0.0;
int            g_euroBreakoutState    = 0;   // 0: None, 1: Long, 2: Short
datetime       g_lastResetDate        = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   // Print EA information
   Log("INFO", "=== XAUUSD Multi-Session Strategy v1.6 ===");
   Log("INFO", StringFormat("TimeZoneOffset: %d hours (Server GMT+2 + %d = Beijing GMT+8)", TimeZoneOffset, TimeZoneOffset));
   Log("INFO", StringFormat("MagicNumber: %d", MagicNumber));
   
   // Verify symbol
   if(Symbol() != "XAUUSD")
   {
      Log("WARNING", StringFormat("EA designed for XAUUSD, current symbol: %s", Symbol()));
      Alert("Warning: EA designed for XAUUSD, current symbol is ", Symbol());
   }
   
   // Verify timeframe
   if(Period() != PERIOD_M5)
   {
      Log("WARNING", StringFormat("EA designed for M5 timeframe, current: %d", Period()));
      Alert("Warning: EA designed for M5 timeframe");
   }
   
   // Verify account
   if(AccountBalance() <= 0)
   {
      Log("ERROR", "Invalid account balance");
      return(INIT_FAILED);
   }
   
   // Verify TimeZoneOffset
   if(TimeZoneOffset < 0 || TimeZoneOffset > 12)
   {
      Log("WARNING", StringFormat("TimeZoneOffset %d seems unusual (expected 0-12)", TimeZoneOffset));
   }
   
   // Load state
   LoadState();
   
   // Log initialization success
   Log("INFO", "EA initialized successfully");
   Log("INFO", StringFormat("Current session: %s", GetSessionName(GetCurrentSession())));
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   SaveState();
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // 每个 tick 都执行：先做时间重置与风控，再按会话分发策略
   // Check for daily reset at 01:00 Beijing time
   datetime bjTime = GetBeijingTime();
   int hour = TimeHour(bjTime);
   int minute = TimeMinute(bjTime);
   
   if(hour == 1 && minute == 0)
      ResetDailyState();
   
   // Check circuit breaker
   if(g_circuitBreakerActive)
      return;
   
   // Check stop loss / take profit
   CheckStopLossTakeProfit();
   
   // Get current session
   int session = GetCurrentSession();
   
   // Execute session strategy
   switch(session)
   {
      case 1: Session1_MorningStable(); break;
      case 2: Session2_MorningBreakout(); break;
      case 3: Session3_TransitionStable(); break;
      case 4: Session4_AsianRange(); break;
      case 5: Session5_EuropeTrend(); break;
      case 6: Session6_NewYorkMomentum(); break;
   }
}

//+------------------------------------------------------------------+
//| Get current Beijing time based on TimeZoneOffset                 |
//| Formula: TimeCurrent() + TimeZoneOffset * 3600                   |
//+------------------------------------------------------------------+
datetime GetBeijingTime()
{
   return TimeCurrent() + TimeZoneOffset * 3600;
}

//+------------------------------------------------------------------+
//| Get current trading session based on Beijing time                |
//| Returns: 1-6, or 0 if outside defined sessions                   |
//| Session 1: 01:00-07:00                                           |
//| Session 2: 07:00-07:15                                           |
//| Session 3: 07:15-08:00                                           |
//| Session 4: 08:00-15:00                                           |
//| Session 5: 15:00-20:30                                           |
//| Session 6: 20:30-01:00 (Cross-day)                               |
//+------------------------------------------------------------------+
int GetCurrentSession()
{
   datetime bjTime = GetBeijingTime();
   int hour = TimeHour(bjTime);
   int minute = TimeMinute(bjTime);
   int totalMinutes = hour * 60 + minute;

   // Session 1: 01:00-07:00 (60 to 419 minutes)
   if (totalMinutes >= 60 && totalMinutes < 420) return 1;
   
   // Session 2: 07:00-07:15 (420 to 434 minutes)
   if (totalMinutes >= 420 && totalMinutes < 435) return 2;
   
   // Session 3: 07:15-08:00 (435 to 479 minutes)
   if (totalMinutes >= 435 && totalMinutes < 480) return 3;
   
   // Session 4: 08:00-15:00 (480 to 899 minutes)
   if (totalMinutes >= 480 && totalMinutes < 900) return 4;
   
   // Session 5: 15:00-20:30 (900 to 1229 minutes)
   if (totalMinutes >= 900 && totalMinutes < 1230) return 5;
   
   // Session 6: 20:30-01:00 (1230 to 1439, or 0 to 59 minutes)
   if (totalMinutes >= 1230 || totalMinutes < 60) return 6;

   return 0;
}

//+------------------------------------------------------------------+
//| Get session name by session ID                                   |
//+------------------------------------------------------------------+
string GetSessionName(int session)
{
   switch(session)
   {
      case 1: return "Asian Session (Range)";
      case 2: return "Asian Session (End)";
      case 3: return "Pre-European (Buffer)";
      case 4: return "European Session (Breakout)";
      case 5: return "US Session (Trend)";
      case 6: return "Late Night (Close)";
      default: return "Unknown Session";
   }
}

//+------------------------------------------------------------------+
//| Log message to file                                              |
//| Format: [YYYY-MM-DD HH:MM:SS] [Level] Message                    |
//+------------------------------------------------------------------+
void Log(string level, string message)
{
   string dateStr = TimeToStr(TimeLocal(), TIME_DATE);
   StringReplace(dateStr, ".", "");
   string fileName = "EA_Log_" + dateStr + ".txt";
   
   int handle = FileOpen(fileName, FILE_READ|FILE_WRITE|FILE_TXT|FILE_SHARE_WRITE|FILE_SHARE_READ);
   if(handle != INVALID_HANDLE)
   {
      FileSeek(handle, 0, SEEK_END);
      string timeStr = TimeToStr(TimeLocal(), TIME_DATE|TIME_SECONDS);
      StringReplace(timeStr, ".", "-");
      string logLine = "[" + timeStr + "] [" + level + "] " + message;
      FileWrite(handle, logLine);
      FileClose(handle);
   }
   else
   {
      Print("Failed to open log file: ", fileName, " Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Log trade activity                                               |
//+------------------------------------------------------------------+
void LogTrade(string action, string symbol, double lots, double price, string reason)
{
   string msg = StringFormat("Trade %s: %s %.2f lots at %.2f. Reason: %s", action, symbol, lots, price, reason);
   Log("TRADE", msg);
}

//+------------------------------------------------------------------+
//| Log signal trigger                                               |
//+------------------------------------------------------------------+
void LogSignal(string signalType, string details)
{
   string msg = StringFormat("Signal %s: %s", signalType, details);
   Log("SIGNAL", msg);
}

//+------------------------------------------------------------------+
//| Log decision process                                             |
//+------------------------------------------------------------------+
void LogDecision(string decision, string reason)
{
   string msg = StringFormat("Decision: %s. Why: %s", decision, reason);
   Log("DECISION", msg);
}

//+------------------------------------------------------------------+
//| Save EA state to file                                            |
//+------------------------------------------------------------------+
void SaveState()
{
   int handle = FileOpen("EA_State.txt", FILE_WRITE | FILE_TXT);
   if(handle != INVALID_HANDLE)
   {
      FileWrite(handle, "DailyProfit=" + DoubleToString(g_dailyProfit, 2));
      FileWrite(handle, "DailyLoss=" + DoubleToString(g_dailyLoss, 2));
      FileWrite(handle, "CircuitBreakerActive=" + (g_circuitBreakerActive ? "1" : "0"));
      FileWrite(handle, "AsianHigh=" + DoubleToString(g_asianHigh, Digits));
      FileWrite(handle, "AsianLow=" + DoubleToString(g_asianLow, Digits));
      FileWrite(handle, "EuroBreakoutState=" + IntegerToString(g_euroBreakoutState));
      FileWrite(handle, "LastResetDate=" + TimeToString(g_lastResetDate));
      FileClose(handle);
      if(LogLevel >= 1) Print("EA state saved successfully.");
   }
   else
   {
      Print("Error saving EA state: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Load EA state from file                                          |
//+------------------------------------------------------------------+
void LoadState()
{
   int handle = FileOpen("EA_State.txt", FILE_READ | FILE_TXT);
   if(handle != INVALID_HANDLE)
   {
      while(!FileIsEnding(handle))
      {
         string line = FileReadString(handle);
         if(line == "") continue;
         
         int pos = StringFind(line, "=");
         if(pos > 0)
         {
            string key = StringSubstr(line, 0, pos);
            string value = StringSubstr(line, pos + 1);
            
            if(key == "DailyProfit") g_dailyProfit = StringToDouble(value);
            else if(key == "DailyLoss") g_dailyLoss = StringToDouble(value);
            else if(key == "CircuitBreakerActive") g_circuitBreakerActive = (StringToInteger(value) != 0);
            else if(key == "AsianHigh") g_asianHigh = StringToDouble(value);
            else if(key == "AsianLow") g_asianLow = StringToDouble(value);
            else if(key == "EuroBreakoutState") g_euroBreakoutState = (int)StringToInteger(value);
            else if(key == "LastResetDate") g_lastResetDate = StringToTime(value);
         }
      }
      FileClose(handle);
      if(LogLevel >= 1) Print("EA state loaded successfully.");
   }
   else
   {
      int error = GetLastError();
      if(error != 4101) // 4101 is ERR_FILE_NOT_FOUND
         Print("Error loading EA state: ", error);
      else
         Print("EA state file not found, using default values.");
         
      // Default values are already initialized in global variables
   }
}

//+------------------------------------------------------------------+
//| Get Exponential Moving Average (EMA)                             |
//| Period: 20 or 50, Timeframe: M5                                  |
//| EMA20: iMA(Symbol(), PERIOD_M5, 20, 0, MODE_EMA, PRICE_CLOSE, shift) |
//| EMA50: iMA(Symbol(), PERIOD_M5, 50, 0, MODE_EMA, PRICE_CLOSE, shift) |
//+------------------------------------------------------------------+
double GetEMA(int period, int shift)
{
   ResetLastError();
   double val = iMA(Symbol(), PERIOD_M5, period, 0, MODE_EMA, PRICE_CLOSE, shift);
   int error = GetLastError();
   if(error != 0)
   {
      Log("ERROR", StringFormat("Error calculating EMA(%d): %d", period, error));
      return -1.0;
   }
   return val;
}

//+------------------------------------------------------------------+
//| Get Relative Strength Index (RSI)                                |
//| Period: 14, Timeframe: M5                                        |
//| RSI: iRSI(Symbol(), PERIOD_M5, 14, PRICE_CLOSE, shift)           |
//+------------------------------------------------------------------+
double GetRSI(int shift)
{
   ResetLastError();
   double val = iRSI(Symbol(), PERIOD_M5, 14, PRICE_CLOSE, shift);
   int error = GetLastError();
   if(error != 0)
   {
      Log("ERROR", StringFormat("Error calculating RSI: %d", error));
      return -1.0;
   }
   return val;
}

//+------------------------------------------------------------------+
//| Get MACD Histogram (Main Line in MT4)                            |
//| Parameters: 12, 26, 9, Timeframe: M5                             |
//| MACD: iMACD(Symbol(), PERIOD_M5, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, shift) |
//+------------------------------------------------------------------+
double GetMACD(int shift)
{
   ResetLastError();
   double val = iMACD(Symbol(), PERIOD_M5, 12, 26, 9, PRICE_CLOSE, MODE_MAIN, shift);
   int error = GetLastError();
   if(error != 0)
   {
      Log("ERROR", StringFormat("Error calculating MACD: %d", error));
      return -1.0;
   }
   return val;
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Build SL/TP by order type using USD chart-price distance         |
//+------------------------------------------------------------------+
void BuildSLTP(int orderType, double slUsd, double tpUsd, double &sl, double &tp)
{
   // 统一按“美元价格差”计算，避免各 Session 重复写 Bid/Ask +/- distance
   if(orderType == OP_BUY)
   {
      sl = NormalizeDouble(Bid - slUsd, Digits);
      tp = NormalizeDouble(Ask + tpUsd, Digits);
   }
   else
   {
      sl = NormalizeDouble(Ask + slUsd, Digits);
      tp = NormalizeDouble(Bid - tpUsd, Digits);
   }
}


//+------------------------------------------------------------------+
//| Get current open position ticket                                 |
//| Returns: Ticket number if position exists, -1 if no position     |
//+------------------------------------------------------------------+
int GetCurrentPosition()
{
   for(int i = 0; i < OrdersTotal(); i++)
   {
      if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
      {
         if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber)
         {
            return OrderTicket();
         }
      }
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Open new order with retry logic                                  |
//| Returns: Ticket number if successful, -1 if failed               |
//+------------------------------------------------------------------+
int OpenOrder(int orderType, double lots, double stopLoss, double takeProfit, string comment)
{
   double price = (orderType == OP_BUY) ? Ask : Bid;
   int ticket = -1;
   
   for(int retry = 0; retry < MAX_RETRIES; retry++)
   {
      ResetLastError();
      ticket = OrderSend(Symbol(), orderType, lots, price, SLIPPAGE, stopLoss, takeProfit, comment, MagicNumber, 0, clrNONE);
      
      if(ticket > 0)
      {
         string direction = (orderType == OP_BUY) ? "BUY" : "SELL";
         LogTrade("OPEN", Symbol(), lots, price, comment);
         Log("INFO", StringFormat("Order opened: #%d %s %.2f lots at %.5f, SL=%.5f, TP=%.5f", 
                                  ticket, direction, lots, price, stopLoss, takeProfit));
         return ticket;
      }
      
      int error = GetLastError();
      Log("ERROR", StringFormat("OrderSend failed (attempt %d/%d): Error %d", retry + 1, MAX_RETRIES, error));
      
      if(retry < MAX_RETRIES - 1)
         Sleep(1000);
   }
   
   Log("ERROR", StringFormat("Failed to open order after %d attempts", MAX_RETRIES));
   return -1;
}

//+------------------------------------------------------------------+
//| Close order with retry logic                                     |
//| Returns: true if successful, false if failed                     |
//+------------------------------------------------------------------+
bool CloseOrder(int ticket, string reason)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET))
   {
      Log("ERROR", StringFormat("CloseOrder: Cannot select order #%d", ticket));
      return false;
   }
   
   double closePrice = (OrderType() == OP_BUY) ? Bid : Ask;
   bool success = false;
   
   for(int retry = 0; retry < MAX_RETRIES; retry++)
   {
      ResetLastError();
      success = OrderClose(ticket, OrderLots(), closePrice, SLIPPAGE, clrNONE);
      
      if(success)
      {
         // Calculate P&L
         double pnl = OrderProfit() + OrderSwap() + OrderCommission();
         
         if(pnl > 0)
            g_dailyProfit += pnl;
         else
            g_dailyLoss += MathAbs(pnl);
         
         LogTrade("CLOSE", OrderSymbol(), OrderLots(), closePrice, reason);
         Log("INFO", StringFormat("Order closed: #%d at %.5f, P&L=%.2f, Reason: %s", 
                                  ticket, closePrice, pnl, reason));
         
         SaveState();
         return true;
      }
      
      int error = GetLastError();
      Log("ERROR", StringFormat("OrderClose failed (attempt %d/%d): Error %d", retry + 1, MAX_RETRIES, error));
      
      if(retry < MAX_RETRIES - 1)
      {
         Sleep(1000);
         if(OrderType() == OP_BUY)
            closePrice = Bid;
         else
            closePrice = Ask;
      }
   }
   
   Log("ERROR", StringFormat("Failed to close order #%d after %d attempts", ticket, MAX_RETRIES));
   return false;
}

//+------------------------------------------------------------------+
//| Check and execute stop loss / take profit                        |
//+------------------------------------------------------------------+
void CheckStopLossTakeProfit()
{
   int ticket = GetCurrentPosition();
   if(ticket < 0) return;
   
   if(!OrderSelect(ticket, SELECT_BY_TICKET)) return;
   
   double currentPrice = (OrderType() == OP_BUY) ? Bid : Ask;
   double openPrice = OrderOpenPrice();
   double sl = OrderStopLoss();
   double tp = OrderTakeProfit();
   
   // Check stop loss
   if(sl > 0)
   {
      if((OrderType() == OP_BUY && currentPrice <= sl) || 
         (OrderType() == OP_SELL && currentPrice >= sl))
      {
         CloseOrder(ticket, "Stop Loss Hit");
         return;
      }
   }
   
   // Check take profit
   if(tp > 0)
   {
      if((OrderType() == OP_BUY && currentPrice >= tp) || 
         (OrderType() == OP_SELL && currentPrice <= tp))
      {
         CloseOrder(ticket, "Take Profit Hit");
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| Check circuit breaker conditions                                 |
//| Returns: true if circuit breaker triggered, false otherwise      |
//+------------------------------------------------------------------+
bool CheckCircuitBreaker()
{
   // 账户级风控：达到日盈利或日亏损阈值后，停止当日交易
   // Check profit threshold
   if(g_dailyProfit >= PROFIT_THRESHOLD_USD)
   {
      g_circuitBreakerActive = true;
      Log("WARNING", StringFormat("Circuit Breaker TRIGGERED: Daily profit %.2f >= %.2f USD", 
                                   g_dailyProfit, PROFIT_THRESHOLD_USD));
      
      // Close all positions
      int ticket = GetCurrentPosition();
      if(ticket > 0)
         CloseOrder(ticket, "Circuit Breaker - Profit Target");
      
      SaveState();
      return true;
   }
   
   // Check loss threshold
   double lossThreshold = AccountBalance() * LOSS_THRESHOLD_PERCENT / 100.0;
   if(g_dailyLoss >= lossThreshold)
   {
      g_circuitBreakerActive = true;
      Log("WARNING", StringFormat("Circuit Breaker TRIGGERED: Daily loss %.2f >= %.2f USD (%.1f%% of balance)", 
                                   g_dailyLoss, lossThreshold, LOSS_THRESHOLD_PERCENT));
      
      // Close all positions
      int ticket = GetCurrentPosition();
      if(ticket > 0)
         CloseOrder(ticket, "Circuit Breaker - Loss Limit");
      
      SaveState();
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Reset daily state at 01:00 Beijing time                          |
//+------------------------------------------------------------------+
void ResetDailyState()
{
   datetime bjTime = GetBeijingTime();
   datetime currentDate = StringToTime(TimeToStr(bjTime, TIME_DATE));
   
   // Check if we need to reset (new day)
   if(g_lastResetDate != currentDate)
   {
      Log("INFO", "Daily reset triggered at 01:00 Beijing time");
      
      // Force close all positions
      int ticket = GetCurrentPosition();
      if(ticket > 0)
      {
         Log("INFO", "Forcing close of position #" + IntegerToString(ticket) + " for daily reset");
         CloseOrder(ticket, "Daily Reset - 01:00");
      }
      
      // Reset all state variables
      g_dailyProfit = 0.0;
      g_dailyLoss = 0.0;
      g_circuitBreakerActive = false;
      g_asianHigh = 0.0;
      g_asianLow = 0.0;
      g_euroBreakoutState = 0;
      g_lastResetDate = currentDate;
      
      SaveState();
      Log("INFO", "Daily state reset complete");
   }
}

//+------------------------------------------------------------------+
//| Session 1: Morning Stable Strategy (01:00-07:00)                 |
//| EMA + RSI + MACD triple confirmation                             |
//+------------------------------------------------------------------+
void Session1_MorningStable()
{
   static int tradeCount = 0;
   static datetime lastResetDate = 0;
   
   // Reset trade count daily
   datetime currentDate = StringToTime(TimeToStr(GetBeijingTime(), TIME_DATE));
   if(lastResetDate != currentDate)
   {
      tradeCount = 0;
      lastResetDate = currentDate;
   }
   
   // Check preconditions
   if(g_circuitBreakerActive)
   {
      LogDecision("Session1 Skip", "Circuit breaker active");
      return;
   }
   
   if(GetCurrentPosition() >= 0)
   {
      LogDecision("Session1 Skip", "Position already open");
      return;
   }
   
   if(tradeCount >= 2)
   {
      LogDecision("Session1 Skip", "Max trades reached (2)");
      return;
   }
   
   // Get indicators
   double ema20 = GetEMA(20, 1);
   double ema50 = GetEMA(50, 1);
   double rsi = GetRSI(1);
   double macd = GetMACD(1);
   double close = Close[1];
   
   if(ema20 < 0 || ema50 < 0 || rsi < 0 || macd == -1.0) return;
   
   // 三指标同向确认后入场，减少单指标噪声
   // Long signal: Price > EMA20 && EMA20 > EMA50 && RSI(55-70) && MACD > 0
   if(close > ema20 && ema20 > ema50 && rsi > 55 && rsi < 70 && macd > 0)
   {
      string details = StringFormat("EMA20=%.2f, EMA50=%.2f, RSI=%.1f, MACD=%.5f", ema20, ema50, rsi, macd);
      LogSignal("Session1 LONG", details);
      
      double sl, tp;
      BuildSLTP(OP_BUY, Session1_3_SL_USD, Session1_3_TP_USD, sl, tp);
      int ticket = OpenOrder(OP_BUY, FIXED_LOTS, sl, tp, "Session1-Long");
      if(ticket > 0) tradeCount++;
      return;
   }
   
   // Short signal: Price < EMA20 && EMA20 < EMA50 && RSI(30-45) && MACD < 0
   if(close < ema20 && ema20 < ema50 && rsi > 30 && rsi < 45 && macd < 0)
   {
      string details = StringFormat("EMA20=%.2f, EMA50=%.2f, RSI=%.1f, MACD=%.5f", ema20, ema50, rsi, macd);
      LogSignal("Session1 SHORT", details);
      
      double sl, tp;
      BuildSLTP(OP_SELL, Session1_3_SL_USD, Session1_3_TP_USD, sl, tp);
      int ticket = OpenOrder(OP_SELL, FIXED_LOTS, sl, tp, "Session1-Short");
      if(ticket > 0) tradeCount++;
      return;
   }
}

//+------------------------------------------------------------------+
//| Session 3: Transition Stable Strategy (07:15-08:00)              |
//| Same as Session 1, max 1 trade                                   |
//+------------------------------------------------------------------+
void Session3_TransitionStable()
{
   static int tradeCount = 0;
   static datetime lastResetDate = 0;
   
   datetime currentDate = StringToTime(TimeToStr(GetBeijingTime(), TIME_DATE));
   if(lastResetDate != currentDate)
   {
      tradeCount = 0;
      lastResetDate = currentDate;
   }
   
   if(g_circuitBreakerActive || GetCurrentPosition() >= 0 || tradeCount >= 1)
      return;
   
   double ema20 = GetEMA(20, 1);
   double ema50 = GetEMA(50, 1);
   double rsi = GetRSI(1);
   double macd = GetMACD(1);
   double close = Close[1];
   
   if(ema20 < 0 || ema50 < 0 || rsi < 0 || macd == -1.0) return;
   
   // Long signal
   if(close > ema20 && ema20 > ema50 && rsi > 55 && rsi < 70 && macd > 0)
   {
      LogSignal("Session3 LONG", StringFormat("EMA20=%.2f, EMA50=%.2f, RSI=%.1f, MACD=%.5f", ema20, ema50, rsi, macd));
      double sl, tp;
      BuildSLTP(OP_BUY, Session1_3_SL_USD, Session1_3_TP_USD, sl, tp);
      int ticket = OpenOrder(OP_BUY, FIXED_LOTS, sl, tp, "Session3-Long");
      if(ticket > 0) tradeCount++;
      return;
   }
   
   // Short signal
   if(close < ema20 && ema20 < ema50 && rsi > 30 && rsi < 45 && macd < 0)
   {
      LogSignal("Session3 SHORT", StringFormat("EMA20=%.2f, EMA50=%.2f, RSI=%.1f, MACD=%.5f", ema20, ema50, rsi, macd));
      double sl, tp;
      BuildSLTP(OP_SELL, Session1_3_SL_USD, Session1_3_TP_USD, sl, tp);
      int ticket = OpenOrder(OP_SELL, FIXED_LOTS, sl, tp, "Session3-Short");
      if(ticket > 0) tradeCount++;
      return;
   }
}

//+------------------------------------------------------------------+
//| Session 2: Morning Breakout (07:00-07:15)                        |
//| First 5-min candle direction follow                              |
//+------------------------------------------------------------------+
void Session2_MorningBreakout()
{
   static bool traded = false;
   static datetime lastResetDate = 0;
   
   datetime bjTime = GetBeijingTime();
   datetime currentDate = StringToTime(TimeToStr(bjTime, TIME_DATE));
   if(lastResetDate != currentDate)
   {
      traded = false;
      lastResetDate = currentDate;
   }
   
   if(g_circuitBreakerActive || GetCurrentPosition() >= 0 || traded)
      return;
   
   int hour = TimeHour(bjTime);
   int minute = TimeMinute(bjTime);
   
   // 只在 07:05 判定一次，追随首根5分钟K线方向
   // Trigger at 07:05 (first 5-min candle closed)
   if(hour == 7 && minute == 5)
   {
      double open1 = Open[1];
      double close1 = Close[1];
      
      if(close1 > open1) // Bullish candle
      {
         LogSignal("Session2 LONG", "First candle bullish");
         double sl, tp;
         BuildSLTP(OP_BUY, Session2_SL_USD, Session2_TP_USD, sl, tp);
         int ticket = OpenOrder(OP_BUY, FIXED_LOTS, sl, tp, "Session2-Long");
         if(ticket > 0) traded = true;
      }
      else if(close1 < open1) // Bearish candle
      {
         LogSignal("Session2 SHORT", "First candle bearish");
         double sl, tp;
         BuildSLTP(OP_SELL, Session2_SL_USD, Session2_TP_USD, sl, tp);
         int ticket = OpenOrder(OP_SELL, FIXED_LOTS, sl, tp, "Session2-Short");
         if(ticket > 0) traded = true;
      }
   }
   
   // Force close at 07:15
   if(hour == 7 && minute == 15)
   {
      int ticket = GetCurrentPosition();
      if(ticket > 0)
         CloseOrder(ticket, "Session2 Force Close 07:15");
   }
}

//+------------------------------------------------------------------+
//| Session 4: Asian Range Strategy (08:00-15:00)                    |
//| High/Low range trading                                           |
//+------------------------------------------------------------------+
void Session4_AsianRange()
{
   static datetime rangeStartDate = 0;
   
   datetime bjTime = GetBeijingTime();
   datetime currentDate = StringToTime(TimeToStr(bjTime, TIME_DATE));
   int hour = TimeHour(bjTime);
   
   // Initialize range at 08:00
   if(hour == 8 && rangeStartDate != currentDate)
   {
      g_asianHigh = High[0];
      g_asianLow = Low[0];
      rangeStartDate = currentDate;
      SaveState();
   }
   
   // Update range continuously
   if(hour >= 8 && hour < 15)
   {
      if(High[0] > g_asianHigh) g_asianHigh = High[0];
      if(Low[0] < g_asianLow) g_asianLow = Low[0];
   }
   
   if(g_circuitBreakerActive || GetCurrentPosition() >= 0)
      return;
   
   // 这里直接使用价格差（美元），不再用 Point 换算
   double rangeWidth = g_asianHigh - g_asianLow;
   if(rangeWidth < Session4_MinRange_USD)
   {
      LogDecision("Session4 Skip", "Range too narrow");
      return;
   }
   
   double currentPrice = Bid;
   
   // 触及区间上沿附近做空，SL 放在区间上沿外侧缓冲
   // Sell at high
   if(currentPrice >= g_asianHigh - Session4_EntryBuffer_USD)
   {
      LogSignal("Session4 SHORT", StringFormat("Price near Asian High: %.5f", g_asianHigh));
      double sl = NormalizeDouble(g_asianHigh + Session4_SL_Buffer_USD, Digits);
      double tp = NormalizeDouble(Bid - Session4_TP_USD, Digits);
      OpenOrder(OP_SELL, FIXED_LOTS, sl, tp, "Session4-Short");
      return;
   }
   
   // 触及区间下沿附近做多，SL 放在区间下沿外侧缓冲
   // Buy at low
   if(currentPrice <= g_asianLow + Session4_EntryBuffer_USD)
   {
      LogSignal("Session4 LONG", StringFormat("Price near Asian Low: %.5f", g_asianLow));
      double sl = NormalizeDouble(g_asianLow - Session4_SL_Buffer_USD, Digits);
      double tp = NormalizeDouble(Ask + Session4_TP_USD, Digits);
      OpenOrder(OP_BUY, FIXED_LOTS, sl, tp, "Session4-Long");
      return;
   }
}

//+------------------------------------------------------------------+
//| Session 6: New York Momentum (20:30-01:00)                       |
//| Large candle momentum trading                                    |
//+------------------------------------------------------------------+
void Session6_NewYorkMomentum()
{
   if(g_circuitBreakerActive || GetCurrentPosition() >= 0)
      return;
   
   // Check for 2 consecutive candles in same direction
   double open1 = Open[1];
   double close1 = Close[1];
   double open2 = Open[2];
   double close2 = Close[2];
   
   bool bullish1 = close1 > open1;
   bool bullish2 = close2 > open2;
   bool bearish1 = close1 < open1;
   bool bearish2 = close2 < open2;
   
   double body1 = MathAbs(close1 - open1);
   double body2 = MathAbs(close2 - open2);
   
   // 至少一根实体达到阈值，过滤无效小波动
   // At least one candle body >= configured USD distance
   if(body1 < Session6_MinBody_USD && body2 < Session6_MinBody_USD)
      return;
   
   double ema20 = GetEMA(20, 0);
   if(ema20 < 0) return;
   
   // Long: 2 bullish candles + price > EMA20
   if(bullish1 && bullish2 && Close[0] > ema20)
   {
      LogSignal("Session6 LONG", "2 bullish candles + above EMA20");
      double sl, tp;
      BuildSLTP(OP_BUY, Session6_SL_USD, Session6_TP_USD, sl, tp);
      OpenOrder(OP_BUY, FIXED_LOTS, sl, tp, "Session6-Long");
      return;
   }
   
   // Short: 2 bearish candles + price < EMA20
   if(bearish1 && bearish2 && Close[0] < ema20)
   {
      LogSignal("Session6 SHORT", "2 bearish candles + below EMA20");
      double sl, tp;
      BuildSLTP(OP_SELL, Session6_SL_USD, Session6_TP_USD, sl, tp);
      OpenOrder(OP_SELL, FIXED_LOTS, sl, tp, "Session6-Short");
      return;
   }
}

//+------------------------------------------------------------------+
//| Session 5: European Trend Strategy (15:00-20:30)                 |
//| Three-signal parallel system                                     |
//+------------------------------------------------------------------+
void Session5_EuropeTrend()
{
   static int tradeCount = 0;
   static datetime lastResetDate = 0;
   static double fakeBreakoutLow = 0;
   static double fakeBreakoutHigh = 0;
   
   datetime currentDate = StringToTime(TimeToStr(GetBeijingTime(), TIME_DATE));
   if(lastResetDate != currentDate)
   {
      tradeCount = 0;
      fakeBreakoutLow = 0;
      fakeBreakoutHigh = 0;
      lastResetDate = currentDate;
   }
   
   if(g_circuitBreakerActive || GetCurrentPosition() >= 0 || tradeCount >= 2)
      return;
   
   double currentPrice = Bid;
   
   // 信号优先级：假突破 > 真突破 > EMA回踩
   // Signal 1: Fake Breakout (highest priority)
   // Fake breakout down: price broke Asian Low by configured USD, then closed back above
   if(g_asianLow > 0 && currentPrice < g_asianLow - Session5_FakeBreakout_Trigger_USD)
   {
      if(fakeBreakoutLow == 0 || Low[0] < fakeBreakoutLow)
         fakeBreakoutLow = Low[0];
   }
   if(fakeBreakoutLow > 0 && Close[1] > g_asianLow)
   {
      LogSignal("Session5 LONG", "Fake breakout below Asian Low");
      double sl = NormalizeDouble(fakeBreakoutLow - Session5_SL_USD, Digits);
      double tp = NormalizeDouble(Ask + Session5_TP_USD, Digits);
      int ticket = OpenOrder(OP_BUY, FIXED_LOTS, sl, tp, "Session5-FakeBreakout-Long");
      if(ticket > 0)
      {
         tradeCount++;
         g_euroBreakoutState = 1;
         SaveState();
      }
      return;
   }
   
   // Fake breakout up: price broke Asian High by configured USD, then closed back below
   if(g_asianHigh > 0 && currentPrice > g_asianHigh + Session5_FakeBreakout_Trigger_USD)
   {
      if(fakeBreakoutHigh == 0 || High[0] > fakeBreakoutHigh)
         fakeBreakoutHigh = High[0];
   }
   if(fakeBreakoutHigh > 0 && Close[1] < g_asianHigh)
   {
      LogSignal("Session5 SHORT", "Fake breakout above Asian High");
      double sl = NormalizeDouble(fakeBreakoutHigh + Session5_SL_USD, Digits);
      double tp = NormalizeDouble(Bid - Session5_TP_USD, Digits);
      int ticket = OpenOrder(OP_SELL, FIXED_LOTS, sl, tp, "Session5-FakeBreakout-Short");
      if(ticket > 0)
      {
         tradeCount++;
         g_euroBreakoutState = 2;
         SaveState();
      }
      return;
   }
   
   // Signal 2: Valid Breakout (second priority)
   // Valid breakout up: 2 consecutive closes above Asian High, breakout > configured USD
   if(g_asianHigh > 0 && Close[1] > g_asianHigh + Session5_ValidBreakout_Trigger_USD && Close[2] > g_asianHigh)
   {
      LogSignal("Session5 LONG", "Valid breakout above Asian High");
      double sl, tp;
      BuildSLTP(OP_BUY, Session5_SL_USD, Session5_TP_USD, sl, tp);
      int ticket = OpenOrder(OP_BUY, FIXED_LOTS, sl, tp, "Session5-ValidBreakout-Long");
      if(ticket > 0)
      {
         tradeCount++;
         g_euroBreakoutState = 1;
         SaveState();
      }
      return;
   }
   
   // Valid breakout down: 2 consecutive closes below Asian Low, breakout > configured USD
   if(g_asianLow > 0 && Close[1] < g_asianLow - Session5_ValidBreakout_Trigger_USD && Close[2] < g_asianLow)
   {
      LogSignal("Session5 SHORT", "Valid breakout below Asian Low");
      double sl, tp;
      BuildSLTP(OP_SELL, Session5_SL_USD, Session5_TP_USD, sl, tp);
      int ticket = OpenOrder(OP_SELL, FIXED_LOTS, sl, tp, "Session5-ValidBreakout-Short");
      if(ticket > 0)
      {
         tradeCount++;
         g_euroBreakoutState = 2;
         SaveState();
      }
      return;
   }
   
   // Signal 3: EMA Pullback (lowest priority)
   double ema20 = GetEMA(20, 1);
   double ema50 = GetEMA(50, 1);
   double rsi = GetRSI(1);
   double close = Close[1];
   
   if(ema20 < 0 || ema50 < 0 || rsi < 0) return;
   
   // Long: EMA20 > EMA50, price pullback to EMA20, bullish bounce, RSI 45-65
   if(ema20 > ema50 && MathAbs(close - ema20) <= Session5_EMA_Tolerance_USD && Close[1] > ema20 && rsi > 45 && rsi < 65)
   {
      LogSignal("Session5 LONG", "EMA pullback long");
      double sl, tp;
      BuildSLTP(OP_BUY, Session5_SL_USD, Session5_TP_USD, sl, tp);
      int ticket = OpenOrder(OP_BUY, FIXED_LOTS, sl, tp, "Session5-EMAPullback-Long");
      if(ticket > 0) tradeCount++;
      return;
   }
   
   // Short: EMA20 < EMA50, price bounce to EMA20, bearish rejection, RSI 35-55
   if(ema20 < ema50 && MathAbs(close - ema20) <= Session5_EMA_Tolerance_USD && Close[1] < ema20 && rsi > 35 && rsi < 55)
   {
      LogSignal("Session5 SHORT", "EMA pullback short");
      double sl, tp;
      BuildSLTP(OP_SELL, Session5_SL_USD, Session5_TP_USD, sl, tp);
      int ticket = OpenOrder(OP_SELL, FIXED_LOTS, sl, tp, "Session5-EMAPullback-Short");
      if(ticket > 0) tradeCount++;
      return;
   }
}
