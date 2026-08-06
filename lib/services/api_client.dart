import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Points at the deployed backend so this build works for real testers on
/// real devices, not just the local dev emulator. For local development
/// against a Django dev server instead, swap this back to the emulator/host
/// addresses (10.0.2.2 for Android emulator, 127.0.0.1 for web/desktop).
String get _apiBaseUrl => 'https://erp-system-seven-eosin.vercel.app';

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => message;
}

class ApiClient {
  static const _accessKey = 'erp_access_token';
  static const _refreshKey = 'erp_refresh_token';

  String get baseUrl => _apiBaseUrl;

  Future<String?> getAccessToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_accessKey);
  }

  Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_refreshKey);
  }

  Future<void> setTokens({required String access, required String refresh}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessKey, access);
    await prefs.setString(_refreshKey, refresh);
  }

  Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKey);
    await prefs.remove(_refreshKey);
  }

  Future<String?> _refreshAccessToken() async {
    final refresh = await getRefreshToken();
    if (refresh == null) return null;
    final res = await http.post(
      Uri.parse('$_apiBaseUrl/api/auth/token/refresh/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refresh': refresh}),
    );
    if (res.statusCode != 200) {
      await clearTokens();
      return null;
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessKey, data['access'] as String);
    return data['access'] as String;
  }

  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    bool auth = true,
  }) async {
    Future<http.Response> doRequest(String? token) {
      final uri = Uri.parse('$_apiBaseUrl$path');
      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (auth && token != null) 'Authorization': 'Bearer $token',
      };
      switch (method) {
        case 'POST':
          return http.post(uri, headers: headers, body: body != null ? jsonEncode(body) : null);
        case 'PATCH':
          return http.patch(uri, headers: headers, body: body != null ? jsonEncode(body) : null);
        case 'DELETE':
          return http.delete(uri, headers: headers);
        default:
          return http.get(uri, headers: headers);
      }
    }

    var token = await getAccessToken();
    var res = await doRequest(token);

    if (res.statusCode == 401 && auth) {
      token = await _refreshAccessToken();
      if (token != null) {
        res = await doRequest(token);
      }
    }

    dynamic data;
    try {
      data = res.body.isNotEmpty ? jsonDecode(res.body) : null;
    } catch (_) {
      data = null;
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final message = (data is Map && (data['error'] ?? data['detail']) != null)
          ? (data['error'] ?? data['detail']).toString()
          : 'Request failed (${res.statusCode})';
      throw ApiException(res.statusCode, message);
    }

    return data;
  }

  /// Fetches a binary (PDF) endpoint with the auth header attached - separate from
  /// [request] since responses here aren't JSON and shouldn't be decoded as such.
  Future<List<int>> requestBytes(String path) async {
    Future<http.Response> doRequest(String? token) {
      final uri = Uri.parse('$_apiBaseUrl$path');
      return http.get(uri, headers: {if (token != null) 'Authorization': 'Bearer $token'});
    }

    var token = await getAccessToken();
    var res = await doRequest(token);

    if (res.statusCode == 401) {
      token = await _refreshAccessToken();
      if (token != null) res = await doRequest(token);
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.statusCode, 'Failed to generate PDF (${res.statusCode}).');
    }
    return res.bodyBytes;
  }
}
