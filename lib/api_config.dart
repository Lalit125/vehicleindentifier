class ApiConfig {
  static final ApiConfig _instance = ApiConfig._internal();

  factory ApiConfig() => _instance;

  ApiConfig._internal();

  // Base URL for production
  String get baseUrl => 'https://bloatware.in/rssb/';

  // Environment flag
  bool get isProduction => true;

  // Add other API-related configurations (e.g., API key, timeouts)
  String get apiKey => 'your-production-api-key-here';

  // Example: Timeout duration for API requests
  Duration get timeout => const Duration(seconds: 30);
}