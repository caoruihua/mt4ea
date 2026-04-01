#ifndef __CORE_SESSION_CLOCK_MQH__
#define __CORE_SESSION_CLOCK_MQH__

/*
 * 文件作用：
 * - 统一处理“服务器时间 -> 北京时间”换算
 * - 根据北京时间返回会话ID（1~6）
 * - 提供会话名称，便于日志与调试
 */

class CSessionClock
{
public:
   // 生成“服务器日键”：只保留日期部分（00:00:00）
   // 用途：
   // 1) 判断是否跨日
   // 2) 对日内风控（如+50锁定）做稳定重置
   datetime GetServerDayKey(datetime serverTime)
   {
      if(serverTime <= 0)
         serverTime = TimeCurrent();
      return StringToTime(TimeToStr(serverTime, TIME_DATE));
   }

   // 获取下一日键（dayKey + 1 day）
   datetime GetNextServerDayKey(datetime dayKey)
   {
      if(dayKey <= 0)
         dayKey = GetServerDayKey(TimeCurrent());
      return dayKey + 86400;
   }

   datetime GetBeijingTime(int timeZoneOffset)
   {
      return TimeCurrent() + timeZoneOffset * 3600;
   }

   int GetCurrentSession(datetime bjTime)
   {
      int hour = TimeHour(bjTime);
      int minute = TimeMinute(bjTime);
      int totalMinutes = hour * 60 + minute;

      if(totalMinutes >= 60 && totalMinutes < 420) return 1;
      if(totalMinutes >= 420 && totalMinutes < 435) return 2;
      if(totalMinutes >= 435 && totalMinutes < 480) return 3;
      if(totalMinutes >= 480 && totalMinutes < 900) return 4;
      if(totalMinutes >= 900 && totalMinutes < 1230) return 5;
      if(totalMinutes >= 1230 || totalMinutes < 60) return 6;

      return 0;
   }

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
      }
      return "Unknown Session";
   }
};

#endif
