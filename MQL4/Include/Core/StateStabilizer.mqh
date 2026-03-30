#ifndef __CORE_STATE_STABILIZER_MQH__
#define __CORE_STATE_STABILIZER_MQH__

/*
 * 文件作用：
 * - 市场状态防抖器
 * - 只有状态连续出现 N 次才确认切换，降低频繁跳变
 */

#include "Types.mqh"

class CStateStabilizer
{
private:
   MarketRegime m_lastRaw;
   MarketRegime m_stable;
   int          m_count;
   int          m_requiredPromote;
   int          m_requiredDemote;

   bool IsTrendRegime(const MarketRegime regime)
   {
      return (regime == REGIME_TREND_UP || regime == REGIME_TREND_DOWN);
   }

public:
   void Init(int requiredPromoteBars = 2, int requiredDemoteBars = 2)
   {
      m_lastRaw = REGIME_UNKNOWN;
      m_stable = REGIME_UNKNOWN;
      m_count = 0;
      m_requiredPromote = MathMax(1, requiredPromoteBars);
      m_requiredDemote = MathMax(1, requiredDemoteBars);
   }

   MarketRegime Stabilize(MarketRegime raw)
   {
      if(raw == m_lastRaw)
         m_count++;
      else
      {
         m_lastRaw = raw;
         m_count = 1;
      }

      if(m_stable == REGIME_UNKNOWN)
      {
         if(m_count >= 1)
            m_stable = raw;
         return m_stable;
      }

      int required = m_requiredPromote;

      if(raw == m_stable)
         required = 1;
      else if(IsTrendRegime(m_stable))
      {
         // 旧趋势失效时分层处理：
         // - 直接反向趋势：允许更快切换（1根）
         // - 降级到震荡/突破准备：保持一定确认，抑制噪声
         if((m_stable == REGIME_TREND_UP && raw == REGIME_TREND_DOWN) ||
            (m_stable == REGIME_TREND_DOWN && raw == REGIME_TREND_UP))
            required = 1;
         else
            required = m_requiredDemote;
      }
      else
      {
         // 非趋势状态下，仅在“升级到趋势”时使用 promote 阈值；
         // 其余（如 RANGE <-> BREAKOUT_SETUP）快速跟随。
         if(IsTrendRegime(raw))
            required = m_requiredPromote;
         else
            required = 1;
      }

      if(m_count >= required)
         m_stable = raw;

      return m_stable;
   }
};

#endif
