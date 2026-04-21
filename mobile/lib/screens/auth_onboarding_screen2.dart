import "dart:math" as math;

import "package:firebase_auth/firebase_auth.dart";
import "package:flutter/material.dart";

import "../services/firestore_repository.dart";

// ── Design tokens ──────────────────────────────────────────────────────────────
// Warm cream + orange palette — matches the app's core design system.

const Color _kBg         = Color(0xFFF7F1E8);   // warm cream — main bg
const Color _kSurface    = Color(0xFFFFFFFF);   // white cards
const Color _kDark       = Color(0xFF1A1410);   // near-black (pill buttons, text)
const Color _kMuted      = Color(0xFF9C8E7A);   // warm muted text
const Color _kOrange     = Color(0xFFFF8C00);   // mascot orange / primary accent
const Color _kOrangeSoft = Color(0xFFFFF0D6);   // soft orange — field fill
const Color _kYellow     = Color(0xFFFFD84D);   // pill accent — focus
const Color _kPink       = Color(0xFFF2C4CE);   // pill accent — rest
const Color _kBlue       = Color(0xFFBDD4E8);   // pill accent — social
const Color _kGreen      = Color(0xFFA8C5A0);   // pill accent — energy
const Color _kSage       = Color(0xFFB5C9A0);   // pill accent — lifestyle

InputDecoration _fieldStyle(String label, {IconData? icon}) {
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(
        color: _kMuted, fontSize: 13, fontWeight: FontWeight.w500),
    prefixIcon:
        icon != null ? Icon(icon, color: _kOrange, size: 18) : null,
    filled: true,
    fillColor: _kOrangeSoft,
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: _kOrange, width: 1.8),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// WALKING SUN MASCOT
// Draws a spiky-sun body (filled orange, toothed rays), stick legs that walk,
// a waving arm, and a simple cartoon face — matching the loading.gif.
// ══════════════════════════════════════════════════════════════════════════════

class _SunMascot extends StatefulWidget {
  const _SunMascot({this.walking = false, this.size = 140.0});
  final bool   walking;
  final double size;

  @override
  State<_SunMascot> createState() => _SunMascotState();
}

class _SunMascotState extends State<_SunMascot>
    with TickerProviderStateMixin {
  late AnimationController _bobCtrl;
  late AnimationController _walkCtrl;
  late AnimationController _waveCtrl;

  @override
  void initState() {
    super.initState();
    _bobCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _walkCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 520))
      ..repeat();
    _waveCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_SunMascot old) {
    super.didUpdateWidget(old);
    if (old.walking != widget.walking) {
      _bobCtrl.duration = widget.walking
          ? const Duration(milliseconds: 340)
          : const Duration(milliseconds: 1800);
    }
  }

  @override
  void dispose() {
    _bobCtrl.dispose();
    _walkCtrl.dispose();
    _waveCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation:
          Listenable.merge(<Listenable>[_bobCtrl, _walkCtrl, _waveCtrl]),
      builder: (_, __) => CustomPaint(
        size: Size(widget.size, widget.size * 1.38),
        painter: _SunPainter(
          bobT:    _bobCtrl.value,
          walkT:   _walkCtrl.value,
          waveT:   _waveCtrl.value,
          walking: widget.walking,
        ),
      ),
    );
  }
}

class _SunPainter extends CustomPainter {
  const _SunPainter({
    required this.bobT,
    required this.walkT,
    required this.waveT,
    required this.walking,
  });

  final double bobT;
  final double walkT;
  final double waveT;
  final bool   walking;

  static const int    _kSpikes     = 22;
  static const double _kInnerR     = 40.0;
  static const double _kOuterR     = 54.0;
  static const double _kLegLen     = 50.0;
  static const double _kFootLen    = 12.0;
  static const Color  _kBodyOrange = Color(0xFFFF8C00);
  static const Color  _kRimOrange  = Color(0xFFE57200);
  static const Color  _kDarkInk    = Color(0xFF1A1410);

  Paint _fill(Color c) =>
      Paint()..color = c..style = PaintingStyle.fill;

  Paint _ink(double w) => Paint()
    ..color = _kDarkInk
    ..strokeWidth = w
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  /// Build the spiky-sun (gear/cog) path
  Path _sunPath() {
    final Path p = Path();
    for (int i = 0; i < _kSpikes * 2; i++) {
      final double angle  = i * math.pi / _kSpikes - math.pi / 2;
      final double radius = i.isEven ? _kOuterR : _kInnerR;
      final double x = math.cos(angle) * radius;
      final double y = math.sin(angle) * radius;
      if (i == 0) p.moveTo(x, y); else p.lineTo(x, y);
    }
    return p..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double bobAmp = walking ? 5.0 : 3.5;
    final double bob    = math.sin(bobT * math.pi) * bobAmp;
    final double s      = size.width / 130.0;

    canvas.save();
    canvas.translate(size.width / 2, size.height * 0.43 + bob * s);
    canvas.scale(s, s);

    _drawLegs(canvas);
    _drawArm(canvas);
    _drawBody(canvas);
    _drawFace(canvas);

    canvas.restore();
  }

