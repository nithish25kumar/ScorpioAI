import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/auth_service.dart';

const Color _kCanvas = Color(0xFFF7F5F2);
const Color _kSurface = Color(0xFFFFFFFF);
const Color _kInk = Color(0xFF1C1B1F);
const Color _kInkMuted = Color(0xFF6F6A63);
const Color _kAccent = Color(0xFF0F5257);
const Color _kDivider = Color(0xFFE7E3DC);
const Color _kDanger = Color(0xFFB3261E);
const Color _kDangerSoft = Color(0xFFFBEAE9);

TextStyle _display(
    {double size = 18,
    FontWeight weight = FontWeight.w600,
    Color color = _kInk}) {
  return GoogleFonts.manrope(
      fontSize: size, fontWeight: weight, color: color, height: 1.2);
}

TextStyle _body(
    {double size = 15,
    FontWeight weight = FontWeight.w400,
    Color color = _kInk}) {
  return GoogleFonts.inter(
      fontSize: size, fontWeight: weight, color: color, height: 1.4);
}

class LoginScreen extends StatefulWidget {
  final AuthService authService;
  final VoidCallback onAuthenticated;

  const LoginScreen(
      {super.key, required this.authService, required this.onAuthenticated});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSignup = false;
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = "Please fill in both fields.");
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (_isSignup) {
        await widget.authService.signup(email, password);
      } else {
        await widget.authService.login(email, password);
      }
      widget.onAuthenticated();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() =>
          _error = "Couldn't reach the server. Is the backend running? ($e)");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _continueAsGuest() async {
    widget.onAuthenticated();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kCanvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                        color: Color(0xFFE4EFEE), shape: BoxShape.circle),
                    child: const Icon(Icons.auto_awesome_rounded,
                        color: _kAccent, size: 26),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _isSignup ? "Create an account" : "Welcome back",
                    style: _display(size: 24),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _isSignup
                        ? "Sign up to save your conversations across sessions."
                        : "Log in to pick up where you left off.",
                    style: _body(size: 14, color: _kInkMuted),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: _kDangerSoft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFF0C4C0)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline_rounded,
                              size: 18, color: _kDanger),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(_error!,
                                  style: _body(size: 13, color: _kDanger))),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _AuthTextField(
                    controller: _emailController,
                    hint: "Email",
                    icon: Icons.mail_outline_rounded,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  _AuthTextField(
                    controller: _passwordController,
                    hint: "Password",
                    icon: Icons.lock_outline_rounded,
                    obscureText: true,
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kAccent,
                        foregroundColor: _kSurface,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: _kSurface),
                            )
                          : Text(
                              _isSignup ? "Sign up" : "Log in",
                              style: _display(size: 15, color: _kSurface),
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => setState(() {
                              _isSignup = !_isSignup;
                              _error = null;
                            }),
                    child: Text(
                      _isSignup
                          ? "Already have an account? Log in"
                          : "New here? Create an account",
                      style: _body(size: 13, color: _kAccent),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: Divider(color: _kDivider)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text("or",
                            style: _body(size: 12, color: _kInkMuted)),
                      ),
                      Expanded(child: Divider(color: _kDivider)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _loading ? null : _continueAsGuest,
                    child: Text(
                      "Continue without an account",
                      style: _body(size: 13, color: _kInkMuted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final void Function(String)? onSubmitted;

  const _AuthTextField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.keyboardType,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kDivider),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        onSubmitted: onSubmitted,
        style: _body(size: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: _body(size: 15, color: _kInkMuted),
          prefixIcon: Icon(icon, size: 20, color: _kInkMuted),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        ),
      ),
    );
  }
}
