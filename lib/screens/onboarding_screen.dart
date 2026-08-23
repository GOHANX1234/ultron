import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/design_tokens.dart';
import '../config/feature_flags.dart';
import '../services/ai_service.dart';
import '../services/screen_automation_service.dart';
import '../services/voice_service.dart';
import '../widgets/app_buttons.dart';
import '../widgets/onboarding/credential_field.dart';
import '../widgets/onboarding/onboarding_stepper.dart';
import '../widgets/onboarding/permission_item.dart';
import '../widgets/ultron_mark.dart';
import 'home_screen.dart';

/// One row of the provider table.
///
/// The old screen scattered these defaults through an if-else chain inside
/// `_selectProvider`, which is why the chip list and the defaults it applied
/// could drift apart. Here the chips are built from the same table that fills
/// the form.
class ProviderOption {
  const ProviderOption({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.model,
    required this.host,
    required this.needsKey,
    this.keysUrl,
  });

  final String id;
  final String name;

  /// Applied to the form on selection. Empty for `custom`, which clears the
  /// form so the user is not editing someone else's endpoint.
  final String baseUrl;
  final String model;

  /// The one-line mono hint under the name in the selector.
  final String host;

  /// Local servers take no credentials, so the key field is hidden for them
  /// rather than shown and then ignored.
  final bool needsKey;

  /// Where this provider issues keys. Null where there is nothing to link to.
  final String? keysUrl;

  static const List<ProviderOption> all = [
    ProviderOption(
      id: 'deepseek',
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-chat',
      host: 'api.deepseek.com',
      needsKey: true,
      keysUrl: 'https://platform.deepseek.com/api_keys',
    ),
    ProviderOption(
      id: 'groq',
      name: 'Groq',
      baseUrl: 'https://api.groq.com/openai/v1',
      model: 'llama-3.3-70b-versatile',
      host: 'api.groq.com',
      needsKey: true,
      keysUrl: 'https://console.groq.com/keys',
    ),
    ProviderOption(
      id: 'nvidia',
      name: 'NVIDIA NIM',
      baseUrl: AiService.nvidiaBaseUrl,
      model: AiService.nvidiaDefaultModel,
      host: 'integrate.api.nvidia.com',
      needsKey: true,
      keysUrl: 'https://build.nvidia.com',
    ),
    ProviderOption(
      id: 'ollama',
      name: 'Ollama',
      baseUrl: 'http://10.0.2.2:11434/v1',
      model: 'gemma2',
      host: 'on this network',
      needsKey: false,
      keysUrl: 'https://ollama.com/download',
    ),
    ProviderOption(
      id: 'local',
      name: 'Local server',
      baseUrl: 'http://10.0.2.2:1234/v1',
      model: 'qwen2.5-7b-instruct',
      host: 'LM Studio, llama.cpp',
      needsKey: false,
    ),
    ProviderOption(
      id: 'custom',
      name: 'Custom endpoint',
      baseUrl: '',
      model: '',
      host: 'any OpenAI-compatible',
      needsKey: true,
    ),
  ];

  static ProviderOption byId(String id) =>
      all.firstWhere((p) => p.id == id, orElse: () => all.last);
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static const List<String> stepLabels = ['Overview', 'Permissions', 'Setup'];

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with WidgetsBindingObserver {
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
  final TextEditingController _ttsApiKeyController = TextEditingController();
  bool _obscureKey = true;
  bool _obscureTtsKey = true;
  bool _isValidating = false;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAiDefaults();
    _checkPermissions();
  }

