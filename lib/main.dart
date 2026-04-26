import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:device_preview/device_preview.dart';
import 'AppState.dart';
import 'HomePage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math' as math;

const String SUPABASE_URL = 'https://hlxgzitkkukbumtucsem.supabase.co';
const String SUPABASE_ANON_KEY =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhseGd6aXRra3VrYnVtdHVjc2VtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM4OTgxNDYsImV4cCI6MjA4OTQ3NDE0Nn0.3qehXC9F0SKkaGQ0B8gZnxuuHow6UnnXF2V3zPzlb2M';

SupabaseClient get supabase => Supabase.instance.client;

ValueNotifier<bool> isDarkMode = ValueNotifier(false);
final AppState _appState = AppState();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: SUPABASE_URL, anonKey: SUPABASE_ANON_KEY);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const BudgetFlowApp());
}

// ─── Design System ─────────────────────────────────────────────────────────────
class BF {
  // Brand palette — deep navy + electric teal + warm gold
  static const navy = Color(0xFF0A0E2A);
  static const navyMid = Color(0xFF111535);
  static const navyLight = Color(0xFF1A2055);
  static const teal = Color(0xFF00C9A7);
  static const tealLight = Color(0xFF4DDFCA);
  static const gold = Color(0xFFFFB547);
  static const goldSoft = Color(0xFFFFD28A);
  static const violet = Color(0xFF7B61FF);
  static const red = Color(0xFFFF5A5F);
  static const green = Color(0xFF00C9A7);

  // ── Aliases for backward compatibility with other files ──────────────────
  /// Primary brand accent — electric teal
  static const accent = Color(0xFF00C9A7);

  /// Soft accent — lighter teal/cyan
  static const accentSoft = Color(0xFF4DDFCA);

  /// Primary dark navy (used as BF.primary in HomePage/AccountsPage etc.)
  static const primary = Color(0xFF0A0E2A);

  /// Amber / warning colour
  static const amber = Color(0xFFFFB547);

  // Surfaces
  static const darkBg = Color(0xFF07091D);
  static const darkSurface = Color(0xFF0E1230);
  static const darkCard = Color(0xFF141840);
  static const darkBorder = Color(0xFF252B5C);

  static const lightBg = Color(0xFFF0F4FF);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightBorder = Color(0xFFDDE3F5);
  static const lightText = Color(0xFF0A0E2A);

  static const brandGradient = LinearGradient(
    colors: [Color(0xFF0A0E2A), Color(0xFF0D1442), Color(0xFF0E2060)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const tealGradient = LinearGradient(
    colors: [Color(0xFF00C9A7), Color(0xFF00A8E8)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const goldGradient = LinearGradient(
    colors: [Color(0xFFFFB547), Color(0xFFFF8C42)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static BoxDecoration card(bool isDark) => BoxDecoration(
    color: isDark ? darkCard : lightCard,
    borderRadius: BorderRadius.circular(24),
    border: Border.all(color: isDark ? darkBorder : lightBorder, width: 1),
    boxShadow: isDark
        ? [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ]
        : [
            BoxShadow(
              color: const Color(0xFF7B61FF).withOpacity(0.08),
              blurRadius: 32,
              offset: const Offset(0, 8),
            ),
          ],
  );
}

// ─── App ───────────────────────────────────────────────────────────────────────
class BudgetFlowApp extends StatelessWidget {
  const BudgetFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DevicePreview(
      enabled: true,
      builder: (context) {
        return ValueListenableBuilder<bool>(
          valueListenable: isDarkMode,
          builder: (context, bool darkMode, _) {
            return AppStateScope(
              state: _appState,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                useInheritedMediaQuery: true,
                locale: DevicePreview.locale(context),
                builder: DevicePreview.appBuilder,
                themeMode: darkMode ? ThemeMode.dark : ThemeMode.light,
                theme: _buildTheme(Brightness.light),
                darkTheme: _buildTheme(Brightness.dark),
                initialRoute: '/auth',
                routes: {
                  '/auth': (context) => const AuthPage(),
                  '/settings': (context) => const SettingsPage(),
                },
              ),
            );
          },
        );
      },
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      brightness: brightness,
      fontFamily: 'Poppins',
      scaffoldBackgroundColor: isDark ? BF.darkBg : BF.lightBg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: BF.teal,
        brightness: brightness,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? BF.darkBg : BF.lightBg,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: isDark ? Colors.white : BF.lightText),
        titleTextStyle: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: isDark ? Colors.white : BF.lightText,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: BF.teal,
        selectionColor: BF.teal.withOpacity(0.3),
        selectionHandleColor: BF.teal,
      ),
    );
  }
}

// ─── Auth Page ─────────────────────────────────────────────────────────────────
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> with TickerProviderStateMixin {
  bool isLogin = true;
  bool _loading = false;
  bool _hidePw = true;

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _first = TextEditingController();
  final _last = TextEditingController();

  late AnimationController _floatController;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _first.dispose();
    _last.dispose();
    _floatController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: BF.darkBg,
      body: Stack(
        children: [
          // Deep space background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF04061A),
                  Color(0xFF070B26),
                  Color(0xFF0A0F35),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.5, 1.0],
              ),
            ),
          ),

