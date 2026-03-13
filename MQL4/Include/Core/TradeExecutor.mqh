#ifndef __CORE_TRADE_EXECUTOR_MQH__
#define __CORE_TRADE_EXECUTOR_MQH__

/*
 * 文件作用：
 * - 统一下单/平仓执行
 * - 重试机制、持仓查询、SL/TP触发检查
 * - 更新日内盈亏统计
 */

#include "Types.mqh"
#include "Logger.mqh"

class CTradeExecutor
{
private:
   CLogger *m_logger;

public:
   void Init(CLogger &logger)
   {
      m_logger = &logger;
   }

   int GetCurrentPosition(const StrategyContext &ctx)
   {
      for(int i = 0; i < OrdersTotal(); i++)
      {
         if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         {
            if(OrderSymbol() == ctx.symbol && OrderMagicNumber() == ctx.magicNumber)
               return OrderTicket();
         }
      }
      return -1;
   }

   int OpenOrder(const StrategyContext &ctx, const TradeSignal &signal)
   {
      double price = (signal.orderType == OP_BUY) ? Ask : Bid;
      int ticket = -1;

      for(int retry = 0; retry < ctx.maxRetries; retry++)
      {
         ResetLastError();
         ticket = OrderSend(ctx.symbol, signal.orderType, signal.lots, price, ctx.slippage,
                           signal.stopLoss, signal.takeProfit, signal.comment,
                           ctx.magicNumber, 0, clrNONE);

         if(ticket > 0)
         {
            if(m_logger != NULL)
               m_logger.Info(StringFormat("Order opened #%d %s lots=%.2f price=%.5f", ticket, signal.comment, signal.lots, price));
            return ticket;
         }

         if(retry < ctx.maxRetries - 1)
            Sleep(1000);
      }

      if(m_logger != NULL)
         m_logger.Error("OrderSend failed after retries");
      return -1;
   }

   bool CloseOrder(const StrategyContext &ctx, int ticket, RuntimeState &state, string reason)
   {
      if(!OrderSelect(ticket, SELECT_BY_TICKET))
         return false;

      double closePrice = (OrderType() == OP_BUY) ? Bid : Ask;
      for(int retry = 0; retry < ctx.maxRetries; retry++)
      {
         ResetLastError();
         bool ok = OrderClose(ticket, OrderLots(), closePrice, ctx.slippage, clrNONE);
         if(ok)
         {
            double pnl = OrderProfit() + OrderSwap() + OrderCommission();
            if(pnl >= 0) state.dailyProfit += pnl;
            else state.dailyLoss += MathAbs(pnl);

            if(m_logger != NULL)
               m_logger.Info(StringFormat("Order closed #%d pnl=%.2f reason=%s", ticket, pnl, reason));
            return true;
         }

         if(retry < ctx.maxRetries - 1)
         {
            Sleep(1000);
            closePrice = (OrderType() == OP_BUY) ? Bid : Ask;
         }
      }

      if(m_logger != NULL)
         m_logger.Error(StringFormat("OrderClose failed #%d", ticket));
      return false;
   }

   void CheckStopLossTakeProfit(const StrategyContext &ctx, RuntimeState &state)
   {
      int ticket = GetCurrentPosition(ctx);
      if(ticket < 0) return;
      if(!OrderSelect(ticket, SELECT_BY_TICKET)) return;

      double currentPrice = (OrderType() == OP_BUY) ? Bid : Ask;
      double sl = OrderStopLoss();
      double tp = OrderTakeProfit();

      if(sl > 0)
      {
         if((OrderType() == OP_BUY && currentPrice <= sl) ||
            (OrderType() == OP_SELL && currentPrice >= sl))
         {
            CloseOrder(ctx, ticket, state, "Stop Loss Hit");
            return;
         }
      }

      if(tp > 0)
      {
         if((OrderType() == OP_BUY && currentPrice >= tp) ||
            (OrderType() == OP_SELL && currentPrice <= tp))
         {
            CloseOrder(ctx, ticket, state, "Take Profit Hit");
            return;
         }
      }
   }
};

#endif
