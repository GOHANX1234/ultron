import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import '../services/ai_service.dart';
import '../services/shizuku_service.dart';
import '../services/screen_automation_service.dart';
import '../services/telegram_service.dart';
import 'task_history_screen.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import '../config/feature_flags.dart';

class SettingsScreen extends StatefulWidget {
  final AiService aiService;
  final ShizukuService shizukuService;
  final ScreenAutomationService screenAutomationService;
  final TelegramService telegramService;

  const SettingsScreen({
    super.key,
    required this.aiService,
    required this.shizukuService,
    required this.screenAutomationService,
    required this.telegramService,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  late TextEditingController _apiKeyController;
  late TextEditingController _baseUrlController;
  late TextEditingController _modelController;
  late TextEditingController _telegramTokenController;
  bool _obscureKey = true;
  bool _telegramEnabled = false;
  double _maxSteps = 15;
  bool _disableMaxSteps = false;
  late TextEditingController _maxTokensController;
  double _temperature = 1.0;
  bool _useScreenCompression = true;
  bool _useSystemPrompt = true;
  bool _floatingIconEnabled = false;
  bool _isOverlayPermissionGranted = false;

  final Map<String, PermissionStatus> _permissions = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _apiKeyController = TextEditingController(text: widget.aiService.apiKey);
    _baseUrlController = TextEditingController(text: widget.aiService.baseUrl);
    _modelController = TextEditingController(text: widget.aiService.model);
    _telegramTokenController = TextEditingController(
      text: widget.telegramService.botToken,
    );
    _telegramEnabled = widget.telegramService.isEnabled;
    _maxSteps = widget.aiService.rawMaxSteps.toDouble();
    _disableMaxSteps = widget.aiService.disableMaxSteps;
    _temperature = widget.aiService.temperature;
    _maxTokensController = TextEditingController(
      text: widget.aiService.maxTokens.toString(),
    );
    _useScreenCompression = widget.aiService.useScreenCompression;
    _useSystemPrompt = widget.aiService.useSystemPrompt;

    // Auto-save listeners
    _apiKeyController.addListener(_autoSave);
    _baseUrlController.addListener(_autoSave);
    _modelController.addListener(_autoSave);
    _telegramTokenController.addListener(_autoSave);
    _maxTokensController.addListener(_autoSave);

    _checkPermissions();
    if (FeatureFlags.floatingOverlayEnabled) {
      _checkOverlayStatus();
    }
  }

  Future<void> _checkOverlayStatus() async {
    bool isActive = await FlutterOverlayWindow.isActive();
    bool isGranted = await FlutterOverlayWindow.isPermissionGranted();
    if (mounted) {
      setState(() {
        _floatingIconEnabled = isActive;
        _isOverlayPermissionGranted = isGranted;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _apiKeyController.removeListener(_autoSave);
    _baseUrlController.removeListener(_autoSave);
    _modelController.removeListener(_autoSave);
    _telegramTokenController.removeListener(_autoSave);
    _maxTokensController.removeListener(_autoSave);
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    _telegramTokenController.dispose();
    _maxTokensController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions();
      if (FeatureFlags.floatingOverlayEnabled) {
        _checkOverlayStatus();
      }
    }
  }

  Future<void> _checkPermissions() async {
    final perms = {
      'Microphone': Permission.microphone,
      'Contacts': Permission.contacts,
      'Phone': Permission.phone,
      'SMS': Permission.sms,
      'Notifications': Permission.notification,
    };

    for (final entry in perms.entries) {
      _permissions[entry.key] = await entry.value.status;
    }
    final overlayGranted = FeatureFlags.floatingOverlayEnabled
        ? await FlutterOverlayWindow.isPermissionGranted()
        : false;
    if (mounted) {
      setState(() {
        _isOverlayPermissionGranted = overlayGranted;
      });
    }
  }

  Future<void> _requestPermission(String name, Permission permission) async {
    final status = await permission.request();
    setState(() => _permissions[name] = status);
  }

  void _autoSave() {
    widget.aiService.saveSettings(
      apiKey: _apiKeyController.text.trim(),
      baseUrl: _baseUrlController.text.trim(),
      model: _modelController.text.trim(),
    );

    widget.telegramService.saveSettings(
      botToken: _telegramTokenController.text.trim(),
      isEnabled: _telegramEnabled,
    );

    widget.aiService.saveMaxSteps(_maxSteps.toInt());
    widget.aiService.saveDisableMaxSteps(_disableMaxSteps);
    widget.aiService.saveAdvancedSettings(
      temperature: _temperature,
      maxTokens: int.tryParse(_maxTokensController.text) ?? 1024,
      useScreenCompression: _useScreenCompression,
      useSystemPrompt: _useSystemPrompt,
    );
  }

  Future<void> _fetchModels() async {
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();

    if (baseUrl.isEmpty || apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter Base URL and API Key first.'),
        ),
      );
      return;
    }

    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final models = await widget.aiService.fetchAvailableModels(baseUrl, apiKey);

    // Hide loading
    if (mounted) Navigator.pop(context);

    if (models.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No models found or error fetching models.'),
          ),
        );
      }
      return;
    }

    if (mounted) {
      final isNvidia = AiService.isNvidiaBaseUrl(baseUrl);
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            isNvidia ? 'Select a Free NVIDIA Model' : 'Select a Model',
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              itemCount: models.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Text(models[index]),
                  onTap: () {
                    setState(() {
                      _modelController.text = models[index];
                    });
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
    }
  }


  Widget _buildSettingsCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required List<Widget> children,
    required bool isDark,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.4),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.7),
                  isDark ? Colors.white.withValues(alpha: 0.02) : Colors.white.withValues(alpha: 0.3),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).primaryColor,
                            Theme.of(context).primaryColor.withValues(alpha: 0.7),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).primaryColor.withValues(alpha: 0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        icon,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                            ),
                          ),
                          if (subtitle != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.6)
                                    : Colors.black.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration({
    required String labelText,
    required String hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.5),
      labelStyle: TextStyle(
        color: isDark ? Colors.white.withValues(alpha: 0.7) : Colors.black.withValues(alpha: 0.6),
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      hintStyle: TextStyle(
        color: isDark ? Colors.white.withValues(alpha: 0.4) : Colors.black.withValues(alpha: 0.4),
        fontSize: 14,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
          width: 1.5,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
          width: 1.5,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: Theme.of(context).colorScheme.primary,
          width: 2,
        ),
      ),
      floatingLabelBehavior: FloatingLabelBehavior.auto,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              color: isDark ? Colors.black.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.2),
            ),
          ),
        ),
        title: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
          ),
          child: const Text(
            'Settings',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Ambient Glow Background
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).primaryColor.withValues(alpha: 0.2),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            right: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.purple.withValues(alpha: 0.2),
              ),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Container(
                color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.8) : const Color(0xFFF8FAFC).withValues(alpha: 0.8),
              ),
            ),
          ),
          ListView(
            padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + kToolbarHeight + 20, 20, 40),
            physics: const BouncingScrollPhysics(),
            children: [
              // 1. Appearance Card
              _buildSettingsCard(
                icon: Icons.palette_rounded,
                title: 'Appearance',
                subtitle: 'Choose your preferred color theme',
                isDark: isDark,
                children: [
                  ValueListenableBuilder<ThemeMode>(
                    valueListenable: themeNotifier,
                    builder: (context, currentMode, _) {
                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: isDark ? Colors.black.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.02),
                          border: Border.all(
                            color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
                          ),
                        ),
                        child: SegmentedButton<ThemeMode>(
                          style: SegmentedButton.styleFrom(
                            selectedBackgroundColor: Theme.of(context).colorScheme.primary,
                            selectedForegroundColor: Colors.white,
                            backgroundColor: Colors.transparent,
                            foregroundColor: isDark ? Colors.white : Colors.black87,
                            side: BorderSide.none,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                          segments: const [
                            ButtonSegment(
                              value: ThemeMode.system,
                              label: Text('System', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              icon: Icon(Icons.brightness_auto_rounded, size: 18),
                            ),
                            ButtonSegment(
                              value: ThemeMode.light,
                              label: Text('Light', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              icon: Icon(Icons.light_mode_rounded, size: 18),
                            ),
                            ButtonSegment(
                              value: ThemeMode.dark,
                              label: Text('Dark', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              icon: Icon(Icons.dark_mode_rounded, size: 18),
                            ),
                          ],
                          selected: {currentMode},
                          onSelectionChanged: (Set<ThemeMode> newSelection) async {
                            final mode = newSelection.first;
                            themeNotifier.value = mode;
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setString('themeMode', mode.name);
                          },
                        ),
                      );
                    },
                  ),
                ],
              ),

              // 2. AI Engine Config Card
              _buildSettingsCard(
                icon: Icons.psychology_rounded,
                title: 'AI Engine Configuration',
                subtitle: 'Supports any OpenAI-compatible API endpoint',
                isDark: isDark,
                children: [
                  TextField(
                    controller: _apiKeyController,
                    decoration: _buildInputDecoration(
                      labelText: 'API Key',
                      hintText: 'sk-...',
                      prefixIcon: const Icon(Icons.key_rounded, size: 20),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscureKey ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                          size: 20,
                        ),
                        onPressed: () => setState(() => _obscureKey = !_obscureKey),
                      ),
                    ),
                    obscureText: _obscureKey,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _baseUrlController,
                    decoration: _buildInputDecoration(
                      labelText: 'API Base URL',
                      hintText: 'https://api.deepseek.com',
                      prefixIcon: const Icon(Icons.dns_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildGlassChip('Local Server', Icons.computer_rounded, () => _baseUrlController.text = 'http://192.168.1.X:8080/v1', isDark, tooltip: 'For local Llama.cpp or LM Studio'),
                      _buildGlassChip('Ollama Cloud', Icons.cloud_rounded, () {
                        _baseUrlController.text = 'https://ollama.com/v1';
                        _modelController.text = 'gemma3:4b';
                      }, isDark),
                      _buildGlassChip('DeepSeek', Icons.search_rounded, () => _baseUrlController.text = 'https://api.deepseek.com', isDark),
                      _buildGlassChip('Groq', Icons.bolt_rounded, () => _baseUrlController.text = 'https://api.groq.com/openai/v1', isDark),
                      _buildGlassChip('NVIDIA', Icons.memory_rounded, () {
                        _baseUrlController.text = AiService.nvidiaBaseUrl;
                        _modelController.text = AiService.nvidiaDefaultModel;
                      }, isDark, tooltip: 'NVIDIA NIM free endpoints'),
                      _buildGlassChip('Custom', Icons.edit_rounded, () {
                        _baseUrlController.clear();
                        _apiKeyController.clear();
                        _modelController.clear();
                      }, isDark, tooltip: 'Clear fields'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _modelController,
                          decoration: _buildInputDecoration(
                            labelText: 'Model',
                            hintText: 'deepseek-chat',
                            prefixIcon: const Icon(Icons.smart_toy_rounded, size: 20),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        height: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            colors: [
                              Theme.of(context).primaryColor,
                              Theme.of(context).primaryColor.withValues(alpha: 0.8),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(context).primaryColor.withValues(alpha: 0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          onPressed: _fetchModels,
                          icon: const Icon(Icons.cloud_download_rounded, size: 20, color: Colors.white),
                          label: const Text(
                            'Fetch',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              // 3. Parameters & Tuning Card
              _buildSettingsCard(
                icon: Icons.tune_rounded,
                title: 'Tuning & Boundaries',
                subtitle: 'Configure LLM agent parameters',
                isDark: isDark,
                children: [
                  _buildGlassSwitch(
                    title: 'Disable Maximum Steps',
                    subtitle: '⚠️ Can cause infinite loops.',
                    value: _disableMaxSteps,
                    onChanged: (bool value) {
                      setState(() {
                        _disableMaxSteps = value;
                      });
                      _autoSave();
                    },
                    isDark: isDark,
                    subtitleColor: Colors.orangeAccent,
                  ),
                  if (!_disableMaxSteps) ...[
                    const SizedBox(height: 16),
                    _buildSliderWithLabel(
                      label: 'Maximum Steps Per Task',
                      value: _maxSteps,
                      min: 5,
                      max: 50,
                      divisions: 45,
                      onChanged: (value) {
                        setState(() {
                          _maxSteps = value;
                        });
                      },
                      onChangeEnd: (value) {
                        _autoSave();
                      },
                      isDark: isDark,
                    ),
                  ],
                  const SizedBox(height: 24),
                  TextField(
                    controller: _maxTokensController,
                    keyboardType: TextInputType.number,
                    decoration: _buildInputDecoration(
                      labelText: 'Context Limit (Max Tokens)',
                      hintText: '1024',
                      prefixIcon: const Icon(Icons.token_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildSliderWithLabel(
                    label: 'Temperature',
                    value: _temperature,
                    min: 0.0,
                    max: 2.0,
                    divisions: 20,
                    isDouble: true,
                    onChanged: (value) {
                      setState(() {
                        _temperature = value;
                      });
                    },
                    onChangeEnd: (value) {
                      _autoSave();
                    },
                    isDark: isDark,
                  ),
                ],
              ),

              // 4. Behavior & Extensions Card
              _buildSettingsCard(
                icon: Icons.extension_rounded,
                title: 'Behavior & Extensions',
                subtitle: 'Additional feature flags and overlay options',
                isDark: isDark,
                children: [
                  _buildGlassSwitch(
                    title: 'Use Screen Compression',
                    subtitle: 'Removes duplicate elements to save tokens',
                    value: _useScreenCompression,
                    onChanged: (bool value) {
                      setState(() {
                        _useScreenCompression = value;
                      });
                      _autoSave();
                    },
                    isDark: isDark,
                  ),
                  const SizedBox(height: 12),
                  _buildGlassSwitch(
                    title: 'Send System Prompt',
                    subtitle: 'Turn off for custom LoRA fine-tunes',
                    value: _useSystemPrompt,
                    onChanged: (bool value) {
                      setState(() {
                        _useSystemPrompt = value;
                      });
                      _autoSave();
                    },
                    isDark: isDark,
                  ),
                  if (FeatureFlags.floatingOverlayEnabled) ...[
                    const SizedBox(height: 12),
                    _buildGlassSwitch(
                      title: 'Enable Floating Agent Icon',
                      subtitle: 'Assign tasks without opening the app',
                      value: _floatingIconEnabled,
                      onChanged: (val) async {
                        if (val) {
                          bool? isGranted = await FlutterOverlayWindow.isPermissionGranted();
                          if (isGranted != true) {
                            bool? result = await FlutterOverlayWindow.requestPermission();
                            if (result != true) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('Permission to draw over other apps is required.'),
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                );
                              }
                              return;
                            }
                          }
                          if (await FlutterOverlayWindow.isActive() == false) {
                            await FlutterOverlayWindow.showOverlay(
                              enableDrag: true,
                              overlayTitle: "Ultron-3",
                              overlayContent: "Floating Assistant",
                              flag: OverlayFlag.focusPointer,
                              alignment: OverlayAlignment.centerRight,
                              visibility: NotificationVisibility.visibilitySecret,
                              positionGravity: PositionGravity.auto,
                              startPosition: const OverlayPosition(0, 200),
                              width: 56,
                              height: 56,
                            );
                          }
                        } else {
                          if (await FlutterOverlayWindow.isActive() == true) {
                            await FlutterOverlayWindow.closeOverlay();
                          }
                        }
                        setState(() => _floatingIconEnabled = val);
                        _autoSave();
                      },
                      isDark: isDark,
                    ),
                  ],
                ],
              ),

              // 5. Telegram Remote Access Card
              _buildSettingsCard(
                icon: Icons.send_and_archive_rounded,
                title: 'Telegram Remote Access',
                subtitle: 'Control your agent remotely from anywhere',
                isDark: isDark,
                children: [
                  TextField(
                    controller: _telegramTokenController,
                    decoration: _buildInputDecoration(
                      labelText: 'Telegram Bot Token',
                      hintText: '123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11',
                      prefixIcon: const Icon(Icons.send_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildGlassSwitch(
                    title: 'Enable Telegram Bot',
                    subtitle: 'Allows remote control via Telegram chat',
                    value: _telegramEnabled,
                    onChanged: (val) {
                      setState(() => _telegramEnabled = val);
                      _autoSave();
                    },
                    isDark: isDark,
                  ),
                ],
              ),

              // 6. Accessibility Screen Control Card
              _buildSettingsCard(
                icon: Icons.visibility_rounded,
                title: 'Screen Control (Accessibility)',
                subtitle: 'Required to read screen and perform automated clicks',
                isDark: isDark,
                children: [_buildAccessibilityCard(isDark)],
              ),

              // 7. System Permissions Card
              _buildSettingsCard(
                icon: Icons.security_rounded,
                title: 'App Permissions',
                subtitle: 'Required for automation, microphone, and contacts',
                isDark: isDark,
                children: _buildPermissionTiles(isDark),
              ),
              
              // 8. Shizuku Card
              _buildSettingsCard(
                icon: Icons.adb_rounded,
                title: 'Shizuku Status',
                subtitle: 'Required for advanced adb execution',
                isDark: isDark,
                children: [_buildShizukuCard(isDark)],
              ),

              // 9. Task History Card
              _buildSettingsCard(
                icon: Icons.history_rounded,
                title: 'Execution logs',
                subtitle: 'View history of tasks and token analytics',
                isDark: isDark,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.02),
                      border: Border.all(
                        color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      title: const Text('View Task History', style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        'Access complete trace of execution steps',
                        style: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.6)),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const TaskHistoryScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildGlassChip(String label, IconData icon, VoidCallback onPressed, bool isDark, {String? tooltip}) {
    final child = ActionChip(
      avatar: Icon(icon, size: 16, color: isDark ? Colors.white : Colors.black87),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      backgroundColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
      side: BorderSide(
        color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onPressed: onPressed,
    );
    
    if (tooltip != null) {
      return Tooltip(message: tooltip, child: child);
    }
    return child;
  }
  
  Widget _buildGlassSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required bool isDark,
    Color? subtitleColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.02),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: SwitchListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: subtitleColor ?? (isDark ? Colors.white.withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.6)),
            fontSize: 12,
          ),
        ),
        value: value,
        onChanged: onChanged,
        activeColor: Theme.of(context).primaryColor,
        activeTrackColor: Theme.of(context).primaryColor.withValues(alpha: 0.4),
        inactiveThumbColor: isDark ? Colors.grey[400] : Colors.grey[600],
        inactiveTrackColor: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
  
  Widget _buildSliderWithLabel({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
    required bool isDark,
    bool isDouble = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.02),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.2),
                ),
                child: Text(
                  isDouble ? value.toStringAsFixed(2) : value.toInt().toString(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Theme.of(context).primaryColor,
              inactiveTrackColor: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1),
              thumbColor: Theme.of(context).primaryColor,
              overlayColor: Theme.of(context).primaryColor.withValues(alpha: 0.2),
              trackHeight: 4,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPermissionTiles(bool isDark) {
    final permissionMap = {
      'Microphone': Permission.microphone,
      'Contacts': Permission.contacts,
      'Phone': Permission.phone,
      'SMS': Permission.sms,
      'Notifications': Permission.notification,
    };

    final icons = {
      'Microphone': Icons.mic_rounded,
      'Contacts': Icons.contacts_rounded,
      'Phone': Icons.phone_rounded,
      'SMS': Icons.sms_rounded,
      'Notifications': Icons.notifications_rounded,
    };

    final list = permissionMap.entries.map((entry) {
      final status = _permissions[entry.key];
      final isGranted = status?.isGranted ?? false;

      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.02),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
          ),
        ),
        child: ListTile(
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isGranted ? Colors.green.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icons[entry.key],
              color: isGranted ? Colors.green : Colors.orange,
              size: 20,
            ),
          ),
          title: Text(entry.key, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            isGranted
                ? 'Granted'
                : (status?.isDenied ?? true ? 'Not granted' : 'Denied permanently'),
            style: TextStyle(
              color: isGranted ? Colors.green : Colors.orange,
              fontSize: 12,
            ),
          ),
          trailing: isGranted
              ? const Icon(Icons.check_circle_rounded, color: Colors.green)
              : ElevatedButton(
                  onPressed: () => _requestPermission(entry.key, entry.value),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.withValues(alpha: 0.2),
                    foregroundColor: Colors.orange,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Grant'),
                ),
        ),
      );
    }).toList();

    if (FeatureFlags.floatingOverlayEnabled) {
      list.add(
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.02),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
            ),
          ),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _isOverlayPermissionGranted ? Colors.green.withValues(alpha: 0.2) : Colors.orange.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.layers_rounded,
                color: _isOverlayPermissionGranted ? Colors.green : Colors.orange,
                size: 20,
              ),
            ),
            title: const Text('Display Over Other Apps (Floating Bubble)', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              _isOverlayPermissionGranted ? 'Granted' : 'Not granted',
              style: TextStyle(
                color: _isOverlayPermissionGranted ? Colors.green : Colors.orange,
                fontSize: 12,
              ),
            ),
            trailing: _isOverlayPermissionGranted
                ? const Icon(Icons.check_circle_rounded, color: Colors.green)
                : ElevatedButton(
                    onPressed: () async {
                      await FlutterOverlayWindow.requestPermission();
                      final granted = await FlutterOverlayWindow.isPermissionGranted();
                      setState(() {
                        _isOverlayPermissionGranted = granted;
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.withValues(alpha: 0.2),
                      foregroundColor: Colors.orange,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Grant'),
                  ),
          ),
        ),
      );
    }

    return list;
  }

  Widget _buildShizukuCard(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.02),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: widget.shizukuService.isAvailable ? Colors.green.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.shizukuService.isAvailable ? Icons.link_rounded : Icons.link_off_rounded,
                  color: widget.shizukuService.isAvailable ? Colors.green : Colors.grey,
                  size: 20,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                widget.shizukuService.isAvailable ? 'Shizuku is running' : 'Shizuku not detected',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: widget.shizukuService.isAvailable ? Colors.green : Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!widget.shizukuService.isAvailable) ...[
            Text(
              '1. Install Shizuku from Play Store
'
              '2. Open Shizuku and start it via Wireless Debugging
'
              '3. Come back here and tap "Check Again"',
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: isDark ? Colors.white.withValues(alpha: 0.7) : Colors.black.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  await widget.shizukuService.checkAvailability();
                  if (mounted) setState(() {});
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.1)),
                ),
                child: const Text('Check Again', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ] else if (!widget.shizukuService.hasPermission) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  await widget.shizukuService.requestPermission();
                  if (mounted) setState(() {});
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  side: const BorderSide(color: Colors.orange),
                  foregroundColor: Colors.orange,
                ),
                child: const Text('Grant Shizuku Permission', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Permission granted — ADB commands available',
                      style: TextStyle(color: Colors.green, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAccessibilityCard(bool isDark) {
    return FutureBuilder<bool>(
      future: widget.screenAutomationService.isServiceRunning(),
      builder: (context, snapshot) {
        final isRunning = snapshot.data ?? false;

        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.02),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05),
            ),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isRunning ? Colors.green.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isRunning ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                      color: isRunning ? Colors.green : Colors.grey,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    isRunning ? 'Screen Control is active' : 'Screen Control is disabled',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isRunning ? Colors.green : Colors.grey,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (!isRunning) ...[
                Text(
                  'Tap below to open Accessibility Settings, then find "Ultron-3 Screen Control" and enable it.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: isDark ? Colors.white.withValues(alpha: 0.7) : Colors.black.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await widget.screenAutomationService.openAccessibilitySettings();
                    },
                    icon: const Icon(Icons.settings_rounded),
                    label: const Text('Open Accessibility Settings', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.1)),
                    ),
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: Colors.green, size: 20),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Can read screen, tap, scroll, and type in other apps',
                          style: TextStyle(color: Colors.green, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
