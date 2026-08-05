import 'package:flutter/foundation.dart';
import 'api_client.dart';

class CurrentUser {
  final int id;
  final String email;
  final String firstName;
  final String lastName;
  final String roleName;

  CurrentUser({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.roleName,
  });

  factory CurrentUser.fromJson(Map<String, dynamic> json) => CurrentUser(
        id: json['id'] as int,
        email: json['email'] as String,
        firstName: (json['first_name'] as String?) ?? '',
        lastName: (json['last_name'] as String?) ?? '',
        roleName: (json['role_name'] as String?) ?? '',
      );

  String get fullName => '$firstName $lastName'.trim();
  String get initials {
    final f = firstName.isNotEmpty ? firstName[0] : '';
    final l = lastName.isNotEmpty ? lastName[0] : '';
    final s = '$f$l'.toUpperCase();
    return s.isEmpty ? '?' : s;
  }
}

class AuthService extends ChangeNotifier {
  final ApiClient _api = ApiClient();

  CurrentUser? _user;
  bool _loading = true;
  String? _error;

  CurrentUser? get user => _user;
  bool get loading => _loading;
  String? get error => _error;
  bool get isAuthenticated => _user != null;

  AuthService() {
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final token = await _api.getAccessToken();
    if (token == null) {
      _loading = false;
      notifyListeners();
      return;
    }
    try {
      final data = await _api.request('/api/auth/me/');
      _user = CurrentUser.fromJson(data as Map<String, dynamic>);
    } catch (_) {
      await _api.clearTokens();
      _user = null;
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    _error = null;
    try {
      final tokens = await _api.request(
        '/api/auth/token/',
        method: 'POST',
        auth: false,
        body: {'email': email, 'password': password},
      );
      await _api.setTokens(
        access: tokens['access'] as String,
        refresh: tokens['refresh'] as String,
      );
      final data = await _api.request('/api/auth/me/');
      _user = CurrentUser.fromJson(data as Map<String, dynamic>);
      notifyListeners();
    } on ApiException catch (e) {
      _error = e.statusCode == 401 ? 'Invalid email or password.' : e.message;
      rethrow;
    }
  }

  Future<void> logout() async {
    await _api.clearTokens();
    _user = null;
    notifyListeners();
  }

  ApiClient get api => _api;
}
