import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/chat_message.dart';
import '../services/ai_service.dart';
import '../services/action_handler.dart';
import '../services/voice_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/floating_nav_bar.dart';
import '../widgets/message_bubble.dart';
import '../widgets/thinking_avatar.dart';
import '../services/telegram_service.dart';
import '../services/chat_history_service.dart';
import '../services/notification_service.dart';
import 'settings_screen.dart';
import 'task_history_screen.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../main.dart';
import '../config/feature_flags.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AiService _aiService = AiService();
  final ActionHandler _actionHandler = ActionHandler();
  final VoiceService _voiceService = VoiceService();
  final NotificationService _notificationService = NotificationService();
  late final TelegramService _telegramService;

  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isListening = false;

  /// Set when the user taps the send button while it is showing Stop; the
  /// streaming loop checks it and breaks out.
  bool _stopRequested = false;

  // Custom switch state: 'chat' or 'agent'
  String _mode = 'chat';

  // Chat Session state tracking
  String _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
  String _sessionTitle = '';

  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  Timer? _overlayHistoryTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _telegramService = TelegramService(_actionHandler, _aiService);
    _initServices();
    _startOverlayHistorySync();
    // Register as the handler for overlay bubble tasks
    onOverlayTask = (task) => _sendMessage(task);
    // Decode the thinking avatar up front so it appears without a first-frame
    // delay the first time a request is sent.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ThinkingAvatar.precache(context);
    });
  }

  Future<void> _initServices() async {
    // The API-key banner is driven by _aiService.isConfigured, which is only
    // true once init() has read SharedPreferences — so this runs first and
    // paints immediately. Previously every service was initialised in one
    // unguarded chain with a single setState at the end, so if any later step
    // threw (a denied notification permission, no Shizuku, a bad Telegram
    // token) the rebuild never happened and a configured app kept showing
    // "API not configured" until something else called setState.
    try {
      await _aiService.init();
    } catch (e) {
      developer.log('AI service init failed: $e');
    }
    if (mounted) setState(() {});

    // Each of the remaining steps is independent; one failing must not stop
    // the others or leave the UI stale.
    await _guarded('notifications', () => _notificationService.requestPermission());
    await _guarded('voice', () => _voiceService.init());
    await _guarded('telegram', () => _telegramService.init());
    await _guarded('shizuku', () => _actionHandler.shizuku.checkAvailability());

    if (mounted) setState(() {});
  }

  Future<void> _guarded(String label, Future<void> Function() step) async {
    try {
      await step();
    } catch (e) {
      developer.log('$label init failed: $e');
    }
  }

  Future<void> _saveSession() async {
    if (_messages.isEmpty) return;

    // Set first user message as session title if not set
    if (_sessionTitle.isEmpty) {
      final firstUserMsg = _messages.firstWhere(
        (m) => m.isUser,
        orElse: () => ChatMessage(role: 'user', content: 'New Chat'),
      );
      _sessionTitle = firstUserMsg.content.length > 28
          ? '${firstUserMsg.content.substring(0, 25)}...'
          : firstUserMsg.content;
    }

    final session = ChatSession(
      id: _sessionId,
      title: _sessionTitle,
      timestamp: DateTime.now(),
      messages: _messages.map((m) => m.toJson()).toList(),
    );

    await ChatHistoryService.saveSession(session);
  }

  /// Stop an in-flight response. Bound to the send button while it shows the
  /// stop icon, replacing the old inline Stop button next to "Thinking...".
  void _stopGeneration() {
    _stopRequested = true;
    _actionHandler.cancelTask();
    _voiceService.cancelStreamingSession();
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
      _updateOverlayState();
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final userMessage = ChatMessage(role: 'user', content: text.trim());
    setState(() {
      _messages.add(userMessage);
      _isLoading = true;
      _stopRequested = false;
    });
    _updateOverlayState();
    _textController.clear();
    _scrollToBottom();
    await _saveSession();

    // The assistant bubble is created lazily, on the first chunk of visible
    // text — inserting it up front showed an empty card while waiting. Null
    // means "no bubble on screen yet"; the animated avatar stands in for it.
    int? assistantIndex;

    await _voiceService.stopSpeaking();

    try {
      final isAgent = _mode == 'agent';
      final stream = _aiService
          .sendMessageStream(text.trim(), isAgentMode: isAgent)
          .timeout(
            const Duration(seconds: 90),
            onTimeout: (sink) {
              sink.addError(
                TimeoutException(
                  'The model did not return visible text within 90 seconds.',
                ),
              );
              sink.close();
            },
          );
      String accumulated = '';

      final bool isTtsStreaming =
          _voiceService.isTtsEnabled && _voiceService.isConfigured;
      if (isTtsStreaming) {
        _voiceService.startStreamingSession();
      }
      bool detectedAction = false;

      await for (final chunk in stream) {
        if (_stopRequested) break;
        accumulated += chunk;

        // A response that opens with JSON or a code fence is a device action,
        // not something to show or speak.
        final trimmed = accumulated.trimLeft();
        final looksLikeAction =
            trimmed.startsWith('{') || trimmed.startsWith('```');

        if (isTtsStreaming && !detectedAction) {
          if (looksLikeAction) {
            detectedAction = true;
            _voiceService.cancelStreamingSession();
          } else {
            _voiceService.feedStreamChunk(chunk);
          }
        } else if (looksLikeAction) {
          detectedAction = true;
        }

        if (mounted && !looksLikeAction && trimmed.isNotEmpty) {
          setState(() {
            final bubble = ChatMessage(
              role: 'assistant',
              content: accumulated,
            );
            if (assistantIndex == null) {
              // First visible text: create the bubble now.
              _messages.add(bubble);
              assistantIndex = _messages.length - 1;
            } else {
              _messages[assistantIndex!] = bubble;
            }
          });
          _scrollToBottom();
        }
      }

      // Stopped by the user: keep whatever text already streamed, and do not
      // run the action or speak the partial reply.
      if (_stopRequested) {
        _voiceService.cancelStreamingSession();
        await _saveSession();
        return;
      }

      await _saveSession();

      // Check if it's an action
      final action = _aiService.parseAction(accumulated);

      if (action != null) {
        _voiceService.cancelStreamingSession();
        // Drop the bubble if one was created before the JSON became apparent.
        if (assistantIndex != null) {
          setState(() {
            _messages.removeAt(assistantIndex!);
          });
          assistantIndex = null;
        }

        await _showTaskProgressOverlay('Starting: ${text.trim()}');

        // Execute the action (pass aiService for multi-step tasks)
        final result = await _actionHandler.execute(
          action,
          userGoal: text.trim(),
          aiService: _aiService,
          onProgress: (msg) {
            developer.log('Task progress: $msg', name: 'Ultron-3');
            _sendOverlayEvent('OVERLAY_PROGRESS', msg);
            if (mounted) {
              setState(() {
                _messages.add(
                  ChatMessage(role: 'assistant', content: '⏳ $msg'),
                );
              });
              _scrollToBottom();
            }
          },
        );

        setState(() {
          _messages.add(
            ChatMessage(
              role: 'assistant',
              content: result.success
                  ? (action.response.isNotEmpty
                        ? action.response
                        : (result.details ?? 'Done.'))
                  : (action.response.isNotEmpty
                        ? '${action.response}\n\n⚠️ ${result.details}'
                        : '⚠️ ${result.details}'),
              actionResult: result,
            ),
          );
        });
        _sendOverlayEvent(
          'OVERLAY_TASK_FINISHED',
          result.success
              ? (result.details ?? 'Task complete.')
              : 'Task failed: ${result.details ?? 'Unknown error'}',
        );
        if (action.action != 'execute_task') {
          await _notificationService.showTaskCompleteNotification(
            result.success ? 'Task Completed' : 'Task Failed',
            result.details ??
                (result.success
                    ? 'Agent finished its goal.'
                    : 'Agent could not complete the task.'),
          );
        }
        if (action.response.isNotEmpty) {
          _voiceService.speak(action.response);
        }
        await _saveSession();
      } else {
        // Plain text response. If nothing was rendered — the text arrived as
        // one chunk that first looked like JSON, or parsing failed — create the
        // bubble now so the reply is never lost.
        if (assistantIndex == null && accumulated.trim().isNotEmpty && mounted) {
          setState(() {
            _messages.add(
              ChatMessage(role: 'assistant', content: accumulated),
            );
            assistantIndex = _messages.length - 1;
          });
          _scrollToBottom();
          await _saveSession();
        }

        if (isTtsStreaming && !detectedAction) {
          _voiceService.finishStreamingSession();
        } else if (!detectedAction) {
          // Never speak a raw JSON blob that failed to parse as an action.
          _voiceService.speak(accumulated);
        }
      }
    } catch (e) {
      _voiceService.cancelStreamingSession();
      if (mounted) {
        setState(() {
          // Remove the partial bubble only if one exists and it is still empty
          // of useful content; otherwise keep what streamed and append the error.
          final idx = assistantIndex;
          if (idx != null && idx < _messages.length &&
              _messages[idx].content.trim().isEmpty) {
            _messages.removeAt(idx);
          }
          _messages.add(
            ChatMessage(
              role: 'assistant',
              content: 'Error: ${e.toString().replaceFirst('Exception: ', '')}',
            ),
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _scrollToBottom();
        _updateOverlayState();
      }
    }
  }

  Future<void> _showTaskProgressOverlay(String message) async {
    if (!FeatureFlags.floatingOverlayEnabled) return;
    if (!await FlutterOverlayWindow.isPermissionGranted()) return;

    // Never cover Ultron-3 itself. The lifecycle observer will create the
    // overlay after an automated action moves this app to the background.
    if (_appLifecycleState != AppLifecycleState.paused) return;

    if (!await FlutterOverlayWindow.isActive()) {
      await FlutterOverlayWindow.showOverlay(
        enableDrag: true,
        overlayTitle: 'Ultron-3',
        overlayContent: 'Performing task...',
        flag: OverlayFlag.focusPointer,
        alignment: OverlayAlignment.centerRight,
        visibility: NotificationVisibility.visibilitySecret,
        positionGravity: PositionGravity.auto,
        startPosition: const OverlayPosition(0, 200),
        width: 56,
        height: 56,
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }

    // Keep the overlay minimized during automation. The user can still tap the
    // bubble to open the full conversation whenever they choose.
    _sendOverlayEvent('OVERLAY_TASK_STARTED', message);
  }

  void _sendOverlayEvent(String type, String message) {
    if (!FeatureFlags.floatingOverlayEnabled) return;
    final safeMessage = message.replaceAll('|', ' ');
    unawaited(
      FlutterOverlayWindow.shareData(
        '$type|$safeMessage',
      ).timeout(const Duration(seconds: 2)).catchError((Object _) {}),
    );
  }

  Future<void> _sendOverlayHistorySnapshot() async {
    if (!FeatureFlags.floatingOverlayEnabled) return;
    final history = base64Encode(
      utf8.encode(
        jsonEncode(_messages.map((message) => message.toJson()).toList()),
      ),
    );
    try {
      await FlutterOverlayWindow.shareData(
        'OVERLAY_HISTORY|$history',
      ).timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _toggleVoice() async {
    await _voiceService.stopSpeaking();
    if (_isListening) {
      await _voiceService.stopListening();
      setState(() => _isListening = false);
      return;
    }

    setState(() => _isListening = true);

    await _voiceService.startListening(
      onResult: (text) {
        _sendMessage(text);
      },
      onDone: () {
        if (mounted) {
          setState(() => _isListening = false);
        }
      },
    );
  }

  void _startNewChat() {
    setState(() {
      _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
      _sessionTitle = '';
      _messages.clear();
      _aiService.clearHistory();
    });
  }

  void _loadChatSession(ChatSession session) {
    setState(() {
      _sessionId = session.id;
      _sessionTitle = session.title;
      _messages.clear();
      for (final m in session.messages) {
        _messages.add(ChatMessage.fromJson(m));
      }

      _aiService.clearHistory();
      for (final m in _messages) {
        if (m.actionResult != null) continue;
        _aiService.addHistoryMessage(m.role, m.content);
      }
    });
    _scrollToBottom();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _overlayHistoryTimer?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    _voiceService.dispose();
    _telegramService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _appLifecycleState = state;
    });
    if (state == AppLifecycleState.resumed) {
      _startOverlayHistorySync();
      unawaited(_handleAppForegrounded());
    } else {
      _overlayHistoryTimer?.cancel();
      _updateOverlayState();
    }
  }

  void _startOverlayHistorySync() {
    _overlayHistoryTimer?.cancel();
    if (!FeatureFlags.floatingOverlayEnabled) return;
    unawaited(_importOverlayChatHistory());
    _overlayHistoryTimer = Timer.periodic(const Duration(milliseconds: 500), (
      _,
    ) {
      if (_appLifecycleState == AppLifecycleState.resumed) {
        unawaited(_importOverlayChatHistory());
      }
    });
  }

  Future<void> _handleAppForegrounded() async {
    await _updateOverlayState();
    await _importOverlayChatHistory();
  }

  Future<void> _importOverlayChatHistory() async {
    if (!FeatureFlags.floatingOverlayEnabled) return;
    if (_importingOverlayHistory) return;
    _importingOverlayHistory = true;
    try {
      final handoff = await ChatHistoryService.consumeOverlayMessages();
      if (!mounted || handoff.isEmpty) return;

      final imported = handoff.map(ChatMessage.fromJson).toList();
      for (final message in imported) {
        if (message.actionResult == null) {
          _aiService.addHistoryMessage(message.role, message.content);
        }
      }
      setState(() {
        _messages.addAll(imported);
      });
      _scrollToBottom();
      await _saveSession();
    } finally {
      _importingOverlayHistory = false;
    }
  }

  int _overlayUpdateGeneration = 0;
  bool _importingOverlayHistory = false;

  Future<void> _updateOverlayState() async {
    if (!FeatureFlags.floatingOverlayEnabled) return;
    final generation = ++_overlayUpdateGeneration;
    final isBackground = _appLifecycleState == AppLifecycleState.paused;
    final shouldBeActive = isBackground;

    bool granted = await FlutterOverlayWindow.isPermissionGranted();
    if (!granted || generation != _overlayUpdateGeneration) return;

    bool active = await FlutterOverlayWindow.isActive();
    if (generation != _overlayUpdateGeneration) return;
    if (shouldBeActive && !active) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (generation != _overlayUpdateGeneration) return;
      if (_appLifecycleState != AppLifecycleState.paused) return;
      if (await FlutterOverlayWindow.isActive()) return;
      await FlutterOverlayWindow.showOverlay(
        enableDrag: true,
        overlayTitle: "Ultron-3",
        overlayContent: _isLoading
            ? "Performing task..."
            : "Floating Assistant",
        flag: OverlayFlag.focusPointer,
        alignment: OverlayAlignment.centerRight,
        visibility: NotificationVisibility.visibilitySecret,
        positionGravity: PositionGravity.auto,
        startPosition: const OverlayPosition(0, 200),
        width: 56,
        height: 56,
      );
      if (_isLoading && _appLifecycleState == AppLifecycleState.paused) {
        // Give the overlay isolate time to attach its listener, then send the
        // full active conversation. A second snapshot makes cold starts
        // reliable without duplicating messages because the overlay replaces
        // its list atomically.
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await _sendOverlayHistorySnapshot();
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (_isLoading && _appLifecycleState == AppLifecycleState.paused) {
          await _sendOverlayHistorySnapshot();
        }
      }
    } else if (shouldBeActive && active && _isLoading) {
      await _sendOverlayHistorySnapshot();
    } else if (!shouldBeActive && active) {
      try {
        await FlutterOverlayWindow.shareData(
          'OVERLAY_RESET|',
        ).timeout(const Duration(milliseconds: 150));
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (generation != _overlayUpdateGeneration) return;
      if (_appLifecycleState == AppLifecycleState.paused) return;
      await FlutterOverlayWindow.closeOverlay();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBody: true,
      extendBodyBehindAppBar: true,
      backgroundColor: isDark ? const Color(0xFF090D16) : const Color(0xFFF8FAFC),
      // The drawer is its own widget so it keeps its session list in state
      // instead of re-reading the history file on every streamed token, which
      // is what the old inline FutureBuilder did.
      drawer: AppDrawer(
        isDark: isDark,
        currentSessionId: _sessionId,
        onNewChat: _startNewChat,
        onOpenSession: _loadChatSession,
        onSessionDeleted: _onSessionDeleted,
        onOpenTaskHistory: _openTaskHistory,
        onOpenSettings: _openSettings,
      ),
      body: Stack(
        children: [
          // Dynamic liquid background glows
          _buildBackgroundGlows(isDark),

          // Master Backdrop blur filter for atmospheric glass diffusion
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
              child: Container(color: Colors.transparent),
            ),
          ),

          // Main Column layout
          Column(
            children: [
              // Floating glass nav bar (replaces a heavy standard AppBar).
              // Its fields are all stable across a streaming reply, and it
              // defines ==, so it is skipped by the per-token setState.
              FloatingNavBar(
                isDark: isDark,
                busy: _isLoading,
                onNewChat: _startNewChat,
                onSettings: _openSettings,
              ),

              // API key warning banner if not configured
              if (!_aiService.isConfigured) _buildApiWarningBanner(context, isDark),

              // Chat Messages or Empty State
              Expanded(
                child: _messages.isEmpty
                    ? _buildEmptyState(isDark)
                    : ListView.builder(
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          return MessageBubble(message: _messages[index]);
                        },
                      ),
              ),

              // Shimmer / Dot pulse thinking loading indicator
              if (_isLoading) _buildThinkingIndicator(),

              // Frosted Liquid Glass Input Bar
              _buildInputBar(isDark),
            ],
          ),
        ],
      ),
    );
  }

  void _openTaskHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TaskHistoryScreen()),
    );
  }

  /// The drawer has already removed the session from storage; this only fixes
  /// up the screen when the deleted session is the one on display, which would
  /// otherwise be re-saved under its old id on the next message.
  void _onSessionDeleted(String id) {
    if (id == _sessionId) _startNewChat();
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          aiService: _aiService,
          shizukuService: _actionHandler.shizuku,
          screenAutomationService: _actionHandler.screenAutomation,
          telegramService: _telegramService,
          voiceService: _voiceService,
        ),
      ),
    );
    await _actionHandler.shizuku.checkAvailability();
    if (mounted) setState(() {});
  }

  Widget _buildBackgroundGlows(bool isDark) {
    return Positioned.fill(
      child: Stack(
        children: [
          // Top-left indigo glow orb
          Positioned(
            top: -120,
            left: -60,
            child: Container(
              width: 380,
              height: 380,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    isDark
                        ? const Color(0xFF6366F1).withValues(alpha: 0.30)
                        : const Color(0xFF4F46E5).withValues(alpha: 0.16),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Bottom-right sky blue orb
          Positioned(
            bottom: 30,
            right: -80,
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    isDark
                        ? const Color(0xFF38BDF8).withValues(alpha: 0.22)
                        : const Color(0xFF0EA5E9).withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Center purple ambient accent orb
          Positioned(
            top: 280,
            right: 40,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    isDark
                        ? const Color(0xFF8B5CF6).withValues(alpha: 0.18)
                        : const Color(0xFFA855F7).withValues(alpha: 0.10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector(bool isDark) {
    final isChat = _mode == 'chat';

    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 8, bottom: 12),
        padding: const EdgeInsets.all(4),
        width: 220,
        height: 44,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        child: Stack(
          children: [
            // Animated Liquid Glass pill slider
            AnimatedAlign(
              alignment: isChat ? Alignment.centerLeft : Alignment.centerRight,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOutCubic,
              child: FractionallySizedBox(
                widthFactor: 0.5,
                child: Container(
                  height: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF0EA5E9)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.40),
                        blurRadius: 12,
                        spreadRadius: -1,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _mode = 'chat'),
                    behavior: HitTestBehavior.opaque,
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 15,
                            color: isChat
                                ? Colors.white
                                : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Chat',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isChat
                                  ? Colors.white
                                  : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _mode = 'agent'),
                    behavior: HitTestBehavior.opaque,
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.smart_toy_outlined,
                            size: 15,
                            color: !isChat
                                ? Colors.white
                                : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Agent',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: !isChat
                                  ? Colors.white
                                  : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Height of one suggestion tile: its padding, the icon chip, a breathing gap
  /// and two lines of title at the device's own text scale. Keep in step with
  /// the tile's own paddings and text style below.
  static double _suggestionTileHeight(BuildContext context) {
    const verticalPadding = 14.0 * 2;
    const iconChip = 8.0 * 2 + 18.0;
    const gap = 10.0;
    const lineHeight = 13.0 * 1.3;
    return verticalPadding +
        iconChip +
        gap +
        MediaQuery.textScalerOf(context).scale(lineHeight) * 2;
  }

  Widget _buildApiWarningBanner(BuildContext context, bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: isDark ? 0.15 : 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.amber.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'API not configured. Tap Settings to set up.',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    aiService: _aiService,
                    shizukuService: _actionHandler.shizuku,
                    screenAutomationService: _actionHandler.screenAutomation,
                    telegramService: _telegramService,
                    voiceService: _voiceService,
                  ),
                ),
              );
              if (mounted) setState(() {});
            },
            child: const Text(
              'Configure',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    final time = DateTime.now();
    String timeGreeting = 'Hello';
    if (time.hour >= 5 && time.hour < 12) {
      timeGreeting = 'Hello, good morning.';
    } else if (time.hour >= 12 && time.hour < 17) {
      timeGreeting = 'Hello, good afternoon.';
    } else if (time.hour >= 17 && time.hour < 22) {
      timeGreeting = 'Hello, good evening.';
    } else {
      timeGreeting = 'Hello.';
    }

    final suggestions = _mode == 'chat'
        ? [
            {'icon': Icons.auto_awesome_rounded, 'title': 'Summarize recent news & tech trends'},
            {'icon': Icons.code_rounded, 'title': 'Write code snippet for Flutter animation'},
            {'icon': Icons.lightbulb_outline_rounded, 'title': 'Explain quantum computing simply'},
            {'icon': Icons.edit_note_rounded, 'title': 'Draft a concise professional email'},
          ]
        : [
            {'icon': Icons.apps_rounded, 'title': 'Open WhatsApp and send message'},
            {'icon': Icons.contact_phone_outlined, 'title': 'Find Mom in contacts and call'},
            {'icon': Icons.volume_up_rounded, 'title': 'Adjust system volume to 80%'},
            {'icon': Icons.screenshot_monitor_rounded, 'title': 'Analyze what is on my screen'},
          ];

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),

          // Greeting text
          Text(
            timeGreeting,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w300,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              letterSpacing: -1.2,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFF6366F1), Color(0xFF0EA5E9)],
            ).createShader(bounds),
            child: const Text(
              'How can I help you?',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -1.2,
                height: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 36),

          // Suggestions Header
          Text(
            'SUGGESTIONS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 14),

          // 2-Column Grid Layout of Glass Suggestion Cards
          //
          // mainAxisExtent rather than childAspectRatio: the tile's contents
          // are a fixed-size icon plus up to two lines of text, so its natural
          // height depends on the device font scale. A ratio-derived height is
          // computed from the width alone, which clipped the bottom of the
          // second line as soon as the user's text size was above the default.
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              mainAxisExtent: _suggestionTileHeight(context),
            ),
            itemCount: suggestions.length,
            itemBuilder: (context, index) {
              final item = suggestions[index];
              final title = item['title'] as String;
              final icon = item['icon'] as IconData;

              return ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.05)
                          : Colors.white.withValues(alpha: 0.70),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : Colors.white.withValues(alpha: 0.80),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isDark
                              ? Colors.black.withValues(alpha: 0.20)
                              : const Color(0x0A0F172A),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _sendMessage(title),
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFF6366F1).withValues(alpha: isDark ? 0.2 : 0.1),
                                ),
                                child: Icon(
                                  icon,
                                  size: 18,
                                  color: const Color(0xFF6366F1),
                                ),
                              ),
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? const Color(0xFFF8FAFC) : const Color(0xFF1E293B),
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// While a response is generating, the only indicator is the animated avatar.
  /// The "Thinking..." label and inline Stop button were removed — the send
  /// button doubles as Stop instead (see [_buildSendButton]).
  Widget _buildThinkingIndicator() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          ThinkingAvatar(size: 44),
        ],
      ),
    );
  }

  /// Radius of the mode dropdown's card.
  static const double _modeMenuRadius = 18;

  /// Inset between the card edge and a row's selection pill. The pill radius is
  /// [_modeMenuRadius] minus this, so the two curves stay concentric.
  static const double _modeMenuInset = 6;

  Widget _buildModeDropdownChip(bool isDark) {
    return PopupMenuButton<String>(
      // Deliberately not passing initialValue: Flutter highlights the matching
      // item by wrapping it in a bare Container(color: highlightColor), a
      // full-bleed rectangle whose square corners overhang the rounded card.
      // The selected row is styled inside its own child instead.
      onSelected: (String value) {
        if (value == _mode) return;
        setState(() {
          _mode = value;
        });
      },
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_modeMenuRadius),
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      // Clips the items' rectangular ink splashes to the rounded card.
      clipBehavior: Clip.antiAlias,
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      elevation: 6,
      // Matches the rows' horizontal inset so the padding around the pills is
      // even on all four sides (the default is 8 vertical, 0 horizontal).
      menuPadding: const EdgeInsets.symmetric(vertical: _modeMenuInset),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        _buildModeMenuItem(
          value: 'chat',
          label: 'Chat Mode',
          icon: Icons.chat_bubble_outline_rounded,
          isDark: isDark,
        ),
        _buildModeMenuItem(
          value: 'agent',
          label: 'Agent Mode',
          icon: Icons.smart_toy_outlined,
          isDark: isDark,
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.16)
                : Colors.black.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _mode == 'chat'
                  ? Icons.chat_bubble_outline_rounded
                  : Icons.smart_toy_outlined,
              size: 14,
              color: isDark ? Colors.white70 : const Color(0xFF475569),
            ),
            const SizedBox(width: 6),
            Text(
              _mode == 'chat' ? 'Chat' : 'Agent',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF1E293B),
              ),
            ),
            const SizedBox(width: 3),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: isDark ? Colors.white54 : const Color(0xFF64748B),
            ),
          ],
        ),
      ),
    );
  }

  /// One row of the mode dropdown. The selection state is drawn as an inset,
  /// rounded pill inside the row so its curve stays concentric with the card,
  /// rather than the square full-bleed highlight Flutter applies by default.
  PopupMenuItem<String> _buildModeMenuItem({
    required String value,
    required String label,
    required IconData icon,
    required bool isDark,
  }) {
    final selected = _mode == value;
    const accent = Color(0xFF6366F1);

    return PopupMenuItem<String>(
      value: value,
      height: 44,
      // The pill supplies the inset, so the item itself must not add padding.
      padding: EdgeInsets.zero,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: _modeMenuInset),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.14) : Colors.transparent,
          borderRadius: BorderRadius.circular(
            _modeMenuRadius - _modeMenuInset,
          ),
          border: Border.all(
            color: selected ? accent.withValues(alpha: 0.38) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected
                  ? accent
                  : (isDark ? Colors.white70 : Colors.black87),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected
                    ? accent
                    : (isDark ? Colors.white : Colors.black87),
              ),
            ),
            const SizedBox(width: 10),
            // Reserved even when unselected so both rows measure the same width
            // and the card does not resize between openings.
            SizedBox(
              width: 16,
              child: selected
                  ? const Icon(Icons.check_rounded, size: 16, color: accent)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(bool isDark) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.16)
                      : Colors.white.withValues(alpha: 0.85),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.30)
                        : const Color(0x140F172A),
                    blurRadius: 24,
                    spreadRadius: -2,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Row inside input bar: Mode selector dropdown chip
                  Row(
                    children: [
                      _buildModeDropdownChip(isDark),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Bottom Row: Text field + side-by-side Voice & Upward Arrow Send Buttons
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          minLines: 1,
                          maxLines: 5,
                          style: TextStyle(
                            fontSize: 14.5,
                            color: isDark ? Colors.white : const Color(0xFF1E293B),
                          ),
                          decoration: InputDecoration(
                            hintText: _isListening
                                ? 'Listening...'
                                : (_mode == 'chat'
                                    ? 'Type a message...'
                                    : 'Type an agent command...'),
                            hintStyle: TextStyle(
                              fontSize: 14.5,
                              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          textInputAction: TextInputAction.send,
                          onSubmitted: _isLoading ? null : (text) => _sendMessage(text),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Side-by-Side Voice Mic + ChatGPT Style Upward Arrow Send Button
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Small Voice Mic Button
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isListening
                                  ? Colors.redAccent
                                  : (isDark
                                        ? Colors.white.withValues(alpha: 0.10)
                                        : Colors.black.withValues(alpha: 0.05)),
                              border: Border.all(
                                color: _isListening
                                    ? Colors.redAccent
                                    : (isDark
                                          ? Colors.white.withValues(alpha: 0.18)
                                          : Colors.black.withValues(alpha: 0.10)),
                                width: 1,
                              ),
                              boxShadow: _isListening
                                  ? [
                                      BoxShadow(
                                        color: Colors.redAccent.withValues(alpha: 0.45),
                                        blurRadius: 10,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: Icon(
                                _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                                color: _isListening
                                    ? Colors.white
                                    : (isDark ? Colors.white70 : const Color(0xFF475569)),
                                size: 18,
                              ),
                              onPressed: _isLoading ? null : _toggleVoice,
                            ),
                          ),
                          const SizedBox(width: 8),

                          // ChatGPT-style button: upward arrow to send, and a
                          // stop square while a response is generating.
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: _isLoading
                                  ? null
                                  : const LinearGradient(
                                      colors: [
                                        Color(0xFF6366F1),
                                        Color(0xFF0EA5E9),
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                              color: _isLoading
                                  ? (isDark
                                        ? Colors.white.withValues(alpha: 0.14)
                                        : Colors.black.withValues(alpha: 0.08))
                                  : null,
                              boxShadow: _isLoading
                                  ? null
                                  : [
                                      BoxShadow(
                                        color: const Color(
                                          0xFF6366F1,
                                        ).withValues(alpha: 0.40),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                            ),
                            child: IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              tooltip: _isLoading ? 'Stop' : 'Send',
                              icon: Icon(
                                _isLoading
                                    ? Icons.stop_rounded
                                    : Icons.arrow_upward_rounded,
                                size: _isLoading ? 18 : 19,
                                color: _isLoading
                                    ? (isDark
                                          ? Colors.white
                                          : const Color(0xFF1E293B))
                                    : Colors.white,
                              ),
                              onPressed: _isLoading
                                  ? _stopGeneration
                                  : () => _sendMessage(_textController.text),
                            ),
                          ),
                        ],
                      ),
                    ],
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

