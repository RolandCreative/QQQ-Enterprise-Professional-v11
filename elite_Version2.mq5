#property strict
#property version   "11.20"
#property copyright "RolandCreative"
#property link      "https://github.com/RolandCreative/QQQ-Enterprise-Professional-v11"

#include <Trade\Trade.mqh>

CTrade trade;

//====================================================================
// INPUTS - EJECUCIÓN Y RIESGO
//====================================================================
input group "=== EJECUCIÓN Y RIESGO ==="
input double RiskPercent              = 0.45;
input double DefensiveRiskPercent     = 0.20;
input bool   EnableLiveTrading        = false;
input long   MagicNumber              = 26081106;
input double MaxSpreadPoints          = 180.0;
input double MaxDynamicSpreadPercent  = 120.0;
input double MaxDailyLossPercent      = 2.0;
input double MaximumDrawdownPercent   = 8.0;
input double DefensiveDrawdownPercent = 4.0;
input int    MaximumConsecutiveLosses = 4;
input int    PauseMinutesAfterLoss    = 90;
input bool   ClosePositionsOnHardStop = true;
input int    SlippagePoints           = 8;
input bool   OnePositionOnly          = false;
input int    MaxTradesPerDay          = 8;
input int    MaxEntriesPerSetup       = 3;
input double MaximumExposurePercent   = 35.0;
input bool   UseKellyCriterion        = true;
input double MaxKellyFraction         = 0.30;
input bool   UseAdaptiveRisk          = true;

//====================================================================
// INPUTS - FILTROS Y SESIÓN
//====================================================================
input group "=== FILTROS ==="
input bool   UseNewsFilter           = true;
input int    NewsBufferMinutes       = 30;
input bool   UseMultiTimeframeFilter = true;
input bool   UseVolatilityFilter     = true;
input double MinimumATRPoints        = 12.0;
input double MaximumATRPoints        = 2200.0;
input bool   UseSessionFilter        = true;
input bool   RestrictToUSMarketHours  = true;
input bool   AvoidEarningsWindow     = true;
input int    EarningsWindowMinutes   = 60;
input string QQQSymbolAlias          = "QQQ";

//====================================================================
// INPUTS - TENDENCIA / ICT
//====================================================================
input group "=== TENDENCIA E ICT ==="
input ENUM_TIMEFRAMES TrendTF          = PERIOD_H4;
input int TrendFastEMA                 = 20;
input int TrendSlowEMA                 = 50;
input bool RequireTrendSlope           = true;
input bool RequireMultiTFTrend         = true;
input bool EnableICTLogic              = true;
input bool RequireLiquiditySweep       = true;
input bool RequireFVGConfirmation      = true;
input int  ICTLookbackBars             = 30;

//====================================================================
// INPUTS - ENTRADAS
//====================================================================
input group "=== ENTRADAS ==="
input bool UseBreakout           = false;
input int  EntryEMA              = 9;
input int  EntrySlowEMA          = 21;
input int  ATRPeriod             = 14;
input int  RSIPeriod             = 14;
input int  BreakoutBars          = 20;
input double BreakoutRSILevel    = 55.0;
input double PullbackBuyRSIMin   = 45.0;
input double PullbackBuyRSIMax   = 68.0;
input double PullbackSellRSIMin  = 32.0;
input double PullbackSellRSIMax  = 55.0;

//====================================================================
// INPUTS - STOPS Y TARGETS
//====================================================================
input group "=== STOP LOSS Y TAKE PROFIT ==="
input double ATRStopMultiplier     = 1.25;
input double MinimumStopPoints      = 20.0;
input double MaxStopLossPoints      = 250.0;
input double RRRatio               = 2.00;
input bool   EnableBreakEven       = true;
input double BreakEvenAtR          = 1.00;
input double BreakEvenOffsetPoints = 8.0;
input bool   EnableTrailing        = true;
input double TrailingStartR        = 1.50;
input double TrailingATRMultiplier = 1.10;
input bool   EnablePartialTP       = false;
input double PartialTPPercent      = 50.0;
input double PartialTPAtR          = 0.50;

//====================================================================
// INPUTS - TELEGRAM Y LOGGING
//====================================================================
input group "=== TELEGRAM ==="
input bool   EnableTelegramAlerts = false;
input string TelegramBotToken      = "";
input string TelegramChatID        = "";
input int    TelegramTimeoutMs     = 5000;

input group "=== LOGGING ==="
input bool   EnableDetailedLogging = true;
input bool   SaveTradeLog          = true;

//====================================================================
// ENUMS
//====================================================================
enum ENUM_BOT_STATE
{
   BOT_NORMAL = 0,
   BOT_DEFENSIVE,
   BOT_HALTED
};

enum ENUM_MARKET_REGIME
{
   REGIME_NEUTRAL = 0,
   REGIME_BULLISH,
   REGIME_BEARISH
};

enum ENUM_SESSION_TYPE
{
   SESSION_PRE_MARKET = 0,
   SESSION_OPEN,
   SESSION_MIDDAY,
   SESSION_CLOSE,
   SESSION_AFTER_HOURS
};

//====================================================================
// ESTRUCTURAS
//====================================================================
struct TradeLog
{
   datetime openTime;
   ENUM_ORDER_TYPE type;
   double entryPrice;
   double stopLoss;
   double takeProfit;
   double volume;
   double riskPercent;
   string trendBias;
   string reason;
};

TradeLog lastTrades[100];
int tradeLogIndex = 0;

struct StrategyStats
{
   int totalTrades;
   int wins;
   int losses;
   int breakeven;
   double grossProfit;
   double grossLoss;
   double avgWin;
   double avgLoss;
   double bestTrade;
   double worstTrade;
   datetime lastUpdated;
};

StrategyStats g_stats;

//====================================================================
// VARIABLES GLOBALES
//====================================================================
ENUM_BOT_STATE CurrentBotState = BOT_NORMAL;
ENUM_BOT_STATE PreviousBotState = BOT_NORMAL;

int hTrendFast = INVALID_HANDLE;
int hTrendSlow = INVALID_HANDLE;
int hEntryEMA  = INVALID_HANDLE;
int hEntrySlow = INVALID_HANDLE;
int hATR       = INVALID_HANDLE;
int hRSI       = INVALID_HANDLE;
int hTrendFastMTF = INVALID_HANDLE;
int hTrendSlowMTF = INVALID_HANDLE;

datetime LastBarTime = 0;
double PeakEquity = 0.0;
string PeakEquityGV = "";
string TradeLogFile = "";