          // Floating grid lines (subtle)
          CustomPaint(
            size: MediaQuery.of(context).size,
            painter: _GridPainter(),
          ),

          // Animated glow orbs
          _buildOrbs(),

          // Content
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Column(
                children: [
                  _buildLogo(),
                  const SizedBox(height: 36),
                  _buildTabSwitch(),
                  const SizedBox(height: 28),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 380),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.05),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: isLogin
                        ? _buildLoginForm(key: const ValueKey('login'))
                        : _buildSignupForm(key: const ValueKey('signup')),
                  ),
                  const SizedBox(height: 28),
                  _buildDivider(),
                  const SizedBox(height: 22),
                  _buildSocials(),
                  const SizedBox(height: 32),
                  _buildBottomHint(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Logo ──────────────────────────────────────────────────────────────────
  Widget _buildLogo() {
    return AnimatedBuilder(
      animation: _floatController,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, math.sin(_floatController.value * math.pi) * 5),
        child: child,
      ),
      child: Column(
        children: [
          // Logo mark
          AnimatedBuilder(
            animation: _pulseController,
            builder: (_, child) {
              final pulse = _pulseController.value;
              return Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00C9A7), Color(0xFF00A8E8)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: BF.teal.withOpacity(0.2 + pulse * 0.25),
                      blurRadius: 24 + pulse * 20,
                      spreadRadius: pulse * 6,
                    ),
                    BoxShadow(
                      color: const Color(0xFF00A8E8).withOpacity(0.15),
                      blurRadius: 50,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: child,
              );
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Background circle rings
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 1.5,
                    ),
                  ),
                ),
                // Icon
                const Icon(
                  Icons.waterfall_chart_rounded,
                  size: 38,
                  color: Colors.white,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Wordmark
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFFFFFFFF), Color(0xFFB8D4FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(bounds),
            child: const Text(
              'BudgetFlow',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.8,
                fontFamily: 'Poppins',
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Your money, mastered.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withOpacity(0.4),
              fontFamily: 'Poppins',
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab Switch ─────────────────────────────────────────────────────────────
  Widget _buildTabSwitch() {
    return Container(
      height: 50,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
      ),
      child: Row(
        children: [
          _tab('Sign In', isLogin, () => setState(() => isLogin = true)),
          _tab('Sign Up', !isLogin, () => setState(() => isLogin = false)),
        ],
      ),
    );
  }

  Widget _tab(String label, bool active, VoidCallback onTap) => Expanded(
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          gradient: active ? BF.tealGradient : null,
          borderRadius: BorderRadius.circular(12),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: BF.teal.withOpacity(0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: active ? Colors.white : Colors.white.withOpacity(0.4),
            ),
          ),
        ),
      ),
    ),
  );

  // ── Login Form ─────────────────────────────────────────────────────────────
  Widget _buildLoginForm({Key? key}) => Column(
    key: key,
    children: [
      _glassField(
        icon: Icons.mail_outline_rounded,
        hint: 'Email address',
        ctrl: _email,
        keyboard: TextInputType.emailAddress,
      ),
      const SizedBox(height: 14),
      _glassField(
        icon: Icons.lock_outline_rounded,
        hint: 'Password',
        ctrl: _password,
        isPw: true,
      ),
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: _handleForgotPassword,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            'Forgot password?',
            style: TextStyle(
              color: BF.tealLight.withOpacity(0.7),
              fontSize: 12,
              fontFamily: 'Poppins',
            ),
          ),
        ),
      ),
      const SizedBox(height: 18),
      _primaryButton('Sign In', _submit),
    ],
  );

  // ── Sign Up Form ───────────────────────────────────────────────────────────
  Widget _buildSignupForm({Key? key}) => Column(
    key: key,
    children: [
      Row(
        children: [
          Expanded(
            child: _glassField(
              icon: Icons.person_outline_rounded,
              hint: 'First name',
              ctrl: _first,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _glassField(
              icon: Icons.person_outline_rounded,
              hint: 'Last name',
              ctrl: _last,
            ),
          ),
        ],
      ),
      const SizedBox(height: 14),
      _glassField(
        icon: Icons.mail_outline_rounded,
        hint: 'Email address',
        ctrl: _email,
        keyboard: TextInputType.emailAddress,
      ),
      const SizedBox(height: 14),
      _glassField(
        icon: Icons.lock_outline_rounded,
        hint: 'Password',
        ctrl: _password,
        isPw: true,
      ),
      const SizedBox(height: 22),
      _primaryButton('Create Account', _submit),
      const SizedBox(height: 14),
      // Password strength hint
      _passwordHintRow(),
    ],
  );

  Widget _passwordHintRow() => Row(
    children: [
      Icon(
        Icons.info_outline_rounded,
        size: 13,
        color: Colors.white.withOpacity(0.3),
      ),
      const SizedBox(width: 6),
      Text(
        'Use at least 6 characters for a strong password',
        style: TextStyle(
          fontSize: 11,
          color: Colors.white.withOpacity(0.3),
          fontFamily: 'Poppins',
        ),
      ),
    ],
  );

  // ── Glass Input Field ──────────────────────────────────────────────────────
  Widget _glassField({
    required IconData icon,
    required String hint,
    required TextEditingController ctrl,
    bool isPw = false,
    TextInputType? keyboard,
  }) {
    return StatefulBuilder(
      builder: (context, setLocalState) {
        bool localHide = isPw ? _hidePw : false;
        return Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.09), width: 1),
          ),
          child: TextField(
            controller: ctrl,
            obscureText: isPw && localHide,
            keyboardType: keyboard,
            autocorrect: !isPw,
            enableSuggestions: !isPw,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontFamily: 'Poppins',
            ),
            decoration: InputDecoration(
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(icon, size: 18, color: BF.teal.withOpacity(0.6)),
              ),
              suffixIcon: isPw
                  ? IconButton(
                      icon: Icon(
                        localHide
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 17,
                        color: Colors.white.withOpacity(0.3),
                      ),
                      onPressed: () {
                        setState(() => _hidePw = !_hidePw);
                      },
                    )
                  : null,
              hintText: hint,
              hintStyle: TextStyle(
                color: Colors.white.withOpacity(0.28),
                fontSize: 13,
                fontFamily: 'Poppins',
              ),
              filled: false,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 16,
                horizontal: 4,
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Primary CTA Button ─────────────────────────────────────────────────────
  Widget _primaryButton(String label, VoidCallback onPressed) => SizedBox(
    width: double.infinity,
    height: 56,
    child: GestureDetector(
      onTap: _loading ? null : onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          gradient: _loading
              ? null
              : const LinearGradient(
                  colors: [Color(0xFF00C9A7), Color(0xFF00A8E8)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
          color: _loading ? Colors.white.withOpacity(0.1) : null,
          borderRadius: BorderRadius.circular(16),
          boxShadow: _loading
              ? []
              : [
                  BoxShadow(
                    color: BF.teal.withOpacity(0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
        ),
        child: Center(
          child: _loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(BF.teal),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ],
                ),
        ),
      ),
    ),
  );

  // ── Divider ────────────────────────────────────────────────────────────────
  Widget _buildDivider() => Row(
    children: [
      Expanded(
        child: Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.transparent, Colors.white.withOpacity(0.1)],
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Text(
          'or continue with',
          style: TextStyle(
            color: Colors.white.withOpacity(0.3),
            fontSize: 11,
            fontFamily: 'Poppins',
            letterSpacing: 0.5,
          ),
        ),
      ),
      Expanded(
        child: Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.white.withOpacity(0.1), Colors.transparent],
            ),
          ),
        ),
      ),
    ],
  );

  // ── Social Buttons ─────────────────────────────────────────────────────────
  Widget _buildSocials() => Row(
    children: [
      _socialBtn('Google', Icons.g_mobiledata_rounded, const Color(0xFFEA4335)),
      const SizedBox(width: 12),
      _socialBtn('Facebook', Icons.facebook_rounded, const Color(0xFF1877F2)),
      const SizedBox(width: 12),
      _socialBtn('Apple', Icons.apple_rounded, Colors.white),
    ],
  );

  Widget _socialBtn(String label, IconData icon, Color iconColor) => Expanded(
    child: GestureDetector(
      onTap: () {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage(username: 'User')),
        );
      },
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.45),
                fontSize: 10,
                fontWeight: FontWeight.w500,
                fontFamily: 'Poppins',
              ),
            ),
          ],
        ),
      ),
    ),
  );

  // ── Bottom Hint ────────────────────────────────────────────────────────────
  Widget _buildBottomHint() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(
        isLogin ? "Don't have an account?" : 'Already have an account?',
        style: TextStyle(
          color: Colors.white.withOpacity(0.4),
          fontSize: 13,
          fontFamily: 'Poppins',
        ),
      ),
      const SizedBox(width: 4),
      GestureDetector(
        onTap: () => setState(() => isLogin = !isLogin),
        child: ShaderMask(
          shaderCallback: (bounds) => BF.tealGradient.createShader(bounds),
          child: Text(
            isLogin ? 'Sign Up' : 'Sign In',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
              fontFamily: 'Poppins',
            ),
          ),
        ),
      ),
    ],
  );

  // ── Orbs ───────────────────────────────────────────────────────────────────
  Widget _buildOrbs() {
    return AnimatedBuilder(
      animation: _floatController,
      builder: (_, __) {
        final t = _floatController.value;
        return Stack(
          children: [
            Positioned(
              top: -60 + math.sin(t * math.pi) * 20,
              right: -80,
              child: _orb(280, BF.teal, 0.06),
            ),
            Positioned(
              bottom: 100 + math.cos(t * math.pi) * 15,
              left: -100,
              child: _orb(320, BF.violet, 0.07),
            ),
            Positioned(
              top: 350 + math.sin(t * math.pi * 1.5) * 10,
              right: 20,
              child: _orb(100, BF.gold, 0.08),
            ),
            Positioned(
              top: 180,
              left: -60 + math.cos(t * math.pi) * 10,
              child: _orb(160, const Color(0xFF00A8E8), 0.06),
            ),
          ],
        );
      },
    );
  }

  Widget _orb(double size, Color color, double opacity) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [color.withOpacity(opacity * 2), color.withOpacity(0)],
        stops: const [0.0, 1.0],
      ),
    ),
  );

  // ── Logic ──────────────────────────────────────────────────────────────────
  void _handleForgotPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _snack('Enter your email address above first');
      return;
    }
    setState(() => _loading = true);
    try {
      await supabase.auth.resetPasswordForEmail(email);
      _snack('Password reset email sent. Check your inbox.');
    } on AuthException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Could not send reset email. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    final firstName = _first.text.trim();
    final lastName = _last.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _snack('Please fill in all fields');
      return;
    }
    if (!email.contains('@') || !email.contains('.')) {
      _snack('Enter a valid email address');
      return;
    }
    if (!isLogin && (firstName.isEmpty || lastName.isEmpty)) {
      _snack('Enter your full name');
      return;
    }
    if (password.length < 6) {
      _snack('Password must be at least 6 characters');
      return;
    }

    setState(() => _loading = true);

    try {
      if (isLogin) {
        final response = await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );
        if (response.user != null) {
          final userName =
              response.user!.userMetadata?['full_name'] as String? ??
              response.user!.email?.split('@').first ??
              'User';
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => HomePage(username: userName)),
          );
        }
      } else {
        // Save credentials before clearing fields
        final savedEmail = email;
        final savedPassword = password;

        final response = await supabase.auth.signUp(
          email: email,
          password: password,
          data: {
            'first_name': firstName,
            'last_name': lastName,
            'full_name': '$firstName $lastName',
          },
        );

        if (!mounted) return;

        if (response.user != null) {
          _snack('Account created! Signing you in now…');
          setState(() {
            isLogin = true;
            // ✅ Auto-fill email & password on the login screen
            _email.text = savedEmail;
            _password.text = savedPassword;
            _first.clear();
            _last.clear();
          });
        }
      }
    } on AuthException catch (e) {
      if (mounted) _snack(e.message);
    } catch (e) {
      if (mounted) _snack('An unexpected error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline_rounded, color: BF.teal, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: BF.darkCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: BF.teal.withOpacity(0.3), width: 1),
        ),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }
}

