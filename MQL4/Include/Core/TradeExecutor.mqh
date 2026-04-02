#ifndef __CORE_TRADE_EXECUTOR_MQH__
#define __CORE_TRADE_EXECUTOR_MQH__

/*
 * 文件作用：
 * - 统一下单/平仓执行
 * - 固定 0.01 手 + symbol+magic 单持仓约束
 * - 动态止盈止损（三段式 ATR 规则）
 */

#include "Types.mqh"
#include "Logger.mqh"

class CTradeExecutor
{
private:
   CLogger *m_logger;

   bool IsOwnedOrder(const StrategyContext &ctx)
   {
      return (OrderSymbol() == ctx.symbol && OrderMagicNumber() == ctx.magicNumber);
   }

   bool CanModifyByBrokerDistance(int orderType, double targetSl, double targetTp)
   {
      double stopLevelPts = MarketInfo(Symbol(), MODE_STOPLEVEL);
      double freezeLevelPts = MarketInfo(Symbol(), MODE_FREEZELEVEL);
      double minDist = MathMax(stopLevelPts, freezeLevelPts) * Point;
      if(minDist < Point)
         minDist = Point;

      if(orderType == OP_BUY)
      {
         if(targetSl > 0 && (Bid - targetSl) < minDist)
            return false;
         if(targetTp > 0 && (targetTp - Ask) < minDist)
            return false;
      }
      else if(orderType == OP_SELL)
      {
         if(targetSl > 0 && (targetSl - Ask) < minDist)
            return false;
         if(targetTp > 0 && (Bid - targetTp) < minDist)
            return false;
      }

      return true;
   }

public:
   void Init(CLogger &logger)
   {
      m_logger = &logger;
   }

   int GetCurrentPosition(const StrategyContext &ctx)
   {
      for(int i = 0; i < OrdersTotal(); i++)
      {
         if(OrderSelect(i, SELECT_BY_POS, MODE_TRADES) && IsOwnedOrder(ctx))
            return OrderTicket();
      }
      return -1;
   }

   int OpenOrder(const StrategyContext &ctx, const TradeSignal &signal)
   {
      // 中文说明：硬性约束固定 0.01 手，不接受外部放大
      double lots = 0.01;
      double price = (signal.orderType == OP_BUY) ? Ask : Bid;

      for(int retry = 0; retry < ctx.maxRetries; retry++)
      {
         ResetLastError();
          int ticket = OrderSend(
             ctx.symbol,
             signal.orderType,
             lots,
             price,
             ctx.slippage,
             signal.stopLoss,
             signal.takeProfit,
             signal.comment,
             ctx.magicNumber,
             0,
             clrNONE
          );

         if(ticket > 0)
         {
            if(m_logger != NULL)
               m_logger.Info(StringFormat("订单开仓成功 #%d comment=%s lots=%.2f", ticket, signal.comment, lots));
            return ticket;
         }

         int err = GetLastError();
         if(m_logger != NULL)
            m_logger.Warning(StringFormat("订单发送失败 retry=%d/%d err=%d", retry + 1, ctx.maxRetries, err));

         if(retry < ctx.maxRetries - 1)
         {
            Sleep(800);
            RefreshRates();
            price = (signal.orderType == OP_BUY) ? Ask : Bid;
         }
      }

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
            // 只累计已平仓净收益
            double pnl = OrderProfit() + OrderSwap() + OrderCommission();
            state.dailyClosedProfit += pnl;

            // 平仓后清理动态跟踪状态
            state.entryPrice = 0.0;
            state.entryAtr = 0.0;
            state.highestCloseSinceEntry = 0.0;
            state.lowestCloseSinceEntry = 0.0;
            state.trailingActive = false;

            if(m_logger != NULL)
               m_logger.Info(StringFormat("订单平仓成功 #%d pnl=%.2f reason=%s", ticket, pnl, reason));
            return true;
         }