//====================================================================
// INIT / DEINIT / TICK
//====================================================================
int OnInit()
{
   if(!IsQQQSymbol())
   {
      Print("Este EA está diseñado para QQQ / NASDAQ100.");
      return INIT_FAILED;
   }

   if(RiskPercent <= 0.0 || RiskPercent > 2.0)
   {
      Print("RiskPercent debe estar entre 0 y 2.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(TrendFastEMA <= 0 || TrendSlowEMA <= TrendFastEMA ||
      EntryEMA <= 0 || EntrySlowEMA <= EntryEMA ||
      ATRPeriod <= 0 || RSIPeriod <= 0)
   {
      Print("Parámetros de indicadores inválidos.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(MaxEntriesPerSetup <= 0 || MaxEntriesPerSetup > 3)
      MaxEntriesPerSetup = 3;

   hTrendFast = iMA(_Symbol, TrendTF, TrendFastEMA, 0, MODE_EMA, PRICE_CLOSE);
   hTrendSlow = iMA(_Symbol, TrendTF, TrendSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hEntryEMA  = iMA(_Symbol, _Period, EntryEMA, 0, MODE_EMA, PRICE_CLOSE);
   hEntrySlow = iMA(_Symbol, _Period, EntrySlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   hATR       = iATR(_Symbol, _Period, ATRPeriod);
   hRSI       = iRSI(_Symbol, _Period, RSIPeriod, PRICE_CLOSE);

   if(UseMultiTimeframeFilter)
   {
      ENUM_TIMEFRAMES mtf = (TrendTF == PERIOD_H4) ? PERIOD_D1 : PERIOD_H4;
      hTrendFastMTF = iMA(_Symbol, mtf, TrendFastEMA, 0, MODE_EMA, PRICE_CLOSE);
      hTrendSlowMTF = iMA(_Symbol, mtf, TrendSlowEMA, 0, MODE_EMA, PRICE_CLOSE);
   }

   if(hTrendFast == INVALID_HANDLE || hTrendSlow == INVALID_HANDLE ||
      hEntryEMA == INVALID_HANDLE || hEntrySlow == INVALID_HANDLE ||
      hATR == INVALID_HANDLE || hRSI == INVALID_HANDLE)
   {
      Print("Error creando indicadores principales.");
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber((ulong)MagicNumber);
   trade.SetDeviationInPoints(SlippagePoints);
   trade.SetTypeFilling(FillingMode());

   InitializePeakEquity();
   InitializeTradeLog();
   InitializeStrategyStats();
   CurrentBotState = EvaluateBotState();

   Print("\n╔══════════════════════════════════════════════════════╗");
   Print("║ QQQ ENTERPRISE PROFESSIONAL v11.20              ║");
   Print("║ Nasdaq-100 | ICT | 3 Entries | Risk Control     ║");
   Print("╠══════════════════════════════════════════════════════╣");
   Print("║ Símbolo: ", _Symbol);
   Print("║ Timeframe: ", _Period, " min");
   Print("║ Trend TF: ", TrendTF, " | MTF: ", UseMultiTimeframeFilter ? "ON" : "OFF");
   Print("║ ICT: ", EnableICTLogic ? "ON" : "OFF");
   Print("║ Estado: ", BotStateText(CurrentBotState));
   Print("╚══════════════════════════════════════════════════════╝\n");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(hTrendFast != INVALID_HANDLE) IndicatorRelease(hTrendFast);
   if(hTrendSlow != INVALID_HANDLE) IndicatorRelease(hTrendSlow);
   if(hEntryEMA != INVALID_HANDLE) IndicatorRelease(hEntryEMA);
   if(hEntrySlow != INVALID_HANDLE) IndicatorRelease(hEntrySlow);
   if(hATR != INVALID_HANDLE) IndicatorRelease(hATR);
   if(hRSI != INVALID_HANDLE) IndicatorRelease(hRSI);

   if(UseMultiTimeframeFilter)
   {
      if(hTrendFastMTF != INVALID_HANDLE) IndicatorRelease(hTrendFastMTF);
      if(hTrendSlowMTF != INVALID_HANDLE) IndicatorRelease(hTrendSlowMTF);
   }

   Comment("");
}

void OnTick()
{
   if(!IsQQQSymbol())
      return;

   UpdatePeakEquity();
   CurrentBotState = EvaluateBotState();
   NotifyStateChange();

   if(CurrentBotState == BOT_HALTED && ClosePositionsOnHardStop)
      CloseOurPositions();

   ManageOpenPositions();
   UpdateDashboard();

   if(!IsNewBar())
      return;

   TryOpenPosition();
}

//====================================================================
// UTILIDADES GENERALES
//====================================================================
bool IsQQQSymbol()
{
   string symbol = _Symbol;
   StringToUpper(symbol);

   string alias = QQQSymbolAlias;
   StringToUpper(alias);

   if(StringLen(alias) > 0 && symbol == alias)
      return true;

   return StringFind(symbol, "QQQ") >= 0 ||
          StringFind(symbol, "NASDAQ") >= 0 ||
          StringFind(symbol, "NDX") >= 0 ||
          StringFind(symbol, "QQQM") >= 0;
}

bool ExecutionAllowed()
{
   return EnableLiveTrading || (bool)MQLInfoInteger(MQL_TESTER);
}

string BotStateText(const ENUM_BOT_STATE state)
{
   if(state == BOT_NORMAL) return "NORMAL";
   if(state == BOT_DEFENSIVE) return "DEFENSIVO";
   return "HALTED";
}

bool IsNewBar()
{
   datetime currentBarTime = iTime(_Symbol, _Period, 0);
   if(currentBarTime <= 0)
      return false;

   if(currentBarTime != LastBarTime)
   {
      LastBarTime = currentBarTime;
      return true;
   }
   return false;
}

ENUM_ORDER_TYPE_FILLING FillingMode()
{
   long mode = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);

   if((mode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;

   if((mode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;

   return ORDER_FILLING_RETURN;
}

double BrokerMinDistancePoints()
{
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   return (double)MathMax(stopsLevel, freezeLevel) + 2.0;
}

bool IsStopAndTargetValid(const double entryPrice, const double stopPrice,
                          const double takeProfit, const bool buySignal)
{
   double minDistance = BrokerMinDistancePoints() * _Point;
   double slDistance = buySignal ? entryPrice - stopPrice : stopPrice - entryPrice;
   double tpDistance = buySignal ? takeProfit - entryPrice : entryPrice - takeProfit;
   return slDistance >= minDistance && tpDistance >= minDistance;
}

double NormalizeVolume(const double requestedVolume)
{
   double minVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxVolume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step      = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(minVolume <= 0.0 || maxVolume <= 0.0 || step <= 0.0)
      return 0.0;

   int digits = 0;
   double value = step;

   while(value < 1.0 && digits < 8)
   {
      value *= 10.0;
      digits++;
   }

   double volume = MathFloor(requestedVolume / step) * step;
   if(volume < minVolume)
      return 0.0;

   volume = MathMin(volume, maxVolume);
   return NormalizeDouble(volume, digits);
}

int CountOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (long)PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         count++;
   }
   return count;
}

double TotalExposurePercent()
{
   double netVolume = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         (long)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      netVolume += PositionGetDouble(POSITION_VOLUME);
   }

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0)
      return 1000000.0;

   return (netVolume / (equity / 100.0)) * 100.0;
}

//====================================================================
// TELEGRAM
//====================================================================
string UrlEncode(string text)
{
   uchar bytes[];
   StringToCharArray(text, bytes, 0, WHOLE_ARRAY, CP_UTF8);
   string result = "";

   for(int i = 0; i < ArraySize(bytes); i++)
   {
      uchar c = bytes[i];
      if(c == 0)
         break;

      bool safe = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                  (c >= '0' && c <= '9') || c == '-' || c == '_' ||
                  c == '.' || c == '~';

      if(safe)
         result += CharToString((uchar)c);
      else if(c == ' ')
         result += "%20";
      else
         result += StringFormat("%%%02X", c);
   }

   return result;
}

bool TelegramConfigured()
{
   return EnableTelegramAlerts && !MQLInfoInteger(MQL_TESTER) &&
          StringLen(TelegramBotToken) > 10 && StringLen(TelegramChatID) > 0;
}

void TelegramAlert(const string message)
{
   if(!TelegramConfigured())
      return;

   string url = "https://api.telegram.org/bot" + TelegramBotToken +
                "/sendMessage?chat_id=" + UrlEncode(TelegramChatID) +
                "&text=" + UrlEncode(message);

   char data[];
   char result[];
   string responseHeaders;

   ResetLastError();
   int responseCode = WebRequest("GET", url, "", TelegramTimeoutMs, data, result, responseHeaders);

   if(responseCode != 200)
      Print("Telegram falló. HTTP=", responseCode);
}

//====================================================================
// LOGGING Y ESTADÍSTICAS
//====================================================================
void InitializeTradeLog()
{
   if(!SaveTradeLog)
      return;

   TradeLogFile = StringFormat("QQQ_EA_%s_%I64d.log",
      TimeToString(TimeCurrent(), TIME_DATE),
      AccountInfoInteger(ACCOUNT_LOGIN));
}

void LogTrade(const TradeLog &tl)
{
   if(!EnableDetailedLogging && !SaveTradeLog)
      return;

   string logMsg = StringFormat(
      "[%s] %s | Entry: %.2f | SL: %.2f | TP: %.2f | Vol: %.2f | Risk: %.2f%% | Trend: %s | Reason: %s",
      TimeToString(tl.openTime, TIME_DATE|TIME_MINUTES),
      tl.type == ORDER_TYPE_BUY ? "BUY" : "SELL",
      tl.entryPrice, tl.stopLoss, tl.takeProfit, tl.volume,
      tl.riskPercent, tl.trendBias, tl.reason
   );

   Print(logMsg);

   if(SaveTradeLog)
   {
      int handle = FileOpen(TradeLogFile, FILE_READ|FILE_WRITE|FILE_TXT);
      if(handle != INVALID_HANDLE)
      {
         FileSeek(handle, 0, SEEK_END);
         FileWrite(handle, logMsg);
         FileClose(handle);
      }
   }

   if(tradeLogIndex < 99)
   {
      lastTrades[tradeLogIndex] = tl;
      tradeLogIndex++;
   }
}

void InitializeStrategyStats()
{
   ZeroMemory(g_stats);
   g_stats.lastUpdated = TimeCurrent();
}

void UpdateStrategyStatsFromDeal(const ulong dealTicket)
{
   if(dealTicket == 0)
      return;

   if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != _Symbol)
      return;

   if((long)HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != MagicNumber)
      return;

   double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT) +
                  HistoryDealGetDouble(dealTicket, DEAL_SWAP) +
                  HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);

   if(profit > 0.0)
   {
      g_stats.totalTrades++;
      g_stats.wins++;
      g_stats.grossProfit += profit;
      g_stats.avgWin = (g_stats.avgWin * (g_stats.wins - 1) + profit) / g_stats.wins;
      if(g_stats.bestTrade < profit)
         g_stats.bestTrade = profit;
   }
   else if(profit < 0.0)
   {
      g_stats.totalTrades++;
      g_stats.losses++;
      g_stats.grossLoss += MathAbs(profit);
      g_stats.avgLoss = (g_stats.avgLoss * (g_stats.losses - 1) + MathAbs(profit)) / g_stats.losses;
      if(g_stats.worstTrade > profit)
         g_stats.worstTrade = profit;
   }
   else
   {
      g_stats.totalTrades++;
      g_stats.breakeven++;
   }

   g_stats.lastUpdated = TimeCurrent();
}

//====================================================================
// EQUITY Y RIESGO
//====================================================================
void InitializePeakEquity()
{
   PeakEquityGV = StringFormat(
      "QQQ_ENTERPRISE_PEAK_%I64d_%s_%I64d",
      AccountInfoInteger(ACCOUNT_LOGIN),
      _Symbol,
      MagicNumber
   );

   if(MQLInfoInteger(MQL_TESTER))
   {
      PeakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      return;
   }

   if(GlobalVariableCheck(PeakEquityGV))
      PeakEquity = GlobalVariableGet(PeakEquityGV);
   else
   {
      PeakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      GlobalVariableSet(PeakEquityGV, PeakEquity);
   }
}

void UpdatePeakEquity()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity > PeakEquity)
   {
      PeakEquity = equity;
      if(!MQLInfoInteger(MQL_TESTER))
         GlobalVariableSet(PeakEquityGV, PeakEquity);
   }
}

