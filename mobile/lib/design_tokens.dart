import "dart:math" as math;

import "package:flutter/material.dart";

// ══════════════════════════════════════════════════════════════════════════════
// DESIGN TOKENS — AdaptEd Design System
//
// Warm cream + orange palette — familiar, energetic, student-friendly.
// Every screen in the app should import this file and use these tokens
// instead of ad-hoc Material colours.
// ══════════════════════════════════════════════════════════════════════════════

// ── Colours ──────────────────────────────────────────────────────────────────

const Color kBg         = Color(0xFFF7F1E8);   // warm cream — main background
const Color kSurface    = Color(0xFFFFFFFF);   // white cards / surfaces
const Color kDark       = Color(0xFF1A1410);   // near-black (text, pill buttons)
const Color kMuted      = Color(0xFF9C8E7A);   // warm muted text
const Color kOrange     = Color(0xFFFF8C00);   // primary accent — orange
const Color kOrangeSoft = Color(0xFFFFF0D6);   // soft orange — field fill
const Color kYellow     = Color(0xFFFFD84D);   // pill accent — focus
const Color kPink       = Color(0xFFF2C4CE);   // pill accent — rest
const Color kBlue       = Color(0xFFBDD4E8);   // pill accent — social
const Color kGreen      = Color(0xFFA8C5A0);   // pill accent — energy
const Color kSage       = Color(0xFFB5C9A0);   // pill accent — lifestyle

// Semantic aliases
const Color kSuccess    = Color(0xFF5BA55B);
const Color kError      = Color(0xFFB03060);
const Color kErrorBg    = Color(0xFFFCE8EF);

// ── Typography helpers ───────────────────────────────────────────────────────

const TextStyle kHeadline = TextStyle(
  fontSize: 28,
  fontWeight: FontWeight.w900,
  color: kDark,
  letterSpacing: -0.6,
  height: 1.1,
);

const TextStyle kTitle = TextStyle(
  fontSize: 20,
  fontWeight: FontWeight.w800,
  color: kDark,
  letterSpacing: -0.3,
  height: 1.3,
);

const TextStyle kSubtitle = TextStyle(
  fontSize: 13,
  fontWeight: FontWeight.w500,
  color: kMuted,
);

const TextStyle kBody = TextStyle(
  fontSize: 14,
  fontWeight: FontWeight.w500,
  color: kDark,
);

const TextStyle kCaption = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w600,
  color: kMuted,
  letterSpacing: 0.2,
);

const TextStyle kSectionLabel = TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w700,
  color: kMuted,
  letterSpacing: 0.8,
);

// ── Input decoration ─────────────────────────────────────────────────────────

InputDecoration locketFieldStyle(String label, {IconData? icon, Widget? suffixIcon}) {
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(
        color: kMuted, fontSize: 13, fontWeight: FontWeight.w500),
    prefixIcon:
        icon != null ? Icon(icon, color: kOrange, size: 18) : null,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: kOrangeSoft,
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
      borderSide: const BorderSide(color: kOrange, width: 1.8),
    ),
  );
}

// ── Locket Card ──────────────────────────────────────────────────────────────

class LocketCard extends StatelessWidget {
  const LocketCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.color,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? kSurface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: kDark.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ── Dark Pill Button ─────────────────────────────────────────────────────────

class DarkPillButton extends StatelessWidget {
  const DarkPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        style: TextButton.styleFrom(
          backgroundColor: kDark,
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
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(icon, size: 16),
                    const SizedBox(width: 8),
                  ],
                  Text(label,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1)),
                ],
              ),
      ),
    );
  }
}

// ── Outline Pill Button ──────────────────────────────────────────────────────

class OutlinePillButton extends StatelessWidget {
  const OutlinePillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = kDark,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(99),
            side: BorderSide(color: color.withOpacity(0.3), width: 1.5),
          ),
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 16),
              const SizedBox(width: 8),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ],
        ),
      ),
    );
  }
}

// ── Pill Badge ───────────────────────────────────────────────────────────────

class PillBadge extends StatelessWidget {
  const PillBadge({super.key, required this.color, required this.label, this.icon});
  final Color color;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 12, color: kDark),
            const SizedBox(width: 5),
          ],
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: kDark,
                  letterSpacing: 0.2)),
        ],
      ),
    );
  }
}

// ── Info / Warning / Success Banners ─────────────────────────────────────────

class LocketBanner extends StatelessWidget {
  const LocketBanner({
    super.key,
    required this.message,
    this.icon,
    this.color = kOrangeSoft,
    this.iconColor = kOrange,
    this.textColor = kDark,
  });
  final String message;
  final IconData? icon;
  final Color color;
  final Color iconColor;
  final Color textColor;

  factory LocketBanner.info(String message) => LocketBanner(
        message: message,
        icon: Icons.tips_and_updates_outlined,
        color: kOrangeSoft,
        iconColor: kOrange,
      );

