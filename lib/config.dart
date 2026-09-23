// Konfiguration kommt beim Build per --dart-define-from-file (env/local.json
// lokal, GitHub Secrets in der CI). Nichts davon liegt im Repo.

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
const coinGeckoKey = String.fromEnvironment('COINGECKO_DEMO_KEY');

bool get hasConfig => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;

/// Hostname der konfigurierten Supabase-Instanz – zur Fehlersuche im Login.
String get supabaseHost => Uri.tryParse(supabaseUrl)?.host ?? supabaseUrl;