double CurrentDrawdownPercent()
{
   if(PeakEquity <= 0.0)
      return 0.0;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity >= PeakEquity)
      return 0.0;

   return ((PeakEquity - equity) / PeakEquity) * 100.0;
}

double DailyNetProfit()
{
   datetime startOfDay = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   if(!HistorySelect(startOfDay, TimeCurrent()))
      return 0.0;

   double result = 0.0;
   int totalDeals = (int)HistoryDealsTotal();

   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;

      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol ||
         (long)HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber)
         continue;

      result += HistoryDealGetDouble(ticket, DEAL_PROFIT);
      result += HistoryDealGetDouble(ticket, DEAL_SWAP);
      result += HistoryDealGetDouble(ticket, DEAL_COMMISSION);
   }
   return result;
}

int ConsecutiveLosses()
{
   datetime fromTime = TimeCurrent() - 90 * 86400;
   if(!HistorySelect(fromTime, TimeCurrent()))
      return 0;

   int losses = 0;
   int totalDeals = (int)HistoryDealsTotal();

   for(int i = totalDeals - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;

      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol ||
         (long)HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber)
         continue;

      long entryType = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entryType != DEAL_ENTRY_OUT && entryType != DEAL_ENTRY_OUT_BY)
         continue;

      double result = HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                     HistoryDealGetDouble(ticket, DEAL_SWAP) +
                     HistoryDealGetDouble(ticket, DEAL_COMMISSION);

      if(result < 0.0)
         losses++;
      else if(result > 0.0)
         break;
   }

   return losses;
}