  factory LocketBanner.warning(String message) => LocketBanner(
        message: message,
        icon: Icons.warning_amber_rounded,
        color: const Color(0xFFFFF3CD),
        iconColor: const Color(0xFFE6A817),
      );

  factory LocketBanner.error(String message) => LocketBanner(
        message: message,
        icon: Icons.error_outline_rounded,
        color: kPink.withOpacity(0.55),
        iconColor: kError,
        textColor: const Color(0xFF8B1A3A),
      );

  factory LocketBanner.success(String message) => LocketBanner(
        message: message,
        icon: Icons.check_circle_outline_rounded,
        color: kGreen.withOpacity(0.35),
        iconColor: kSuccess,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, color: iconColor, size: 16),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(message,
                style: TextStyle(
                    color: textColor, fontSize: 12, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

// ── Stat Pill (for dashboard stats row) ──────────────────────────────────────

class StatPill extends StatelessWidget {
  const StatPill({
    super.key,
    required this.value,
    required this.label,
    required this.color,
  });
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.18),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: <Widget>[
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: kDark)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(fontSize: 10, color: kMuted)),
          ],
        ),
      ),
    );
  }
}

// ── Section Header ───────────────────────────────────────────────────────────

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Container(
          width: 4,
          height: 18,
          margin: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
            color: kOrange,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Expanded(
          child: Text(title,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: kDark,
                  letterSpacing: -0.2)),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// WALKING SUN MASCOT (public, reusable across all screens)
// ══════════════════════════════════════════════════════════════════════════════

class SunMascot extends StatefulWidget {
  const SunMascot({super.key, this.walking = false, this.size = 140.0});
  final bool   walking;
  final double size;

  @override
  State<SunMascot> createState() => _SunMascotState();
}

class _SunMascotState extends State<SunMascot>
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
  void didUpdateWidget(SunMascot old) {
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
    final double swing =
        walking ? math.sin(walkT * 2 * math.pi) * 22.0 : 0.0;
    final double lA = (swing * math.pi) / 180.0;

    canvas.save();
    canvas.translate(-11, _kInnerR - 2);
    canvas.rotate(lA);
    canvas.drawLine(Offset.zero, Offset(0, _kLegLen), p);
    canvas.drawLine(
        Offset(0, _kLegLen), Offset(-_kFootLen, _kLegLen), p);
    canvas.restore();

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

    canvas.drawOval(
        Rect.fromCenter(
            center: const Offset(-13, -8), width: 12, height: 15),
        whiteFill);
    canvas.drawOval(
        Rect.fromCenter(
            center: const Offset(-13, -8), width: 12, height: 15),
        outline);
    canvas.drawCircle(const Offset(-12, -7), 4.2, darkFill);

    canvas.drawOval(
        Rect.fromCenter(
            center: const Offset(11, -8), width: 12, height: 15),
        whiteFill);
    canvas.drawOval(
        Rect.fromCenter(
            center: const Offset(11, -8), width: 12, height: 15),
        outline);
    canvas.drawCircle(const Offset(12, -7), 4.2, darkFill);

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

// ── Bouncing Dots (loading indicator) ────────────────────────────────────────

class BouncingDots extends StatefulWidget {
  const BouncingDots({super.key, this.color = kOrange});
  final Color color;

  @override
  State<BouncingDots> createState() => _BouncingDotsState();
}

class _BouncingDotsState extends State<BouncingDots>
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

// ── Floating Pill Decorations (background flair) ─────────────────────────────

class FloatingPills extends StatelessWidget {
  const FloatingPills({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned(top: 52, right: -18,
            child: Transform.rotate(angle: 0.4,
              child: Container(width: 78, height: 30,
                decoration: BoxDecoration(
                  color: kYellow.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(99))))),
        Positioned(top: 102, right: 38,
            child: Transform.rotate(angle: -0.2,
              child: Container(width: 48, height: 22,
                decoration: BoxDecoration(
                  color: kPink.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(99))))),
        Positioned(top: 74, left: -12,
            child: Transform.rotate(angle: -0.5,
              child: Container(width: 62, height: 24,
                decoration: BoxDecoration(
                  color: kBlue.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(99))))),
        Positioned(top: 138, left: 28,
            child: Transform.rotate(angle: 0.3,
              child: Container(width: 36, height: 18,
                decoration: BoxDecoration(
                  color: kGreen.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(99))))),
      ],
    );
  }
}

// ── Category pills row ───────────────────────────────────────────────────────

class CategoryPillsRow extends StatelessWidget {
  const CategoryPillsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: <Widget>[
        PillBadge(color: kYellow, label: "Focus"),
        PillBadge(color: kPink,   label: "Rest"),
        PillBadge(color: kBlue,   label: "Energy"),
        PillBadge(color: kGreen,  label: "Habits"),
        PillBadge(color: kSage,   label: "Lifestyle"),
      ],
    );
  }
}
