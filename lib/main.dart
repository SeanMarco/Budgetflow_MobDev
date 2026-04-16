import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:device_preview/device_preview.dart';
import 'AppState.dart';
import 'HomePage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// TODO: Replace with your actual Supabase credentials
const String SUPABASE_URL = 'https://hlxgzitkkukbumtucsem.supabase.co';
const String SUPABASE_ANON_KEY =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhseGd6aXRra3VrYnVtdHVjc2VtIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzM4OTgxNDYsImV4cCI6MjA4OTQ3NDE0Nn0.3qehXC9F0SKkaGQ0B8gZnxuuHow6UnnXF2V3zPzlb2M';

final supabase = Supabase.instance.client;

ValueNotifier<bool> isDarkMode = ValueNotifier(false);
final AppState _appState = AppState();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await Supabase.initialize(url: SUPABASE_URL, anonKey: SUPABASE_ANON_KEY);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const BudgetFlowApp());
}

// ─── Design System ────────────────────────────────────────────────────────────
class BF {
  // Core palette
  static const primary = Color(0xFF1A2F6E);
  static const primaryMid = Color(0xFF2D3FA8);
  static const accent = Color(0xFF6C63FF);
  static const accentSoft = Color(0xFF9D97FF);
  static const green = Color(0xFF0EA974);
  static const red = Color(0xFFE53E3E);
  static const amber = Color(0xFFF6A623);

  // Dark theme
  static const darkBg = Color(0xFF0C0C12);
  static const darkSurface = Color(0xFF141420);
  static const darkCard = Color(0xFF1C1C2C);
  static const darkBorder = Color(0xFF2A2A3E);

  // Light theme
  static const lightBg = Color(0xFFF4F6FC);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightBorder = Color(0xFFE8ECF4);

  // Gradients
  static const brandGradient = LinearGradient(
    colors: [Color(0xFF1A2F6E), Color(0xFF3B30C4), Color(0xFF6C63FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: [0.0, 0.5, 1.0],
  );

  // Shared decoration helpers
  static BoxDecoration card(bool isDark) => BoxDecoration(
    color: isDark ? darkCard : lightCard,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: isDark ? darkBorder : lightBorder, width: 1),
    boxShadow: isDark
        ? []
        : [
            BoxShadow(
              color: const Color(0xFF6C63FF).withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
  );

  static BoxDecoration surface(bool isDark) => BoxDecoration(
    color: isDark ? darkSurface : lightCard,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: isDark ? darkBorder : lightBorder, width: 1),
  );
}

// ─── App ──────────────────────────────────────────────────────────────────────

class BudgetFlowApp extends StatelessWidget {
  const BudgetFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DevicePreview(
      enabled: true,
      builder: (context) {
        return ValueListenableBuilder(
          valueListenable: isDarkMode,
          builder: (context, bool darkMode, _) {
            return AppStateScope(
              state: _appState,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                useInheritedMediaQuery: true,
                locale: DevicePreview.locale(context),
                builder: (context, child) =>
                    DevicePreview.appBuilder(context, child),
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
        seedColor: BF.accent,
        brightness: brightness,
      ),
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      // Ensure consistent AppBar styling across all pages
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? BF.darkBg : BF.lightBg,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),
        titleTextStyle: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      // Ensure consistent text selection colors
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: BF.accent,
        selectionColor: BF.accent.withOpacity(0.3),
        selectionHandleColor: BF.accent,
      ),
      // Ensure consistent input decoration theme
      inputDecorationTheme: InputDecorationTheme(
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: BF.accent, width: 1.5),
        ),
      ),
    );
  }
}