bool LossCooldownActive()
{
   if(PauseMinutesAfterLoss <= 0)
      return false;

   datetime lastLoss = 0;
   datetime fromTime = TimeCurrent() - 90 * 86400;

   if(!HistorySelect(fromTime, TimeCurrent()))
      return false;

   int totalDeals = (int)HistoryDealsTotal();

   for(int i = totalDeals - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;

      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol ||
         (long)HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber)
         continue;

      long entryType = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entryType != DEAL_ENTRY_OUT && entryType != DEAL_ENTRY_OUT_BY)
         continue;

      double result = HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                     HistoryDealGetDouble(ticket, DEAL_SWAP) +
                     HistoryDealGetDouble(ticket, DEAL_COMMISSION);

      if(result < 0.0)
      {
         lastLoss = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         break;
      }
   }

   if(lastLoss == 0)
      return false;

   return TimeCurrent() < lastLoss + PauseMinutesAfterLoss * 60;
}

int TradesOpenedToday()
{
   datetime startOfDay = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   if(!HistorySelect(startOfDay, TimeCurrent()))
      return 0;

   int count = 0;
   int totalDeals = (int)HistoryDealsTotal();

   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0)
         continue;

      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol ||
         (long)HistoryDealGetInteger(ticket, DEAL_MAGIC) != MagicNumber)
         continue;

      long entryType = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entryType == DEAL_ENTRY_IN)
         count++;
   }

   return count;
}

double AdaptiveRiskPercent()
{
   double base = RiskPercent;
   if(!UseAdaptiveRisk)
      return base;

   double dd = CurrentDrawdownPercent();
   double daily = DailyNetProfit();
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(equity <= 0.0)
      return 0.0;

   if(dd >= DefensiveDrawdownPercent)
      base *= 0.60;
   if(dd >= MaximumDrawdownPercent * 0.75)
      base *= 0.40;

   if(daily < 0.0)
      base *= 0.85;

   return MathMax(0.0, MathMin(base, 2.0));
}

double EffectiveRiskPercent()
{
   CurrentBotState = EvaluateBotState();

   if(CurrentBotState == BOT_HALTED)
      return 0.0;

   if(CurrentBotState == BOT_DEFENSIVE)
      return DefensiveRiskPercent;

   return AdaptiveRiskPercent();
}

ENUM_BOT_STATE EvaluateBotState()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0)
      return BOT_HALTED;

   double dailyProfit = DailyNetProfit();
   double dailyLimit = equity * MaxDailyLossPercent / 100.0;
   double drawdown = CurrentDrawdownPercent();
   int losses = ConsecutiveLosses();

   if(dailyProfit <= -dailyLimit)
      return BOT_HALTED;

   if(drawdown >= MaximumDrawdownPercent)
      return BOT_HALTED;

   if(losses >= MaximumConsecutiveLosses)
      return BOT_HALTED;

   if(drawdown >= DefensiveDrawdownPercent)
      return BOT_DEFENSIVE;

   if(losses >= 2)
      return BOT_DEFENSIVE;

   return BOT_NORMAL;
}

//====================================================================
// POSICIONES
//====================================================================
bool HasOurPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (long)PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         return true;
   }
   return false;
}

double LotsForRisk(const ENUM_ORDER_TYPE orderType,
                   const double entryPrice,
                   const double stopPrice,
                   const double riskPercent)
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0 || riskPercent <= 0.0)
      return 0.0;

   double cashRisk = equity * riskPercent / 100.0;
   double lossForOneLot = 0.0;

   if(!OrderCalcProfit(orderType, _Symbol, 1.0, entryPrice, stopPrice, lossForOneLot))
   {
      Print("OrderCalcProfit falló. Error=", GetLastError());
      return 0.0;
   }

   lossForOneLot = MathAbs(lossForOneLot);
   if(lossForOneLot <= 0.0)
      return 0.0;

   return NormalizeVolume(cashRisk / lossForOneLot);
}

//====================================================================
// FILTROS
//====================================================================
bool SpreadOK()
{
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);

   if(spread > (long)MaxSpreadPoints)
   {
      Print("Entrada bloqueada por spread. Actual=", spread, " Máximo=", MaxSpreadPoints);
      return false;
   }

   double dynamicLimit = (double)spread * MaxDynamicSpreadPercent / 100.0;
   if(spread > dynamicLimit)
   {
      Print("Spread dinámico superado. Actual=", spread, " Límite=", dynamicLimit);
      return false;
   }

   return true;
}

bool VolatilityOK(const double atrValue)
{
   if(!UseVolatilityFilter)
      return true;

   if(atrValue <= 0.0)
      return false;

   double atrPoints = atrValue / _Point;
   if(atrPoints < MinimumATRPoints)
      return false;

   if(MaximumATRPoints > 0.0 && atrPoints > MaximumATRPoints)
      return false;

   return true;
}

bool IsUSMarketOpen()
{
   MqlDateTime dt;
   TimeToStruct(TimeLocal(), dt);

   int day = dt.day_of_week;
   if(day == 0 || day == 6)
      return false;

   int totalMinutes = dt.hour * 60 + dt.min;
   return totalMinutes >= 9 * 60 + 30 && totalMinutes < 16 * 60;
}

bool EarningsWindowOK()
{
   if(!AvoidEarningsWindow)
      return true;
   return true;
}

bool NewsFilterOK()
{
   if(!UseNewsFilter)
      return true;
   if(!IsUSMarketOpen())
      return false;
   return true;
}

ENUM_SESSION_TYPE GetCurrentSession()
{
   MqlDateTime dt;
   TimeToStruct(TimeLocal(), dt);

   int totalMinutes = dt.hour * 60 + dt.min;

   if(totalMinutes < 9 * 60 + 30)
      return SESSION_PRE_MARKET;
   if(totalMinutes < 12 * 60)
      return SESSION_OPEN;
   if(totalMinutes < 15 * 60)
      return SESSION_MIDDAY;
   if(totalMinutes < 16 * 60)
      return SESSION_CLOSE;

   return SESSION_AFTER_HOURS;
}

bool SessionFilterOK()
{
   if(!UseSessionFilter)
      return true;

   if(!RestrictToUSMarketHours)
      return true;

   return IsUSMarketOpen();
}

bool HardExposureOK()
{
   double exposurePercent = TotalExposurePercent();
   if(exposurePercent > MaximumExposurePercent)
   {
      Print("Exposición máxima superada. Exposure=", exposurePercent, "%");
      return false;
   }
   return true;
}

