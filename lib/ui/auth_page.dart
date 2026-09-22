import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(bool signUp) async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final auth = Supabase.instance.client.auth;
    try {
      if (signUp) {
        final res = await auth.signUp(
            email: _email.text.trim(), password: _password.text);
        if (res.session == null) {
          _message = 'Konto angelegt. Bitte bestätige den Link in der E-Mail '
              'und melde dich danach hier an.';
        }
      } else {
        await auth.signInWithPassword(
            email: _email.text.trim(), password: _password.text);
      }
    } on AuthException catch (e) {
      _message = e.message;
    } catch (e) {
      _message = 'Verbindung fehlgeschlagen: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Form(
              key: _form,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Trade Tracker', style: t.headlineMedium),
                    const SizedBox(height: 4),
                    Text('Melde dich mit deinem Supabase-Konto an.', style: t.bodySmall),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'E-Mail'),
                      validator: (v) =>
                          (v ?? '').contains('@') ? null : 'Gültige E-Mail eingeben',
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      decoration: const InputDecoration(labelText: 'Passwort'),
                      onFieldSubmitted: (_) => _run(false),
                      validator: (v) =>
                          (v ?? '').length >= 10 ? null : 'Mindestens 10 Zeichen',
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : () => _run(false),
                      child: Text(_busy ? 'Bitte warten…' : 'Anmelden'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy ? null : () => _run(true),
                      child: const Text('Einmalig: Konto registrieren'),
                    ),
                    if (_message != null) ...[
                      const SizedBox(height: 12),
                      Text(_message!, style: t.bodySmall),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Wird angezeigt, wenn beim Build keine Supabase-Zugangsdaten übergeben wurden.
class MissingConfigPage extends StatelessWidget {
  const MissingConfigPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Text(
                'Konfiguration fehlt.\n\nDie App wurde ohne SUPABASE_URL / '
                'SUPABASE_PUBLISHABLE_KEY gebaut. Starte sie mit\n'
                'flutter run --dart-define-from-file=env/local.json\n'
                '(siehe README).',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
        ),
      );
}