         if(retry < ctx.maxRetries - 1)
         {
            Sleep(800);
            closePrice = (OrderType() == OP_BUY) ? Bid : Ask;
         }
      }

      return false;
   }

   bool CheckStopLossTakeProfit(const StrategyContext &ctx, RuntimeState &state)
   {
      int ticket = GetCurrentPosition(ctx);
      if(ticket < 0)
         return false;
      if(!OrderSelect(ticket, SELECT_BY_TICKET))
         return false;

      double currentPrice = (OrderType() == OP_BUY) ? Bid : Ask;
      double sl = OrderStopLoss();
      double tp = OrderTakeProfit();

      if(sl > 0)
      {
         if((OrderType() == OP_BUY && currentPrice <= sl) ||
            (OrderType() == OP_SELL && currentPrice >= sl))
            return CloseOrder(ctx, ticket, state, "止损触发");
      }

      if(tp > 0)
      {
         if((OrderType() == OP_BUY && currentPrice >= tp) ||
            (OrderType() == OP_SELL && currentPrice <= tp))
            return CloseOrder(ctx, ticket, state, "止盈触发");
      }

      return false;
   }

   // 三段式动态保护：
   // 1) 浮盈 >= 1.0*ATR：SL提到保本±0.1*ATR，TP至少扩到2.5*ATR
   // 2) 浮盈 >= 1.5*ATR：激活追踪，SL按极值±0.9*ATR，TP按极值±0.8*ATR外推
   // 3) 仅允许朝有利方向推进，绝不回退保护
   void ApplyGlobalProfitLockIfNeeded(const StrategyContext &ctx)
   {
      int ticket = GetCurrentPosition(ctx);
      if(ticket < 0)
         return;
      if(!OrderSelect(ticket, SELECT_BY_TICKET))
         return;

      double atr = MathMax(ctx.atr14, Point * 10.0);
      double entry = OrderOpenPrice();
      int orderType = OrderType();

      double profitDistance = (orderType == OP_BUY) ? (Bid - entry) : (entry - Ask);
      if(profitDistance <= 0)
         return;

      double oldSl = OrderStopLoss();
      double oldTp = OrderTakeProfit();
      double newSl = oldSl;
      double newTp = oldTp;

      // 阶段1：1.0*ATR 触发保本上移 + TP扩展
      if(profitDistance >= atr * 1.0)
      {
         if(orderType == OP_BUY)
         {
            double bePlus = NormalizeDouble(entry + atr * 0.1, ctx.digits);
            if(oldSl <= 0 || bePlus > oldSl)
               newSl = bePlus;

            double tp25 = NormalizeDouble(entry + atr * 2.5, ctx.digits);
            if(oldTp <= 0 || tp25 > oldTp)
               newTp = tp25;
         }
         else
         {
            double bePlus = NormalizeDouble(entry - atr * 0.1, ctx.digits);
            if(oldSl <= 0 || bePlus < oldSl)
               newSl = bePlus;

            double tp25 = NormalizeDouble(entry - atr * 2.5, ctx.digits);
            if(oldTp <= 0 || tp25 < oldTp)
               newTp = tp25;
         }
      }

      // 阶段2：1.5*ATR 激活追踪
      if(profitDistance >= atr * 1.5)
      {
         double close1 = Close[1];
         if(orderType == OP_BUY)
         {
            if(close1 > 0)
            {
               if(close1 > newTp || newTp <= 0)
               {
                  double tpTrail = NormalizeDouble(close1 + atr * 0.8, ctx.digits);
                  if(tpTrail > newTp)
                     newTp = tpTrail;
               }
               double slTrail = NormalizeDouble(close1 - atr * 0.9, ctx.digits);
               if(slTrail > newSl)
                  newSl = slTrail;
            }
         }
         else
         {
            if(close1 > 0)
            {
               if(close1 < newTp || newTp <= 0)
               {
                  double tpTrail = NormalizeDouble(close1 - atr * 0.8, ctx.digits);
                  if(newTp <= 0 || tpTrail < newTp)
                     newTp = tpTrail;
               }
               double slTrail = NormalizeDouble(close1 + atr * 0.9, ctx.digits);
               if(newSl <= 0 || slTrail < newSl)
                  newSl = slTrail;
            }
         }
      }

      // 仅当真正有利推进且满足经纪商距离限制时才修改
      bool changed = false;
      if(orderType == OP_BUY)
         changed = ((newSl > oldSl + Point) || (newTp > oldTp + Point));
      else
         changed = ((newSl > 0 && (oldSl <= 0 || newSl < oldSl - Point)) ||
                    (newTp > 0 && (oldTp <= 0 || newTp < oldTp - Point)));

      if(!changed)
         return;
      if(!CanModifyByBrokerDistance(orderType, newSl, newTp))
         return;

      if(!OrderModify(ticket, entry, newSl, newTp, 0, clrNONE))
      {
         int err = GetLastError();
         if(m_logger != NULL)
            m_logger.Warning(StringFormat("动态保护修改失败 ticket=%d err=%d", ticket, err));
      }
      else
      {
         if(m_logger != NULL)
            m_logger.Info(StringFormat("动态保护更新 ticket=%d oldSL=%.5f newSL=%.5f oldTP=%.5f newTP=%.5f", ticket, oldSl, newSl, oldTp, newTp));
      }
   }

   // 兼容旧调用：统一转到三段式动态保护逻辑
   void ApplyProtectionIfNeeded(const StrategyContext &ctx)
   {
      ApplyGlobalProfitLockIfNeeded(ctx);
   }
};

#endif