double CalculateStopDistance(const double atrValue)
{
   if(atrValue <= 0.0)
      return 0.0;

   double brokerMinDistance = BrokerMinDistancePoints() * _Point;
   double atrDistance = atrValue * ATRStopMultiplier;
   double stopDistance = MathMax(atrDistance, brokerMinDistance);

   if(MinimumStopPoints > 0.0)
      stopDistance = MathMax(stopDistance, MinimumStopPoints * _Point);

   if(MaxStopLossPoints > 0.0 && stopDistance > MaxStopLossPoints * _Point)
   {
      Print("Entrada cancelada: Stop demasiado amplio.");
      return 0.0;
   }

   return stopDistance;
}

//====================================================================
// TENDENCIA / ICT
//====================================================================
ENUM_MARKET_REGIME GetMarketRegime()
{
   double fast[];
   double slow[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);

   if(CopyBuffer(hTrendFast, 0, 0, 5, fast) < 5)
      return REGIME_NEUTRAL;

   if(CopyBuffer(hTrendSlow, 0, 0, 5, slow) < 5)
      return REGIME_NEUTRAL;

   double closeCurrent = iClose(_Symbol, TrendTF, 1);
   if(closeCurrent <= 0.0)
      return REGIME_NEUTRAL;

   bool bullish = closeCurrent > fast[1] && fast[1] > slow[1];
   bool bearish = closeCurrent < fast[1] && fast[1] < slow[1];

   if(RequireTrendSlope)
   {
      bullish = bullish && fast[1] > fast[2] && slow[1] >= slow[2];
      bearish = bearish && fast[1] < fast[2] && slow[1] <= slow[2];
   }

   if(bullish)
      return REGIME_BULLISH;

   if(bearish)
      return REGIME_BEARISH;

   return REGIME_NEUTRAL;
}

int GetTrendBias()
{
   double fast[];
   double slow[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);

   if(CopyBuffer(hTrendFast, 0, 0, 4, fast) < 4)
      return 0;

   if(CopyBuffer(hTrendSlow, 0, 0, 4, slow) < 4)
      return 0;

   double trendClose = iClose(_Symbol, TrendTF, 1);
   if(trendClose <= 0.0)
      return 0;

   bool bullish = trendClose > fast[1] && fast[1] > slow[1];
   bool bearish = trendClose < fast[1] && fast[1] < slow[1];

   if(RequireTrendSlope)
   {
      bullish = bullish && fast[1] > fast[2] && slow[1] >= slow[2];
      bearish = bearish && fast[1] < fast[2] && slow[1] <= slow[2];
   }

   if(bullish)
      return 1;

   if(bearish)
      return -1;

   return 0;
}

int GetMultiTimeframeTrend()
{
   if(!UseMultiTimeframeFilter)
      return 1;

   double fast[];
   double slow[];
   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);

   if(CopyBuffer(hTrendFastMTF, 0, 0, 2, fast) < 2)
      return 1;

   if(CopyBuffer(hTrendSlowMTF, 0, 0, 2, slow) < 2)
      return 1;

   ENUM_TIMEFRAMES mtf = (TrendTF == PERIOD_H4) ? PERIOD_D1 : PERIOD_H4;
   double mtfClose = iClose(_Symbol, mtf, 1);

   if(mtfClose <= 0.0)
      return 1;

   bool bullish = mtfClose > fast[1] && fast[1] > slow[1];
   bool bearish = mtfClose < fast[1] && fast[1] < slow[1];

   if(bullish)
      return 1;

   if(bearish)
      return -1;

   return 0;
}

bool ReadEntryIndicators(double &ema[], double &slowEMA[], double &rsi[], double &atr[])
{
   ArraySetAsSeries(ema, true);
   ArraySetAsSeries(slowEMA, true);
   ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(atr, true);

   if(CopyBuffer(hEntryEMA, 0, 0, 4, ema) < 4)
      return false;

   if(CopyBuffer(hEntrySlow, 0, 0, 4, slowEMA) < 4)
      return false;

   if(CopyBuffer(hRSI, 0, 0, 4, rsi) < 4)
      return false;

   if(CopyBuffer(hATR, 0, 0, 4, atr) < 4)
      return false;

   return true;
}

bool IsLiquiditySweepBullish()
{
   double high1 = iHigh(_Symbol, PERIOD_M15, 1);
   double high2 = iHigh(_Symbol, PERIOD_M15, 2);
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   double open1 = iOpen(_Symbol, PERIOD_M15, 1);
   return high1 > high2 && close1 > open1;
}

bool IsLiquiditySweepBearish()
{
   double low1 = iLow(_Symbol, PERIOD_M15, 1);
   double low2 = iLow(_Symbol, PERIOD_M15, 2);
   double close1 = iClose(_Symbol, PERIOD_M15, 1);
   double open1 = iOpen(_Symbol, PERIOD_M15, 1);
   return low1 < low2 && close1 < open1;
}

bool HasBullishFVG()
{
   double c1 = iClose(_Symbol, PERIOD_M15, 1);
   double o1 = iOpen(_Symbol, PERIOD_M15, 1);
   double c2 = iClose(_Symbol, PERIOD_M15, 2);
   double o2 = iOpen(_Symbol, PERIOD_M15, 2);
   double c3 = iClose(_Symbol, PERIOD_M15, 3);
   double o3 = iOpen(_Symbol, PERIOD_M15, 3);

   if(c1 <= 0.0 || o1 <= 0.0 || c2 <= 0.0 || o2 <= 0.0 || c3 <= 0.0 || o3 <= 0.0)
      return false;

   return (MathMax(o1, c1) < MathMin(o2, c2)) && (c3 > o3);
}

bool HasBearishFVG()
{
   double c1 = iClose(_Symbol, PERIOD_M15, 1);
   double o1 = iOpen(_Symbol, PERIOD_M15, 1);
   double c2 = iClose(_Symbol, PERIOD_M15, 2);
   double o2 = iOpen(_Symbol, PERIOD_M15, 2);
   double c3 = iClose(_Symbol, PERIOD_M15, 3);
   double o3 = iOpen(_Symbol, PERIOD_M15, 3);

   if(c1 <= 0.0 || o1 <= 0.0 || c2 <= 0.0 || o2 <= 0.0 || c3 <= 0.0 || o3 <= 0.0)
      return false;

   return (MathMin(o1, c1) > MathMax(o2, c2)) && (c3 < o3);
}