// ─── Auth Page ────────────────────────────────────────────────────────────────

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage>
    with SingleTickerProviderStateMixin {
  bool isLogin = true;
  bool _loading = false;

  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _first = TextEditingController();
  final _last = TextEditingController();

  bool _hidePw = true;
  bool _hideCnf = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _first.dispose();
    _last.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Deep gradient background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF0C1445),
                  Color(0xFF1A2A7A),
                  Color(0xFF3B30C4),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: [0.0, 0.55, 1.0],
              ),
            ),
          ),
          // Atmospheric orbs
          Positioned(
            top: -130,
            right: -100,
            child: _orb(340, BF.accentSoft, 0.08),
          ),
          Positioned(
            bottom: -180,
            left: -90,
            child: _orb(400, BF.primaryMid, 0.13),
          ),
          Positioned(top: 220, left: -70, child: _orb(170, BF.accent, 0.06)),
          Positioned(
            bottom: 180,
            right: -50,
            child: _orb(130, BF.accentSoft, 0.06),
          ),

          SafeArea(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 450),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.04),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: SingleChildScrollView(
                key: ValueKey(isLogin),
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 36,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(),
                    const SizedBox(height: 38),
                    _formCard(),
                    const SizedBox(height: 22),
                    _switchRow(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() => Column(
    children: [
      Container(
        width: 78,
        height: 78,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [BF.accent, BF.accentSoft],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: BF.accent.withOpacity(0.45),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: const Icon(
          Icons.account_balance_wallet_rounded,
          size: 34,
          color: Colors.white,
        ),
      ),
      const SizedBox(height: 18),
      const Text(
        "BudgetFlow",
        style: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: -0.5,
        ),
      ),
      const SizedBox(height: 6),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: Text(
          isLogin ? "Welcome back 👋" : "Let's get you started ✨",
          key: ValueKey(isLogin),
          style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 15),
        ),
      ),
    ],
  );

  Widget _formCard() => Container(
    padding: const EdgeInsets.all(26),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.07),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: Colors.white.withOpacity(0.13), width: 1),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!isLogin) ...[
          Row(
            children: [
              Expanded(
                child: _field(
                  icon: Icons.person_rounded,
                  hint: "First name",
                  ctrl: _first,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _field(
                  icon: Icons.person_outline_rounded,
                  hint: "Last name",
                  ctrl: _last,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
        ],
        _field(
          icon: Icons.mail_outline_rounded,
          hint: "Email",
          ctrl: _email,
          keyboard: TextInputType.emailAddress,
        ),
        const SizedBox(height: 13),
        _field(
          icon: Icons.lock_outline_rounded,
          hint: "Password",
          ctrl: _password,
          isPw: true,
          hide: _hidePw,
          toggle: () => setState(() => _hidePw = !_hidePw),
        ),
        if (!isLogin) ...[
          const SizedBox(height: 13),
          _field(
            icon: Icons.shield_outlined,
            hint: "Confirm password",
            ctrl: _confirm,
            isPw: true,
            hide: _hideCnf,
            toggle: () => setState(() => _hideCnf = !_hideCnf),
          ),
        ],
        const SizedBox(height: 20),
        _primaryBtn(),
        if (isLogin) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {},
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                "Forgot password?",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        _divider(),
        const SizedBox(height: 18),
        _socials(),
      ],
    ),
  );

  Widget _primaryBtn() => SizedBox(
    height: 52,
    child: ElevatedButton(
      onPressed: _loading ? null : _submit,
      style: ElevatedButton.styleFrom(
        backgroundColor: BF.accent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: BF.accent.withOpacity(0.5),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          fontFamily: 'Poppins',
        ),
      ),
      child: _loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            )
          : Text(isLogin ? "Sign In" : "Create Account"),
    ),
  );

  Widget _divider() => Row(
    children: [
      Expanded(
        child: Divider(thickness: 0.7, color: Colors.white.withOpacity(0.12)),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(
          "or",
          style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 12),
        ),
      ),
      Expanded(
        child: Divider(thickness: 0.7, color: Colors.white.withOpacity(0.12)),
      ),
    ],
  );

  Widget _socials() => Row(
    children: [
      _socialBtn("Google", Icons.g_mobiledata_rounded),
      const SizedBox(width: 10),
      _socialBtn("Facebook", Icons.facebook_rounded),
      const SizedBox(width: 10),
      _socialBtn("Apple", Icons.apple_rounded),
    ],
  );

  Widget _switchRow() => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text(
        isLogin ? "No account?" : "Have an account?",
        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
      ),
      TextButton(
        onPressed: () => setState(() => isLogin = !isLogin),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          isLogin ? "Sign Up" : "Sign In",
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: BF.accentSoft,
          ),
        ),
      ),
    ],
  );

  Widget _field({
    required IconData icon,
    required String hint,
    required TextEditingController ctrl,
    bool isPw = false,
    bool hide = false,
    VoidCallback? toggle,
    TextInputType? keyboard,
  }) => Container(
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.07),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: Colors.white.withOpacity(0.10), width: 1),
    ),
    child: TextField(
      controller: ctrl,
      obscureText: isPw && hide,
      keyboardType: keyboard,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontFamily: 'Poppins',
      ),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, size: 18, color: Colors.white.withOpacity(0.4)),
        suffixIcon: isPw
            ? IconButton(
                icon: Icon(
                  hide
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 17,
                  color: Colors.white.withOpacity(0.3),
                ),
                onPressed: toggle,
              )
            : null,
        hintText: hint,
        hintStyle: TextStyle(
          color: Colors.white.withOpacity(0.3),
          fontSize: 13,
        ),
        filled: false,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 4),
      ),
    ),
  );

  Widget _socialBtn(String label, IconData icon) => Expanded(
    child: GestureDetector(
      onTap: () {
        // TODO: Implement social login with Supabase
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage(username: "User")),
        );
      },
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.white.withOpacity(0.10), width: 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.55),
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _orb(double size, Color color, double opacity) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color.withOpacity(opacity),
    ),
  );

  void _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    final firstName = _first.text.trim();
    final lastName = _last.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _snack("Fill in all fields");
      return;
    }
    if (!isLogin && (firstName.isEmpty || lastName.isEmpty)) {
      _snack("Enter your full name");
      return;
    }
    if (!isLogin && password != _confirm.text) {
      _snack("Passwords do not match");
      return;
    }
    if (!email.contains('@')) {
      _snack("Enter a valid email");
      return;
    }

    setState(() => _loading = true);

    try {
      if (isLogin) {
        // Sign in with Supabase
        final response = await supabase.auth.signInWithPassword(
          email: email,
          password: password,
        );

        if (response.user != null) {
          // Fetch user metadata
          final userName =
              response.user!.userMetadata?['full_name'] ??
              response.user!.email?.split('@').first ??
              "User";

          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => HomePage(username: userName)),
          );
        }
      } else {
        // Sign up with Supabase - this will throw an exception on error
        final response = await supabase.auth.signUp(
          email: email,
          password: password,
          data: {
            'first_name': firstName,
            'last_name': lastName,
            'full_name': '$firstName $lastName',
          },
        );

        if (response.user != null) {
          _snack("Account created! You may now sign in.");
          // Clear fields and switch to login
          setState(() {
            isLogin = true;
            _email.clear();
            _password.clear();
            _first.clear();
            _last.clear();
            _confirm.clear();
          });
        }
      }
    } on AuthException catch (e) {
      // Handle Supabase auth errors specifically
      _snack(e.message);
    } catch (e) {
      // Handle any other errors
      _snack("An error occurred: ${e.toString()}");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
      behavior: SnackBarBehavior.floating,
      backgroundColor: BF.darkCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ),
  );
}

// ─── Settings Page ────────────────────────────────────────────────────────────
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
          "Settings",
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_rounded,
            color: isDark ? Colors.white : Colors.black87,
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
                    Icons.dark_mode,
                    color: isDark ? BF.accent : BF.primary,
                  ),
                  title: Text(
                    "Dark Mode",
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  trailing: ValueListenableBuilder(
                    valueListenable: isDarkMode,
                    builder: (context, bool isDarkValue, _) {
                      return Switch(
                        value: isDarkValue,
                        onChanged: (val) => isDarkMode.value = val,
                        activeColor: BF.accent,
                      );
                    },
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.logout, color: BF.red),
                  title: Text(
                    "Sign Out",
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: isDark ? Colors.white : Colors.black87,
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
            padding: const EdgeInsets.all(16),
            decoration: BF.card(isDark),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "About BudgetFlow",
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Version 1.0.0",
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Your personal finance companion",
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
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
