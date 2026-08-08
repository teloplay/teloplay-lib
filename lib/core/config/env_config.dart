import 'package:flutter_dotenv/flutter_dotenv.dart';

/// .env ফাইল থেকে environment variables read করার জন্য single source।
/// অন্য কোথাও সরাসরি dotenv.env[...] ব্যবহার করা হবে না।
class EnvConfig {
  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  static String get googleWebClientId => dotenv.env['GOOGLE_WEB_CLIENT_ID'] ?? '';
  
  static Future<void> load() async {
    await dotenv.load(fileName: '.env');
  }
}