int GetICTBias()
{
   if(!EnableICTLogic)
      return GetTrendBias();

   int trendBias = GetTrendBias();
   if(trendBias == 0)
      return 0;

   bool bullishStructure = trendBias == 1 && (iClose(_Symbol, PERIOD_H1, 1) > iClose(_Symbol, PERIOD_H1, 2));
   bool bearishStructure = trendBias == -1 && (iClose(_Symbol, PERIOD_H1, 1) < iClose(_Symbol, PERIOD_H1, 2));

   bool liquidityBull = IsLiquiditySweepBullish();
   bool liquidityBear = IsLiquiditySweepBearish();
   bool fvgBull = HasBullishFVG();
   bool fvgBear = HasBearishFVG();

   if(trendBias == 1 && bullishStructure && (!RequireLiquiditySweep || liquidityBull) && (!RequireFVGConfirmation || fvgBull))
      return 1;

   if(trendBias == -1 && bearishStructure && (!RequireLiquiditySweep || liquidityBear) && (!RequireFVGConfirmation || fvgBear))
      return -1;

   if(trendBias == 1 && bullishStructure && (!RequireFVGConfirmation || fvgBull))
      return 1;

   if(trendBias == -1 && bearishStructure && (!RequireFVGConfirmation || fvgBear))
      return -1;

   return trendBias;
}

void CheckPullbackSignal(const int bias, bool &buySignal, bool &sellSignal)
{
   double ema[];
   double slowEMA[];
   double rsi[];
   double atr[];

   if(!ReadEntryIndicators(ema, slowEMA, rsi, atr))
      return;

   double low1 = iLow(_Symbol, _Period, 1);
   double high1 = iHigh(_Symbol, _Period, 1);
   double close1 = iClose(_Symbol, _Period, 1);
   double close2 = iClose(_Symbol, _Period, 2);

   if(low1 <= 0.0 || high1 <= 0.0 || close1 <= 0.0 || close2 <= 0.0)
      return;

   bool bullishPullback =
      bias == 1 &&
      ema[1] > slowEMA[1] &&
      low1 <= ema[1] &&
      close1 > ema[1] &&
      close1 > slowEMA[1] &&
      close2 <= ema[2] &&
      rsi[1] >= PullbackBuyRSIMin &&
      rsi[1] <= PullbackBuyRSIMax;

   bool bearishPullback =
      bias == -1 &&
      ema[1] < slowEMA[1] &&
      high1 >= ema[1] &&
      close1 < ema[1] &&
      close1 < slowEMA[1] &&
      close2 >= ema[2] &&
      rsi[1] >= PullbackSellRSIMin &&
      rsi[1] <= PullbackSellRSIMax;

   if(bullishPullback)
      buySignal = true;

   if(bearishPullback)
      sellSignal = true;
}

void CheckBreakoutSignal(const int bias, bool &buySignal, bool &sellSignal)
{
   if(BreakoutBars < 2)
      return;

   double rsi[];
   ArraySetAsSeries(rsi, true);

   if(CopyBuffer(hRSI, 0, 0, 4, rsi) < 4)
      return;

   int highestIndex = iHighest(_Symbol, _Period, MODE_HIGH, BreakoutBars, 2);
   int lowestIndex  = iLowest(_Symbol, _Period, MODE_LOW, BreakoutBars, 2);

   if(highestIndex < 0 || lowestIndex < 0)
      return;

   double highestHigh = iHigh(_Symbol, _Period, highestIndex);
   double lowestLow   = iLow(_Symbol, _Period, lowestIndex);
   double signalClose = iClose(_Symbol, _Period, 1);

   if(bias == 1 && signalClose > highestHigh && rsi[1] > BreakoutRSILevel)
      buySignal = true;

   if(bias == -1 && signalClose < lowestLow && rsi[1] < (100.0 - BreakoutRSILevel))
      sellSignal = true;
}

//====================================================================
// ÓRDENES
//====================================================================
bool ModifyPositionStops(const ulong ticket, const double stopLoss, const double takeProfit)
{
   MqlTradeRequest request;
   MqlTradeResult result;

   ZeroMemory(request);
   ZeroMemory(result);

   request.action   = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.symbol   = _Symbol;
   request.sl       = stopLoss;
   request.tp       = takeProfit;

   if(!OrderSend(request, result))
   {
      Print("Error modificando stops: ", GetLastError());
      return false;
   }

   if(result.retcode != TRADE_RETCODE_DONE)
   {
      Print("Stops rechazados. Retcode=", result.retcode);
      return false;
   }

   return true;
}

bool SendMarketOrder(const ENUM_ORDER_TYPE orderType,
                     const double volume,
                     const double stopLoss,
                     const double takeProfit,
                     const string comment = "")
{
   for(int attempt = 0; attempt < 3; attempt++)
   {
      MqlTick tick;
      if(!SymbolInfoTick(_Symbol, tick))
         return false;

      MqlTradeRequest request;
      MqlTradeResult result;

      ZeroMemory(request);
      ZeroMemory(result);

      request.action = TRADE_ACTION_DEAL;
      request.symbol = _Symbol;
      request.magic = (ulong)MagicNumber;
      request.volume = volume;
      request.type = orderType;
      request.price = orderType == ORDER_TYPE_BUY ? tick.ask : tick.bid;
      request.sl = stopLoss;
      request.tp = takeProfit;
      request.deviation = SlippagePoints;
      request.type_filling = FillingMode();
      request.comment = comment == "" ? "QQQ Enterprise v11.20" : comment;

      bool sent = OrderSend(request, result);
      if(sent && (result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED))
      {
         Print("✓ ORDEN EJECUTADA: ", orderType == ORDER_TYPE_BUY ? "BUY" : "SELL",
               " Volumen=", DoubleToString(volume, 2),
               " SL=", DoubleToString(stopLoss, _Digits),
               " TP=", DoubleToString(takeProfit, _Digits));

         TradeLog tl;
         tl.openTime = TimeCurrent();
         tl.type = orderType;
         tl.entryPrice = request.price;
         tl.stopLoss = stopLoss;
         tl.takeProfit = takeProfit;
         tl.volume = volume;
         tl.riskPercent = EffectiveRiskPercent();
         tl.trendBias = GetTrendBias() == 1 ? "BULL" : "BEAR";
         tl.reason = UseBreakout ? "BREAKOUT" : "PULLBACK";

         LogTrade(tl);
         TelegramAlert(StringFormat("%s %s abierto. Volumen %.2f", _Symbol,
            orderType == ORDER_TYPE_BUY ? "BUY" : "SELL", volume));
         return true;
      }

      if(result.retcode == TRADE_RETCODE_REQUOTE ||
         result.retcode == TRADE_RETCODE_PRICE_OFF ||
         result.retcode == TRADE_RETCODE_TIMEOUT)
      {
         Sleep(250);
         continue;
      }

      if(result.retcode == TRADE_RETCODE_INVALID_STOPS)
      {
         MqlTradeRequest openRequest = request;
         MqlTradeResult openResult;
         ZeroMemory(openResult);

         openRequest.sl = 0.0;
         openRequest.tp = 0.0;

         bool opened = OrderSend(openRequest, openResult);
         if(opened && (openResult.retcode == TRADE_RETCODE_DONE || openResult.retcode == TRADE_RETCODE_PLACED))
         {
            Sleep(250);
            if(ModifyPositionStops(openResult.order, stopLoss, takeProfit))
               Print("SL/TP añadidos.");
            return true;
         }
      }

      return false;
   }

   return false;
}

void CloseOurPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         (long)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      if(!trade.PositionClose(ticket))
         Print("Error cerrando: ", trade.ResultRetcodeDescription());
   }
}

//====================================================================
// GESTIÓN DE POSICIONES
//====================================================================
void ManageOpenPositions()
{
   if(!ExecutionAllowed())
      return;

   if(!HardExposureOK())
      return;

   double atr[];
   ArraySetAsSeries(atr, true);

   if(CopyBuffer(hATR, 0, 0, 3, atr) < 3)
      return;

   if(atr[1] <= 0.0)
      return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;

   double minimumDistance = BrokerMinDistancePoints() * _Point;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         (long)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      ENUM_POSITION_TYPE positionType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double oldStop = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);

      double referenceRisk = 0.0;
      if(tp > 0.0 && RRRatio > 0.0)
         referenceRisk = MathAbs(tp - openPrice) / RRRatio;
      else if(oldStop > 0.0)
         referenceRisk = MathAbs(openPrice - oldStop);

      if(referenceRisk <= 0.0)
         continue;

      double marketPrice = positionType == POSITION_TYPE_BUY ? tick.bid : tick.ask;
      double progress = positionType == POSITION_TYPE_BUY ? marketPrice - openPrice : openPrice - marketPrice;
      if(progress <= 0.0)
         continue;

      double newStop = oldStop;
      bool modify = false;

      if(EnableBreakEven && progress >= referenceRisk * BreakEvenAtR)
      {
         double breakEvenStop = positionType == POSITION_TYPE_BUY ?
                                openPrice - BreakEvenOffsetPoints * _Point :
                                openPrice + BreakEvenOffsetPoints * _Point;

         if(positionType == POSITION_TYPE_BUY)
         {
            if(oldStop == 0.0 || breakEvenStop > oldStop)
            {
               newStop = breakEvenStop;
               modify = true;
            }
         }
         else
         {
            if(oldStop == 0.0 || breakEvenStop < oldStop)
            {
               newStop = breakEvenStop;
               modify = true;
            }
         }
      }

      if(EnableTrailing && progress >= referenceRisk * TrailingStartR)
      {
         double trailingStop = positionType == POSITION_TYPE_BUY ?
                               marketPrice - atr[1] * TrailingATRMultiplier :
                               marketPrice + atr[1] * TrailingATRMultiplier;

         if(positionType == POSITION_TYPE_BUY)
         {
            if(newStop == 0.0 || trailingStop > newStop)
            {
               newStop = trailingStop;
               modify = true;
            }
         }
         else
         {
            if(newStop == 0.0 || trailingStop < newStop)
            {
               newStop = trailingStop;
               modify = true;
            }
         }
      }

      if(!modify)
         continue;

      if(positionType == POSITION_TYPE_BUY)
      {
         double maximumAllowed = tick.bid - minimumDistance;
         newStop = MathMin(newStop, maximumAllowed);
         if(newStop <= 0.0)
            continue;
         if(oldStop > 0.0 && newStop <= oldStop)
            continue;
      }
      else
      {
         double minimumAllowed = tick.ask + minimumDistance;
         newStop = MathMax(newStop, minimumAllowed);
         if(oldStop > 0.0 && newStop >= oldStop)
            continue;
      }

      ModifyPositionStops(ticket, NormalizeDouble(newStop, _Digits), tp);
   }
}

//====================================================================
// ENTRADAS ESCALONADAS
//====================================================================
bool TryAddScaledEntry(const ENUM_ORDER_TYPE orderType,
                       const double baseVolume,
                       const double referenceEntry,
                       const double stopDistance,
                       const int maxEntries)
{
   if(baseVolume <= 0.0 || maxEntries <= 0)
      return false;

   int alreadyOpen = CountOpenPositions();
   int slots = MathMax(0, MaxEntriesPerSetup - alreadyOpen);
   if(slots <= 0)
      return false;

   double stepDistance = MathMax(stopDistance * 0.75, 20.0 * _Point);
   int entriesToPlace = MathMin(slots, maxEntries);

   for(int step = 0; step < entriesToPlace; step++)
   {
      double entryPrice = orderType == ORDER_TYPE_BUY ?
                         referenceEntry + step * stepDistance :
                         referenceEntry - step * stepDistance;

      double stopPrice = orderType == ORDER_TYPE_BUY ?
                        entryPrice - stopDistance :
                        entryPrice + stopDistance;

      double takeProfit = orderType == ORDER_TYPE_BUY ?
                         entryPrice + stopDistance * RRRatio :
                         entryPrice - stopDistance * RRRatio;

      stopPrice = NormalizeDouble(stopPrice, _Digits);
      takeProfit = NormalizeDouble(takeProfit, _Digits);

      if(!IsStopAndTargetValid(entryPrice, stopPrice, takeProfit, orderType == ORDER_TYPE_BUY))
         continue;

      double factor = 1.0;
      if(step == 1) factor = 0.60;
      else if(step == 2) factor = 0.40;

      double volume = NormalizeVolume(baseVolume * factor);
      if(volume <= 0.0)
         continue;

      string comment = StringFormat("QQQ-ENTRY-%s-%d",
         orderType == ORDER_TYPE_BUY ? "BUY" : "SELL",
         step + 1);

      if(SendMarketOrder(orderType, volume, stopPrice, takeProfit, comment))
         return true;
      else
         break;
   }

   return false;
}