  void _drawBody(Canvas canvas) {
    final Path sun = _sunPath();
    canvas.drawPath(sun, _fill(_kBodyOrange));
    canvas.drawPath(sun,
        Paint()
          ..color = _kRimOrange
          ..strokeWidth = 1.6
          ..style = PaintingStyle.stroke);
  }

  void _drawLegs(Canvas canvas) {
    final Paint p = _ink(4.4);

    // Left / right legs swing in opposite phase when walking
    final double swing =
        walking ? math.sin(walkT * 2 * math.pi) * 22.0 : 0.0;
    final double lA = (swing * math.pi) / 180.0;

    // Left leg
    canvas.save();
    canvas.translate(-11, _kInnerR - 2);
    canvas.rotate(lA);
    canvas.drawLine(Offset.zero, Offset(0, _kLegLen), p);
    canvas.drawLine(
        Offset(0, _kLegLen), Offset(-_kFootLen, _kLegLen), p);
    canvas.restore();

    // Right leg (opposite phase)
    canvas.save();
    canvas.translate(11, _kInnerR - 2);
    canvas.rotate(-lA);
    canvas.drawLine(Offset.zero, Offset(0, _kLegLen), p);
    canvas.drawLine(
        Offset(0, _kLegLen), Offset(_kFootLen, _kLegLen), p);
    canvas.restore();
  }

  void _drawArm(Canvas canvas) {
    final Paint p = _ink(4.4);
    final double waveAngle = (waveT * 2.0 - 1.0) * 0.45;

    canvas.save();
    canvas.translate(_kInnerR - 2, -6);
    canvas.rotate(waveAngle);

    final Path arm = Path()
      ..moveTo(0, 0)
      ..cubicTo(16, -14, 26, -26, 30, -40);
    canvas.drawPath(arm, p);

    const Offset tip = Offset(30, -40);
    final double base = math.atan2(-40.0, 30.0);
    for (int i = -1; i <= 1; i++) {
      final double a = base + i * 0.28;
      canvas.drawLine(tip,
          Offset(tip.dx + math.cos(a) * 10, tip.dy + math.sin(a) * 10),
          p);
    }
    canvas.restore();
  }

  void _drawFace(Canvas canvas) {
    final Paint whiteFill = _fill(Colors.white);
    final Paint darkFill  = _fill(_kDarkInk);
    final Paint outline   = Paint()
      ..color = _kDarkInk
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    // Left eye
    canvas.drawOval(
        Rect.fromCenter(
            center: const Offset(-13, -8), width: 12, height: 15),
        whiteFill);
    canvas.drawOval(
        Rect.fromCenter(
            center: const Offset(-13, -8), width: 12, height: 15),
        outline);
    canvas.drawCircle(const Offset(-12, -7), 4.2, darkFill);

    // Right eye
    canvas.drawOval(
        Rect.fromCenter(
            center: const Offset(11, -8), width: 12, height: 15),
        whiteFill);
    canvas.drawOval(
        Rect.fromCenter(
            center: const Offset(11, -8), width: 12, height: 15),
        outline);
    canvas.drawCircle(const Offset(12, -7), 4.2, darkFill);

    // Smile
    final Path smile = Path()
      ..moveTo(-14, 12)
      ..cubicTo(-7, 22, 7, 22, 14, 12);
    canvas.drawPath(smile, _ink(2.6));
  }

  @override
  bool shouldRepaint(_SunPainter old) =>
      old.bobT != bobT || old.walkT != walkT ||
      old.waveT != waveT || old.walking != walking;
}

// ══════════════════════════════════════════════════════════════════════════════
// BOUNCING DOTS
// ══════════════════════════════════════════════════════════════════════════════

class _BouncingDots extends StatefulWidget {
  const _BouncingDots({this.color = _kOrange});
  final Color color;

  @override
  State<_BouncingDots> createState() => _BouncingDotsState();
}

class _BouncingDotsState extends State<_BouncingDots>
    with TickerProviderStateMixin {
  final List<AnimationController> _ctrls = <AnimationController>[];

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < 3; i++) {
      final AnimationController c = AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 560));
      _ctrls.add(c);
      Future<void>.delayed(Duration(milliseconds: i * 160),
          () { if (mounted) c.repeat(reverse: true); });
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(3, (i) => AnimatedBuilder(
        animation: _ctrls[i],
        builder: (_, __) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Transform.translate(
            offset: Offset(0, -(_ctrls[i].value * 10)),
            child: Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                  color: widget.color.withOpacity(0.75),
                  shape: BoxShape.circle),
            ),
          ),
        ),
      )),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// PILL BADGE  (coloured capsule — matches the health app's segment pills)
