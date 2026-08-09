import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'offline_db.dart';

class CurrentUser {
  final int id;
  final String email;
  final String firstName;
  final String lastName;
  final String roleName;
  final bool isSuperuser;

  CurrentUser({
    required this.id,
    required this.email,
    required this.firstName,
    required this.lastName,
    required this.roleName,
    required this.isSuperuser,
  });

  factory CurrentUser.fromJson(Map<String, dynamic> json) => CurrentUser(
        id: json['id'] as int,
        email: json['email'] as String,
        firstName: (json['first_name'] as String?) ?? '',
        lastName: (json['last_name'] as String?) ?? '',
        roleName: (json['role_name'] as String?) ?? '',
        isSuperuser: (json['is_superuser'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'first_name': firstName,
        'last_name': lastName,
        'role_name': roleName,
        'is_superuser': isSuperuser,
      };

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

  /// Owner/Manager gate for destructive actions (delete, recycle bin) - the backend
  /// enforces the same check server-side (403 otherwise), this just controls whether
  /// the UI offers the action at all.
  bool get isAdmin => user?.roleName == 'Owner' || user?.roleName == 'Manager';

  AuthService() {
    _restoreSession();
  }

  static const _cachedUserKey = 'erp_cached_user';

  Future<void> _cacheUser(CurrentUser user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cachedUserKey, jsonEncode(user.toJson()));
  }

  Future<CurrentUser?> _readCachedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cachedUserKey);
    if (raw == null) return null;
    try {
      return CurrentUser.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
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
      await _cacheUser(_user!);
    } on ApiException catch (e) {
      // A real rejection from the server (token genuinely invalid/expired, or the
      // refresh token itself expired after being offline >7 days) - the stored tokens
      // are no good, there's nothing to fall back to.
      if (e.statusCode == 401) {
        await _api.clearTokens();
        _user = null;
      } else {
        // Some other server-side error - keep the existing session rather than kicking
        // the user out over a transient server issue.
        _user = await _readCachedUser();
      }
    } catch (_) {
      // No response at all reached us (no internet) - the token itself might still be
      // perfectly valid. Losing connectivity should never be indistinguishable from
      // being logged out, or the app becomes unusable offline the moment it's closed
      // and reopened. Stay signed in using the last-known profile.
      _user = await _readCachedUser();
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
      await _cacheUser(_user!);
      notifyListeners();
    } on ApiException catch (e) {
      _error = e.statusCode == 401 ? 'Invalid email or password.' : e.message;
      rethrow;
    }
  }

  Future<void> logout() async {
    await _api.clearTokens();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cachedUserKey);
    // A different account may sign in next on this device - don't leave the previous
    // company's cached products/customers or queued (possibly unsynced!) writes behind.
    // Anything still pending in the sync queue is lost here; callers should steer users
    // to Sync Status to clear the queue before logging out if that matters.
    await OfflineDb.clearAll();
    _user = null;
    notifyListeners();
  }

  ApiClient get api => _api;
}
