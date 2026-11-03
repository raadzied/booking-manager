/// Supabase Configuration & Hybrid Mode Support
///
/// If [supabaseUrl] and [supabaseAnonKey] are left as placeholders,
/// the app operates fully offline using local storage (storage.dart).
/// Once configured, it seamlessly switches to Supabase cloud sync.
class SupabaseConfig {
  static const String supabaseUrl = 'YOUR_SUPABASE_URL';
  static const String supabaseAnonKey = 'YOUR_SUPABASE_ANON_KEY';

  /// Returns true if valid Supabase credentials have been provided.
  static bool get isConfigured =>
      supabaseUrl != 'YOUR_SUPABASE_URL' &&
      supabaseAnonKey != 'YOUR_SUPABASE_ANON_KEY' &&
      supabaseUrl.isNotEmpty &&
      supabaseAnonKey.isNotEmpty;
}
