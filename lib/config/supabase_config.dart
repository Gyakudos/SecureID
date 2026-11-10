/// Build-time Supabase configuration.
///
/// Provide the values with `--dart-define` when building or running:
///
/// ```powershell
/// flutter run `
///   --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co `
///   --dart-define=SUPABASE_ANON_KEY=YOUR-ANON-OR-PUBLISHABLE-KEY
/// ```
///
/// The key is the public anon/publishable key. Never put the service-role key
/// in the app.
class SupabaseConfig {
  const SupabaseConfig._();

  static const String url = String.fromEnvironment('SUPABASE_URL');
  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured =>
      url.trim().isNotEmpty && anonKey.trim().isNotEmpty;
}
