import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../state/app_scope.dart';
import 'notifications_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final t = Theme.of(context).textTheme;
    final user = Supabase.instance.client.auth.currentUser;

    Widget label(String s) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
          child: Text(s.toUpperCase(), style: t.labelSmall?.copyWith(letterSpacing: 0.8)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Einstellungen')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
            children: [
              label('Darstellung'),
              SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ThemeMode.dark, label: Text('Dunkel')),
                  ButtonSegment(value: ThemeMode.light, label: Text('Hell')),
                  ButtonSegment(value: ThemeMode.system, label: Text('System')),
                ],
                selected: {state.themeMode},
                onSelectionChanged: (s) => state.setThemeMode(s.first),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Kompakte Ansicht'),
                subtitle: const Text('Ohne Sparklines, z. B. für den Zweitbildschirm'),
                value: state.compact,
                onChanged: (_) => state.toggleCompact(),
              ),
              label('Meldungen'),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Benachrichtigungen'),
                subtitle: const Text('Telegram, ntfy, Ruhezeiten, Verlauf'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const NotificationsPage())),
              ),
              label('Tastenkürzel (Windows)'),
              Text(
                'Strg+N  Neuer Trade\n'
                'Strg+R / F5  Aktualisieren\n'
                'Strg+1 / 2 / 3  Offen / Geschlossen / Alle\n'
                'Strg+K  Kompakte Ansicht\n'
                'Strg+S  Formular speichern\n'
                'Esc  Dialog schließen',
                style: t.bodySmall?.copyWith(height: 1.7),
              ),
              label('Konto'),
              Text(user?.email ?? '–', style: t.bodyMedium),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  await state.signedOut();
                  await Supabase.instance.client.auth.signOut();
                  if (context.mounted) Navigator.popUntil(context, (r) => r.isFirst);
                },
                child: const Text('Abmelden'),
              ),
              label('Kursquellen'),
              Text(
                'Aktien/ETFs: Lang & Schwarz Exchange · Derivate: onvista · '
                'Krypto: CoinGecko · Wechselkurse: EZB (Frankfurter). '
                'Kurse können verzögert sein. LS und onvista sind inoffizielle '
                'Schnittstellen und können ausfallen – dann greift der manuelle Kurs.',
                style: t.bodySmall?.copyWith(height: 1.5),
              ),
              label('Hinweis'),
              Text(
                'Diese App dient ausschließlich der persönlichen Dokumentation. '
                'Sie gibt keine Anlageberatung und keine Kauf- oder '
                'Verkaufsempfehlungen. Alle Berechnungen ohne Gewähr; '
                'maßgeblich sind die Abrechnungen deines Brokers.',
                style: t.bodySmall?.copyWith(height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