// ─── Grid Painter ──────────────────────────────────────────────────────────────
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.025)
      ..strokeWidth = 0.5;

    const step = 60.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter oldDelegate) => false;
}

// ─── Settings Page ─────────────────────────────────────────────────────────────
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? BF.darkBg : BF.lightBg,
      appBar: AppBar(
        backgroundColor: isDark ? BF.darkBg : BF.lightBg,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Settings',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: isDark ? Colors.white : BF.lightText,
          ),
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_rounded,
            color: isDark ? Colors.white : BF.lightText,
          ),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            decoration: BF.card(isDark),
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    Icons.dark_mode_rounded,
                    color: isDark ? BF.teal : BF.navy,
                  ),
                  title: Text(
                    'Dark Mode',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : BF.lightText,
                    ),
                  ),
                  trailing: ValueListenableBuilder<bool>(
                    valueListenable: isDarkMode,
                    builder: (context, bool isDarkValue, _) {
                      return Switch(
                        value: isDarkValue,
                        onChanged: (val) => isDarkMode.value = val,
                        activeColor: BF.teal,
                      );
                    },
                  ),
                ),
                Divider(
                  height: 1,
                  color: isDark ? BF.darkBorder : BF.lightBorder,
                ),
                ListTile(
                  leading: const Icon(Icons.logout_rounded, color: BF.red),
                  title: Text(
                    'Sign Out',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : BF.lightText,
                    ),
                  ),
                  onTap: () async {
                    await supabase.auth.signOut();
                    if (context.mounted) {
                      Navigator.pushReplacementNamed(context, '/auth');
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BF.card(isDark),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: BF.tealGradient,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.waterfall_chart_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'BudgetFlow',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: isDark ? Colors.white : BF.lightText,
                          ),
                        ),
                        Text(
                          'Version 1.0.0',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 11,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Your personal finance companion — track spending, set budgets, and reach your goals.',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    height: 1.6,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
