import 'package:flutter/material.dart';

import 'screens/chat_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';

// Single source of truth for the backend URL, passed down into both
// AuthService and ChatScreen — change it here only, nowhere else.
//   Android emulator      -> http://10.0.2.2:8000
//   iOS simulator / macOS -> http://127.0.0.1:8000
//   Physical device       -> http://<your-computer-LAN-IP>:8000
//   Deployed backend      -> https://your-app.onrender.com
const String kBackendBase = "https://chatbot-backend-f9d6.onrender.com";

void main() => runApp(const ChatApp());

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chatbot',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0F5257)),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

/// Shows a loading spinner while checking for a saved token, then routes
/// to LoginScreen or ChatScreen accordingly. "Continue as guest" on the
/// login screen also lands here — the chat screen itself works fine with
/// no token, it just won't have persisted history or a logout button.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final AuthService _authService = AuthService(kBackendBase);
  bool _checking = true;
  bool _showLogin = true;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    final loggedIn = await _authService.isLoggedIn();
    if (!mounted) return;
    setState(() {
      _showLogin = !loggedIn;
      _checking = false;
    });
  }

  void _onAuthenticated() {
    setState(() => _showLogin = false);
  }

  void _onLogout() {
    setState(() => _showLogin = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: Color(0xFFF7F5F2),
        body:
            Center(child: CircularProgressIndicator(color: Color(0xFF0F5257))),
      );
    }

    if (_showLogin) {
      return LoginScreen(
          authService: _authService, onAuthenticated: _onAuthenticated);
    }

    return ChatScreen(
        authService: _authService,
        onLogout: _onLogout,
        backendBase: kBackendBase);
  }
}