//====================================================================
// APERTURA DE POSICIONES
//====================================================================
void TryOpenPosition()
{
   CurrentBotState = EvaluateBotState();

   if(CurrentBotState == BOT_HALTED)
   {
      Print("Bot detenido por protección.");
      if(ClosePositionsOnHardStop)
         CloseOurPositions();
      return;
   }

   if(LossCooldownActive())
      return;

   if(!NewsFilterOK())
      return;

   if(!EarningsWindowOK())
      return;

   if(!SessionFilterOK())
      return;

   if(!SpreadOK())
      return;

   if(!HardExposureOK())
      return;

   if(OnePositionOnly && HasOurPosition())
      return;

   if(MaxTradesPerDay > 0 && TradesOpenedToday() >= MaxTradesPerDay)
   {
      Print("Límite diario alcanzado.");
      return;
   }

   ENUM_MARKET_REGIME regime = GetMarketRegime();
   if(regime == REGIME_NEUTRAL)
      return;

   int bias = GetICTBias();
   if(bias == 0)
      return;

   if(UseMultiTimeframeFilter)
   {
      int mtfBias = GetMultiTimeframeTrend();
      if(mtfBias != bias)
      {
         Print("Entrada bloqueada: tendencia MTF no alineada.");
         return;
      }
   }

   double ema[];
   double slowEMA[];
   double rsi[];
   double atr[];

   if(!ReadEntryIndicators(ema, slowEMA, rsi, atr))
      return;

   if(atr[1] <= 0.0 || !VolatilityOK(atr[1]))
      return;

   bool buySignal = false;
   bool sellSignal = false;

   if(UseBreakout)
      CheckBreakoutSignal(bias, buySignal, sellSignal);
   else
      CheckPullbackSignal(bias, buySignal, sellSignal);

   if(!buySignal && !sellSignal)
      return;

   if(buySignal && regime != REGIME_BULLISH)
      return;

   if(sellSignal && regime != REGIME_BEARISH)
      return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick))
      return;

   double stopDistance = CalculateStopDistance(atr[1]);
   if(stopDistance <= 0.0)
      return;

   ENUM_ORDER_TYPE orderType = buySignal ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   double entryPrice = buySignal ? tick.ask : tick.bid;
   double stopPrice = buySignal ? entryPrice - stopDistance : entryPrice + stopDistance;
   double takeProfit = buySignal ? entryPrice + stopDistance * RRRatio : entryPrice - stopDistance * RRRatio;

   stopPrice = NormalizeDouble(stopPrice, _Digits);
   takeProfit = NormalizeDouble(takeProfit, _Digits);

   if(!IsStopAndTargetValid(entryPrice, stopPrice, takeProfit, buySignal))
      return;

   if(buySignal && (stopPrice >= entryPrice || takeProfit <= entryPrice))
      return;

   if(sellSignal && (stopPrice <= entryPrice || takeProfit >= entryPrice))
      return;

   double riskToUse = EffectiveRiskPercent();
   if(riskToUse <= 0.0)
      return;

   double volume = LotsForRisk(orderType, entryPrice, stopPrice, riskToUse);
   if(volume <= 0.0)
      return;

   if(!ExecutionAllowed())
   {
      Print("SEÑAL: ", buySignal ? "BUY" : "SELL");
      return;
   }

   if(OnePositionOnly)
   {
      SendMarketOrder(orderType, volume, stopPrice, takeProfit, "QQQ-ONE-SETUP");
      return;
   }

   if(CountOpenPositions() >= MaxEntriesPerSetup)
      return;

   TryAddScaledEntry(orderType, volume, entryPrice, stopDistance, MaxEntriesPerSetup - CountOpenPositions());
}

//====================================================================
// DASHBOARD
//====================================================================
void UpdateDashboard()
{
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double drawdown = CurrentDrawdownPercent();
   double dailyProfit = DailyNetProfit();
   int tradesOpened = TradesOpenedToday();
   int consecutiveLosses = ConsecutiveLosses();
   double exposure = TotalExposurePercent();
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   int openPositions = CountOpenPositions();

   Comment(
      "╔═══════════════════════════════════════════════════╗\n",
      "║ QQQ ENTERPRISE PROFESSIONAL v11.20           ║\n",
      "╠═══════════════════════════════════════════════════╣\n",
      "║ Estado: ", BotStateText(CurrentBotState), " | Sesión: ", GetCurrentSession() == SESSION_PRE_MARKET ? "PRE-MKT" :
                    GetCurrentSession() == SESSION_OPEN ? "OPEN" :
                    GetCurrentSession() == SESSION_MIDDAY ? "MIDDAY" :
                    GetCurrentSession() == SESSION_CLOSE ? "CLOSE" : "AFTER HOUR", " ║\n",
      "╠═══════════════════════════════════════════════════╣\n",
      "║ EQUITY: $", DoubleToString(equity, 2), " | BALANCE: $", DoubleToString(balance, 2), "              ║\n",
      "║ Drawdown: ", DoubleToString(drawdown, 2), "% | P/L Hoy: $", DoubleToString(dailyProfit, 2), "      ║\n",
      "║ Exposición: ", DoubleToString(exposure, 2), "% | Spread: ", (int)spread, " pts                    ║\n",
      "╠═══════════════════════════════════════════════════╣\n",
      "║ Operaciones Hoy: ", IntegerToString(tradesOpened), " | Pérdidas Consecutivas: ", IntegerToString(consecutiveLosses), "       ║\n",
      "║ Riesgo Efectivo: ", DoubleToString(EffectiveRiskPercent(), 2), "% | Posición: ", openPositions > 0 ? "ABIERTA" : "CERRADA", "         ║\n",
      "║ Entradas Activas: ", IntegerToString(openPositions), " / ", IntegerToString(MaxEntriesPerSetup), " | ICT: ", EnableICTLogic ? "ON" : "OFF", "      ║\n",
      "╠═══════════════════════════════════════════════════╣\n",
      "║ News Filter: ", UseNewsFilter ? "ON" : "OFF", " | MTF Filter: ", UseMultiTimeframeFilter ? "ON" : "OFF", " | Vol Filter: ", UseVolatilityFilter ? "ON" : "OFF", " ║\n",
      "║ Logging: ", EnableDetailedLogging ? "ON" : "OFF", " | Kelly: ", UseKellyCriterion ? "ON" : "OFF", "          ║\n",
      "╚═══════════════════════════════════════════════════╝"
   );
}

void NotifyStateChange()
{
   if(CurrentBotState == PreviousBotState)
      return;

   string message = StringFormat(
      "%s cambio a %s. DD %.2f%%. P/L %.2f.",
      _Symbol,
      BotStateText(CurrentBotState),
      CurrentDrawdownPercent(),
      DailyNetProfit()
   );

   Print(message);
   TelegramAlert(message);
   PreviousBotState = CurrentBotState;
}

//====================================================================
// EVENTOS
//====================================================================
void OnTradeTransaction(
   const MqlTradeTransaction &transaction,
   const MqlTradeRequest &request,
   const MqlTradeResult &result)
{
   if(transaction.deal == 0)
      return;

   ulong deal = transaction.deal;
   if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol)
      return;

   if((long)HistoryDealGetInteger(deal, DEAL_MAGIC) != MagicNumber)
      return;

   long entryType = HistoryDealGetInteger(deal, DEAL_ENTRY);
   if(entryType != DEAL_ENTRY_OUT && entryType != DEAL_ENTRY_OUT_BY)
      return;

   double profit = HistoryDealGetDouble(deal, DEAL_PROFIT) +
                   HistoryDealGetDouble(deal, DEAL_SWAP) +
                   HistoryDealGetDouble(deal, DEAL_COMMISSION);

   UpdateStrategyStatsFromDeal(deal);
   Print("✓ Operación cerrada. Ganancia: ", DoubleToString(profit, 2),
         " | Total trades: ", g_stats.totalTrades);
}

//====================================================================
// FIN
//====================================================================
