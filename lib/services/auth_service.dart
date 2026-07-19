import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Handles signup/login/logout and local token storage.
///
/// Token is stored with shared_preferences for simplicity. Note: this is
/// NOT encrypted storage — fine for a portfolio/demo project, but for a
/// production app storing real user credentials you'd want
/// flutter_secure_storage instead, which keeps the token in the
/// platform keychain/keystore rather than plain SharedPreferences.
class AuthService {
  AuthService(this.backendBase);

  final String backendBase;
  static const _tokenKey = "auth_token";

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  /// Throws an [AuthException] with a user-facing message on failure.
  Future<void> signup(String email, String password) async {
    final uri = Uri.parse("$backendBase/auth/signup");
    final response = await http
        .post(
          uri,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"email": email, "password": password}),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await _saveToken(data["access_token"]);
      return;
    }

    throw AuthException(_extractDetail(response));
  }

  Future<void> login(String email, String password) async {
    final uri = Uri.parse("$backendBase/auth/login");
    final response = await http
        .post(
          uri,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({"email": email, "password": password}),
        )
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      await _saveToken(data["access_token"]);
      return;
    }

    throw AuthException(_extractDetail(response));
  }

  String _extractDetail(http.Response response) {
    try {
      final data = jsonDecode(response.body);
      if (data is Map && data["detail"] != null)
        return data["detail"].toString();
    } catch (_) {
      // fall through to generic message
    }
    return "Something went wrong (${response.statusCode}). Please try again.";
  }
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}