// ══════════════════════════════════════════════════════════════════════════════

class _PillBadge extends StatelessWidget {
  const _PillBadge({required this.color, required this.label});
  final Color  color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(99)),
      child: Text(label,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _kDark,
              letterSpacing: 0.2)),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// DARK PILL BUTTON  (matches health app's "Plan check-up" style)
// ══════════════════════════════════════════════════════════════════════════════

class _DarkPillButton extends StatelessWidget {
  const _DarkPillButton(
      {required this.label, required this.onPressed, this.loading = false});
  final String       label;
  final VoidCallback? onPressed;
  final bool         loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        style: TextButton.styleFrom(
          backgroundColor: _kDark,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 17),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(99)),
        ),
        onPressed: loading ? null : onPressed,
        child: loading
            ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2.2, color: Colors.white))
            : Text(label,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1)),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// QUESTION MODEL
// ══════════════════════════════════════════════════════════════════════════════

enum _QuestionType { scale, choice, open }

class _Question {
  const _Question({
    required this.id,
    required this.prompt,
    required this.type,
    this.options   = const <String>[],
    this.scaleLow  = "",
    this.scaleHigh = "",
  });
  final String        id;
  final String        prompt;
  final _QuestionType type;
  final List<String>  options;
  final String        scaleLow;
  final String        scaleHigh;
}

