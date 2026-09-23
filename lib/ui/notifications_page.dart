import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/format.dart';
import '../core/notifications.dart';
import '../state/app_scope.dart';
import 'theme.dart';
import 'widgets.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  NotificationSettings _s = const NotificationSettings();
  final _chatId = TextEditingController();
  final _topic = TextEditingController();
  final _server = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  String? _error;
  List<AlertEvent> _events = const [];
  BackendRun? _lastRun;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _chatId.dispose();
    _topic.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = AppScope.read(context).repo;
    try {
      final results = await Future.wait([
        repo.loadNotificationSettings(),
        repo.loadAlertEvents(),
        repo.lastBackendRun(),
      ]);
      if (!mounted) return;
      setState(() {
        _s = (results[0] as NotificationSettings?) ?? const NotificationSettings();
        _events = results[1] as List<AlertEvent>;
        _lastRun = results[2] as BackendRun?;
        _chatId.text = _s.telegramChatId ?? '';
        _topic.text = _s.ntfyTopic ?? '';
        _server.text = _s.ntfyServer;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _save({bool silent = false}) async {
    final state = AppScope.read(context);
    final userId = state.userId;
    if (userId == null) return;
    setState(() => _saving = true);
    try {
      final saved = await state.repo.saveNotificationSettings(
        _s.copyWith(
          telegramChatId: _chatId.text.trim(),
          ntfyTopic: _topic.text.trim(),
          ntfyServer: _server.text.trim().isEmpty ? 'https://ntfy.sh' : _server.text.trim(),
        ),
        userId,
      );
      if (!mounted) return;
      setState(() => _s = saved);
      if (!silent) showInfo(context, 'Gespeichert.');
    } catch (e) {
      if (mounted) showError(context, 'Speichern fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test() async {
    final repo = AppScope.read(context).repo;
    setState(() => _testing = true);
    try {
      await _save(silent: true);
      final delivered = await repo.sendTestNotification();
      if (mounted) showInfo(context, 'Zugestellt über: ${delivered.join(', ')}');
    } catch (e) {
      if (mounted) showError(context, 'Test fehlgeschlagen: $e');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _suggestTopic() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final r = Random.secure();
    final suffix = List.generate(16, (_) => chars[r.nextInt(chars.length)]).join();
    setState(() => _topic.text = 'tt-$suffix');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final pnl = context.pnl;

    Widget label(String s) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
          child: Text(s.toUpperCase(), style: t.labelSmall?.copyWith(letterSpacing: 0.8)),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Benachrichtigungen'),
        actions: [
          TextButton(
            onPressed: _saving || _loading ? null : () => _save(),
            child: Text(_saving ? 'Speichert…' : 'Speichern'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_error!, style: t.bodySmall?.copyWith(color: pnl.loss)),
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Meldungen aktiv'),
                      subtitle: const Text('Schaltet alle Alarme zentral ein oder aus'),
                      value: _s.alertsEnabled,
                      onChanged: (v) => setState(() => _s = _s.copyWith(alertsEnabled: v)),
                    ),
                    label('Telegram'),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Über Telegram zustellen'),
                      value: _s.telegramEnabled,
                      onChanged: (v) => setState(() => _s = _s.copyWith(telegramEnabled: v)),
                    ),
                    TextField(
                      controller: _chatId,
                      keyboardType: TextInputType.text,
                      decoration: const InputDecoration(
                        labelText: 'Chat-ID',
                        helperText: 'Vom Bot @userinfobot; bei dir meist eine Zahl',
                      ),
                    ),
                    label('ntfy'),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Über ntfy zustellen'),
                      value: _s.ntfyEnabled,
                      onChanged: (v) => setState(() => _s = _s.copyWith(ntfyEnabled: v)),
                    ),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _topic,
                          decoration: const InputDecoration(
                            labelText: 'Topic',
                            helperText: 'Wer den Namen kennt, liest mit – lang wählen',
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      TextButton(onPressed: _suggestTopic, child: const Text('Vorschlag')),
                    ]),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _server,
                      decoration: const InputDecoration(labelText: 'Server'),
                    ),
                    label('Inhalt & Zeiten'),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Beträge mitschicken'),
                      subtitle: const Text('Aus: nur Prozentwerte, keine Euro-Beträge'),
                      value: _s.includeAmounts,
                      onChanged: (v) => setState(() => _s = _s.copyWith(includeAmounts: v)),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Tagesübersicht'),
                      subtitle: const Text('Werktags um 21:00 Uhr'),
                      value: _s.dailySnapshot,
                      onChanged: (v) => setState(() => _s = _s.copyWith(dailySnapshot: v)),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: _HourPicker(
                          label: 'Ruhe ab',
                          value: _s.quietFrom,
                          onChanged: (v) => setState(() => _s = _s.copyWith(quietFrom: v)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _HourPicker(
                          label: 'Ruhe bis',
                          value: _s.quietTo,
                          onChanged: (v) => setState(() => _s = _s.copyWith(quietTo: v)),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 20),
                    FilledButton.tonal(
                      onPressed: _testing || _saving ? null : _test,
                      child: Text(_testing ? 'Sendet…' : 'Testnachricht senden'),
                    ),
                    label('Hintergrunddienst'),
                    Text(
                      _lastRun == null
                          ? 'Noch kein Lauf protokolliert. Läuft der Zeitplan schon?'
                          : 'Letzter Lauf: ${fmtDateTime(_lastRun!.at)} '
                              '(${_lastRun!.kind})',
                      style: t.bodySmall?.copyWith(
                          color: _lastRun?.isStale == true ? pnl.loss : null),
                    ),
                    label('Letzte Meldungen'),
                    if (_events.isEmpty)
                      Text('Noch keine Meldungen.', style: t.bodySmall)
                    else
                      Card(
                        child: Column(
                          children: [
                            for (final (i, e) in _events.take(20).indexed) ...[
                              if (i > 0) const Divider(),
                              ListTile(
                                dense: true,
                                title: Text(e.message),
                                subtitle: Text(
                                  '${fmtDateTime(e.at)} · ${e.kindLabel}'
                                  '${e.delivered.isEmpty ? '' : ' · ${e.delivered.join(', ')}'}',
                                  style: t.bodySmall,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    const SizedBox(height: 24),
                    Text(
                      'Hinweis: Meldungen laufen über Telegram bzw. ntfy und damit über '
                      'deren Server. Wenn du keine Beträge übertragen möchtest, schalte '
                      '„Beträge mitschicken“ aus.',
                      style: t.bodySmall?.copyWith(height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _HourPicker extends StatelessWidget {
  const _HourPicker({required this.label, required this.value, required this.onChanged});

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<int>(
        isExpanded: true,
        initialValue: value,
        decoration: InputDecoration(labelText: label),
        items: [
          for (var h = 0; h < 24; h++)
            DropdownMenuItem(
                value: h, child: Text('${h.toString().padLeft(2, '0')}:00')),
        ],
        onChanged: (v) {
          if (v != null) {
            HapticFeedback.selectionClick();
            onChanged(v);
          }
        },
      );
}
