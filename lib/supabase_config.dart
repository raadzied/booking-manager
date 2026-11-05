/// Supabase Configuration & Hybrid Mode Support
///
/// If [supabaseUrl] and [supabaseAnonKey] are left as placeholders,
/// the app operates fully offline using local storage (storage.dart).
/// Once configured, it seamlessly switches to Supabase cloud sync.
class SupabaseConfig {
  static const String supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  /// Returns true if valid Supabase credentials have been provided.
  static bool get isSupabaseConfigured {
    final uri = Uri.tryParse(supabaseUrl);
    final secureUrl = uri?.scheme == 'https' && uri!.hasAuthority;
    final localDevelopmentUrl = uri?.scheme == 'http' &&
        (uri!.host == 'localhost' || uri.host == '127.0.0.1');
    return (secureUrl || localDevelopmentUrl) && supabaseAnonKey.isNotEmpty;
  }
}