// ══════════════════════════════════════════════════════════════════════════════
// LOADING SCREEN — Splash 1
// App launch splash: bold centered layout — large walking SunMascot,
// orange gradient AdaptEd wordmark, tagline, animated orange progress pill.
// Warm cream background, no visual clutter — strong first impression.
// ══════════════════════════════════════════════════════════════════════════════

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeCtrl;
  late AnimationController _slideCtrl;
  late AnimationController _progressCtrl;
  late AnimationController _glowCtrl;

  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..forward();
    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..forward();
    _progressCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat();
    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat(reverse: true);

    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.10),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _glowAnim = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _slideCtrl.dispose();
    _progressCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        children: <Widget>[

          // ── Pulsing radial glow behind mascot ──────────────────────────
          AnimatedBuilder(
            animation: _glowAnim,
            builder: (_, __) => Positioned(
              top: MediaQuery.of(context).size.height * 0.18,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: <Color>[
                        _kOrange.withOpacity(0.13 + _glowAnim.value * 0.09),
                        _kBg.withOpacity(0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Main content ────────────────────────────────────────────────
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[

                      // ── Walking sun mascot (large) ─────────────────────
                      const _SunMascot(walking: true, size: 200),
                      const SizedBox(height: 36),

                      // ── AdaptEd orange gradient wordmark ───────────────
                      ShaderMask(
                        shaderCallback: (Rect bounds) =>
                            const LinearGradient(
                          colors: <Color>[
                            Color(0xFFFF8C00),
                            Color(0xFFFFB347),
                          ],
                        ).createShader(bounds),
                        child: const Text(
                          "AdaptEd",
                          style: TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -1.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // ── Tagline ────────────────────────────────────────
                      const Text(
                        "Your AI-powered adaptive study companion",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: _kMuted,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.1,
                        ),
                      ),

                      const SizedBox(height: 52),

                      // ── Animated orange progress pill ──────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 72),
                        child: AnimatedBuilder(
                          animation: _progressCtrl,
                          builder: (_, __) => ClipRRect(
                            borderRadius: BorderRadius.circular(99),
                            child: LinearProgressIndicator(
                              value: _progressCtrl.value,
                              minHeight: 5,
                              backgroundColor: _kOrange.withOpacity(0.14),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  _kOrange),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// WELCOME SPLASH — Splash 2
// Shows briefly after the user successfully logs in for the first time
// in a session. SunMascot waving + personalised greeting + smooth fade.
// ══════════════════════════════════════════════════════════════════════════════

class WelcomeSplashScreen extends StatefulWidget {
  const WelcomeSplashScreen({super.key, required this.displayName});
  final String displayName;

  @override
  State<WelcomeSplashScreen> createState() => _WelcomeSplashScreenState();
}

class _WelcomeSplashScreenState extends State<WelcomeSplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeCtrl;
  late AnimationController _slideCtrl;
  late AnimationController _scaleCtrl;

  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..forward();
    _slideCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..forward();
    _scaleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700))
      ..forward();

    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
    _scaleAnim = Tween<double>(begin: 0.88, end: 1.0)
        .animate(CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeOutBack));
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _slideCtrl.dispose();
    _scaleCtrl.dispose();
    super.dispose();
  }

  String get _greeting {
    final int h = DateTime.now().hour;
    if (h < 12) return "Good morning";
    if (h < 17) return "Good afternoon";
    return "Good evening";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        children: <Widget>[

          // ── Soft orange glow at top ────────────────────────────────────
          Positioned(
            top: -80,
            left: 0,
            right: 0,
            child: Container(
              height: 280,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 1.0,
                  colors: <Color>[
                    _kOrange.withOpacity(0.18),
                    _kBg.withOpacity(0),
                  ],
                ),
              ),
            ),
          ),

          // ── Floating pills (subtle) ────────────────────────────────────
          Positioned(
            top: 48,
            right: -16,
            child: Transform.rotate(
              angle: 0.4,
              child: Container(
                width: 72,
                height: 28,
                decoration: BoxDecoration(
                  color: _kYellow.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ),
          Positioned(
            top: 100,
            left: -10,
            child: Transform.rotate(
              angle: -0.5,
              child: Container(
                width: 56,
                height: 22,
                decoration: BoxDecoration(
                  color: _kPink.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
          ),

          // ── Main content ───────────────────────────────────────────────
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: ScaleTransition(
                  scale: _scaleAnim,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[

                          // Waving mascot
                          const _SunMascot(walking: false, size: 160),
                          const SizedBox(height: 24),

                          // AdaptEd wordmark
                          ShaderMask(
                            shaderCallback: (Rect b) => const LinearGradient(
                              colors: <Color>[
                                Color(0xFFFF8C00),
                                Color(0xFFFFB347),
                              ],
                            ).createShader(b),
                            child: const Text(
                              "AdaptEd",
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: -0.7,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Greeting
                          Text(
                            "$_greeting, ${widget.displayName}! 👋",
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: _kDark,
                              letterSpacing: -0.4,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            "Your study companion is ready.\nLet's make today count.",
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: _kMuted,
                              height: 1.5,
                            ),
                          ),

                          const SizedBox(height: 28),

                          // Animated pill row
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: const <Widget>[
                              _PillBadge(color: _kYellow, label: "Focus"),
                              _PillBadge(color: _kPink,   label: "Rest"),
                              _PillBadge(color: _kBlue,   label: "Energy"),
                              _PillBadge(color: _kGreen,  label: "Habits"),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// AUTH SCREEN
// Health-app inspired: cream background, pill decoration, white card form,
// dark pill button, pastel error banner, walking sun for loading overlay.
// ══════════════════════════════════════════════════════════════════════════════

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  bool _isLogin = true;
  bool _loading = false;
  bool _obscurePassword = true;
  bool _awaitingVerification = false;

  final TextEditingController _email    = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _username = TextEditingController();
  String? _error;

  late AnimationController _shakeCtrl;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 400));
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _username.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _shake() => _shakeCtrl.forward(from: 0);

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    try {
      if (_isLogin) {
        final UserCredential cred =
            await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text.trim(),
        );
        if (cred.user != null && !cred.user!.emailVerified) {
          await FirebaseAuth.instance.signOut();
          setState(() => _error =
              "Email not verified. Check your inbox, then log in again.");
          _shake();
        }
      } else {
        final String username = _username.text.trim();
        if (username.isEmpty || username.length < 3) {
          setState(() {
            _error = "Display name must be at least 3 characters.";
            _loading = false;
          });
          _shake();
          return;
        }
        final UserCredential cred =
            await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _email.text.trim(),
          password: _password.text.trim(),
        );
        await cred.user?.updateDisplayName(username);
        if (cred.user != null) {
          await FirestoreRepository(cred.user!.uid).saveUsername(username);
        }
        try {
          await cred.user?.sendEmailVerification();
          if (mounted) setState(() => _awaitingVerification = true);
        } catch (e) {
          setState(
              () => _error = "Account created but email failed: $e");
        }
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = e.message ?? e.code);
      _shake();
    } catch (e) {
      setState(() => _error = "$e");
      _shake();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_awaitingVerification) return _verificationScreen();

    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        children: <Widget>[

          // ── Background floating pill decorations ─────────────────────────
          Positioned(top: 52, right: -18,
              child: Transform.rotate(angle: 0.4,
                child: Container(width: 78, height: 30,
                  decoration: BoxDecoration(
                    color: _kYellow.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(99))))),
          Positioned(top: 102, right: 38,
              child: Transform.rotate(angle: -0.2,
                child: Container(width: 48, height: 22,
                  decoration: BoxDecoration(
                    color: _kPink.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(99))))),
          Positioned(top: 74, left: -12,
              child: Transform.rotate(angle: -0.5,
                child: Container(width: 62, height: 24,
                  decoration: BoxDecoration(
                    color: _kBlue.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(99))))),
          Positioned(top: 138, left: 28,
              child: Transform.rotate(angle: 0.3,
                child: Container(width: 36, height: 18,
                  decoration: BoxDecoration(
                    color: _kGreen.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(99))))),

          // ── Main scrollable form ─────────────────────────────────────────
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[

                      // Mascot (idle walking = false)
                      const _SunMascot(size: 148),
                      const SizedBox(height: 2),

                      // Headline
                      Text(
                        _isLogin ? "Welcome back 👋" : "Join AdaptEd",
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: _kDark,
                          letterSpacing: -0.6,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _isLogin
                            ? "Log in to AdaptEd"
                            : "Create your account to get started",
                        style: const TextStyle(
                            fontSize: 13,
                            color: _kMuted,
                            fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 22),

                      // ── Form card (white rounded rect) ─────────────────
                      AnimatedBuilder(
                        animation: _shakeCtrl,
                        builder: (_, Widget? child) {
                          final double dx = math.sin(
                                  _shakeCtrl.value * math.pi * 5) *
                              6.0;
                          return Transform.translate(
                              offset: Offset(dx, 0), child: child);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: _kSurface,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: _kDark.withOpacity(0.06),
                                blurRadius: 28,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[

                              if (!_isLogin) ...<Widget>[
                                TextField(
                                  controller: _username,
                                  decoration: _fieldStyle("Display name",
                                      icon: Icons.person_outline_rounded),
                                  style: const TextStyle(
                                      fontSize: 14, color: _kDark),
                                ),
                                const SizedBox(height: 12),
                              ],

                              TextField(
                                controller: _email,
                                keyboardType:
                                    TextInputType.emailAddress,
                                decoration: _fieldStyle("Email",
                                    icon: Icons.mail_outline_rounded),
                                style: const TextStyle(
                                    fontSize: 14, color: _kDark),
                              ),
                              const SizedBox(height: 12),

                              TextField(
                                controller: _password,
                                obscureText: _obscurePassword,
                                style: const TextStyle(
                                    fontSize: 14, color: _kDark),
                                decoration: _fieldStyle("Password",
                                    icon: Icons.lock_outline_rounded)
                                  .copyWith(
                                    suffixIcon: GestureDetector(
                                      onTap: () => setState(() =>
                                          _obscurePassword =
                                              !_obscurePassword),
                                      child: Icon(
                                        _obscurePassword
                                            ? Icons
                                                .visibility_off_outlined
                                            : Icons.visibility_outlined,
                                        color: _kMuted, size: 18),
                                    ),
                                  ),
                              ),

                              // Pastel pink error banner
                              if (_error != null) ...<Widget>[
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 11),
                                  decoration: BoxDecoration(
                                    color: _kPink.withOpacity(0.55),
                                    borderRadius:
                                        BorderRadius.circular(14),
                                  ),
                                  child: Row(
                                    children: <Widget>[
                                      const Icon(
                                          Icons.error_outline_rounded,
                                          color: Color(0xFFB03060),
                                          size: 16),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(_error!,
                                          style: const TextStyle(
                                              color: Color(0xFF8B1A3A),
                                              fontSize: 12,
                                              fontWeight:
                                                  FontWeight.w500)),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              const SizedBox(height: 22),

                              // Dark pill submit button
                              _DarkPillButton(
                                label: _isLogin
                                    ? "Log in"
                                    : "Create Account",
                                loading: _loading,
                                onPressed: _submit,
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Toggle link
                      GestureDetector(
                        onTap: _loading
                            ? null
                            : () => setState(() {
                                  _isLogin = !_isLogin;
                                  _error = null;
                                }),
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(
                                fontSize: 13,
                                color: _kMuted,
                                fontWeight: FontWeight.w500),
                            children: <TextSpan>[
                              TextSpan(
                                  text: _isLogin
                                      ? "Don't have an account?  "
                                      : "Already have an account?  "),
                              TextSpan(
                                text:
                                    _isLogin ? "Register" : "Log in",
                                style: const TextStyle(
                                  color: _kOrange,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),

                      // Category pill flair
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: const <Widget>[
                          _PillBadge(color: _kYellow, label: "Focus"),
                          _PillBadge(color: _kPink,   label: "Rest"),
                          _PillBadge(color: _kBlue,   label: "Energy"),
                          _PillBadge(color: _kGreen,  label: "Habits"),
                          _PillBadge(color: _kSage,   label: "Lifestyle"),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Loading overlay: walking sun + bouncing dots ─────────────────
          if (_loading)
            Container(
              color: _kBg.withOpacity(0.94),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const _SunMascot(walking: true, size: 200),
                    const SizedBox(height: 14),
                    Text(
                      _isLogin
                          ? "Signing you in…"
                          : "Creating your account…",
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: _kDark,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const _BouncingDots(),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Email verification card ────────────────────────────────────────────────
  Widget _verificationScreen() {
    return Scaffold(
      backgroundColor: _kBg,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.circular(28),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                      color: _kDark.withOpacity(0.06),
                      blurRadius: 28,
                      offset: const Offset(0, 8)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const _SunMascot(size: 120),
                  const SizedBox(height: 12),
                  const Text("Check your inbox ✉️",
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: _kDark,
                          letterSpacing: -0.4)),
                  const SizedBox(height: 10),
                  Text(
                    "We sent a verification link to ${_email.text.trim()}.\n\n"
                    "Click the link, then come back and log in.",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: _kMuted, fontSize: 13, height: 1.6)),
                  const SizedBox(height: 20),
                  // Yellow tip banner
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: _kYellow.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Row(
                      children: <Widget>[
                        Icon(Icons.tips_and_updates_outlined,
                            color: _kDark, size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Check your spam folder if you don't see it.",
                            style: TextStyle(
                                fontSize: 12,
                                color: _kDark,
                                fontWeight: FontWeight.w500)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _DarkPillButton(
                    label: "Go to Login",
                    onPressed: () => setState(() {
                      _awaitingVerification = false;
                      _isLogin = true;
                    }),
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

// ══════════════════════════════════════════════════════════════════════════════
// ASSESSMENT ONBOARDING SCREEN
// ══════════════════════════════════════════════════════════════════════════════

class AssessmentOnboardingScreen extends StatefulWidget {
  const AssessmentOnboardingScreen({super.key, required this.repo});
  final FirestoreRepository repo;

  @override
  State<AssessmentOnboardingScreen> createState() =>
      _AssessmentOnboardingScreenState();
}

class _AssessmentOnboardingScreenState
    extends State<AssessmentOnboardingScreen>
    with SingleTickerProviderStateMixin {
  late final Map<String, dynamic> _answers = _buildDefaultAnswers();
  int  _index   = 0;
  bool _started = false;
  bool _saving  = false;

  final Map<String, TextEditingController> _openControllers =
      <String, TextEditingController>{};

  static const List<Color> _kCatColors = <Color>[
    _kYellow, _kPink, _kBlue, _kGreen, _kSage,
  ];

  static final List<_Question> _questions = <_Question>[
    _qScale("focus_duration",
        "How long can you stay focused without distraction?",
        "<10 mins", "2+ hours"),
    _qScale("focus_distraction_frequency",
        "How often do you get distracted while studying?",
        "Rarely", "Very often"),
    _qScale("focus_post_study_drain",
        "How mentally drained do you feel after studying?",
        "Not at all", "Extremely drained"),
    _qChoice("focus_study_style", "What study style fits you best?",
        <String>["Long deep sessions", "Short bursts (Pomodoro)", "Random / inconsistent"]),
    _qChoice("focus_environment", "What environment helps you focus most?",
        <String>["Silence", "Music", "Background noise"]),
    _qScale("energy_morning_productive",
        "How productive are you in the morning?",
        "Not at all", "Very productive"),
    _qScale("energy_night_productive",
        "How productive are you at night?",
        "Not at all", "Very productive"),
    _qScale("energy_low_during_day",
        "How often do you feel low energy during the day?",
        "Rarely", "Very often"),
    _qChoice("energy_peak_time", "When do you feel your peak energy?",
        <String>["Morning", "Afternoon", "Night", "It changes a lot"]),
    _qScale("rest_sleep_quality",
        "How well-rested do you feel after sleep?",
        "Not rested", "Fully rested"),
    _qScale("rest_break_frequency",
        "How often do you take breaks while working?",
        "Never", "Very often"),
    _qScale("rest_guilt_when_resting",
        "How guilty do you feel when resting?",
        "Not guilty", "Very guilty"),
    _qChoice("rest_sleep_hours", "Average sleep per night:",
        <String>["Less than 5 hours", "5–6 hours", "7–8 hours", "9+ hours"]),
    _qScale("social_after_interaction_energy",
        "After social interaction, how energized do you feel?",
        "Drained", "Energized"),
    _qScale("social_interruptions_impact",
        "How much do interruptions affect your focus?",
        "Not at all", "A lot"),
    _qChoice("social_work_preference", "You prefer to work:",
        <String>["Alone", "With others", "Depends"]),
    _qScale("thinking_idea_frequency",
        "How often do you come up with new ideas?",
        "Rarely", "Very often"),
    _qScale("thinking_structure_preference",
        "How much do you prefer structure when working?",
        "No structure", "Very structured"),
    _qChoice("thinking_problem_style", "When solving problems, you:",
        <String>["Follow clear steps", "Experiment freely", "Mix both"]),
    _qScale("lifestyle_exercise_frequency",
        "How often do you exercise or move?", "Never", "Daily"),
    _qScale("lifestyle_physical_effect_on_focus",
        "How much does your physical state affect your focus?",
        "Not at all", "A lot"),
    _qScale("lifestyle_physically_tired",
        "How often do you feel physically tired?", "Rarely", "Very often"),
    _qScale("habits_phone_checking",
        "How often do you check your phone while working?",
        "Rarely", "Constantly"),
    _qScale("habits_procrastination",
        "How often do you procrastinate?", "Rarely", "Always"),
    _qChoice("habits_biggest_distraction", "Your biggest distraction is:",
        <String>["Phone", "Thoughts", "People", "Environment"]),
    _qScale("motivation_task_drive",
        "How motivated do you feel to complete tasks?",
        "Not motivated", "Very motivated"),
    _qScale("motivation_routine_consistency",
        "How consistent are you with your routines?",
        "Not consistent", "Very consistent"),
    _qChoice("motivation_driver", "What drives you more?",
        <String>["Deadlines", "Personal goals", "Rewards", "Pressure"]),
    _qChoice("motivation_planning_style", "You prefer:",
        <String>["Strict schedule", "Flexible planning", "No plan"]),
    _qOpen("reflection_productivity_blocker",
        "What usually stops you from being productive?"),
    _qOpen("reflection_habit_to_improve",
        "What habit do you want to improve the most?"),
    _qOpen("reflection_when_best", "When do you feel at your best?"),
    _qOpen("reflection_ideal_day", "Describe your ideal productive day."),
  ];

  static Map<String, dynamic> _buildDefaultAnswers() {
    final Map<String, dynamic> d = <String, dynamic>{};
    for (final _Question q in _questions) {
      if (q.type == _QuestionType.scale) d[q.id] = 3;
    }
    return d;
  }

  static _Question _qScale(String id, String p, String lo, String hi) =>
      _Question(id: id, prompt: p, type: _QuestionType.scale,
          scaleLow: lo, scaleHigh: hi);
  static _Question _qChoice(String id, String p, List<String> opts) =>
      _Question(id: id, prompt: p, type: _QuestionType.choice,
          options: opts);
  static _Question _qOpen(String id, String p) =>
      _Question(id: id, prompt: p, type: _QuestionType.open);

  TextEditingController _controllerFor(String id) {
    return _openControllers.putIfAbsent(id, () {
      final c =
          TextEditingController(text: (_answers[id] ?? "") as String);
      c.addListener(() => _answers[id] = c.text);
      return c;
    });
  }

  @override
  void initState() => super.initState();

  @override
  void dispose() {
    for (final c in _openControllers.values) c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    // ── Intro splash ──────────────────────────────────────────────────────────
    if (!_started) {
      return Scaffold(
        backgroundColor: _kBg,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const _SunMascot(size: 170),
                  const SizedBox(height: 24),
                  const Text(
                    "What you do daily\nshapes who you become.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: _kDark,
                      height: 1.25,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Answer a few questions so we can\npersonalise your experience.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: _kMuted, fontSize: 14,
                        height: 1.5, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8, runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: const <Widget>[
                      _PillBadge(color: _kYellow, label: "Focus"),
                      _PillBadge(color: _kPink,   label: "Rest"),
                      _PillBadge(color: _kBlue,   label: "Energy"),
                      _PillBadge(color: _kGreen,  label: "Habits"),
                      _PillBadge(color: _kSage,   label: "Lifestyle"),
                    ],
                  ),
                  const SizedBox(height: 36),
                  _DarkPillButton(
                    label: "Start Self-Assessment",
                    onPressed: () => setState(() => _started = true),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // ── Question flow ─────────────────────────────────────────────────────────
    final _Question q        = _questions[_index];
    final double    progress = (_index + 1) / _questions.length;
    final int       pct      = (progress * 100).round();
    final Color     catColor = _kCatColors[_index % _kCatColors.length];

    return Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[

              // ── Top bar ───────────────────────────────────────────────────
              Row(
                children: <Widget>[
                  if (_index > 0)
                    GestureDetector(
                      onTap: () => setState(() => _index -= 1),
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: _kSurface,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                                color: _kDark.withOpacity(0.06),
                                blurRadius: 8,
                                offset: const Offset(0, 2))
                          ],
                        ),
                        child: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 16, color: _kDark),
                      ),
                    )
                  else
                    const SizedBox(width: 40),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                        color: catColor,
                        borderRadius: BorderRadius.circular(99)),
                    child: Text("$pct% done",
                        style: const TextStyle(
                            fontSize: 12,
                            color: _kDark,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Progress bar (colour = current category)
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: _kDark.withOpacity(0.08),
                  valueColor: AlwaysStoppedAnimation<Color>(catColor),
                ),
              ),

              const SizedBox(height: 22),

              Text(
                "Question ${_index + 1} of ${_questions.length}",
                style: const TextStyle(
                    fontSize: 11,
                    color: _kMuted,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8),
              ),
              const SizedBox(height: 8),
              Text(q.prompt,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: _kDark,
                    height: 1.3,
                    letterSpacing: -0.3,
                  )),

              const SizedBox(height: 22),
              Expanded(child: _questionBody(q, catColor)),
              const SizedBox(height: 12),

              _DarkPillButton(
                label: _index == _questions.length - 1
                    ? "Finish 🎉"
                    : "Continue",
                loading: _saving,
                onPressed: _saving ? null : () => _next(q),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _questionBody(_Question q, Color catColor) {
    switch (q.type) {

      case _QuestionType.scale:
        final int value = (_answers[q.id] ?? 3) as int;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(q.scaleLow,
                    style: const TextStyle(
                        fontSize: 11, color: _kMuted,
                        fontWeight: FontWeight.w600)),
                Text(q.scaleHigh,
                    style: const TextStyle(
                        fontSize: 11, color: _kMuted,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 10),
            SliderTheme(
              data: SliderThemeData(
                trackHeight: 7,
                activeTrackColor: catColor,
                inactiveTrackColor: _kDark.withOpacity(0.08),
                thumbColor: _kDark,
                overlayColor: _kDark.withOpacity(0.08),
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 11),
              ),
              child: Slider(
                value: value.toDouble(),
                min: 1, max: 5, divisions: 4,
                onChanged: (v) =>
                    setState(() => _answers[q.id] = v.toInt()),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List<Widget>.generate(5, (i) {
                final bool active = (i + 1) == value;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: active ? 36 : 26,
                  height: active ? 36 : 26,
                  decoration: BoxDecoration(
                    color: active ? _kDark : _kSurface,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: active
                          ? _kDark
                          : _kDark.withOpacity(0.10),
                      width: 1.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text("${i + 1}",
                      style: TextStyle(
                        fontSize: active ? 14 : 11,
                        color: active ? Colors.white : _kMuted,
                        fontWeight: FontWeight.w700,
                      )),
                );
              }),
            ),
          ],
        );

      case _QuestionType.choice:
        final String? sel = _answers[q.id] as String?;
        return ListView(
          children: q.options.asMap().entries.map((e) {
            final bool  isSel    = sel == e.value;
            final Color chipCol =
                _kCatColors[e.key % _kCatColors.length];
            return GestureDetector(
              onTap: () =>
                  setState(() => _answers[q.id] = e.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 16),
                decoration: BoxDecoration(
                  color: isSel ? _kDark : _kSurface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isSel
                        ? _kDark
                        : _kDark.withOpacity(0.08),
                    width: isSel ? 0 : 1.5,
                  ),
                  boxShadow: isSel
                      ? <BoxShadow>[
                          BoxShadow(
                              color: _kDark.withOpacity(0.18),
                              blurRadius: 14,
                              offset: const Offset(0, 4))
                        ]
                      : null,
                ),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 10, height: 10,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: isSel
                            ? Colors.white.withOpacity(0.45)
                            : chipCol,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Text(e.value,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSel
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isSel ? Colors.white : _kDark,
                          )),
                    ),
                    if (isSel)
                      const Icon(Icons.check_circle_rounded,
                          color: Colors.white, size: 18),
                  ],
                ),
              ),
            );
          }).toList(),
        );

      case _QuestionType.open:
        return TextField(
          controller: _controllerFor(q.id),
          maxLines: 6,
          style: const TextStyle(fontSize: 14, color: _kDark),
          decoration: InputDecoration(
            hintText: "Type your answer here…",
            hintStyle: const TextStyle(
                color: _kMuted, fontSize: 13),
            filled: true,
            fillColor: _kOrangeSoft,
            contentPadding: const EdgeInsets.all(18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18),
              borderSide:
                  const BorderSide(color: _kOrange, width: 1.8),
            ),
          ),
        );
    }
  }

  Future<void> _next(_Question q) async {
    if (q.type == _QuestionType.choice && _answers[q.id] == null)
      return;
    if (q.type == _QuestionType.open &&
        ((_answers[q.id] ?? "") as String).trim().isEmpty) return;

    if (_index < _questions.length - 1) {
      setState(() => _index += 1);
      return;
    }
    setState(() => _saving = true);
    await widget.repo.completeAssessment(answers: _answers);
    if (mounted) setState(() => _saving = false);
  }
}
