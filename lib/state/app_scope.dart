import 'package:flutter/widgets.dart';

import 'app_state.dart';

/// Stellt den [AppState] im Widget-Baum bereit.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  /// Mit Abhängigkeit: Widget baut bei Änderungen neu.
  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// Ohne Abhängigkeit, z. B. in Callbacks.
  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
