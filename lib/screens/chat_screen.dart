import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../services/auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────
// Design tokens
// Palette: warm-neutral canvas + a single deep-teal accent. Chosen instead
// of the default cream/terracotta or near-black/neon combos so the app
// doesn't read as templated. Manrope carries headers and UI chrome; Inter
// carries message text, since it's built for long-form on-screen reading.
// ─────────────────────────────────────────────────────────────────────────

const Color _kCanvas = Color(0xFFF7F5F2);
const Color _kSurface = Color(0xFFFFFFFF);
const Color _kInk = Color(0xFF1C1B1F);
const Color _kInkMuted = Color(0xFF6F6A63);
const Color _kAccent = Color(0xFF0F5257);
const Color _kAccentSoft = Color(0xFFE4EFEE);
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

bool _looksLikeError(String content) {
  return content.startsWith("Error:") ||
      content.contains("Couldn't reach the server") ||
      content.startsWith("Server error") ||
      content.startsWith("Upload failed") ||
      content.startsWith("Upload error");
}

class ChatScreen extends StatefulWidget {
  final AuthService authService;
  final VoidCallback onLogout;

  const ChatScreen(
      {super.key, required this.authService, required this.onLogout});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];
  bool _loading = false;
  bool _uploading = false;
  bool _loadingHistory = false;
  bool _isLoggedIn = false;

  // Voice input
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;
  bool _listening = false;

  // Voice output
  final FlutterTts _tts = FlutterTts();
  bool _speakReplies = false;

  // IMPORTANT — pick the right host for where you're running the app:
  //   Android emulator      -> http://10.0.2.2:8000
  //   iOS simulator / macOS -> http://127.0.0.1:8000
  //   Physical device       -> http://<your-computer-LAN-IP>:8000
  //   Deployed backend      -> https://your-app.onrender.com
  static const String backendBase = "http://10.255.97.155:8001";
  @override
  void initState() {
    super.initState();
    _initSpeech();
    _loadHistoryIfLoggedIn();
  }

  Future<Map<String, String>> _authHeaders() async {
    final token = await widget.authService.getToken();
    if (token == null) return {};
    return {"Authorization": "Bearer $token"};
  }

  Future<void> _loadHistoryIfLoggedIn() async {
    final loggedIn = await widget.authService.isLoggedIn();
    if (!loggedIn || !mounted) return;

    setState(() {
      _isLoggedIn = true;
      _loadingHistory = true;
    });

    try {
      final headers = await _authHeaders();
      final uri = Uri.parse("$backendBase/chat/history");
      final response = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 && mounted) {
        final data = jsonDecode(response.body);
        final loaded = (data["messages"] as List)
            .map((m) => {
                  "role": m["role"].toString(),
                  "content": m["content"].toString(),
                })
            .toList();
        setState(() {
          _messages.clear();
          _messages.addAll(loaded.cast<Map<String, String>>());
        });
        _scrollToBottom();
      }
    } catch (_) {
      // If history can't load (offline, expired token, etc.), just start
      // with an empty conversation rather than blocking the UI.
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _logout() async {
    await widget.authService.logout();
    widget.onLogout();
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == "done" || status == "notListening") {
          setState(() => _listening = false);
        }
      },
      onError: (error) {
        setState(() => _listening = false);
      },
    );
    setState(() => _speechAvailable = available);
  }

  Future<void> _toggleListening() async {
    if (!_speechAvailable) return;

    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }

    setState(() => _listening = true);
    await _speech.listen(
      onResult: (result) {
        setState(() {
          _controller.text = result.recognizedWords;
        });
        if (result.finalResult) {
          setState(() => _listening = false);
        }
      },
    );
  }

  Future<void> _speak(String text) async {
    if (!_speakReplies || text.trim().isEmpty) return;
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> _pickAndUploadDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ["txt", "pdf"],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) return;

    setState(() => _uploading = true);
    try {
      final uri = Uri.parse("$backendBase/ingest/file");
      final request = http.MultipartRequest("POST", uri);
      request.headers.addAll(await _authHeaders());
      request.files.add(
        http.MultipartFile.fromBytes("file", file.bytes!, filename: file.name),
      );
      final streamedResponse = await request.send().timeout(
            const Duration(seconds: 60),
          );
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _showSnack(
          "Added '${file.name}' (${data['chunks_added']} chunks) to the bot's knowledge.",
        );
      } else {
        _showSnack("Upload failed (${response.statusCode}).");
      }
    } catch (e) {
      _showSnack("Upload error: $e");
    } finally {
      setState(() => _uploading = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: _body(size: 13, color: _kSurface)),
        backgroundColor: _kInk,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _loading) return;

    setState(() {
      _messages.add({"role": "user", "content": text});
      _messages.add({"role": "assistant", "content": ""});
      _loading = true;
    });
    _controller.clear();
    _scrollToBottom();

    final historyForRequest = _messages
        .sublist(0,
            _messages.length - 1) // exclude the empty placeholder we just added
        .map((m) => {"role": m["role"], "content": m["content"]})
        .toList();

    final assistantIndex = _messages.length - 1;
    final buffer = StringBuffer();

    try {
      final uri = Uri.parse("$backendBase/chat");
      final request = http.Request("POST", uri);
      request.headers["Content-Type"] = "application/json";
      request.headers.addAll(await _authHeaders());
      request.body = jsonEncode({
        "message": text,
        "history": historyForRequest,
      });

      final streamedResponse = await http.Client()
          .send(request)
          .timeout(const Duration(seconds: 30));

      if (streamedResponse.statusCode != 200) {
        setState(() {
          _messages[assistantIndex]["content"] =
              "Server error (${streamedResponse.statusCode}). Please try again.";
        });
        return;
      }

      final stream = streamedResponse.stream.transform(utf8.decoder);
      String pending = "";

      await for (final chunk in stream) {
        pending += chunk;
        final lines = pending.split("\n");
        // Keep the last (possibly incomplete) line in `pending`
        pending = lines.removeLast();

        for (final line in lines) {
          if (!line.startsWith("data: ")) continue;
          final jsonStr = line.substring("data: ".length).trim();
          if (jsonStr.isEmpty) continue;

          try {
            final data = jsonDecode(jsonStr);
            if (data["delta"] != null) {
              buffer.write(data["delta"]);
              setState(() {
                _messages[assistantIndex]["content"] = buffer.toString();
              });
              _scrollToBottom();
            } else if (data["error"] != null) {
              setState(() {
                _messages[assistantIndex]["content"] =
                    "Error: ${data["error"]}";
              });
            }
          } catch (_) {
            // ignore malformed partial JSON lines
          }
        }
      }

      _speak(buffer.toString());
    } catch (e) {
      setState(() {
        _messages[assistantIndex]["content"] =
            "Couldn't reach the server. Is the backend running? ($e)";
      });
    } finally {
      setState(() => _loading = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _tts.stop();
    _speech.stop();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kCanvas,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _loadingHistory
                  ? const Center(
                      child: CircularProgressIndicator(color: _kAccent))
                  : (_messages.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          itemCount: _messages.length,
                          itemBuilder: (context, i) =>
                              _buildMessageRow(_messages[i]),
                        )),
            ),
            _buildInputBar(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _kCanvas,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleSpacing: 20,
      title: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 8),
            decoration:
                const BoxDecoration(color: _kAccent, shape: BoxShape.circle),
          ),
          Text("Assistant", style: _display(size: 18)),
        ],
      ),
      actions: [
        _AppBarIconButton(
          tooltip: _speakReplies ? "Voice replies on" : "Voice replies off",
          icon: _speakReplies
              ? Icons.volume_up_rounded
              : Icons.volume_off_rounded,
          active: _speakReplies,
          onPressed: () => setState(() => _speakReplies = !_speakReplies),
        ),
        _AppBarIconButton(
          tooltip: "Add a document",
          icon: Icons.upload_rounded,
          loading: _uploading,
          onPressed: _uploading ? null : _pickAndUploadDocument,
        ),
        if (_isLoggedIn)
          _AppBarIconButton(
            tooltip: "Log out",
            icon: Icons.logout_rounded,
            onPressed: _logout,
          ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                  color: _kAccentSoft, shape: BoxShape.circle),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: _kAccent, size: 26),
            ),
            const SizedBox(height: 18),
            Text("Ask me anything", style: _display(size: 19)),
            const SizedBox(height: 8),
            Text(
              "Start a conversation, add a document for grounded answers, "
              "or tap the mic to speak instead of typing.",
              textAlign: TextAlign.center,
              style: _body(size: 14, color: _kInkMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageRow(Map<String, String> msg) {
    final isUser = msg["role"] == "user";
    final content = msg["content"] ?? "";
    final isError = !isUser && _looksLikeError(content);
    final isThinking = !isUser && content.isEmpty;

    final bubble = Container(
      constraints:
          BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.74),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: isUser ? _kAccent : (isError ? _kDangerSoft : _kSurface),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(isUser ? 18 : 4),
          topRight: Radius.circular(isUser ? 4 : 18),
          bottomLeft: const Radius.circular(18),
          bottomRight: const Radius.circular(18),
        ),
        border: isUser
            ? null
            : Border.all(color: isError ? const Color(0xFFF0C4C0) : _kDivider),
      ),
      child: isThinking
          ? const _TypingDots()
          : Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isError) ...[
                  const Icon(Icons.error_outline_rounded,
                      size: 16, color: _kDanger),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    content,
                    style: _body(
                      size: 15,
                      color: isUser ? _kSurface : (isError ? _kDanger : _kInk),
                    ),
                  ),
                ),
              ],
            ),
    );

    if (isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child:
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [bubble]),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 26,
            height: 26,
            margin: const EdgeInsets.only(right: 8),
            decoration: const BoxDecoration(
                color: _kAccentSoft, shape: BoxShape.circle),
            child: const Icon(Icons.auto_awesome_rounded,
                size: 13, color: _kAccent),
          ),
          Flexible(child: bubble),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Container(
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _kDivider),
          boxShadow: [
            BoxShadow(
              color: _kInk.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          children: [
            IconButton(
              tooltip: _listening ? "Stop listening" : "Speak your message",
              icon: Icon(
                _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                color: _listening ? _kDanger : _kInkMuted,
              ),
              onPressed: _speechAvailable ? _toggleListening : null,
            ),
            Expanded(
              child: TextField(
                controller: _controller,
                style: _body(size: 15),
                decoration: InputDecoration(
                  hintText: "Type a message…",
                  hintStyle: _body(size: 15, color: _kInkMuted),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onSubmitted: (_) => _sendMessage(),
                textInputAction: TextInputAction.send,
              ),
            ),
            const SizedBox(width: 4),
            _SendButton(enabled: !_loading, onPressed: _sendMessage),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Small presentational widgets
// ─────────────────────────────────────────────────────────────────────────

class _AppBarIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool active;
  final bool loading;
  final VoidCallback? onPressed;

  const _AppBarIconButton({
    required this.tooltip,
    required this.icon,
    this.active = false,
    this.loading = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: active ? _kAccentSoft : Colors.transparent,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tooltip,
          icon: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: _kAccent),
                )
              : Icon(icon, color: active ? _kAccent : _kInkMuted, size: 21),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onPressed;

  const _SendButton({required this.enabled, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? _kAccent : _kDivider,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onPressed : null,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            Icons.arrow_upward_rounded,
            size: 18,
            color: enabled ? _kSurface : _kInkMuted,
          ),
        ),
      ),
    );
  }
}

/// Three-dot "thinking" indicator shown while a streamed reply hasn't
/// produced its first token yet. One deliberate motion moment, kept subtle.
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1000))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _dotOpacity(double t, double offset) {
    final phase = (t + offset) % 1.0;
    return 0.3 + 0.7 * (0.5 - (phase - 0.5).abs()) * 2;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 14,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(3, (i) {
              return Opacity(
                opacity: _dotOpacity(_controller.value, i * 0.2),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                      color: _kAccent, shape: BoxShape.circle),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
