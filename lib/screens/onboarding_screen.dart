import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../config/feature_flags.dart';
import '../services/ai_service.dart';
import '../services/screen_automation_service.dart';
import 'home_screen.dart';

/// Signature gradient used across the liquid-glass surfaces.
const List<Color> _primaryGradient = [
  Color(0xFF6366F1), // Indigo-500
  Color(0xFF8B5CF6), // Violet-500
  Color(0xFF06B6D4), // Cyan-500
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  final ScreenAutomationService _screenAutomationService =
      ScreenAutomationService();
  final AiService _aiService = AiService();

  int _currentStep = 0;
  bool _isAccessibilityGranted = false;
  bool _isMicrophoneGranted = false;
  bool _isNotificationsGranted = false;
  bool _isContactsGranted = false;
  bool _isPhoneGranted = false;
  bool _isSmsGranted = false;
  bool _isOverlayGranted = false;

  // AI config states
  String _selectedProvider = 'deepseek';
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _baseUrlController = TextEditingController(
    text: 'https://api.deepseek.com',
  );
  final TextEditingController _modelController = TextEditingController(
    text: 'deepseek-chat',
  );
  bool _obscureKey = true;
  bool _isValidating = false;
  String? _validationError;

  // Ambient animation
  late final AnimationController _fxController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fxController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat();
    _loadAiDefaults();
    _checkPermissions();
  }

  Future<void> _loadAiDefaults() async {
    await _aiService.init();
    if (!mounted || !_aiService.isConfigured) return;
    setState(() {
      _selectedProvider = 'custom';
      _apiKeyController.text = _aiService.apiKey;
      _baseUrlController.text = _aiService.baseUrl;
      _modelController.text = _aiService.model;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fxController.dispose();
    _pageController.dispose();
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
    }
  }

  Future<void> _checkPermissions() async {
    final accessibilityRunning = await _screenAutomationService
        .isServiceRunning();
    final microphoneStatus = await Permission.microphone.status;
    final notificationsStatus = await Permission.notification.status;
    final contactsStatus = await Permission.contacts.status;
    final phoneStatus = await Permission.phone.status;
    final smsStatus = await Permission.sms.status;
    final overlayGranted = FeatureFlags.floatingOverlayEnabled
        ? await FlutterOverlayWindow.isPermissionGranted()
        : false;

    if (mounted) {
      setState(() {
        _isAccessibilityGranted = accessibilityRunning;
        _isMicrophoneGranted = microphoneStatus.isGranted;
        _isNotificationsGranted = notificationsStatus.isGranted;
        _isContactsGranted = contactsStatus.isGranted;
        _isPhoneGranted = phoneStatus.isGranted;
        _isSmsGranted = smsStatus.isGranted;
        _isOverlayGranted = overlayGranted;
      });
    }
  }

  Future<void> _requestPermission(Permission permission) async {
    await permission.request();
    _checkPermissions();
  }

  Future<void> _requestAccessibility() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enable Screen Control'),
        content: const Text(
          'If Android shows “Restricted setting”, open App Info first, tap the '
          'three-dot menu, and choose “Allow restricted settings”. Then return '
          'and open Accessibility Settings to enable Ultron-3 Screen Control.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _screenAutomationService.openAccessibilitySettings();
            },
            child: const Text('Accessibility Settings'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              openAppSettings();
            },
            child: const Text('Open App Info First'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestOverlayPermission() async {
    if (!FeatureFlags.floatingOverlayEnabled) return;
    bool granted = await FlutterOverlayWindow.isPermissionGranted();
    if (!granted) {
      await FlutterOverlayWindow.requestPermission();
      granted = await FlutterOverlayWindow.isPermissionGranted();
    }
    setState(() {
      _isOverlayGranted = granted;
    });
  }

  void _selectProvider(String provider) {
    setState(() {
      _selectedProvider = provider;
      _validationError = null;
      if (provider == 'deepseek') {
        _baseUrlController.text = 'https://api.deepseek.com';
        _modelController.text = 'deepseek-chat';
      } else if (provider == 'groq') {
        _baseUrlController.text = 'https://api.groq.com/openai/v1';
        _modelController.text = 'llama-3.3-70b-versatile';
      } else if (provider == 'nvidia') {
        _baseUrlController.text = AiService.nvidiaBaseUrl;
        _modelController.text = AiService.nvidiaDefaultModel;
      } else if (provider == 'ollama') {
        _baseUrlController.text = 'http://10.0.2.2:11434/v1';
        _modelController.text = 'gemma2';
      } else if (provider == 'local') {
        _baseUrlController.text = 'http://10.0.2.2:1234/v1';
        _modelController.text = 'qwen2.5-7b-instruct';
      } else {
        _baseUrlController.clear();
        _modelController.clear();
      }
    });
  }

  Future<void> _testAndSave() async {
    setState(() {
      _isValidating = true;
      _validationError = null;
    });

    final apiKey = _apiKeyController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    final model = _modelController.text.trim();

    if (baseUrl.isEmpty || model.isEmpty) {
      setState(() {
        _validationError = 'Please fill out API Base URL and Model.';
        _isValidating = false;
      });
      return;
    }

    if (_selectedProvider != 'ollama' &&
        _selectedProvider != 'local' &&
        apiKey.isEmpty) {
      setState(() {
        _validationError = 'API Key is required for this provider.';
        _isValidating = false;
      });
      return;
    }

    try {
      final models = await _aiService.fetchAvailableModels(baseUrl, apiKey);
      if (models.isNotEmpty ||
          _selectedProvider == 'ollama' ||
          _selectedProvider == 'local') {
        await _aiService.saveSettings(
          apiKey: apiKey,
          baseUrl: baseUrl,
          model: model,
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('onboarding_completed', true);

        if (mounted) {
          setState(() {
            _isValidating = false;
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Configuration validated! Launching Ultron-3...',
              ),
              backgroundColor: Colors.indigoAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      } else {
        setState(() {
          _validationError =
              'Failed to fetch models from the server. Verify base URL and API Key.';
          _isValidating = false;
        });
      }
    } catch (e) {
      setState(() {
        _validationError =
            'Error: ${e.toString().replaceFirst('Exception: ', '')}';
        _isValidating = false;
      });
    }
  }

  Future<void> _fetchModels() async {
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();

    if (baseUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter an API Base URL first.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    setState(() {
      _isValidating = true;
    });

    try {
      final models = await _aiService.fetchAvailableModels(baseUrl, apiKey);

      setState(() {
        _isValidating = false;
      });

      if (models.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'No models found. Check base URL or API Key.',
              ),
              backgroundColor: Colors.orangeAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
        return;
      }

      if (mounted) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        showModalBottomSheet(
          context: context,
          backgroundColor: isDark ? const Color(0xFF161329) : Colors.white,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          builder: (context) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AiService.isNvidiaBaseUrl(baseUrl)
                          ? 'Select a Free NVIDIA Model'
                          : 'Select a Model',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        itemCount: models.length,
                        itemBuilder: (context, index) {
                          final modelName = models[index];
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                            title: Text(
                              modelName,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? Colors.white70
                                    : Colors.black87,
                              ),
                            ),
                            trailing: const Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                            ),
                            onTap: () {
                              setState(() {
                                _modelController.text = modelName;
                              });
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }
    } catch (e) {
      setState(() {
        _isValidating = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error: ${e.toString().replaceFirst('Exception: ', '')}',
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  bool get _canProceedToModel {
    return _isAccessibilityGranted &&
        _isMicrophoneGranted &&
        (!FeatureFlags.floatingOverlayEnabled || _isOverlayGranted);
  }

  // ─────────────────────────────────────────────────────────────
  // LAYOUT
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      body: Stack(
        children: [
          // Living gradient + drifting orbs (blurred by the glass above)
          Positioned.fill(child: _buildBackground(isDark)),

          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: _buildGlassStepper(isDark),
                ),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (page) {
                      setState(() {
                        _currentStep = page;
                      });
                    },
                    children: [
                      _buildWelcomePage(isDark),
                      _buildPermissionsPage(isDark),
                      _buildModelSetupPage(isDark),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Ambient background ───────────────────────────────────────

  Widget _buildBackground(bool isDark) {
    return AnimatedBuilder(
      animation: _fxController,
      builder: (context, _) {
        final t = _fxController.value;
        double drift(double amp, double speed, double phase) =>
            math.sin((t * math.pi * 2 * speed) + phase) * amp;

        return Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? const [
                          Color(0xFF0B0F19),
                          Color(0xFF1E1B4B),
                          Color(0xFF172554),
                        ]
                      : const [
                          Color(0xFFC7D2FE),
                          Color(0xFFE9D5FF),
                          Color(0xFFBAE6FD),
                        ],
                ),
              ),
            ),
            Positioned(
              top: -70 + drift(18, 1, 0),
              left: -70 + drift(24, 0.7, 2),
              child: _orb(
                340,
                isDark
                    ? const Color(0xFF6366F1).withOpacity(0.55)
                    : const Color(0xFF818CF8).withOpacity(0.75),
              ),
            ),
            Positioned(
              top: 90 + drift(16, 0.9, 1),
              right: -80 + drift(26, 0.6, 3),
              child: _orb(
                300,
                isDark
                    ? const Color(0xFF8B5CF6).withOpacity(0.5)
                    : const Color(0xFFC084FC).withOpacity(0.7),
              ),
            ),
            Positioned(
              bottom: -60 + drift(20, 0.8, 4),
              left: -40 + drift(22, 1.1, 1),
              child: _orb(
                360,
                isDark
                    ? const Color(0xFF0EA5E9).withOpacity(0.5)
                    : const Color(0xFF38BDF8).withOpacity(0.7),
              ),
            ),
            Positioned(
              bottom: 120 + drift(14, 1.2, 5),
              right: 40 + drift(20, 0.7, 0),
              child: _orb(
                220,
                isDark
                    ? const Color(0xFFEC4899).withOpacity(0.4)
                    : const Color(0xFFF472B6).withOpacity(0.6),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _orb(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withOpacity(0)],
        ),
      ),
    );
  }

  // ── Glass stepper ────────────────────────────────────────────

  Widget _buildGlassStepper(bool isDark) {
    final muted = isDark ? Colors.white70 : const Color(0xFF475569);

    return _GlassBox(
      radius: 24,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      blur: 32,
      strong: true,
      child: Row(
        children: List.generate(3, (index) {
          final active = _currentStep == index;
          final done = _currentStep > index;
          return Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    if (index == 0)
                      const SizedBox(width: 6)
                    else
                      Expanded(
                        child: _stepLine(
                          _currentStep >= index,
                          isDark,
                        ),
                      ),
                    _stepDot(index, active, done, isDark),
                    if (index == 2)
                      const SizedBox(width: 6)
                    else
                      Expanded(
                        child: _stepLine(_currentStep > index, isDark),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  const ['Welcome', 'Permissions', 'AI Setup'][index],
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.3,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    color: active
                        ? (isDark
                              ? Colors.white
                              : const Color(0xFF4F46E5))
                        : done
                        ? muted
                        : muted.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _stepLine(bool filled, bool isDark) {
    return Container(
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        gradient: filled
            ? const LinearGradient(
                colors: [Color(0xFF8B5CF6), Color(0xFF06B6D4)],
              )
            : LinearGradient(
                colors: [
                  Colors.white.withOpacity(isDark ? 0.10 : 0.28),
                  Colors.white.withOpacity(isDark ? 0.10 : 0.28),
                ],
              ),
      ),
    );
  }

  Widget _stepDot(int index, bool active, bool done, bool isDark) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      width: active ? 36 : 30,
      height: active ? 36 : 30,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: (active || done)
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _primaryGradient,
              )
            : LinearGradient(
                colors: [
                  Colors.white.withOpacity(isDark ? 0.10 : 0.30),
                  Colors.white.withOpacity(isDark ? 0.06 : 0.18),
                ],
              ),
        border: Border.all(
          color: Colors.white.withOpacity(isDark ? 0.14 : 0.5),
          width: 1,
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: const Color(0xFF6366F1).withOpacity(0.5),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ]
            : null,
      ),
      child: done
          ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
          : Text(
              '${index + 1}',
              style: TextStyle(
                color: active ? Colors.white : Colors.white.withOpacity(0.7),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }

  // ── STEP 1: WELCOME ──────────────────────────────────────────

  Widget _buildWelcomePage(bool isDark) {
    final muted = isDark ? Colors.white70 : const Color(0xFF475569);

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
      child: Column(
        children: [
          const SizedBox(height: 14),
          _buildFloatingLogo(isDark),
          const SizedBox(height: 34),
          _GradientText(
            'Ultron-3',
            style: TextStyle(
              fontSize: 44,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.2,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 12),
          _GlassBox(
            radius: 999,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            blur: 20,
            child: Text(
              'AI AGENT FOR ANDROID',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 2.2,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF4F46E5),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Your local, secure, and smart mobile companion. Ultron-3 can '
            'navigate apps, perform operations, and speak with you.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: muted,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 30),
          _buildFeatureCard(
            Icons.shield_outlined,
            const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
            'Local & Private',
            'Keys stay on-device. Works with local servers too.',
            isDark,
          ),
          const SizedBox(height: 12),
          _buildFeatureCard(
            Icons.touch_app_rounded,
            const [Color(0xFF06B6D4), Color(0xFF3B82F6)],
            'Automated Actions',
            'Reads your screen and operates any app hands-free.',
            isDark,
          ),
          const SizedBox(height: 12),
          _buildFeatureCard(
            Icons.record_voice_over_rounded,
            const [Color(0xFFF43F5E), Color(0xFFFB923C)],
            'Voice & Remote',
            'Speak commands or control from Telegram anywhere.',
            isDark,
          ),
          const SizedBox(height: 30),
          _gradientButton(
            label: 'Get Started',
            icon: Icons.arrow_forward_rounded,
            height: 58,
            radius: 20,
            onPressed: () {
              _pageController.nextPage(
                duration: const Duration(milliseconds: 450),
                curve: Curves.easeOutCubic,
              );
            },
          ),
          const SizedBox(height: 12),
          // Hint that glass is interactive
          Text(
            'Swipe freely — everything below is frosted glass.',
            style: TextStyle(
              fontSize: 11.5,
              color: muted.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingLogo(bool isDark) {
    return AnimatedBuilder(
      animation: _fxController,
      builder: (context, _) {
        final floatY = math.sin(_fxController.value * math.pi * 2) * 7;
        return Transform.translate(
          offset: Offset(0, floatY),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Ambient glow
              Container(
                width: 210,
                height: 210,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF8B5CF6).withOpacity(
                        isDark ? 0.40 : 0.30,
                      ),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              // Gradient ring
              Container(
                width: 150,
                height: 150,
                padding: const EdgeInsets.all(3.5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(38),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: _primaryGradient,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withOpacity(0.45),
                      blurRadius: 30,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(35),
                    color: isDark ? const Color(0xFF0F172A) : Colors.white,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(35),
                    child: Image.asset(
                      'assets/app-logo.png',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stack) => Icon(
                        Icons.smart_toy_rounded,
                        size: 64,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFeatureCard(
    IconData icon,
    List<Color> gradient,
    String title,
    String subtitle,
    bool isDark,
  ) {
    final onGlass = isDark ? Colors.white : const Color(0xFF1E293B);
    final muted = isDark ? Colors.white70 : const Color(0xFF475569);

    return _GlassBox(
      radius: 22,
      padding: const EdgeInsets.all(16),
      blur: 26,
      child: Row(
        children: [
          _GradientIcon(icon: icon, gradient: gradient, size: 21),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: onGlass,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: muted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: muted.withOpacity(0.6),
            size: 20,
          ),
        ],
      ),
    );
  }

  // ── STEP 2: PERMISSIONS ──────────────────────────────────────

  Widget _buildPermissionsPage(bool isDark) {
    final onGlass = isDark ? Colors.white : const Color(0xFF1E293B);
    final muted = isDark ? Colors.white70 : const Color(0xFF475569);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          _GradientText(
            'Permissions',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
              color: onGlass,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Grant access so Ultron-3 can see, hear, and act for you.',
            style: TextStyle(
              fontSize: 13.5,
              color: muted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              children: [
                _buildSectionHeader('MANDATORY', isDark),
                _buildPermissionCard(
                  title: 'Screen Control (Accessibility)',
                  description:
                      'Allows the AI to read your screen and automatically '
                      'perform clicks, scrolls, and typing to execute tasks '
                      'across other apps on your phone.',
                  icon: Icons.visibility_rounded,
                  gradient: const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  isGranted: _isAccessibilityGranted,
                  onGrant: _requestAccessibility,
                  isDark: isDark,
                ),
                const SizedBox(height: 12),
                _buildPermissionCard(
                  title: 'Microphone',
                  description:
                      'Required to listen to your voice commands and convert '
                      'speech to text.',
                  icon: Icons.mic_rounded,
                  gradient: const [Color(0xFFF43F5E), Color(0xFFFB7185)],
                  isGranted: _isMicrophoneGranted,
                  onGrant: () => _requestPermission(Permission.microphone),
                  isDark: isDark,
                ),
                if (FeatureFlags.floatingOverlayEnabled) ...[
                  const SizedBox(height: 12),
                  _buildPermissionCard(
                    title: 'Display Over Other Apps (Floating Bubble)',
                    description:
                        'Allows Ultron-3 to show a floating overlay bubble '
                        'when backgrounded or executing a task so you can '
                        'monitor progress and execute actions.',
                    icon: Icons.layers_rounded,
                    gradient: const [Color(0xFF06B6D4), Color(0xFF22D3EE)],
                    isGranted: _isOverlayGranted,
                    onGrant: _requestOverlayPermission,
                    isDark: isDark,
                  ),
                ],
                const SizedBox(height: 20),
                _buildSectionHeader('OPTIONAL', isDark),
                _buildPermissionCard(
                  title: 'Notifications',
                  description:
                      'Allows Ultron-3 to show ongoing tasks, alerts, and '
                      'execution updates in your notification tray.',
                  icon: Icons.notifications_rounded,
                  gradient: const [Color(0xFFF59E0B), Color(0xFFF97316)],
                  isGranted: _isNotificationsGranted,
                  onGrant: () => _requestPermission(Permission.notification),
                  isDark: isDark,
                ),
                const SizedBox(height: 12),
                _buildPermissionCard(
                  title: 'Contacts',
                  description:
                      'Used to look up phone numbers and contact names when '
                      'you ask the AI to call or text someone.',
                  icon: Icons.contacts_rounded,
                  gradient: const [Color(0xFF10B981), Color(0xFF34D399)],
                  isGranted: _isContactsGranted,
                  onGrant: () => _requestPermission(Permission.contacts),
                  isDark: isDark,
                ),
                const SizedBox(height: 12),
                _buildPermissionCard(
                  title: 'Phone',
                  description:
                      'Enables the AI to dial phone calls on your behalf when '
                      'requested.',
                  icon: Icons.phone_rounded,
                  gradient: const [Color(0xFF3B82F6), Color(0xFF60A5FA)],
                  isGranted: _isPhoneGranted,
                  onGrant: () => _requestPermission(Permission.phone),
                  isDark: isDark,
                ),
                const SizedBox(height: 12),
                _buildPermissionCard(
                  title: 'SMS',
                  description:
                      'Allows the AI to send and read text messages on your '
                      'behalf when requested.',
                  icon: Icons.sms_rounded,
                  gradient: const [Color(0xFF8B5CF6), Color(0xFFA78BFA)],
                  isGranted: _isSmsGranted,
                  onGrant: () => _requestPermission(Permission.sms),
                  isDark: isDark,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _backButton(
                onTap: () {
                  _pageController.previousPage(
                    duration: const Duration(milliseconds: 450),
                    curve: Curves.easeOutCubic,
                  );
                },
                isDark: isDark,
              ),
              const Spacer(),
              SizedBox(
                width: 150,
                child: _gradientButton(
                  label: 'Next',
                  icon: Icons.arrow_forward_rounded,
                  height: 52,
                  radius: 18,
                  onPressed: _canProceedToModel
                      ? () {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 450),
                            curve: Curves.easeOutCubic,
                          );
                        }
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    final muted = isDark ? Colors.white70 : const Color(0xFF475569);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4, left: 6),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Color(0xFF8B5CF6), Color(0xFF06B6D4)],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
              color: muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionCard({
    required String title,
    required String description,
    required IconData icon,
    required List<Color> gradient,
    required bool isGranted,
    required VoidCallback onGrant,
    required bool isDark,
  }) {
    final onGlass = isDark ? Colors.white : const Color(0xFF1E293B);
    final muted = isDark ? Colors.white70 : const Color(0xFF475569);

    return _GlassBox(
      radius: 24,
      padding: const EdgeInsets.all(16),
      blur: 26,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _GradientIcon(icon: icon, gradient: gradient, size: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: onGlass,
                  ),
                ),
              ),
              if (isGranted)
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutBack,
                  builder: (context, value, child) =>
                      Transform.scale(scale: value, child: child),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF10B981), Color(0xFF34D399)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF10B981).withOpacity(0.45),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                )
              else
                _PillButton(
                  label: 'Grant',
                  gradient: gradient,
                  onTap: onGrant,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: muted,
            ),
          ),
        ],
      ),
    );
  }

  // ── STEP 3: MODEL SETUP ──────────────────────────────────────

  Widget _buildModelSetupPage(bool isDark) {
    final onGlass = isDark ? Colors.white : const Color(0xFF1E293B);
    final muted = isDark ? Colors.white70 : const Color(0xFF475569);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          _GradientText(
            'AI Setup',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.6,
              color: onGlass,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Select a provider to prefill API details automatically.',
            style: TextStyle(
              fontSize: 13.5,
              color: muted,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),

          // Providers horizontal picker
          SizedBox(
            height: 104,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              children: [
                _buildProviderCard(
                  'deepseek',
                  'DeepSeek',
                  Icons.analytics_rounded,
                  const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  isDark,
                ),
                const SizedBox(width: 12),
                _buildProviderCard(
                  'groq',
                  'Groq',
                  Icons.speed_rounded,
                  const [Color(0xFFF59E0B), Color(0xFFF97316)],
                  isDark,
                ),
                const SizedBox(width: 12),
                _buildProviderCard(
                  'nvidia',
                  'NVIDIA',
                  Icons.memory_rounded,
                  const [Color(0xFF10B981), Color(0xFF34D399)],
                  isDark,
                ),
                const SizedBox(width: 12),
                _buildProviderCard(
                  'ollama',
                  'Ollama',
                  Icons.computer_rounded,
                  const [Color(0xFF06B6D4), Color(0xFF22D3EE)],
                  isDark,
                ),
                const SizedBox(width: 12),
                _buildProviderCard(
                  'local',
                  'Local Server',
                  Icons.dns_rounded,
                  const [Color(0xFF3B82F6), Color(0xFF60A5FA)],
                  isDark,
                ),
                const SizedBox(width: 12),
                _buildProviderCard(
                  'custom',
                  'Custom',
                  Icons.settings_suggest_rounded,
                  const [Color(0xFF8B5CF6), Color(0xFFA78BFA)],
                  isDark,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              children: [
                if (_selectedProvider != 'ollama' &&
                    _selectedProvider != 'local') ...[
                  _buildFormTextField(
                    controller: _apiKeyController,
                    label: 'API Key',
                    hint: 'sk-xxxxxxxxxxxx',
                    obscure: _obscureKey,
                    isDark: isDark,
                    suffix: IconButton(
                      icon: Icon(
                        _obscureKey
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        color: muted,
                      ),
                      onPressed: () =>
                          setState(() => _obscureKey = !_obscureKey),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                _buildFormTextField(
                  controller: _baseUrlController,
                  label: 'API Base URL',
                  hint: 'https://api.deepseek.com',
                  isDark: isDark,
                ),
                const SizedBox(height: 16),
                _buildFormTextField(
                  controller: _modelController,
                  label: 'Model Name',
                  hint: 'deepseek-chat',
                  isDark: isDark,
                  suffix: IconButton(
                    icon: _isValidating
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(muted),
                            ),
                          )
                        : Icon(Icons.sync_rounded, color: muted),
                    tooltip: 'Fetch models list',
                    onPressed: _isValidating ? null : _fetchModels,
                  ),
                ),

                if (_validationError != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF43F5E).withOpacity(
                        isDark ? 0.18 : 0.10,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFFF43F5E).withOpacity(0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Color(0xFFF43F5E),
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _validationError!,
                            style: const TextStyle(
                              color: Color(0xFFF43F5E),
                              fontSize: 12.5,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 32),
              ],
            ),
          ),

          const SizedBox(height: 8),
          Row(
            children: [
              _backButton(
                onTap: _isValidating
                    ? null
                    : () {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 450),
                          curve: Curves.easeOutCubic,
                        );
                      },
                isDark: isDark,
              ),
              const Spacer(),
              SizedBox(
                width: 190,
                child: _gradientButton(
                  label: 'Finish Setup',
                  icon: Icons.check_circle_outline_rounded,
                  height: 52,
                  radius: 18,
                  busy: _isValidating,
                  onPressed: _isValidating ? null : _testAndSave,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildProviderCard(
    String id,
    String label,
    IconData icon,
    List<Color> gradient,
    bool isDark,
  ) {
    final isSelected = _selectedProvider == id;
    final muted = isDark ? Colors.grey.shade300 : const Color(0xFF475569);

    return GestureDetector(
      onTap: () => _selectProvider(id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        width: 106,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: isSelected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradient,
                )
              : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: gradient.first.withOpacity(0.45),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(19),
            gradient: isDark
                ? LinearGradient(
                    colors: [
                      const Color(0xFF1E293B).withOpacity(0.92),
                      const Color(0xFF0F172A).withOpacity(0.9),
                    ],
                  )
                : LinearGradient(
                    colors: [
                      Colors.white.withOpacity(0.88),
                      Colors.white.withOpacity(0.62),
                    ],
                  ),
            border: Border.all(
              color: Colors.white.withOpacity(isDark ? 0.10 : 0.5),
              width: 1,
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      icon,
                      size: 26,
                      color: isSelected
                          ? Colors.white
                          : (isDark ? Colors.grey.shade300 : muted),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              isSelected ? FontWeight.w800 : FontWeight.w600,
                          color: isSelected
                              ? Colors.white
                              : (isDark ? Colors.grey.shade300 : muted),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: 14,
                      color: gradient.first,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool obscure = false,
    Widget? suffix,
    required bool isDark,
  }) {
    final onGlass = isDark ? Colors.white : const Color(0xFF1E293B);
    final muted = isDark ? Colors.white70 : const Color(0xFF475569);

    return _GlassBox(
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      blur: 24,
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: TextStyle(fontSize: 14, color: onGlass),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            fontSize: 12.5,
            color: muted.withOpacity(0.85),
          ),
          floatingLabelStyle: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isDark ? const Color(0xFFA5B4FC) : const Color(0xFF4F46E5),
          ),
          hintText: hint,
          hintStyle: TextStyle(
            fontSize: 13,
            color: muted.withOpacity(0.55),
          ),
          border: InputBorder.none,
          suffixIcon: suffix,
        ),
      ),
    );
  }

  // ── Shared UI primitives ─────────────────────────────────────

  Widget _backButton({
    required VoidCallback? onTap,
    required bool isDark,
  }) {
    final onGlass = isDark ? Colors.white : const Color(0xFF1E293B);
    return GestureDetector(
      onTap: onTap,
      child: _GlassBox(
        radius: 16,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        blur: 22,
        strong: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chevron_left_rounded, color: onGlass, size: 20),
            const SizedBox(width: 4),
            Text(
              'Back',
              style: TextStyle(
                color: onGlass,
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gradientButton({
    required VoidCallback? onPressed,
    required String label,
    IconData? icon,
    bool busy = false,
    double height = 56,
    double radius = 18,
  }) {
    final enabled = onPressed != null && !busy;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: _primaryGradient,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withOpacity(0.45),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(radius),
            onTap: enabled ? onPressed : null,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Glass shine on top half of the button
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(radius),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withOpacity(0.32),
                            Colors.white.withOpacity(0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                              letterSpacing: 0.2,
                            ),
                          ),
                          if (icon != null) ...[
                            const SizedBox(width: 10),
                            Icon(icon, color: Colors.white, size: 19),
                          ],
                        ],
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────
// Reusable liquid-glass primitives
// ───────────────────────────────────────────────────────────────

class _GlassBox extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double blur;
  final bool strong;

  const _GlassBox({
    required this.child,
    this.radius = 26,
    this.padding = const EdgeInsets.all(20),
    this.blur = 28,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bRadius = BorderRadius.circular(radius);

    return Container(
      decoration: BoxDecoration(
        borderRadius: bRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.28 : 0.10),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: bRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        Colors.white.withOpacity(strong ? 0.14 : 0.08),
                        Colors.white.withOpacity(0.03),
                      ]
                    : [
                        Colors.white.withOpacity(strong ? 0.62 : 0.40),
                        Colors.white.withOpacity(0.14),
                      ],
              ),
              borderRadius: bRadius,
              border: Border.all(
                color: Colors.white.withOpacity(isDark ? 0.10 : 0.55),
                width: 1,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _GradientText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Gradient gradient;

  const _GradientText(
    this.text, {
    required this.style,
    Gradient? gradient,
  }) : gradient =
            gradient ??
            const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: _primaryGradient,
            );

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => gradient.createShader(bounds),
      child: Text(
        text,
        style: style.copyWith(color: Colors.white),
      ),
    );
  }
}

class _GradientIcon extends StatelessWidget {
  final IconData icon;
  final List<Color> gradient;
  final double size;

  const _GradientIcon({
    required this.icon,
    required this.gradient,
    this.size = 20,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size + 16,
      height: size + 16,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        boxShadow: [
          BoxShadow(
            color: gradient.first.withOpacity(0.4),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: size),
    );
  }
}

class _PillButton extends StatelessWidget {
  final String label;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _PillButton({
    required this.label,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient,
          ),
          boxShadow: [
            BoxShadow(
              color: gradient.first.withOpacity(0.4),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}
