#ifndef __CORE_LOGGER_MQH__
#define __CORE_LOGGER_MQH__

/*
 * 文件作用：
 * - 提供统一日志接口（Info/Debug/Warning/Error）
 * - 日志同时输出到文件与终端（Print）
 * - 通过日志级别控制输出详细程度
 */

class CLogger
{
private:
   int m_level;

public:
   void Init(int level)
   {
      m_level = level;
   }

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
         FileWrite(handle, "[" + timeStr + "] [" + level + "] " + message);
         FileClose(handle);
      }

      if(m_level >= 1)
         Print("[", level, "] ", message);
   }

   void Info(string message)    { if(m_level >= 1) Log("INFO", message); }
   void Debug(string message)   { if(m_level >= 2) Log("DEBUG", message); }
   void Warning(string message) { Log("WARNING", message); }
   void Error(string message)   { Log("ERROR", message); }
};

#endif