  Future<void> _loadAiDefaults() async {
    await _aiService.init();
    final prefs = await SharedPreferences.getInstance();
    final savedTtsKey = prefs.getString('tts_api_key') ?? '';
    if (!mounted) return;
    if (_aiService.isConfigured) {
      setState(() {
        _selectedProvider = 'custom';
        _apiKeyController.text = _aiService.apiKey;
        _baseUrlController.text = _aiService.baseUrl;
        _modelController.text = _aiService.model;
        if (savedTtsKey.isNotEmpty) {
          _ttsApiKeyController.text = savedTtsKey;
        }
      });
    } else if (savedTtsKey.isNotEmpty) {
      setState(() {
        _ttsApiKeyController.text = savedTtsKey;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    _ttsApiKeyController.dispose();
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

  /// Android will not let an app open the accessibility toggle directly on a
  /// sideloaded build until "restricted settings" is allowed, so this is two
  /// destinations rather than one button, in the order they have to be visited.
  Future<void> _requestAccessibility() async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Brand.surface,
        insetPadding: const EdgeInsets.all(Space.x3),
        shape: const RoundedRectangleBorder(
          borderRadius: Corner.sheetR,
          side: BorderSide(color: Brand.line),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Space.x3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('TWO STEPS', style: AppType.eyebrow),
              const SizedBox(height: Space.x1 + Space.half),
              const Text(
                'Turn on the accessibility service',
                style: AppType.title,
              ),
              const SizedBox(height: Space.x1 + Space.half),
              const Text(
                'Because this build was installed outside the Play Store, '
                'Android hides the toggle until you allow it.',
                style: AppType.body,
              ),
              const SizedBox(height: Space.x2),
              const _DialogStep(
                index: '01',
                text: 'In App info, open the ⋮ menu and tap '
                    '"Allow restricted settings".',
              ),
              const SizedBox(height: Space.x1 + Space.half),
              const _DialogStep(
                index: '02',
                text: 'In Accessibility, find Ultron 3 under Installed apps '
                    'and switch it on.',
              ),
              const SizedBox(height: Space.x3),
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: 'App info',
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        openAppSettings();
                      },
                    ),
                  ),
                  const SizedBox(width: Space.x1 + Space.half),
                  Expanded(
                    child: PrimaryButton(
                      label: 'Accessibility',
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        _screenAutomationService.openAccessibilitySettings();
                      },
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
    if (!mounted) return;
    setState(() {
      _isOverlayGranted = granted;
    });
  }

  void _selectProvider(String id) {
    final option = ProviderOption.byId(id);
    setState(() {
      _selectedProvider = id;
      _validationError = null;
      _baseUrlController.text = option.baseUrl;
      _modelController.text = option.model;
    });
  }

  Future<void> _openKeysPage(String url) async {
    final uri = Uri.parse(url);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      _notify('Could not open $url');
    }
  }

  void _notify(String message, {bool good = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            if (good) ...[
              const Icon(Icons.check_rounded, size: 18, color: Brand.signal),
              const SizedBox(width: Space.x1 + Space.half),
            ],
            Expanded(child: Text(message, style: AppType.bodyStrong)),
          ],
        ),
        margin: const EdgeInsets.all(Space.x2),
      ),
    );
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
        _validationError = 'Enter both an endpoint and a model name.';
        _isValidating = false;
      });
      return;
    }

    if (ProviderOption.byId(_selectedProvider).needsKey && apiKey.isEmpty) {
      setState(() {
        _validationError =
            'This provider needs an API key. Local servers do not.';
        _isValidating = false;
      });
      return;
    }

    try {
      final models = await _aiService.fetchAvailableModels(baseUrl, apiKey);
      // A local server that answers with an empty list is still a working
      // endpoint, so absence of models is only fatal for cloud providers.
      if (models.isNotEmpty ||
          !ProviderOption.byId(_selectedProvider).needsKey) {
        await _aiService.saveSettings(
          apiKey: apiKey,
          baseUrl: baseUrl,
          model: model,
        );
        final ttsApiKey = _ttsApiKeyController.text.trim();
        final voiceService = VoiceService();
        await voiceService.saveSettings(
          apiKey: ttsApiKey,
          endpoint: VoiceService.defaultEndpoint,
          model: VoiceService.defaultModel,
          voice: VoiceService.defaultVoice,
          enabled: true,
        );
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('onboarding_completed', true);

        if (mounted) {
          setState(() {
            _isValidating = false;
          });

          _notify('Endpoint reachable. Opening Ultron 3.', good: true);

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      } else if (mounted) {
        setState(() {
          _validationError =
              'The endpoint answered, but listed no models. Check the URL '
              'and key.';
          _isValidating = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _validationError = e.toString().replaceFirst('Exception: ', '');
        _isValidating = false;
      });
    }
  }

  Future<void> _fetchModels() async {
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();

    if (baseUrl.isEmpty) {
      _notify('Enter an endpoint first.');
      return;
    }

    setState(() {
      _isValidating = true;
    });

    try {
      final models = await _aiService.fetchAvailableModels(baseUrl, apiKey);
      if (!mounted) return;

      setState(() {
        _isValidating = false;
      });

      if (models.isEmpty) {
        _notify('No models came back. Check the endpoint and key.');
        return;
      }

      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => _ModelSheet(
          models: models,
          selected: _modelController.text,
          nvidiaOnly: AiService.isNvidiaBaseUrl(baseUrl),
          onPick: (name) {
            setState(() => _modelController.text = name);
            Navigator.pop(sheetContext);
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isValidating = false;
      });
      _notify(e.toString().replaceFirst('Exception: ', ''));
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

  void _goToStep(int step) {
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    // The flow carries its own theme rather than following the system one: this
    // is the first screen of a fresh install, before the user has any settings,
    // and it is the one surface where the brand has to land the same way on
    // every device.
    return Theme(
      data: onboardingTheme(),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Brand.ink,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: Brand.ink,
          body: SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                const Divider(height: 1),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    // Gated navigation: swiping past a step the user has not
                    // satisfied is the one way to reach the setup form without
                    // the accessibility service, which then fails silently on
                    // the first task.
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (index) =>
                        setState(() => _currentStep = index),
                    children: [
                      _buildOverviewPage(),
                      _buildPermissionsPage(),
                      _buildSetupPage(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.x2,
        Space.gutter,
        Space.x2,
      ),
      child: Column(
        children: [
          Row(
            children: [
              const UltronWordmark(),
              const Spacer(),
              Text(
                'STEP 0${_currentStep + 1} / 0${OnboardingScreen.stepLabels.length}',
                style: AppType.dataSmall,
              ),
            ],
          ),
          const SizedBox(height: Space.x2),
          OnboardingStepper(
            labels: OnboardingScreen.stepLabels,
            current: _currentStep,
            onSelect: _goToStep,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- overview

  /// Leads with the mechanism, not a tagline.
  ///
  /// The hierarchy is deliberate and uneven: one sentence of what the app does,
  /// one panel explaining the loop that does it, two low-emphasis cards for the
  /// things a sceptical user wants to know next, and a plain note handing over
  /// to the permission screen. The four equal-weight feature cards this replaces
  /// gave a first-time reader nothing to read first.
  Widget _buildOverviewPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.x3,
        Space.gutter,
        Space.x4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ultron runs your phone\nfrom one written instruction.',
            style: AppType.display,
          ),
          const SizedBox(height: Space.x2),
          const Text(
            'Type or dictate what you want done. Ultron reads what is on '
            'screen, decides the next tap, and repeats until the job is '
            'finished — in the apps already on this phone.',
            style: AppType.body,
          ),
          const SizedBox(height: Space.x3),
          const _Panel(
            label: 'How a run works',
            children: [
              _NumberedStep(
                index: '01',
                title: 'It reads the screen',
                body: 'Android\'s accessibility service exposes what is on '
                    'screen as text: labels, buttons, and where each one sits.',
              ),
              _NumberedStep(
                index: '02',
                title: 'Your model picks one action',
                body: 'That text and your goal go to the model you configure. '
                    'It answers with a single step — tap, type, scroll, back.',
              ),
              _NumberedStep(
                index: '03',
                title: 'It acts, then looks again',
                body: 'The step is dispatched, the screen is re-read, and the '
                    'loop continues until the goal is met or it stops and says '
                    'why.',
              ),
            ],
          ),
          const SizedBox(height: Space.x2),
          // IntrinsicHeight, because stretch alone resolves against the
          // scroll view's infinite height. The two bodies are different
          // lengths, and a pair of cards whose bottom edges do not line up is
          // the first thing that reads as unconsidered.
          const IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _MiniCard(
                    title: 'Your model, your key',
                    body: 'DeepSeek, Groq, NVIDIA, or an Ollama or LM Studio '
                        'server on your own machine.',
                  ),
                ),
                SizedBox(width: Space.x2),
                Expanded(
                  child: _MiniCard(
                    title: 'Nothing runs quietly',
                    body: 'Every step is written to task history, and a run can '
                        'be stopped mid-step.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.x3),
          const _Note(
            label: 'Next',
            text: 'Two permissions do the actual work: the accessibility '
                'service, and the microphone if you want to speak to it. The '
                'next screen explains what each one reads, and what you lose '
                'by declining it.',
          ),
          const SizedBox(height: Space.x3),
          PrimaryButton(
            label: 'Review permissions',
            icon: Icons.arrow_forward_rounded,
            onPressed: () => _goToStep(1),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- permissions

  Widget _buildPermissionsPage() {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.x3,
              Space.gutter,
              Space.x3,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'What Ultron needs\naccess to.',
                  style: AppType.display,
                ),
                const SizedBox(height: Space.x2),
                const Text(
                  'Ultron cannot find its way around your phone by guessing. '
                  'Each item below says what it reads, what it does with it, '
                  'and what stops working if you decline.',
                  style: AppType.body,
                ),
                const SizedBox(height: Space.x2),
                Text(
                  'GRANTED $_grantedCount / $_totalCount',
                  style: AppType.dataSmall,
                ),
                const SizedBox(height: Space.x3),
                _Panel(
                  label: 'Required to run',
                  children: [
                    PermissionItem(
                      name: 'Screen reading and tap control',
                      why: 'Android exposes on-screen elements, and the ability '
                          'to tap them, only through the accessibility '
                          'service. This is the whole mechanism: Ultron reads '
                          'the element tree as text and dispatches taps back '
                          'through the same channel.',
                      consequence: 'Without it, Ultron can still hold a '
                          'conversation but cannot touch your phone. Every '
                          'task will refuse to start.',
                      granted: _isAccessibilityGranted,
                      onGrant: _requestAccessibility,
                      grantLabel: 'Set up',
                    ),
                    PermissionItem(
                      name: 'Microphone',
                      why: 'Speech is transcribed on device while you hold the '
                          'mic button, and the microphone is released as soon '
                          'as you let go. Nothing is recorded between commands.',
                      consequence: 'Without it, you can still type every '
                          'instruction. Voice input is the only thing you lose.',
                      granted: _isMicrophoneGranted,
                      onGrant: () => _requestPermission(Permission.microphone),
                    ),
                    if (FeatureFlags.floatingOverlayEnabled)
                      PermissionItem(
                        name: 'Draw over other apps',
                        why: 'Keeps a small control bubble on screen while a '
                            'task runs in another app, so you can watch and '
                            'stop it without switching back.',
                        consequence: 'Without it, you have to reopen Ultron to '
                            'see progress or cancel a run.',
                        granted: _isOverlayGranted,
                        onGrant: _requestOverlayPermission,
                      ),
                  ],
                ),
                const SizedBox(height: Space.x3),
                _Panel(
                  label: 'Optional — widens what it can do',
                  children: [
                    PermissionItem(
                      name: 'Notifications',
                      why: 'Posts one notification when a task finishes or '
                          'fails, with the outcome in the text.',
                      consequence: 'Without it, results are only visible '
                          'inside the app.',
                      granted: _isNotificationsGranted,
                      onGrant: () =>
                          _requestPermission(Permission.notification),
                    ),
                    PermissionItem(
                      name: 'Contacts',
                      why: 'Resolves a name in your instruction to a number, '
                          'so "call Priya" works. Contacts are read on demand, '
                          'never uploaded.',
                      consequence: 'Without it, you will have to give full '
                          'phone numbers.',
                      granted: _isContactsGranted,
                      onGrant: () => _requestPermission(Permission.contacts),
                    ),
                    PermissionItem(
                      name: 'Phone',
                      why: 'Places a call directly once you have asked for one.',
                      consequence: 'Without it, Ultron opens the dialer with '
                          'the number filled in and you press call.',
                      granted: _isPhoneGranted,
                      onGrant: () => _requestPermission(Permission.phone),
                    ),
                    PermissionItem(
                      name: 'SMS',
                      why: 'Sends a text message you have dictated or typed.',
                      consequence: 'Without it, Ultron composes the message in '
                          'your messaging app and leaves sending to you.',
                      granted: _isSmsGranted,
                      onGrant: () => _requestPermission(Permission.sms),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        _Footer(
          note: _canProceedToModel
              ? null
              : 'Continue unlocks once screen control and the microphone are on.',
          children: [
            SecondaryButton(
              label: 'Back',
              expand: false,
              onPressed: () => _goToStep(0),
            ),
            const SizedBox(width: Space.x1 + Space.half),
            Expanded(
              child: PrimaryButton(
                label: 'Continue',
                icon: Icons.arrow_forward_rounded,
                onPressed: _canProceedToModel ? () => _goToStep(2) : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ------------------------------------------------------------------- setup

  Widget _buildSetupPage() {
    final provider = ProviderOption.byId(_selectedProvider);

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              Space.gutter,
              Space.x3,
              Space.gutter,
              Space.x3,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Connect a model.', style: AppType.display),
                const SizedBox(height: Space.x2),
                const Text(
                  'Ultron works with any OpenAI-compatible endpoint: it posts '
                  'the screen text and expects one JSON action back. Pick a '
                  'provider to fill in its defaults, then paste your key.',
                  style: AppType.body,
                ),
                const SizedBox(height: Space.x3),
                const Text('PROVIDER', style: AppType.eyebrow),
                const SizedBox(height: Space.x1 + Space.half),
                _buildProviderGrid(),
                const SizedBox(height: Space.x3),
                _Panel(
                  label: 'Credentials',
                  divided: false,
                  padded: true,
                  children: [
                    if (provider.needsKey) ...[
                      CredentialField(
                        label: 'API key',
                        controller: _apiKeyController,
                        obscure: _obscureKey,
                        onToggleObscure: () =>
                            setState(() => _obscureKey = !_obscureKey),
                        hint: 'sk-...',
                        helper: 'Stored in this app\'s private preferences on '
                            'this device. It is sent only to the endpoint below.',
                        hasError: _validationError != null,
                        trailingLink: provider.keysUrl == null
                            ? null
                            : _LinkButton(
                                label: 'GET A KEY',
                                onTap: () => _openKeysPage(provider.keysUrl!),
                              ),
                      ),
                      const SizedBox(height: Space.x2),
                    ] else
                      const Padding(
                        padding: EdgeInsets.only(bottom: Space.x2),
                        child: _Note(
                          label: 'No key needed',
                          text: 'Local servers accept requests without '
                              'credentials. Make sure the server is reachable '
                              'from this phone — 10.0.2.2 only resolves on an '
                              'emulator, so on a real device use the machine\'s '
                              'LAN address.',
                        ),
                      ),
                    CredentialField(
                      label: 'Endpoint',
                      controller: _baseUrlController,
                      hint: 'https://api.example.com/v1',
                      keyboardType: TextInputType.url,
                      hasError: _validationError != null,
                    ),
                    const SizedBox(height: Space.x2),
                    CredentialField(
                      label: 'Model',
                      controller: _modelController,
                      hint: 'model-name',
                      actionLabel: 'Fetch',
                      onAction: _isValidating ? null : _fetchModels,
                      helper: 'Fetch lists what this key can actually reach.',
                    ),
                    if (_isValidating || _validationError != null) ...[
                      const SizedBox(height: Space.x2),
                      _FormStatus(
                        busy: _isValidating,
                        error: _validationError,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: Space.x2),
                _Panel(
                  label: 'Spoken replies',
                  divided: false,
                  padded: true,
                  children: [
                    const Text(
                      'Replies can be read aloud through a cloud voice. Leave '
                      'this blank to keep Ultron silent — you can add it later '
                      'in Settings.',
                      style: AppType.body,
                    ),
                    const SizedBox(height: Space.x2),
                    CredentialField(
                      label: 'Voice API key',
                      controller: _ttsApiKeyController,
                      optional: true,
                      obscure: _obscureTtsKey,
                      onToggleObscure: () =>
                          setState(() => _obscureTtsKey = !_obscureTtsKey),
                      hint: 'sk-...',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        _Footer(
          children: [
            SecondaryButton(
              label: 'Back',
              expand: false,
              onPressed: _isValidating ? null : () => _goToStep(1),
            ),
            const SizedBox(width: Space.x1 + Space.half),
            Expanded(
              child: PrimaryButton(
                label: 'Verify and finish',
                busy: _isValidating,
                onPressed: _testAndSave,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Two columns of plain outlined cells.
  ///
  /// Not a scrolling strip of gradient-filled icon chips: a provider is a form
  /// value, and a form value should look selectable rather than promotional. All
  /// six are visible at once, which is also how you notice the local options
  /// exist.
  Widget _buildProviderGrid() {
    final options = ProviderOption.all;
    final rows = <Widget>[];

    for (var i = 0; i < options.length; i += 2) {
      if (i > 0) rows.add(const SizedBox(height: Space.x1 + Space.half));
      rows.add(
        // Not CrossAxisAlignment.stretch: this grid lives in a
        // SingleChildScrollView, where stretch would resolve against an
        // infinite height. Both cells are one line of name over one line of
        // host, so they measure the same anyway.
        Row(
          children: [
            Expanded(child: _providerCell(options[i])),
            const SizedBox(width: Space.x1 + Space.half),
            if (i + 1 < options.length)
              Expanded(child: _providerCell(options[i + 1]))
            else
              const Spacer(),
          ],
        ),
      );
    }

    return Column(children: rows);
  }

  Widget _providerCell(ProviderOption option) {
    return _ProviderCell(
      option: option,
      selected: option.id == _selectedProvider,
      onTap: () => _selectProvider(option.id),
    );
  }
}

/// A titled surface: one hairline border, no shadow, no blur.
///
/// The label sits *outside* the box, so the box itself is only content. Groups
/// of rows are separated by 1px rules rather than by being broken into separate
/// floating cards, which is what makes a list of six permissions read as one
/// list.
class _Panel extends StatelessWidget {
  const _Panel({
    this.label,
    required this.children,
    this.divided = true,
    this.padded = false,
  });

  final String? label;
  final List<Widget> children;

  /// Rules between children. Off for forms, where the fields carry their own
  /// spacing.
  final bool divided;

  /// Pads the box. Off for rows that pad themselves edge to edge.
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final content = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (divided && i > 0) content.add(const Divider(height: 1));
      content.add(children[i]);
    }

    final Widget box = Container(
      decoration: BoxDecoration(
        color: Brand.surface,
        borderRadius: Corner.cardR,
        border: Brand.hairline(),
      ),
      padding: padded ? const EdgeInsets.all(Space.x2) : EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: content,
      ),
    );

    if (label == null) return box;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label!.toUpperCase(), style: AppType.eyebrow),
        const SizedBox(height: Space.x1 + Space.half),
        box,
      ],
    );
  }
}

/// A step in the "how a run works" panel. The number is set in the data face and
/// in the accent, which is the only ornament on the overview screen.
class _NumberedStep extends StatelessWidget {
  const _NumberedStep({
    required this.index,
    required this.title,
    required this.body,
  });

  final String index;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Space.x2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 26,
            child: Text(
              index,
              style: AppType.dataSmall.copyWith(
                color: Brand.signal,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppType.bodyStrong),
                const SizedBox(height: Space.half),
                Text(body, style: AppType.body),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The lower-emphasis pair on the overview screen: smaller type, same surface,
/// no number and no accent — so they read as supporting detail next to the panel
/// above them.
class _MiniCard extends StatelessWidget {
  const _MiniCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Space.x2),
      decoration: BoxDecoration(
        color: Brand.surface,
        borderRadius: Corner.cardR,
        border: Brand.hairline(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppType.label),
          const SizedBox(height: Space.x1 - Space.half),
          Text(body, style: AppType.caption),
        ],
      ),
    );
  }
}

/// An aside with no fill — a border and text. Used where something has to be
/// said but does not deserve the weight of a panel.
class _Note extends StatelessWidget {
  const _Note({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Space.x2),
      decoration: BoxDecoration(
        borderRadius: Corner.cardR,
        border: Brand.hairline(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: AppType.eyebrow),
          const SizedBox(height: Space.x1),
          Text(text, style: AppType.body),
        ],
      ),
    );
  }
}

/// The pinned action row. Sits on a rule so it reads as chrome rather than as
/// the end of the scrolling content, and carries one line of plain text when the
/// primary action is unavailable — the reason, not a nag.
class _Footer extends StatelessWidget {
  const _Footer({required this.children, this.note});

  final List<Widget> children;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Brand.line)),
      ),
      padding: const EdgeInsets.fromLTRB(
        Space.gutter,
        Space.x2,
        Space.gutter,
        Space.x2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (note != null) ...[
            Text(note!, style: AppType.caption),
            const SizedBox(height: Space.x1 + Space.half),
          ],
          Row(children: children),
        ],
      ),
    );
  }
}

/// One provider in the selector: a square indicator, the name, and the host it
/// will actually talk to. The host line is there because "Ollama" does not tell
/// you the request is going to your own machine.
class _ProviderCell extends StatelessWidget {
  const _ProviderCell({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final ProviderOption option;
  final bool selected;
  final VoidCallback onTap;

  static Key cellKey(String id) => Key('provider-$id');

  @override
  Widget build(BuildContext context) {
    return Material(
      key: cellKey(option.id),
      color: selected ? Brand.surfaceHigh : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: Corner.controlR,
        side: BorderSide(color: selected ? Brand.signal : Brand.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Space.x1 + Space.half),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: selected ? Brand.signal : Colors.transparent,
                      borderRadius: Corner.markR,
                      border: selected
                          ? null
                          : Border.all(color: Brand.lineStrong),
                    ),
                  ),
                  const SizedBox(width: Space.x1),
                  Expanded(
                    child: Text(
                      option.name,
                      style: AppType.label.copyWith(
                        color: selected
                            ? Brand.textPrimary
                            : Brand.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.half + 2),
              Text(
                option.host,
                style: AppType.dataSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A text link in the accent, for documentation the user has to leave the app to
/// read.
class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.half),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: AppType.eyebrow.copyWith(color: Brand.signal)),
            const SizedBox(width: Space.half),
            const Icon(Icons.north_east_rounded, size: 12, color: Brand.signal),
          ],
        ),
      ),
    );
  }
}

/// The form's validation state, in one place under the fields.
///
/// The old screen only ever showed failure, and showed it as a red-tinted card
/// with an icon. Progress is the state a user is actually waiting on, so it is
/// reported first and in plain type.
class _FormStatus extends StatelessWidget {
  const _FormStatus({required this.busy, required this.error});

  final bool busy;
  final String? error;

  static const Key busyKey = Key('form-status-busy');
  static const Key errorKey = Key('form-status-error');

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const Row(
        key: busyKey,
        children: [
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 1.6),
          ),
          SizedBox(width: Space.x1 + Space.half),
          Text('Checking the endpoint…', style: AppType.caption),
        ],
      );
    }

    if (error == null) return const SizedBox.shrink();

    return Container(
      key: errorKey,
      padding: const EdgeInsets.all(Space.x1 + Space.half),
      decoration: BoxDecoration(
        color: Brand.danger.withValues(alpha: 0.08),
        borderRadius: Corner.controlR,
        border: Border.all(color: Brand.danger.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, size: 16, color: Brand.danger),
          const SizedBox(width: Space.x1 + Space.half),
          Expanded(
            child: Text(
              error!,
              style: AppType.body.copyWith(color: Brand.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogStep extends StatelessWidget {
  const _DialogStep({required this.index, required this.text});

  final String index;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          index,
          style: AppType.dataSmall.copyWith(
            color: Brand.signal,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: Space.x1 + Space.half),
        Expanded(child: Text(text, style: AppType.body)),
      ],
    );
  }
}

/// The model picker. Model ids are data, so the list is set in mono and the
/// current one is marked rather than recoloured.
class _ModelSheet extends StatelessWidget {
  const _ModelSheet({
    required this.models,
    required this.selected,
    required this.nvidiaOnly,
    required this.onPick,
  });

  final List<String> models;
  final String selected;
  final bool nvidiaOnly;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.62,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.x3, Space.x2, Space.x3, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: const BoxDecoration(
                  color: Brand.lineStrong,
                  borderRadius: Corner.markR,
                ),
              ),
            ),
            const SizedBox(height: Space.x3),
            Text(
              nvidiaOnly ? 'Free NVIDIA models' : 'Available models',
              style: AppType.title,
            ),
            const SizedBox(height: Space.half),
            Text('${models.length} REACHABLE WITH THIS KEY',
                style: AppType.dataSmall),
            const SizedBox(height: Space.x2),
            Expanded(
              child: ListView.separated(
                itemCount: models.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final name = models[index];
                  final isCurrent = name == selected;
                  return InkWell(
                    onTap: () => onPick(name),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Space.x2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: AppType.data.copyWith(
                                color: isCurrent
                                    ? Brand.textPrimary
                                    : Brand.textSecondary,
                              ),
                            ),
                          ),
                          if (isCurrent)
                            const Icon(
                              Icons.check_rounded,
                              size: 17,
                              color: Brand.signal,
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
