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
               m_logger.Info(StringFormat("订单开仓成功 #%d %s 手数=%.2f 价格=%.5f", ticket, signal.comment, signal.lots, price));
            return ticket;
         }

         int err = GetLastError();
         if(m_logger != NULL)
            m_logger.Warning(StringFormat("订单发送失败 retry=%d/%d err=%d price=%.5f", retry + 1, ctx.maxRetries, err, price));

         if(retry < ctx.maxRetries - 1)
         {
            Sleep(1000);
            price = (signal.orderType == OP_BUY) ? Ask : Bid;
         }
      }

      if(m_logger != NULL)
         m_logger.Error("订单发送失败，重试次数已用尽");
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
            double priceDelta = 0.0;
            if(OrderType() == OP_BUY)
               priceDelta = OrderClosePrice() - OrderOpenPrice();
            else if(OrderType() == OP_SELL)
               priceDelta = OrderOpenPrice() - OrderClosePrice();

            if(pnl >= 0) state.dailyProfit += pnl;
            else state.dailyLoss += MathAbs(pnl);

            if(priceDelta > 0)
               state.dailyPriceDelta += priceDelta;

            if(m_logger != NULL)
               m_logger.Info(StringFormat("订单平仓成功 #%d 盈亏=%.2f 价格差=%.2f 原因=%s", ticket, pnl, priceDelta, reason));
            return true;
         }

         if(retry < ctx.maxRetries - 1)
         {
            Sleep(1000);
            closePrice = (OrderType() == OP_BUY) ? Bid : Ask;
         }
      }

      if(m_logger != NULL)
         m_logger.Error(StringFormat("订单平仓失败 #%d", ticket));
      return false;
   }

   bool CheckStopLossTakeProfit(const StrategyContext &ctx, RuntimeState &state)
   {
      int ticket = GetCurrentPosition(ctx);
      if(ticket < 0) return false;
      if(!OrderSelect(ticket, SELECT_BY_TICKET)) return false;

      double currentPrice = (OrderType() == OP_BUY) ? Bid : Ask;
      double sl = OrderStopLoss();
      double tp = OrderTakeProfit();

      if(sl > 0)
      {
         if((OrderType() == OP_BUY && currentPrice <= sl) ||
            (OrderType() == OP_SELL && currentPrice >= sl))
         {
            CloseOrder(ctx, ticket, state, "止损触发");
            return true;
         }
      }

      if(tp > 0)
      {
         if((OrderType() == OP_BUY && currentPrice >= tp) ||
            (OrderType() == OP_SELL && currentPrice <= tp))
         {
            CloseOrder(ctx, ticket, state, "止盈触发");
            return true;
         }
      }

      return false;
   }

   void ApplyGlobalProfitLockIfNeeded(const StrategyContext &ctx)
   {
      if(!ctx.enable_global_profit_lock)
         return;

      int ticket = GetCurrentPosition(ctx);
      if(ticket < 0)
         return;
      if(!OrderSelect(ticket, SELECT_BY_TICKET))
         return;

      double trigger = MathMax(ctx.global_profit_lock_trigger_usd, 0.0);
      double offset = MathMax(ctx.global_profit_lock_offset_usd, 0.0);
      if(trigger <= 0)
         return;

      double openPrice = OrderOpenPrice();
      double oldSl = OrderStopLoss();
      double tp = OrderTakeProfit();
      double minGap = MathMax(Point * 2.0, 0.01);

      if(OrderType() == OP_BUY)
      {
         double floating = Bid - openPrice;
         if(floating < trigger)
            return;

         double newSl = NormalizeDouble(openPrice + offset, ctx.digits);

         // 阶梯推进止损（封顶 +15）：
         // 浮盈>=10 -> 锁+5；浮盈>=15 -> 锁+10；浮盈>=20 -> 锁+15
         if(floating >= 10.0)
         {
            int stepLevel = (int)MathFloor((floating - 10.0) / 5.0) + 1;
            if(stepLevel < 1)
               stepLevel = 1;
            if(stepLevel > 3)
               stepLevel = 3;

            double stepSl = NormalizeDouble(openPrice + stepLevel * 5.0, ctx.digits);
            if(stepSl > newSl)
               newSl = stepSl;
         }

         // 仅允许止损朝有利方向移动
         if(oldSl > 0 && newSl <= oldSl + Point)
            return;
         if(newSl >= Bid - minGap)
            return;

         if(OrderModify(ticket, openPrice, newSl, tp, 0, clrNONE) && m_logger != NULL)
            m_logger.Info(StringFormat("全局锁利/阶梯止损生效 #%d BUY oldSL=%.5f newSL=%.5f floating=%.2f trigger=%.2f", ticket, oldSl, newSl, floating, trigger));
      }
      else if(OrderType() == OP_SELL)
      {
         double floating = openPrice - Ask;
         if(floating < trigger)
            return;

         double newSl = NormalizeDouble(openPrice - offset, ctx.digits);

         // 阶梯推进止损（封顶 +15）：
         // 浮盈>=10 -> 锁+5；浮盈>=15 -> 锁+10；浮盈>=20 -> 锁+15
         if(floating >= 10.0)
         {
            int stepLevel = (int)MathFloor((floating - 10.0) / 5.0) + 1;
            if(stepLevel < 1)
               stepLevel = 1;
            if(stepLevel > 3)
               stepLevel = 3;

            double stepSl = NormalizeDouble(openPrice - stepLevel * 5.0, ctx.digits);
            if(stepSl < newSl)
               newSl = stepSl;
         }

         // 仅允许止损朝有利方向移动
         if(oldSl > 0 && newSl >= oldSl - Point)
            return;
         if(newSl <= Ask + minGap)
            return;

         if(OrderModify(ticket, openPrice, newSl, tp, 0, clrNONE) && m_logger != NULL)
            m_logger.Info(StringFormat("全局锁利/阶梯止损生效 #%d SELL oldSL=%.5f newSL=%.5f floating=%.2f trigger=%.2f", ticket, oldSl, newSl, floating, trigger));
      }
   }

   void ApplyProtectionIfNeeded(const StrategyContext &ctx)
   {
      if(!ctx.range_edge_enable_protection)
         return;

      int ticket = GetCurrentPosition(ctx);
      if(ticket < 0)
         return;
      if(!OrderSelect(ticket, SELECT_BY_TICKET))
         return;

      // 仅对区间边界反转策略订单应用移动保护
      string cmt = OrderComment();
      if(StringFind(cmt, "RangeEdgeReversion", 0) < 0)
         return;

      double trigger = MathMax(ctx.range_edge_protection_trigger_usd, 0.0);
      double lockUsd = MathMax(ctx.range_edge_protection_lock_usd, 0.0);
      if(trigger <= 0)
         return;

      double openPrice = OrderOpenPrice();
      double tp = OrderTakeProfit();
      double oldSl = OrderStopLoss();
      double minGap = MathMax(Point * 2.0, 0.01);

      if(OrderType() == OP_BUY)
      {
         double floating = Bid - openPrice;
         if(floating < trigger)
            return;

         double newSl = NormalizeDouble(openPrice + lockUsd, ctx.digits);
         if(oldSl > 0 && newSl <= oldSl + Point)
            return;
         if(newSl >= Bid - minGap)
            return;

         if(OrderModify(ticket, openPrice, newSl, tp, 0, clrNONE) && m_logger != NULL)
            m_logger.Info(StringFormat("移动保护生效 #%d BUY oldSL=%.5f newSL=%.5f", ticket, oldSl, newSl));
      }
      else if(OrderType() == OP_SELL)
      {
         double floating = openPrice - Ask;
         if(floating < trigger)
            return;

         double newSl = NormalizeDouble(openPrice - lockUsd, ctx.digits);
         if(oldSl > 0 && newSl >= oldSl - Point)
            return;
         if(newSl <= Ask + minGap)
            return;

         if(OrderModify(ticket, openPrice, newSl, tp, 0, clrNONE) && m_logger != NULL)
            m_logger.Info(StringFormat("移动保护生效 #%d SELL oldSL=%.5f newSL=%.5f", ticket, oldSl, newSl));
      }
   }
};

#endif
