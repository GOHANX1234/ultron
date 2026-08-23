import 'package:flutter/material.dart';

import '../widgets/background_glows.dart';

/// The animated launch screen.
///
/// One [AnimationController] drives every entrance: the pieces are staged with
/// [Interval]s off a single timeline rather than a controller each, so there is
/// one ticker and the choreography is readable in one place. A second, looping
/// controller owns the two idle motions (the halo breath and the sweep on the
/// progress line) — those have a different period and outlive the entrance.
///
/// Nothing here waits on I/O: `main()` has already read SharedPreferences by
/// the time this builds, so the duration is purely presentational and the
/// screen replaces itself with [next] when the timeline finishes.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.next});

  /// Built lazily, once the animation is done, so its own initState work does
  /// not compete with the entrance for the first frames.
  final WidgetBuilder next;

  /// The whole entrance. Long enough to read as deliberate, short enough that
  /// it never feels like a wait.
  static const Duration entrance = Duration(milliseconds: 2100);

  /// The entrance when the platform asks for animations to be removed. Short
  /// enough not to read as an animation, long enough that the handover is a
  /// fade rather than a flash.
  static const Duration reducedEntrance = Duration(milliseconds: 300);

  static const Color _accent = Color(0xFF6366F1);
  static const Color _accentAlt = Color(0xFF0EA5E9);

  static const Key logoKey = Key('splash-logo');
  static const Key wordmarkKey = Key('splash-wordmark');

  /// The two staged fades a test needs to read directly. Addressed by key
  /// rather than by `find.ancestor(matching: FadeTransition)`, which also
  /// matches the FadeTransitions inside the page transition wrapping the route.
  static const Key logoFadeKey = Key('splash-logo-fade');
  static const Key taglineFadeKey = Key('splash-tagline-fade');

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: SplashScreen.entrance,
  );

  /// The idle loop. Separate from the entrance because it repeats and because
  /// its period is unrelated to the staging above.
  late final AnimationController _idle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  bool _leaving = false;
  bool _reducedMotion = false;

  // Staged off the one timeline. Ordered as they appear.
  late final Animation<double> _haloIn = _curve(0.00, 0.55);
  late final Animation<double> _logoIn = _curve(0.05, 0.50);
  late final Animation<double> _wordmarkIn = _curve(0.32, 0.70);
  late final Animation<double> _taglineIn = _curve(0.50, 0.82);
  late final Animation<double> _progressIn = _curve(0.60, 0.90);

  Animation<double> _curve(double begin, double end) {
    return CurvedAnimation(
      parent: _entrance,
      // easeOutCubic everywhere: it settles without the overshoot of easeOutBack,
      // which is what keeps this feeling like product UI rather than a title card.
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
  }

  @override
  void initState() {
    super.initState();
    _entrance.addStatusListener((status) {
      if (status == AnimationStatus.completed) _goNext();
    });
    _entrance.forward();
    _idle.repeat(reverse: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // "Remove animations" in Android accessibility settings. The timeline is
    // compressed rather than skipped: the same staged entrance runs, just too
    // fast to read as motion, and the idle loop -- the only thing here that
    // moves indefinitely -- is stopped outright.
    //
    // Deliberately not `_entrance.value = 1` plus a hand-rolled handover:
    // assigning value reports no completed status, so that needed its own
    // post-frame push and left two ways off this screen. Shortening the
    // duration keeps exactly one, the status listener below.
    if (MediaQuery.disableAnimationsOf(context) && !_reducedMotion) {
      _reducedMotion = true;
      _idle.stop();
      _entrance.duration = SplashScreen.reducedEntrance;
      _entrance.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    _idle.dispose();
    super.dispose();
  }

  void _goNext() {
    if (_leaving || !mounted) return;
    _leaving = true;

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondary) => widget.next(context),
        // The outgoing splash and incoming screen cross-fade over a shared
        // background, and the new screen scales up a touch from 0.98 — the
        // motion continues instead of cutting.
        transitionsBuilder: (context, animation, _, child) {
          final eased = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: eased,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.98, end: 1).animate(eased),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      // Explicit, so the route's own background matches the native launch
      // window colour and the handover is not visible as a flash.
      backgroundColor:
          isDark ? const Color(0xFF0B0F19) : const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          // The ambient glows are the app's own; fading them in on the halo's
          // timeline means the splash dissolves into the real background.
          //
          // BackgroundGlows is itself a Positioned.fill, so it has to be the
          // direct child of a Stack -- hence the inner Stack rather than
          // handing it straight to the FadeTransition, which would throw
          // "Incorrect use of ParentDataWidget".
          Positioned.fill(
            child: FadeTransition(
              opacity: _haloIn,
              child: const RepaintBoundary(
                child: Stack(children: [BackgroundGlows()]),
              ),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildMark(isDark),
                const SizedBox(height: 26),
                _buildWordmark(),
                const SizedBox(height: 8),
                _buildTagline(isDark),
              ],
            ),
          ),
          Align(
            alignment: const Alignment(0, 0.82),
            child: _buildProgressLine(isDark),
          ),
        ],
      ),
    );
  }

  /// The logo, its drop glow, and the breathing halo behind it.
  Widget _buildMark(bool isDark) {
    return SizedBox(
      width: 168,
      height: 168,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Painted rather than assembled from decorated Containers: two rings
          // and a wash in one layer, and only this subtree repaints on the idle
          // ticker.
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: Listenable.merge([_haloIn, _idle]),
              builder: (context, _) => CustomPaint(
                size: const Size.square(168),
                painter: _HaloPainter(
                  entrance: _haloIn.value,
                  breath: Curves.easeInOut.transform(_idle.value),
                  isDark: isDark,
                ),
              ),
            ),
          ),
          FadeTransition(
            key: SplashScreen.logoFadeKey,
            opacity: _logoIn,
            child: ScaleTransition(
              // From 0.88 rather than 0: the mark arrives, it does not grow out
              // of nothing, which is the difference between composed and cute.
              scale: Tween<double>(begin: 0.88, end: 1).animate(_logoIn),
              child: _buildLogo(isDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo(bool isDark) {
    return Container(
      key: SplashScreen.logoKey,
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: SplashScreen._accent.withValues(alpha: isDark ? 0.42 : 0.30),
            blurRadius: 34,
            spreadRadius: -4,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Image.asset(
          'assets/app-logo.png',
          width: 92,
          height: 92,
          fit: BoxFit.cover,
          // Drawn at 92dp from a 512px source; without a cache size the full
          // bitmap is decoded and kept for the life of the image cache.
          cacheWidth: 276,
          cacheHeight: 276,
        ),
      ),
    );
  }

  Widget _buildWordmark() {
    return FadeTransition(
      opacity: _wordmarkIn,
      child: SlideTransition(
        // A fraction of the wordmark's own height (~18px), so the text lifts
        // into place instead of simply appearing.
        position: Tween<Offset>(
          begin: const Offset(0, 0.45),
          end: Offset.zero,
        ).animate(_wordmarkIn),
        child: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [
              SplashScreen._accent,
              SplashScreen._accentAlt,
              Color(0xFF38BDF8),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: const Text(
            'Ultron-3',
            key: SplashScreen.wordmarkKey,
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              height: 1.2,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTagline(bool isDark) {
    return FadeTransition(
      key: SplashScreen.taglineFadeKey,
      opacity: _taglineIn,
      child: Text(
        'Automation agent',
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 2.6,
          color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
        ),
      ),
    );
  }

  /// A 2px rail with a gradient highlight travelling along it. An indeterminate
  /// bar reads as "starting"; a spinner reads as "waiting".
  Widget _buildProgressLine(bool isDark) {
    return FadeTransition(
      opacity: _progressIn,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _idle,
          builder: (context, _) => CustomPaint(
            size: const Size(104, 2),
            painter: _SweepPainter(
              phase: Curves.easeInOut.transform(_idle.value),
              isDark: isDark,
            ),
          ),
        ),
      ),
    );
  }
}

/// Two concentric rings and a soft wash behind the logo.
///
/// [entrance] scales and fades the whole halo in; [breath] (0..1, ping-ponged)
/// makes it expand and contract by a couple of percent for as long as the
/// screen is up. Painting it means one layer instead of three decorated boxes,
/// and it keeps the animation off the widget tree entirely.
class _HaloPainter extends CustomPainter {
  const _HaloPainter({
    required this.entrance,
    required this.breath,
    required this.isDark,
  });

  final double entrance;
  final double breath;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    if (entrance <= 0) return;

    final center = size.center(Offset.zero);
    // Two percent of travel, on top of a slight scale-up during the entrance.
    final scale = (0.90 + 0.10 * entrance) * (1 + 0.02 * breath);
    final outer = size.width / 2 * scale;

    // The wash: a radial falloff, strongest just outside the logo.
    canvas.drawCircle(
      center,
      outer,
      Paint()
        ..shader = RadialGradient(
          colors: [
            SplashScreen._accent.withValues(
              alpha: (isDark ? 0.22 : 0.14) * entrance,
            ),
            SplashScreen._accent.withValues(alpha: 0),
          ],
          stops: const [0.35, 1],
        ).createShader(Rect.fromCircle(center: center, radius: outer)),
    );

    // Two hairline rings. The outer one fades in later and lower, so the pair
    // reads as depth rather than as a target.
    _ring(canvas, center, outer * 0.72, 1.2, (isDark ? 0.30 : 0.22) * entrance);
    _ring(
      canvas,
      center,
      outer * 0.97,
      1.0,
      (isDark ? 0.14 : 0.10) * entrance * breath.clamp(0.35, 1),
    );
  }

  void _ring(
    Canvas canvas,
    Offset center,
    double radius,
    double width,
    double alpha,
  ) {
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..shader = SweepGradient(
          colors: [
            SplashScreen._accent.withValues(alpha: alpha),
            SplashScreen._accentAlt.withValues(alpha: alpha * 0.85),
            SplashScreen._accent.withValues(alpha: alpha),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
  }

  @override
  bool shouldRepaint(_HaloPainter old) =>
      old.entrance != entrance || old.breath != breath || old.isDark != isDark;
}

/// The rail under the mark: a dim track with a bright segment sliding across it.
///
/// [phase] runs 0..1 and back (the controller ping-pongs), so the highlight
/// travels right, then left, without a discontinuity at either end — which is
/// what a wrapping 0→1 loop would give.
class _SweepPainter extends CustomPainter {
  const _SweepPainter({required this.phase, required this.isDark});

  final double phase;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    final track = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      radius,
    );

    canvas.drawRRect(
      track,
      Paint()
        ..color = isDark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.black.withValues(alpha: 0.08),
    );

    // A third of the rail, positioned so it stays fully inside it at both ends.
    final segment = size.width / 3;
    final left = (size.width - segment) * phase;

    canvas.save();
    canvas.clipRRect(track);
    canvas.drawRect(
      Rect.fromLTWH(left, 0, segment, size.height),
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0x006366F1),
            SplashScreen._accent,
            SplashScreen._accentAlt,
            Color(0x000EA5E9),
          ],
          stops: [0, 0.35, 0.65, 1],
        ).createShader(Rect.fromLTWH(left, 0, segment, size.height)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SweepPainter old) =>
      old.phase != phase || old.isDark != isDark;
}
