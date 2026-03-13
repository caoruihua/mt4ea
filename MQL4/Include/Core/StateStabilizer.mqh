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
   int          m_required;

public:
   void Init(int requiredBars = 2)
   {
      m_lastRaw = REGIME_UNKNOWN;
      m_stable = REGIME_UNKNOWN;
      m_count = 0;
      m_required = requiredBars;
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

      if(m_count >= m_required)
         m_stable = raw;

      return m_stable;
   }
};

#endif
