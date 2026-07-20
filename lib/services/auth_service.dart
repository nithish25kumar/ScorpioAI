import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  AuthService(this.backendBase) {
    debugPrint("[AuthService] initialized with backendBase = $backendBase");
  }

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

  Future<void> signup(String email, String password) async {
    await _authRequest("signup", "/auth/signup", email, password);
  }

  Future<void> login(String email, String password) async {
    await _authRequest("login", "/auth/login", email, password);
  }

  Future<void> _authRequest(
    String label,
    String path,
    String email,
    String password,
  ) async {
    final uri = Uri.parse("$backendBase$path");
    debugPrint("[AuthService] $label -> POST $uri");

    try {
      final response = await http
          .post(
            uri,
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({"email": email, "password": password}),
          )
          .timeout(const Duration(seconds: 60));

      debugPrint("[AuthService] $label <- status ${response.statusCode}");
      debugPrint("[AuthService] $label <- body ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        await _saveToken(data["access_token"]);
        debugPrint("[AuthService] $label succeeded, token saved");
        return;
      }

      throw AuthException(_extractDetail(response));
    } on AuthException {
      rethrow;
    } catch (e) {
      debugPrint("[AuthService] $label FAILED with exception: $e");

      rethrow;
    }
  }

  String _extractDetail(http.Response response) {
    try {
      final data = jsonDecode(response.body);
      if (data is Map && data["detail"] != null) {
        return data["detail"].toString();
      }
    } catch (_) {}
    return "Something went wrong (${response.statusCode}). Please try again.";
  }
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}
