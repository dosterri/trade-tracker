/// Einstellungen für die Zustellung von Meldungen (Etappe 2).
/// Das Telegram-Bot-Token liegt bewusst NICHT hier, sondern nur als Secret
/// der Edge Function im Backend.
class NotificationSettings {
  const NotificationSettings({
    this.alertsEnabled = true,
    this.telegramEnabled = false,
    this.telegramChatId,
    this.ntfyEnabled = false,
    this.ntfyTopic,
    this.ntfyServer = 'https://ntfy.sh',
    this.includeAmounts = true,
    this.dailySnapshot = true,
    this.quietFrom = 22,
    this.quietTo = 7,
    this.timezone = 'Europe/Berlin',
  });

  final bool alertsEnabled;
  final bool telegramEnabled;
  final String? telegramChatId;
  final bool ntfyEnabled;
  final String? ntfyTopic;
  final String ntfyServer;

  /// Beträge in den Meldungen mitschicken (sonst nur Prozentwerte).
  final bool includeAmounts;
  final bool dailySnapshot;
  final int quietFrom;
  final int quietTo;
  final String timezone;

  bool get anyChannel =>
      (telegramEnabled && _nz(telegramChatId) != null) ||
      (ntfyEnabled && _nz(ntfyTopic) != null);

  factory NotificationSettings.fromRow(Map<String, dynamic> r) => NotificationSettings(
        alertsEnabled: r['alerts_enabled'] as bool? ?? true,
        telegramEnabled: r['telegram_enabled'] as bool? ?? false,
        telegramChatId: r['telegram_chat_id'] as String?,
        ntfyEnabled: r['ntfy_enabled'] as bool? ?? false,
        ntfyTopic: r['ntfy_topic'] as String?,
        ntfyServer: r['ntfy_server'] as String? ?? 'https://ntfy.sh',
        includeAmounts: r['include_amounts'] as bool? ?? true,
        dailySnapshot: r['daily_snapshot'] as bool? ?? true,
        quietFrom: (r['quiet_from'] as num?)?.toInt() ?? 22,
        quietTo: (r['quiet_to'] as num?)?.toInt() ?? 7,
        timezone: r['timezone'] as String? ?? 'Europe/Berlin',
      );

  Map<String, dynamic> toRow() => {
        'alerts_enabled': alertsEnabled,
        'telegram_enabled': telegramEnabled,
        'telegram_chat_id': _nz(telegramChatId),
        'ntfy_enabled': ntfyEnabled,
        'ntfy_topic': _nz(ntfyTopic),
        'ntfy_server': ntfyServer.isEmpty ? 'https://ntfy.sh' : ntfyServer,
        'include_amounts': includeAmounts,
        'daily_snapshot': dailySnapshot,
        'quiet_from': quietFrom,
        'quiet_to': quietTo,
        'timezone': timezone,
      };

  static String? _nz(String? v) {
    final s = v?.trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  NotificationSettings copyWith({
    bool? alertsEnabled,
    bool? telegramEnabled,
    String? telegramChatId,
    bool? ntfyEnabled,
    String? ntfyTopic,
    String? ntfyServer,
    bool? includeAmounts,
    bool? dailySnapshot,
    int? quietFrom,
    int? quietTo,
  }) =>
      NotificationSettings(
        alertsEnabled: alertsEnabled ?? this.alertsEnabled,
        telegramEnabled: telegramEnabled ?? this.telegramEnabled,
        telegramChatId: telegramChatId ?? this.telegramChatId,
        ntfyEnabled: ntfyEnabled ?? this.ntfyEnabled,
        ntfyTopic: ntfyTopic ?? this.ntfyTopic,
        ntfyServer: ntfyServer ?? this.ntfyServer,
        includeAmounts: includeAmounts ?? this.includeAmounts,
        dailySnapshot: dailySnapshot ?? this.dailySnapshot,
        quietFrom: quietFrom ?? this.quietFrom,
        quietTo: quietTo ?? this.quietTo,
        timezone: timezone,
      );
}

/// Eine verschickte (oder versuchte) Meldung – Verlauf in der App.
class AlertEvent {
  const AlertEvent({
    required this.id,
    required this.kind,
    required this.message,
    required this.at,
    this.positionId,
    this.price,
    this.pct,
    this.delivered = const [],
  });

  final int id;
  final String kind;
  final String message;
  final DateTime at;
  final String? positionId;
  final double? price;
  final double? pct;
  final List<String> delivered;

  static const kindLabels = {
    'up': 'Gewinnschwelle',
    'down': 'Verlustschwelle',
    'stop_loss': 'Stop-Loss',
    'take_profit': 'Take-Profit',
    'daily': 'Tagesübersicht',
  };

  String get kindLabel => kindLabels[kind] ?? kind;

  factory AlertEvent.fromRow(Map<String, dynamic> r) => AlertEvent(
        id: (r['id'] as num).toInt(),
        kind: r['kind'] as String,
        message: r['message'] as String,
        at: DateTime.parse(r['at'] as String),
        positionId: r['position_id'] as String?,
        price: (r['price'] as num?)?.toDouble(),
        pct: (r['pct'] as num?)?.toDouble(),
        delivered: [
          for (final d in (r['delivered'] as List? ?? const [])) d.toString(),
        ],
      );
}

/// Letzter Lauf des Hintergrunddienstes – zeigt, ob der Scheduler lebt.
class BackendRun {
  const BackendRun({required this.kind, required this.at, required this.minutesAgo});

  final String kind;
  final DateTime at;
  final double minutesAgo;

  /// Nach 26 Stunden ohne Lauf stimmt etwas nicht (auch am Wochenende läuft er).
  bool get isStale => minutesAgo > 26 * 60;

  factory BackendRun.fromRow(Map<String, dynamic> r) => BackendRun(
        kind: r['kind'] as String,
        at: DateTime.parse(r['at'] as String),
        minutesAgo: (r['minutes_ago'] as num).toDouble(),
      );
}
