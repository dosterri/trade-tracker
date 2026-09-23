import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'data/quote_sources.dart';
import 'data/repository.dart';
import 'state/app_scope.dart';
import 'state/app_state.dart';
import 'ui/auth_page.dart';
import 'ui/home_page.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'de_DE';
  pdfrxFlutterInitialize();
  await initializeDateFormatting('de_DE');

  if (!hasConfig) {
    runApp(const _Shell(child: MissingConfigPage()));
    return;
  }

  await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseKey);
  final state = AppState(
    repo: Repository(Supabase.instance.client),
    quotes: QuoteService(coinGeckoKey: coinGeckoKey),
  );
  await state.loadSettings();
  runApp(AppScope(state: state, child: const TradeTrackerApp()));
}

class TradeTrackerApp extends StatelessWidget {
  const TradeTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return _Shell(themeMode: state.themeMode, child: const _AuthGate());
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child, this.themeMode = ThemeMode.dark});
  final Widget child;
  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Trade Tracker',
        debugShowCheckedModeBanner: false,
        theme: lightTheme,
        darkTheme: darkTheme,
        themeMode: themeMode,
        locale: const Locale('de', 'DE'),
        supportedLocales: const [Locale('de', 'DE')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: child,
      );
}

/// Zeigt Login oder Portfolio, je nach Sitzung.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> with WidgetsBindingObserver {
  late final StreamSubscription<AuthState> _sub;
  Session? _session;
  bool _wasPaused = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final auth = Supabase.instance.client.auth;
    _session = auth.currentSession;
    if (_session != null) _startLater();
    _sub = auth.onAuthStateChange.listen((e) {
      if (!mounted) return;
      final had = _session != null;
      setState(() => _session = e.session);
      AppScope.read(context).userId = e.session?.user.id;
      if (!had && e.session != null) _startLater();
    });
  }

  void _startLater() => WidgetsBinding.instance.addPostFrameCallback((_) {
        final state = AppScope.read(context);
        state.userId = Supabase.instance.client.auth.currentUser?.id;
        state.start();
      });

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (_session == null) return;
    final state = AppScope.read(context);
    // Nur nach echtem Hintergrund neu laden, nicht bei jedem Fokuswechsel.
    if (s == AppLifecycleState.resumed && _wasPaused) {
      _wasPaused = false;
      state.start();
    } else if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
      _wasPaused = true;
      state.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _session == null ? const AuthPage() : const HomePage();
}
