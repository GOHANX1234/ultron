import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'dart:ui';
import 'dart:math' as math;
import '../config/feature_flags.dart';
import '../services/ai_service.dart';
import '../services/screen_automation_service.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final PageController _pageController = PageController();
  final ScreenAutomationService _screenAutomationService =
      ScreenAutomationService();
  final AiService _aiService = AiService();

  late AnimationController _liquidAnimationController;
  late Animation<double> _liquidAnimation;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _liquidAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat(reverse: true);

    _liquidAnimation = CurvedAnimation(
      parent: _liquidAnimationController,
      curve: Curves.easeInOutSine,
    );

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
    _liquidAnimationController.dispose();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: LiquidGlassContainer(
          borderRadius: 24,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF6366F1).withOpacity(0.25),
                      const Color(0xFF0EA5E9).withOpacity(0.15),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.accessibility_new_rounded,
                  size: 32,
                  color: Color(0xFF6366F1),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Enable Screen Automation',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Android Security Note:\nIf Android displays "Restricted setting", open App Info first, tap the top-right menu, select "Allow restricted settings", then enable PrivateAgent Screen Control.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        openAppSettings();
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        side: BorderSide(
                          color: isDark
                              ? Colors.white.withOpacity(0.2)
                              : Colors.black.withOpacity(0.15),
                        ),
                      ),
                      child: Text(
                        '1. App Info',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : const Color(0xFF1E293B),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        _screenAutomationService.openAccessibilitySettings();
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: const Color(0xFF6366F1),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        '2. Settings',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
        _validationError = 'Please specify the API Base URL and Model Name.';
        _isValidating = false;
      });
      return;
    }

    if (_selectedProvider != 'ollama' &&
        _selectedProvider != 'local' &&
        apiKey.isEmpty) {
      setState(() {
        _validationError = 'API Key is required for cloud AI providers.';
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
              content: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.white),
                  SizedBox(width: 12),
                  Text(
                    'Configuration Verified! Launching PrivateAgent...',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
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
              'Could not connect to AI endpoint. Please verify endpoint URL & key.';
          _isValidating = false;
        });
      }
    } catch (e) {
      setState(() {
        _validationError =
            'Connection Error: ${e.toString().replaceFirst('Exception: ', '')}';
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
              content: const Text('No models retrieved. Verify URL & Key.'),
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
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (context) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.6,
              padding: const EdgeInsets.only(top: 8),
              child: LiquidGlassContainer(
                borderRadius: 24,
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withOpacity(0.2)
                              : Colors.black.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(
                          Icons.dns_rounded,
                          color: Theme.of(context).primaryColor,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          AiService.isNvidiaBaseUrl(baseUrl)
                              ? 'Select Free NVIDIA Model'
                              : 'Select AI Model',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        itemCount: models.length,
                        separatorBuilder: (_, __) => Divider(
                          color: isDark
                              ? Colors.white.withOpacity(0.08)
                              : Colors.black.withOpacity(0.05),
                          height: 1,
                        ),
                        itemBuilder: (context, index) {
                          final modelName = models[index];
                          final isCurrent =
                              _modelController.text == modelName;

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 2,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            tileColor: isCurrent
                                ? Theme.of(
                                    context,
                                  ).primaryColor.withOpacity(0.12)
                                : Colors.transparent,
                            title: Text(
                              modelName,
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: isCurrent
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                                color: isCurrent
                                    ? Theme.of(context).primaryColor
                                    : (isDark
                                          ? Colors.white70
                                          : Colors.black87),
                              ),
                            ),
                            trailing: isCurrent
                                ? Icon(
                                    Icons.check_circle_rounded,
                                    color: Theme.of(context).primaryColor,
                                    size: 18,
                                  )
                                : const Icon(
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

  int get _grantedCount {
    int count = 0;
    if (_isAccessibilityGranted) count++;
    if (_isMicrophoneGranted) count++;
    if (_isOverlayGranted && FeatureFlags.floatingOverlayEnabled) count++;
    if (_isNotificationsGranted) count++;
    if (_isContactsGranted) count++;
    if (_isPhoneGranted) count++;
    if (_isSmsGranted) count++;
    return count;
  }

  int get _totalCount {
    return FeatureFlags.floatingOverlayEnabled ? 7 : 6;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF090D16)
          : const Color(0xFFF1F5F9),
      body: Stack(
        children: [
          // Dynamic Soft Ambient Liquid Background
          AnimatedBuilder(
            animation: _liquidAnimation,
            builder: (context, child) {
              final value = _liquidAnimation.value;
              return _buildLiquidBackgroundGlows(isDark, value);
            },
          ),

          // Master Backdrop Blur Layer for Glass Diffusion
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Container(color: Colors.transparent),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // Top Navigation & Step Indicator Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: _buildLiquidHeader(isDark),
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

  Widget _buildLiquidBackgroundGlows(bool isDark, double animValue) {
    final shiftX = math.sin(animValue * math.pi * 2) * 35;
    final shiftY = math.cos(animValue * math.pi * 2) * 35;

    return Positioned.fill(
      child: Stack(
        children: [
          // Indigo Orb Top Right
          Positioned(
            top: -50 + shiftY,
            right: -50 + shiftX,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    isDark
                        ? const Color(0xFF6366F1).withOpacity(0.30)
                        : const Color(0xFF818CF8).withOpacity(0.20),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // Cyan Orb Bottom Left
          Positioned(
            bottom: -70 - shiftY,
            left: -70 - shiftX,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    isDark
                        ? const Color(0xFF0EA5E9).withOpacity(0.25)
                        : const Color(0xFF38BDF8).withOpacity(0.18),
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

  Widget _buildLiquidHeader(bool isDark) {
    return LiquidGlassContainer(
      borderRadius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [
                          const Color(0xFF6366F1).withOpacity(0.8),
                          const Color(0xFF0EA5E9).withOpacity(0.8),
                        ],
                      ),
                    ),
                    child: const Icon(
                      Icons.bubble_chart_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PRIVATE AGENT',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        'Setup Guide',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // Step Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: isDark
                      ? Colors.white.withOpacity(0.08)
                      : Colors.black.withOpacity(0.05),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.12)
                        : Colors.black.withOpacity(0.06),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'STEP ${_currentStep + 1} OF 3',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: isDark ? Colors.white70 : const Color(0xFF334155),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Progress Bar
          Stack(
            children: [
              Container(
                height: 5,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: isDark
                      ? Colors.white.withOpacity(0.08)
                      : Colors.black.withOpacity(0.06),
                ),
              ),
              AnimatedFractionallySizedBox(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
                widthFactor: (_currentStep + 1) / 3.0,
                child: Container(
                  height: 5,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6366F1), Color(0xFF0EA5E9)],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStepTitle(0, 'Overview'),
              _buildStepTitle(1, 'Permissions'),
              _buildStepTitle(2, 'AI Setup'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepTitle(int stepIndex, String title) {
    final isActive = _currentStep == stepIndex;
    final isDone = _currentStep > stepIndex;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        if (isDone)
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: Icon(
              Icons.check_circle_rounded,
              size: 12,
              color: Color(0xFF10B981),
            ),
          ),
        Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isActive || isDone ? FontWeight.bold : FontWeight.w500,
            color: isActive
                ? (isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5))
                : isDone
                ? const Color(0xFF10B981)
                : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
          ),
        ),
      ],
    );
  }

  // --- STEP 1: WELCOME & OVERVIEW ---
  Widget _buildWelcomePage(bool isDark) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        children: [
          const SizedBox(height: 10),
          // Liquid Orb Visual
          Center(
            child: SizedBox(
              width: 150,
              height: 150,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _liquidAnimation,
                    builder: (context, child) {
                      return Transform.rotate(
                        angle: _liquidAnimation.value * math.pi * 2,
                        child: Container(
                          width: 145,
                          height: 145,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF6366F1).withOpacity(0.25),
                              width: 1.5,
                            ),
                          ),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF38BDF8),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  LiquidGlassContainer(
                    borderRadius: 100,
                    padding: const EdgeInsets.all(24),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [Color(0xFF6366F1), Color(0xFF0EA5E9)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: const Icon(
                        Icons.psychology_rounded,
                        size: 38,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: isDark
                  ? const Color(0xFF6366F1).withOpacity(0.12)
                  : const Color(0xFF4F46E5).withOpacity(0.08),
              border: Border.all(
                color: const Color(0xFF6366F1).withOpacity(0.25),
              ),
            ),
            child: const Text(
              '✦ PRIVATE LOCAL AI ASSISTANT',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: Color(0xFF6366F1),
              ),
            ),
          ),
          const SizedBox(height: 12),

          Text(
            'Personal Phone Automation',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),

          Text(
            'PrivateAgent enables hands-free voice control, smart screen action execution, and local privacy for your daily phone tasks.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 20),

          // Capabilities Cards Grid
          Row(
            children: [
              Expanded(
                child: _buildCapabilityCard(
                  icon: Icons.shield_outlined,
                  title: 'On-Device Privacy',
                  desc: 'Secure key storage with zero telemetry data sharing.',
                  color: const Color(0xFF10B981),
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCapabilityCard(
                  icon: Icons.touch_app_rounded,
                  title: 'Screen Automation',
                  desc: 'Navigates apps & completes actions on screen.',
                  color: const Color(0xFF38BDF8),
                  isDark: isDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildCapabilityCard(
                  icon: Icons.hub_rounded,
                  title: 'Multi-LLM Engine',
                  desc: 'Connect DeepSeek, Groq, NVIDIA or local Ollama.',
                  color: const Color(0xFF8B5CF6),
                  isDark: isDark,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCapabilityCard(
                  icon: Icons.picture_in_picture_alt_rounded,
                  title: 'Floating HUD',
                  desc: 'Background status overlay for instant control.',
                  color: const Color(0xFFF59E0B),
                  isDark: isDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Next Button
          LiquidGlassButton(
            onPressed: () {
              _pageController.nextPage(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOutCubic,
              );
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Continue to Permissions',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward_rounded, size: 18),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildCapabilityCard({
    required IconData icon,
    required String title,
    required String desc,
    required Color color,
    required bool isDark,
  }) {
    return LiquidGlassContainer(
      borderRadius: 18,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.12),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            desc,
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }

  // --- STEP 2: PERMISSIONS ---
  Widget _buildPermissionsPage(bool isDark) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: LiquidGlassContainer(
            borderRadius: 18,
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF10B981).withOpacity(0.15),
                  ),
                  child: const Icon(
                    Icons.verified_user_rounded,
                    color: Color(0xFF10B981),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Permissions & Access',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                      ),
                      Text(
                        '$_grantedCount of $_totalCount Active',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark
                              ? const Color(0xFF94A3B8)
                              : const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: _canProceedToModel
                        ? const Color(0xFF10B981).withOpacity(0.12)
                        : Colors.amber.withOpacity(0.12),
                    border: Border.all(
                      color: _canProceedToModel
                          ? const Color(0xFF10B981)
                          : Colors.amber,
                    ),
                  ),
                  child: Text(
                    _canProceedToModel ? 'READY' : 'ACTION NEEDED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: _canProceedToModel
                          ? const Color(0xFF10B981)
                          : Colors.amber[800],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        Expanded(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            children: [
              _buildCategoryHeader('Core Permissions (Required)', isDark),
              _buildPermissionGlassCard(
                title: 'Screen Automation (Accessibility)',
                subtitle:
                    'Allows the agent to view screen elements and automate taps/scrolls.',
                icon: Icons.accessibility_new_rounded,
                isGranted: _isAccessibilityGranted,
                isRequired: true,
                onGrant: _requestAccessibility,
                isDark: isDark,
              ),
              _buildPermissionGlassCard(
                title: 'Microphone Access',
                subtitle:
                    'Captures voice commands for speech interaction.',
                icon: Icons.mic_rounded,
                isGranted: _isMicrophoneGranted,
                isRequired: true,
                onGrant: () => _requestPermission(Permission.microphone),
                isDark: isDark,
              ),
              if (FeatureFlags.floatingOverlayEnabled)
                _buildPermissionGlassCard(
                  title: 'Floating Overlay Window',
                  subtitle:
                      'Displays the HUD bubble over other apps.',
                  icon: Icons.layers_rounded,
                  isGranted: _isOverlayGranted,
                  isRequired: true,
                  onGrant: _requestOverlayPermission,
                  isDark: isDark,
                ),

              const SizedBox(height: 8),
              _buildCategoryHeader('Optional Permissions', isDark),
              _buildPermissionGlassCard(
                title: 'System Notifications',
                subtitle:
                    'Displays status notifications and task summaries.',
                icon: Icons.notifications_rounded,
                isGranted: _isNotificationsGranted,
                isRequired: false,
                onGrant: () => _requestPermission(Permission.notification),
                isDark: isDark,
              ),
              _buildPermissionGlassCard(
                title: 'Contacts Access',
                subtitle:
                    'Used to find contacts when placing calls or sending messages.',
                icon: Icons.contacts_rounded,
                isGranted: _isContactsGranted,
                isRequired: false,
                onGrant: () => _requestPermission(Permission.contacts),
                isDark: isDark,
              ),
              _buildPermissionGlassCard(
                title: 'Phone Calls',
                subtitle:
                    'Allows initiating calls directly via voice command.',
                icon: Icons.phone_rounded,
                isGranted: _isPhoneGranted,
                isRequired: false,
                onGrant: () => _requestPermission(Permission.phone),
                isDark: isDark,
              ),
              _buildPermissionGlassCard(
                title: 'SMS Messaging',
                subtitle:
                    'Allows sending text messages on your request.',
                icon: Icons.sms_rounded,
                isGranted: _isSmsGranted,
                isRequired: false,
                onGrant: () => _requestPermission(Permission.sms),
                isDark: isDark,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),

        // Navigation Bar
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: () {
                  _pageController.previousPage(
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                  );
                },
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Back'),
                style: TextButton.styleFrom(
                  foregroundColor: isDark ? Colors.white70 : const Color(0xFF475569),
                ),
              ),
              const Spacer(),
              Expanded(
                flex: 2,
                child: LiquidGlassButton(
                  onPressed: _canProceedToModel
                      ? () {
                          _pageController.nextPage(
                            duration: const Duration(milliseconds: 400),
                            curve: Curves.easeOutCubic,
                          );
                        }
                      : null,
                  disabled: !_canProceedToModel,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Continue',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
        ),
      ),
    );
  }

  Widget _buildPermissionGlassCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isGranted,
    required bool isRequired,
    required VoidCallback onGrant,
    required bool isDark,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: LiquidGlassContainer(
        borderRadius: 18,
        padding: const EdgeInsets.all(14),
        borderColor: isGranted
            ? const Color(0xFF10B981).withOpacity(0.3)
            : (isRequired
                ? const Color(0xFF6366F1).withOpacity(0.2)
                : Colors.transparent),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isGranted
                    ? const Color(0xFF10B981).withOpacity(0.12)
                    : const Color(0xFF6366F1).withOpacity(0.10),
              ),
              child: Icon(
                icon,
                size: 20,
                color: isGranted
                    ? const Color(0xFF10B981)
                    : const Color(0xFF6366F1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.bold,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                      ),
                      if (isRequired && !isGranted)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            color: Colors.indigo.withOpacity(0.15),
                          ),
                          child: const Text(
                            'REQUIRED',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF6366F1),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: isGranted
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              color: const Color(0xFF10B981).withOpacity(0.12),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle_rounded,
                                  size: 13,
                                  color: Color(0xFF10B981),
                                ),
                                SizedBox(width: 5),
                                Text(
                                  'Granted',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF10B981),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ElevatedButton(
                            onPressed: onGrant,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text(
                              'Enable',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- STEP 3: MODEL SETUP ---
  Widget _buildModelSetupPage(bool isDark) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            children: [
              Text(
                'Choose AI Provider',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Select a cloud AI service or connect to a local server.',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 12),

              // Provider Chips Horizontal Scroll
              SizedBox(
                height: 76,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _buildProviderGlassChip(
                      'deepseek',
                      'DeepSeek',
                      Icons.auto_awesome_rounded,
                      isDark,
                    ),
                    const SizedBox(width: 8),
                    _buildProviderGlassChip(
                      'groq',
                      'Groq',
                      Icons.bolt_rounded,
                      isDark,
                    ),
                    const SizedBox(width: 8),
                    _buildProviderGlassChip(
                      'nvidia',
                      'NVIDIA AI',
                      Icons.memory_rounded,
                      isDark,
                    ),
                    const SizedBox(width: 8),
                    _buildProviderGlassChip(
                      'ollama',
                      'Ollama',
                      Icons.computer_rounded,
                      isDark,
                    ),
                    const SizedBox(width: 8),
                    _buildProviderGlassChip(
                      'local',
                      'Local Server',
                      Icons.dns_rounded,
                      isDark,
                    ),
                    const SizedBox(width: 8),
                    _buildProviderGlassChip(
                      'custom',
                      'Custom API',
                      Icons.tune_rounded,
                      isDark,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Form Glass Container
              LiquidGlassContainer(
                borderRadius: 20,
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_selectedProvider != 'ollama' &&
                        _selectedProvider != 'local') ...[
                      _buildGlassTextField(
                        controller: _apiKeyController,
                        label: 'API Key',
                        hint: 'sk-xxxxxxxxxxxxxxxxxxxxxxxx',
                        obscure: _obscureKey,
                        icon: Icons.key_rounded,
                        isDark: isDark,
                        suffix: IconButton(
                          icon: Icon(
                            _obscureKey
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                            size: 18,
                          ),
                          onPressed: () =>
                              setState(() => _obscureKey = !_obscureKey),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    _buildGlassTextField(
                      controller: _baseUrlController,
                      label: 'API Base URL',
                      hint: 'https://api.deepseek.com',
                      icon: Icons.link_rounded,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 14),
                    _buildGlassTextField(
                      controller: _modelController,
                      label: 'Model Name',
                      hint: 'deepseek-chat',
                      icon: Icons.psychology_alt_rounded,
                      isDark: isDark,
                      suffix: IconButton(
                        icon: _isValidating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Color(0xFF6366F1),
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.format_list_bulleted_rounded,
                                color: Color(0xFF6366F1),
                                size: 18,
                              ),
                        tooltip: 'Fetch Available Models',
                        onPressed: _isValidating ? null : _fetchModels,
                      ),
                    ),
                    if (_validationError != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.redAccent.withOpacity(0.25),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: Colors.redAccent,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _validationError!,
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 12,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),

        // Bottom Finish Button
        Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: _isValidating
                    ? null
                    : () {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOutCubic,
                        );
                      },
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Back'),
                style: TextButton.styleFrom(
                  foregroundColor: isDark ? Colors.white70 : const Color(0xFF475569),
                ),
              ),
              const Spacer(),
              Expanded(
                flex: 2,
                child: LiquidGlassButton(
                  onPressed: _isValidating ? null : _testAndSave,
                  child: _isValidating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Save & Launch',
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward_rounded, size: 18),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProviderGlassChip(
    String id,
    String label,
    IconData icon,
    bool isDark,
  ) {
    final isSelected = _selectedProvider == id;

    return GestureDetector(
      onTap: () => _selectProvider(id),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 90,
        child: LiquidGlassContainer(
          borderRadius: 16,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          borderColor: isSelected
              ? const Color(0xFF6366F1)
              : (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06)),
          gradient: isSelected
              ? LinearGradient(
                  colors: [
                    const Color(0xFF6366F1).withOpacity(0.25),
                    const Color(0xFF0EA5E9).withOpacity(0.15),
                  ],
                )
              : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected
                    ? const Color(0xFF6366F1)
                    : (isDark ? Colors.white70 : const Color(0xFF64748B)),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected
                      ? (isDark ? Colors.white : const Color(0xFF4F46E5))
                      : (isDark ? Colors.white54 : const Color(0xFF64748B)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    required bool isDark,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: isDark
                ? Colors.black.withOpacity(0.2)
                : Colors.white.withOpacity(0.6),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.1)
                  : Colors.black.withOpacity(0.06),
            ),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscure,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
            decoration: InputDecoration(
              prefixIcon: Icon(
                icon,
                size: 18,
                color: isDark ? Colors.white54 : const Color(0xFF64748B),
              ),
              hintText: hint,
              hintStyle: TextStyle(
                fontSize: 12.5,
                color: isDark ? Colors.white30 : Colors.black38,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: InputBorder.none,
              suffixIcon: suffix,
            ),
          ),
        ),
      ],
    );
  }
}

// Custom Liquid Glass Container Widget
class LiquidGlassContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final Gradient? gradient;

  const LiquidGlassContainer({
    super.key,
    required this.child,
    this.borderRadius = 20.0,
    this.padding = const EdgeInsets.all(16.0),
    this.borderColor,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final defaultGradient = gradient ??
        LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [
                  Colors.white.withOpacity(0.08),
                  Colors.white.withOpacity(0.03),
                ]
              : [
                  Colors.white.withOpacity(0.85),
                  Colors.white.withOpacity(0.60),
                ],
        );

    final borderGrad = borderColor != null
        ? Border.all(color: borderColor!, width: 1.0)
        : Border.all(
            color: isDark
                ? Colors.white.withOpacity(0.15)
                : Colors.white.withOpacity(0.60),
            width: 1.0,
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            gradient: defaultGradient,
            border: borderGrad,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.25 : 0.04),
                blurRadius: 16,
                spreadRadius: -2,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

// Liquid Glass Button Widget
class LiquidGlassButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final bool disabled;

  const LiquidGlassButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (disabled || onPressed == null) {
      return Container(
        width: double.infinity,
        height: 50,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : Colors.black.withOpacity(0.05),
        ),
        child: Center(
          child: DefaultTextStyle(
            style: TextStyle(
              color: isDark ? Colors.white30 : Colors.black38,
              fontWeight: FontWeight.bold,
            ),
            child: child,
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF0EA5E9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withOpacity(0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: child,
      ),
    );
  }
}
