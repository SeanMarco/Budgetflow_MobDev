import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main.dart' show BF, AuthPage, isDarkMode;
import 'AppState.dart';
import 'BudgetPage.dart';
import 'ReportsPage.dart';
import 'RecurringPage.dart';
import 'AccountsPage.dart';
import 'SavingsPage.dart';

SupabaseClient get supabase => Supabase.instance.client;

// ── Category constants ────────────────────────────────────────────────────────
class TxCategories {
  static const List<Map<String, dynamic>> list = [
    {'label': 'Food', 'emoji': '🍜', 'color': Color(0xFFFF6B6B)},
    {'label': 'Transportation', 'emoji': '🚗', 'color': Color(0xFF4ECDC4)},
    {'label': 'Bills & Utilities', 'emoji': '💡', 'color': Color(0xFFFFE66D)},
    {'label': 'Rent / Housing', 'emoji': '🏠', 'color': Color(0xFF6C63FF)},
    {'label': 'Entertainment', 'emoji': '🎬', 'color': Color(0xFFFF9FF3)},
    {'label': 'Shopping', 'emoji': '🛍️', 'color': Color(0xFFFFA502)},
    {'label': 'Health / Medical', 'emoji': '💊', 'color': Color(0xFF2ED573)},
    {'label': 'Education', 'emoji': '📚', 'color': Color(0xFF1E90FF)},
    {'label': 'Savings', 'emoji': '🏦', 'color': Color(0xFF0EA974)},
    {'label': 'Investments', 'emoji': '📈', 'color': Color(0xFF00D2D3)},
    {'label': 'Debt / Loans', 'emoji': '💳', 'color': Color(0xFFFF4757)},
    {'label': 'Insurance', 'emoji': '🛡️', 'color': Color(0xFF747D8C)},
    {'label': 'Subscriptions', 'emoji': '🔄', 'color': Color(0xFFA29BFE)},
    {'label': 'Travel', 'emoji': '✈️', 'color': Color(0xFF00CEC9)},
    {'label': 'Personal Care', 'emoji': '🧴', 'color': Color(0xFFFD79A8)},
    {'label': 'Gifts / Donations', 'emoji': '🎁', 'color': Color(0xFFE17055)},
    {'label': 'Family / Kids', 'emoji': '👨‍👩‍👧', 'color': Color(0xFFFFB8B8)},
    {'label': 'Emergency', 'emoji': '🚨', 'color': Color(0xFFD63031)},
    {'label': 'Others', 'emoji': '✏️', 'color': Color(0xFF636E72)},
  ];

  static Map<String, dynamic>? findByLabel(String label) {
    try {
      return list.firstWhere((c) => c['label'] == label);
    } catch (_) {
      return null;
    }
  }

  static Color colorFor(String label) =>
      findByLabel(label)?['color'] as Color? ?? BF.accent;

  static String emojiFor(String label) =>
      findByLabel(label)?['emoji'] as String? ?? '📌';
}

class HomePage extends StatefulWidget {
  final String username;
  const HomePage({super.key, required this.username});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  int _tab = 0;
  bool _loading = true;
  String? _profileImagePath;

  bool get _isDarkMode => isDarkMode.value;

  late AnimationController _fabAnimCtrl;
  late AnimationController _pieChartAnimationController;

  // ── Wallet scroll state ───────────────────────────────────────────────────
  final ScrollController _walletScrollCtrl = ScrollController();
  int _walletScrollIndex = 0;

  final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱');

  String _searchQuery = '';
  String _filterCategory = 'All';
  String _filterType = 'All';
  DateTimeRange? _filterDateRange;

  AppState get _s => AppStateScope.of(context);

  double get _balance =>
      _s.accounts.fold(0.0, (s, a) => s + (a['balance'] as double));

  String get _userId => supabase.auth.currentUser?.id ?? '';

  // Card width + margin = 160 + 12 = 172
  static const double _walletCardStep = 172.0;

  @override
  void initState() {
    super.initState();
    _fabAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();
    _pieChartAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();
    isDarkMode.addListener(_onThemeChanged);
    _walletScrollCtrl.addListener(_onWalletScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
    _loadPrefs();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  void _onWalletScroll() {
    if (!mounted) return;
    final idx = (_walletScrollCtrl.offset / _walletCardStep).round().clamp(
      0,
      (_s.accounts.length - 1).clamp(0, 99),
    );
    if (idx != _walletScrollIndex) {
      setState(() => _walletScrollIndex = idx);
    }
  }

  @override
  void dispose() {
    isDarkMode.removeListener(_onThemeChanged);
    _walletScrollCtrl.removeListener(_onWalletScroll);
    _walletScrollCtrl.dispose();
    _fabAnimCtrl.dispose();
    _pieChartAnimationController.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _profileImagePath = prefs.getString('profile_image_path');
    });
  }

  Future<void> _saveThemePref(bool isDark) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_dark_mode', isDark);
    isDarkMode.value = isDark;
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);
    final s = AppStateScope.of(context);

    try {
      final accountsResponse = await supabase
          .from('accounts')
          .select()
          .eq('user_id', _userId);

      final transactionsResponse = await supabase
          .from('transactions')
          .select()
          .eq('user_id', _userId)
          .order('date', ascending: false);

      final budgetsResponse = await supabase
          .from('budgets')
          .select()
          .eq('user_id', _userId);

      final savingsResponse = await supabase
          .from('savings_goals')
          .select()
          .eq('user_id', _userId);

      if (!mounted) return;

      s.accounts.clear();
      s.transactions.clear();
      s.budgets.clear();
      s.savingsGoals.clear();

      if ((accountsResponse as List).isNotEmpty) {
        for (final acc in accountsResponse) {
          s.accounts.add({
            'id': acc['id'].toString(),
            'name': acc['name'] as String,
            'type': acc['type'] as String,
            'emoji': acc['emoji'] as String? ?? '💰',
            'balance': (acc['balance'] as num).toDouble(),
            'color': acc['color'] as String? ?? '#0EA974',
          });
        }
      } else {
        final newAccount = await supabase.from('accounts').insert({
          'user_id': _userId,
          'name': 'Cash Wallet',
          'type': 'Cash',
          'emoji': '👛',
          'balance': 0.0,
          'color': '#0EA974',
        }).select();

        if (!mounted) return;
        if ((newAccount as List).isNotEmpty) {
          s.accounts.add({
            'id': newAccount[0]['id'].toString(),
            'name': 'Cash Wallet',
            'type': 'Cash',
            'emoji': '👛',
            'balance': 0.0,
            'color': '#0EA974',
          });
        }
      }

      for (final tx in (transactionsResponse as List)) {
        s.transactions.add({
          'id': tx['id'].toString(),
          'title': tx['title'] as String,
          'amount': (tx['amount'] as num).toDouble(),
          'isIncome': tx['is_income'] as bool,
          'isTransfer': tx['is_transfer'] as bool? ?? false,
          'category': tx['category'] as String? ?? 'General',
          'note': tx['note'] as String? ?? '',
          'date': DateTime.parse(tx['date'] as String),
          'accountId': tx['account_id'].toString(),
        });
      }

      for (final bud in (budgetsResponse as List)) {
        s.budgets.add({
          'id': bud['id'].toString(),
          'category': bud['category'] as String,
          'limit': (bud['budget_limit'] as num).toDouble(),
        });
      }

      for (final goal in (savingsResponse as List)) {
        s.savingsGoals.add({
          'id': goal['id'].toString(),
          'title': goal['title'] as String,
          'emoji': goal['emoji'] as String? ?? '🎯',
          'target': (goal['target'] as num).toDouble(),
          'saved': (goal['saved'] as num).toDouble(),
          'deadline': goal['deadline'] != null
              ? DateTime.parse(goal['deadline'] as String)
              : null,
        });
      }
    } catch (e) {
      debugPrint('[HomePage] _loadData error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to load data. Pull to refresh.',
              style: const TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: BF.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clearSessionData() async {
    await supabase.auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('profile_image_path');
  }

  Future<void> _pickProfileImage() async {
    final picker = ImagePicker();
    final isDark = _isDarkMode;
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: isDark ? BF.darkCard : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(),
            const SizedBox(height: 20),
            Text(
              'Change Profile Photo',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                fontFamily: 'Poppins',
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _imageSourceOption(
                    Icons.camera_alt_rounded,
                    'Camera',
                    const Color(0xFF3B82F6),
                    () async {
                      Navigator.pop(context);
                      final img = await picker.pickImage(
                        source: ImageSource.camera,
                        imageQuality: 80,
                      );
                      if (img != null && mounted) {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('profile_image_path', img.path);
                        setState(() => _profileImagePath = img.path);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _imageSourceOption(
                    Icons.photo_library_rounded,
                    'Gallery',
                    BF.accent,
                    () async {
                      Navigator.pop(context);
                      final img = await picker.pickImage(
                        source: ImageSource.gallery,
                        imageQuality: 80,
                      );
                      if (img != null && mounted) {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('profile_image_path', img.path);
                        setState(() => _profileImagePath = img.path);
                      }
                    },
                  ),
                ),
                if (_profileImagePath != null) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: _imageSourceOption(
                      Icons.delete_rounded,
                      'Remove',
                      BF.red,
                      () async {
                        Navigator.pop(context);
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove('profile_image_path');
                        if (mounted) {
                          setState(() => _profileImagePath = null);
                        }
                      },
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _imageSourceOption(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredTxs {
    return _s.transactions.where((tx) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final titleMatch = (tx['title'] as String).toLowerCase().contains(q);
        final catMatch = (tx['category'] as String).toLowerCase().contains(q);
        if (!titleMatch && !catMatch) return false;
      }
      if (_filterCategory != 'All' && tx['category'] != _filterCategory) {
        return false;
      }
      if (_filterType == 'Income' && !(tx['isIncome'] as bool)) return false;
      if (_filterType == 'Expense' && (tx['isIncome'] as bool)) return false;
      if (_filterDateRange != null) {
        final d = tx['date'] as DateTime;
        if (d.isBefore(_filterDateRange!.start) ||
            d.isAfter(_filterDateRange!.end.add(const Duration(days: 1)))) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  List<String> get _categories => [
    'All',
    ..._s.transactions.map((t) => t['category'] as String).toSet(),
  ];

  Map<String, double> get _thisMonthStats {
    final now = DateTime.now();
    double income = 0, expense = 0;
    for (final tx in _s.transactions) {
      if (tx['isTransfer'] == true) continue;
      final d = tx['date'] as DateTime;
      if (d.year == now.year && d.month == now.month) {
        if (tx['isIncome'] as bool) {
          income += tx['amount'] as double;
        } else {
          expense += tx['amount'] as double;
        }
      }
    }
    return {'income': income, 'expense': expense};
  }

  Map<String, double> get _allTimeStats {
    double income = 0, expense = 0;
    for (final tx in _s.transactions) {
      if (tx['isTransfer'] == true) continue;
      if (tx['isIncome'] as bool) {
        income += tx['amount'] as double;
      } else {
        expense += tx['amount'] as double;
      }
    }
    return {'income': income, 'expense': expense};
  }

  Color _parseColor(dynamic raw, Color fallback) {
    if (raw is Color) return raw;
    if (raw is String) {
      try {
        final hex = raw.replaceFirst('#', '');
        return Color(int.parse('FF$hex', radix: 16));
      } catch (_) {}
    }
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _isDarkMode;

    if (_loading) {
      return Scaffold(
        backgroundColor: isDark ? BF.darkBg : BF.lightBg,
        body: const Center(child: CircularProgressIndicator(color: BF.accent)),
      );
    }
    return Scaffold(
      backgroundColor: isDark ? BF.darkBg : BF.lightBg,
      body: SafeArea(child: _page()),
      bottomNavigationBar: _navBar(isDark),
      floatingActionButton: ScaleTransition(
        scale: CurvedAnimation(parent: _fabAnimCtrl, curve: Curves.elasticOut),
        child: _fab(),
      ),
    );
  }

  Widget _fab() => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      gradient: const LinearGradient(
        colors: [BF.accent, BF.accentSoft],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      boxShadow: [
        BoxShadow(
          color: BF.accent.withOpacity(0.4),
          blurRadius: 20,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: FloatingActionButton(
      backgroundColor: Colors.transparent,
      elevation: 0,
      onPressed: () => _showTxSheet(context),
      child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
    ),
  );

  Widget _navBar(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? BF.darkSurface : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? BF.darkBorder : BF.lightBorder,
            width: 1,
          ),
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 24,
                  offset: const Offset(0, -6),
                ),
              ],
      ),
      child: BottomNavigationBar(
        currentIndex: _tab,
        onTap: (i) => setState(() => _tab = i),
        selectedItemColor: BF.accent,
        unselectedItemColor: isDark
            ? Colors.white.withOpacity(0.3)
            : Colors.black.withOpacity(0.3),
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedLabelStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 11,
        ),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_rounded),
            label: 'Activity',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_rounded),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  Widget _page() {
    switch (_tab) {
      case 0:
        return _dashboard();
      case 1:
        return _activityPage();
      default:
        return _profilePage();
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // NAVIGATION HELPERS
  // ══════════════════════════════════════════════════════════════════════════
  void _push(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _pushAndReload(Widget page) async {
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (!mounted) return;
    await _loadData();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ADD / EDIT TRANSACTION SHEET (RESPONSIVE)
  // ══════════════════════════════════════════════════════════════════════════
  void _showTxSheet(BuildContext context, {Map<String, dynamic>? existing}) {
    final isDark = _isDarkMode;
    final appState = _s;
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final isSmallScreen = screenHeight < 700;

    final amountCtrl = TextEditingController(
      text: existing != null
          ? (existing['amount'] as double).toStringAsFixed(2)
          : '',
    );
    final noteCtrl = TextEditingController(
      text: existing?['title'] as String? ?? '',
    );
    final categoryCtrl = TextEditingController(
      text: existing?['category'] as String? ?? '',
    );

    bool isIncome = existing?['isIncome'] as bool? ?? false;

    String localAccountId = '';
    if (existing != null && existing['accountId'] != null) {
      localAccountId = existing['accountId'].toString();
    } else if (appState.accounts.isNotEmpty) {
      localAccountId = appState.accounts[0]['id'].toString();
    }

    String selectedCategory = existing?['category'] as String? ?? '';
    bool isCustomCategory =
        selectedCategory.isNotEmpty &&
        TxCategories.findByLabel(selectedCategory) == null;

    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) {
          return Container(
            decoration: BoxDecoration(
              color: isDark ? BF.darkCard : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom:
                  MediaQuery.of(ctx).viewInsets.bottom +
                  (isSmallScreen ? 16 : 28),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: _sheetHandle()),
                  SizedBox(height: isSmallScreen ? 12 : 20),
                  Text(
                    existing != null ? 'Edit Transaction' : 'New Transaction',
                    style: TextStyle(
                      fontSize: isSmallScreen ? 18 : 20,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Poppins',
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  SizedBox(height: isSmallScreen ? 12 : 20),
                  Container(
                    height: isSmallScreen ? 44 : 50,
                    decoration: BoxDecoration(
                      color: isDark ? BF.darkSurface : BF.lightBg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        _toggle(
                          'Income',
                          true,
                          isIncome,
                          isDark,
                          setS,
                          () => setS(() => isIncome = true),
                          isSmallScreen: isSmallScreen,
                        ),
                        _toggle(
                          'Expense',
                          false,
                          isIncome,
                          isDark,
                          setS,
                          () => setS(() => isIncome = false),
                          isSmallScreen: isSmallScreen,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: isSmallScreen ? 10 : 14),
                  _sheetField(
                    amountCtrl,
                    'Amount',
                    isDark,
                    prefix: '₱ ',
                    type: const TextInputType.numberWithOptions(decimal: true),
                    isSmallScreen: isSmallScreen,
                  ),
                  SizedBox(height: isSmallScreen ? 8 : 12),
                  _sheetField(
                    noteCtrl,
                    'Title / Note',
                    isDark,
                    isSmallScreen: isSmallScreen,
                  ),
                  SizedBox(height: isSmallScreen ? 8 : 12),
                  Text(
                    'Category',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: isSmallScreen ? 12 : 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  SizedBox(height: isSmallScreen ? 6 : 8),
                  if (selectedCategory.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: TxCategories.colorFor(
                          selectedCategory,
                        ).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: TxCategories.colorFor(
                            selectedCategory,
                          ).withOpacity(0.35),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            TxCategories.emojiFor(selectedCategory),
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            selectedCategory,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: TxCategories.colorFor(selectedCategory),
                            ),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => setS(() {
                              selectedCategory = '';
                              isCustomCategory = false;
                              categoryCtrl.clear();
                            }),
                            child: Icon(
                              Icons.close_rounded,
                              size: 12,
                              color: TxCategories.colorFor(selectedCategory),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: TxCategories.list.map((cat) {
                      final label = cat['label'] as String;
                      final emoji = cat['emoji'] as String;
                      final color = cat['color'] as Color;
                      final isSelected = selectedCategory == label;

                      if (label == 'Others') {
                        return GestureDetector(
                          onTap: () => setS(() {
                            selectedCategory = 'Others';
                            isCustomCategory = true;
                            categoryCtrl.text = '';
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: EdgeInsets.symmetric(
                              horizontal: isSmallScreen ? 8 : 12,
                              vertical: isSmallScreen ? 5 : 7,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? color
                                  : color.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: isSelected
                                    ? color
                                    : color.withOpacity(0.25),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  emoji,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Custom…',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: isSmallScreen ? 10 : 12,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected ? Colors.white : color,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return GestureDetector(
                        onTap: () => setS(() {
                          selectedCategory = label;
                          isCustomCategory = false;
                          categoryCtrl.text = label;
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: EdgeInsets.symmetric(
                            horizontal: isSmallScreen ? 8 : 12,
                            vertical: isSmallScreen ? 5 : 7,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected ? color : color.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isSelected
                                  ? color
                                  : color.withOpacity(0.25),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(emoji, style: const TextStyle(fontSize: 12)),
                              const SizedBox(width: 4),
                              Text(
                                label,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: isSmallScreen ? 10 : 12,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected ? Colors.white : color,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  if (isCustomCategory || selectedCategory == 'Others') ...[
                    const SizedBox(height: 8),
                    _sheetField(
                      categoryCtrl,
                      'Type your category…',
                      isDark,
                      isSmallScreen: isSmallScreen,
                    ),
                  ],
                  SizedBox(height: isSmallScreen ? 10 : 14),
                  if (appState.accounts.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: isDark ? BF.darkSurface : BF.lightBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark ? BF.darkBorder : BF.lightBorder,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: localAccountId.isNotEmpty
                              ? localAccountId
                              : null,
                          isExpanded: true,
                          hint: Text(
                            'Select Account',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: isSmallScreen ? 12 : 14,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                          ),
                          dropdownColor: isDark ? BF.darkCard : Colors.white,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: isSmallScreen ? 12 : 14,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          items: appState.accounts.map((a) {
                            return DropdownMenuItem<String>(
                              value: a['id'].toString(),
                              child: Row(
                                children: [
                                  Text(
                                    a['emoji'] as String? ?? '💰',
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      a['name'] as String,
                                      style: const TextStyle(
                                        fontFamily: 'Poppins',
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    (a['balance'] as double).toStringAsFixed(0),
                                    style: TextStyle(
                                      fontSize: isSmallScreen ? 10 : 11,
                                      color: isDark
                                          ? Colors.white38
                                          : Colors.black38,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setS(() => localAccountId = v);
                            }
                          },
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: BF.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: BF.red.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_rounded,
                            color: BF.red,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'No accounts found. Please create an account first.',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 11,
                                color: BF.red,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(height: isSmallScreen ? 16 : 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: BF.accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: EdgeInsets.symmetric(
                          vertical: isSmallScreen ? 12 : 15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: isSmallScreen ? 13 : 15,
                        ),
                      ),
                      onPressed: isSaving
                          ? null
                          : () async {
                              final rawAmount = amountCtrl.text.trim();
                              final amount = double.tryParse(rawAmount) ?? 0;
                              if (amount <= 0) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Please enter a valid positive amount',
                                    ),
                                    backgroundColor: BF.red,
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                                return;
                              }
                              if (localAccountId.isEmpty) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text('Please select an account'),
                                    backgroundColor: BF.red,
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                                return;
                              }

                              final finalCategory =
                                  (selectedCategory == 'Others' ||
                                      isCustomCategory)
                                  ? (categoryCtrl.text.trim().isEmpty
                                        ? 'Others'
                                        : categoryCtrl.text.trim())
                                  : (selectedCategory.isEmpty
                                        ? (categoryCtrl.text.trim().isEmpty
                                              ? 'General'
                                              : categoryCtrl.text.trim())
                                        : selectedCategory);

                              setS(() => isSaving = true);

                              final title = noteCtrl.text.trim().isEmpty
                                  ? (isIncome ? 'Income' : 'Expense')
                                  : noteCtrl.text.trim();

                              final now = DateTime.now();
                              final dateStr = now.toIso8601String();
                              final accountIdInt = int.tryParse(localAccountId);
                              if (accountIdInt == null) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text('Invalid account selected'),
                                    backgroundColor: BF.red,
                                  ),
                                );
                                setS(() => isSaving = false);
                                return;
                              }

                              try {
                                if (existing != null) {
                                  final existingId = int.tryParse(
                                    existing['id'].toString(),
                                  );
                                  if (existingId == null) {
                                    throw Exception('Invalid transaction id');
                                  }
                                  await supabase
                                      .from('transactions')
                                      .update({
                                        'title': title,
                                        'amount': amount,
                                        'is_income': isIncome,
                                        'category': finalCategory,
                                        'account_id': accountIdInt,
                                        'note': noteCtrl.text.trim(),
                                        'date': dateStr,
                                      })
                                      .eq('id', existingId);
                                } else {
                                  await supabase.from('transactions').insert({
                                    'user_id': _userId,
                                    'title': title,
                                    'amount': amount,
                                    'is_income': isIncome,
                                    'category': finalCategory,
                                    'account_id': accountIdInt,
                                    'note': noteCtrl.text.trim(),
                                    'date': dateStr,
                                  });

                                  final account = appState.accounts.firstWhere(
                                    (a) => a['id'].toString() == localAccountId,
                                  );
                                  final currentBalance =
                                      account['balance'] as double;
                                  final newBalance = isIncome
                                      ? currentBalance + amount
                                      : currentBalance - amount;

                                  await supabase
                                      .from('accounts')
                                      .update({'balance': newBalance})
                                      .eq('id', accountIdInt);
                                }

                                await _loadData();

                                if (mounted) {
                                  setState(() {});
                                }

                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        existing != null
                                            ? 'Transaction updated!'
                                            : 'Transaction added!',
                                      ),
                                      backgroundColor: BF.green,
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                  Navigator.pop(ctx);
                                }
                              } catch (e) {
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content: Text('Error: $e'),
                                      backgroundColor: BF.red,
                                      duration: const Duration(seconds: 3),
                                    ),
                                  );
                                }
                              } finally {
                                if (ctx.mounted) {
                                  setS(() => isSaving = false);
                                }
                              }
                            },
                      child: isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              existing != null
                                  ? 'Save Changes'
                                  : 'Add Transaction',
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // DASHBOARD
  // ══════════════════════════════════════════════════════════════════════════
  Widget _dashboard() {
    final isDark = _isDarkMode;
    double income = 0, expense = 0;
    final Map<String, double> catTotals = {};
    for (final tx in _s.transactions) {
      if (tx['isTransfer'] == true) continue;
      if (tx['isIncome'] as bool) {
        income += tx['amount'] as double;
      } else {
        expense += tx['amount'] as double;
        final c = tx['category'] as String;
        catTotals[c] = (catTotals[c] ?? 0) + (tx['amount'] as double);
      }
    }
    final monthStats = _thisMonthStats;

    return RefreshIndicator(
      color: BF.accent,
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hi, ${widget.username.isNotEmpty ? widget.username.split(' ')[0] : 'User'} 👋',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Poppins',
                        color: isDark ? Colors.white : BF.primary,
                      ),
                    ),
                    Text(
                      'Your finance overview',
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: 'Poppins',
                        color: isDark
                            ? Colors.white.withOpacity(0.45)
                            : Colors.black.withOpacity(0.4),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => _saveThemePref(!_isDarkMode),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withOpacity(0.08)
                              : Colors.black.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                            color: isDark ? BF.darkBorder : BF.lightBorder,
                          ),
                        ),
                        child: Icon(
                          isDark
                              ? Icons.wb_sunny_rounded
                              : Icons.nightlight_round,
                          color: isDark ? Colors.amber : BF.accent,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () => setState(() => _tab = 2),
                      child: _avatarWidget(widget.username, size: 44),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 22),
            _balanceCard(isDark),
            const SizedBox(height: 14),
            if (_s.accounts.isNotEmpty) ...[
              _sectionHead(
                'My Wallets',
                isDark,
                action: _viewAll(
                  'Manage',
                  () => _pushAndReload(const AccountsPage()),
                ),
              ),
              const SizedBox(height: 10),
              _walletSection(isDark),
              const SizedBox(height: 14),
            ],
            Row(
              children: [
                Expanded(child: _summaryTile('Income', income, true, isDark)),
                const SizedBox(width: 12),
                Expanded(
                  child: _summaryTile('Expenses', expense, false, isDark),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _thisMonthCard(monthStats, isDark),
            const SizedBox(height: 18),
            _featureGrid(isDark),
            const SizedBox(height: 18),
            _budgetAlerts(isDark),
            if (income > 0 || expense > 0) ...[
              _sectionHead('Financial Overview', isDark),
              const SizedBox(height: 12),
              _enhancedPieChart(income, expense, isDark),
              const SizedBox(height: 18),
            ],
            if (catTotals.isNotEmpty) ...[
              _sectionHead('Spending Breakdown', isDark),
              const SizedBox(height: 12),
              SizedBox(
                height: 110,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: catTotals.entries.map((e) {
                    final pct = expense > 0
                        ? (e.value / expense * 100).toStringAsFixed(0)
                        : '0';
                    return _catChip(e.key, pct, isDark);
                  }).toList(),
                ),
              ),
              const SizedBox(height: 18),
            ],
            if (_s.savingsGoals.isNotEmpty) ...[
              _sectionHead(
                'Savings Goals',
                isDark,
                action: _viewAll(
                  'View All',
                  () => _pushAndReload(const SavingsPage()),
                ),
              ),
              const SizedBox(height: 12),
              ..._s.savingsGoals.take(2).map((g) => _goalMini(g, isDark)),
              const SizedBox(height: 18),
            ],
            _sectionHead(
              'Recent Transactions',
              isDark,
              action: _s.transactions.isNotEmpty
                  ? _viewAll('See All', () => setState(() => _tab = 1))
                  : null,
            ),
            const SizedBox(height: 12),
            _s.transactions.isEmpty
                ? _emptyState(
                    isDark,
                    'No transactions yet',
                    Icons.receipt_long_outlined,
                  )
                : Column(
                    children: _s.transactions
                        .take(5)
                        .map((tx) => _txTile(tx, isDark))
                        .toList(),
                  ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // WALLET SECTION — with native scrollbar
  // ══════════════════════════════════════════════════════════════════════════
  // ══════════════════════════════════════════════════════════════════════════
  // WALLET SECTION — with themed scrollbar
  // ══════════════════════════════════════════════════════════════════════════
  // ══════════════════════════════════════════════════════════════════════════
  // WALLET SECTION — with themed scrollbar
  // ══════════════════════════════════════════════════════════════════════════
  // ══════════════════════════════════════════════════════════════════════════
  // WALLET SECTION — with scrollbar below the wallet cards
  // ══════════════════════════════════════════════════════════════════════════
  Widget _walletSection(bool isDark) {
    final count = _s.accounts.length;
    if (count == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Wallet cards with scrollbar and bottom padding
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SizedBox(
            height: 112,
            child: Scrollbar(
              controller: _walletScrollCtrl,
              thumbVisibility: true,
              trackVisibility: true,
              thickness: 4.0,
              radius: const Radius.circular(2.0),
              interactive: true,
              child: ListView.builder(
                controller: _walletScrollCtrl,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: count,
                itemBuilder: (_, i) => _walletCard(_s.accounts[i], isDark),
              ),
            ),
          ),
        ),
        if (count > 2) ...[
          Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              Icons.chevron_right_rounded,
              size: 14,
              color: isDark
                  ? Colors.white.withOpacity(0.2)
                  : Colors.black.withOpacity(0.12),
            ),
          ),
        ],
      ],
    );
  }

  // Helper method to build a Scrollbar that blends with the theme
  Widget buildWalletScrollbar(bool isDark) {
    return Scrollbar(
      controller: _walletScrollCtrl,
      thumbVisibility: true,
      trackVisibility: true,
      thickness: 3.0,
      radius: const Radius.circular(1.5),
      interactive: true,
      child: Container(
        height: 3,
        color: Colors.transparent,
        child: const SizedBox.shrink(),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ENHANCED PIE CHART
  // ══════════════════════════════════════════════════════════════════════════
  Widget _enhancedPieChart(double income, double expense, bool isDark) {
    final total = income + expense;
    final double incomePercent = total > 0 ? (income / total * 100) : 0;
    final double expensePercent = total > 0 ? (expense / total * 100) : 0;

    return AnimatedBuilder(
      animation: _pieChartAnimationController,
      builder: (context, child) {
        final animationValue = Curves.easeOutCubic.transform(
          _pieChartAnimationController.value,
        );
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [BF.darkCard, BF.darkSurface]
                  : [Colors.white, BF.lightBg],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: BF.accent.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Income vs Expenses',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Poppins',
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [BF.accent, BF.accentSoft],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.all(Radius.circular(20)),
                    ),
                    child: Text(
                      DateFormat('MMMM').format(DateTime.now()),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Poppins',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: BF.accent.withOpacity(0.15),
                          blurRadius: 30,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    height: 180,
                    child: CustomPaint(
                      painter: _DonutChartPainter(
                        incomePercent: incomePercent * animationValue,
                        expensePercent: expensePercent * animationValue,
                        incomeColor: BF.green,
                        expenseColor: BF.red,
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TweenAnimationBuilder<double>(
                        duration: const Duration(milliseconds: 800),
                        curve: Curves.easeOutCubic,
                        tween: Tween(begin: 0, end: total),
                        builder: (context, value, child) => Text(
                          currency.format(value),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'Poppins',
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Total Flow',
                        style: TextStyle(
                          fontSize: 10,
                          fontFamily: 'Poppins',
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _legendItem(
                    color: BF.green,
                    label: 'Income',
                    value: income,
                    percent: incomePercent,
                    isDark: isDark,
                  ),
                  const SizedBox(width: 40),
                  _legendItem(
                    color: BF.red,
                    label: 'Expense',
                    value: expense,
                    percent: expensePercent,
                    isDark: isDark,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (total > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: (income > expense ? BF.green : BF.red).withOpacity(
                      0.1,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (income > expense ? BF.green : BF.red).withOpacity(
                        0.3,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        income > expense
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded,
                        color: income > expense ? BF.green : BF.red,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          income > expense
                              ? "You're saving ${((income - expense) / income * 100).toStringAsFixed(1)}% of your income!"
                              : expense > 0
                              ? "Your expenses are ${((expense - income) / expense * 100).toStringAsFixed(1)}% above income"
                              : 'Add transactions to see insights',
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            color: income > expense ? BF.green : BF.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _legendItem({
    required Color color,
    required String label,
    required double value,
    required double percent,
    required bool isDark,
  }) {
    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [
                  BoxShadow(color: color.withOpacity(0.5), blurRadius: 6),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          currency.format(value),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            fontFamily: 'Poppins',
            color: color,
          ),
        ),
        Text(
          '${percent.toStringAsFixed(1)}%',
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // WALLET CARD — enhanced with account count badge + better layout
  // ══════════════════════════════════════════════════════════════════════════
  Widget _walletCard(Map<String, dynamic> acc, bool isDark) {
    final Color baseColor = _parseColor(acc['color'], BF.accent);
    final balance = acc['balance'] as double;
    final isNegative = balance < 0;

    return GestureDetector(
      onTap: () => _pushAndReload(const AccountsPage()),
      child: Container(
        width: 160,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              baseColor.withOpacity(isDark ? 0.28 : 0.18),
              baseColor.withOpacity(isDark ? 0.12 : 0.07),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: baseColor.withOpacity(0.35), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: baseColor.withOpacity(isDark ? 0.15 : 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: baseColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    acc['emoji'] as String? ?? '💰',
                    style: const TextStyle(fontSize: 17),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    acc['name'] as String,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  currency.format(balance),
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: isNegative
                        ? BF.red
                        : (isDark ? Colors.white : Colors.black87),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: baseColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    acc['type'] as String? ?? 'Wallet',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 9,
                      color: baseColor,
                      fontWeight: FontWeight.w600,
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

  Widget _thisMonthCard(Map<String, double> stats, bool isDark) {
    final monthName = DateFormat('MMMM').format(DateTime.now());
    final net = stats['income']! - stats['expense']!;
    final isPositive = net >= 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.04)
            : Colors.black.withOpacity(0.02),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: isDark ? BF.darkBorder : BF.lightBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: BF.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.calendar_month_rounded,
              color: BF.accent,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$monthName Summary',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${isPositive ? '+' : ''}${currency.format(net)}',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: isPositive ? BF.green : BF.red,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _miniStat('In', stats['income']!, BF.green, isDark),
              const SizedBox(height: 4),
              _miniStat('Out', stats['expense']!, BF.red, isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, double val, Color color, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 10,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
        Text(
          currency.format(val),
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ACTIVITY PAGE
  // ══════════════════════════════════════════════════════════════════════════
  Widget _activityPage() {
    final isDark = _isDarkMode;
    final txs = _filteredTxs;

    final sortedTxs = List<Map<String, dynamic>>.from(
      txs,
    )..sort((a, b) => (a['date'] as DateTime).compareTo(b['date'] as DateTime));

    double runningBalance = 0;
    final List<Map<String, dynamic>> withBalance = [];
    for (final tx in sortedTxs) {
      runningBalance += (tx['isIncome'] as bool)
          ? (tx['amount'] as double)
          : -(tx['amount'] as double);
      withBalance.add({...tx, 'runningBalance': runningBalance});
    }
    final displayTransactions = withBalance.reversed.toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Column(
            children: [
              Container(
                height: 48,
                decoration: BF
                    .card(isDark)
                    .copyWith(borderRadius: BorderRadius.circular(14)),
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    Icon(
                      Icons.search_rounded,
                      color: isDark ? Colors.white38 : Colors.black38,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        onChanged: (v) => setState(() => _searchQuery = v),
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search transactions…',
                          hintStyle: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                    if (_searchQuery.isNotEmpty)
                      GestureDetector(
                        onTap: () => setState(() => _searchQuery = ''),
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Icon(
                            Icons.close_rounded,
                            color: isDark ? Colors.white38 : Colors.black38,
                            size: 18,
                          ),
                        ),
                      ),
                    if (_searchQuery.isEmpty) const SizedBox(width: 12),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _chip(
                      'All',
                      _filterType == 'All' && _filterCategory == 'All',
                      isDark,
                      () => setState(() {
                        _filterType = 'All';
                        _filterCategory = 'All';
                        _filterDateRange = null;
                      }),
                    ),
                    _chip(
                      'Income',
                      _filterType == 'Income',
                      isDark,
                      () => setState(
                        () => _filterType = _filterType == 'Income'
                            ? 'All'
                            : 'Income',
                      ),
                    ),
                    _chip(
                      'Expense',
                      _filterType == 'Expense',
                      isDark,
                      () => setState(
                        () => _filterType = _filterType == 'Expense'
                            ? 'All'
                            : 'Expense',
                      ),
                    ),
                    ..._categories
                        .where((c) => c != 'All')
                        .map(
                          (c) => _chip(
                            c,
                            _filterCategory == c,
                            isDark,
                            () => setState(
                              () => _filterCategory = _filterCategory == c
                                  ? 'All'
                                  : c,
                            ),
                          ),
                        ),
                    _chip(
                      _filterDateRange != null ? '📅 Date ✓' : '📅 Date',
                      _filterDateRange != null,
                      isDark,
                      () async {
                        final r = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          initialDateRange: _filterDateRange,
                        );
                        if (mounted) {
                          setState(() => _filterDateRange = r);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_s.transactions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: _activitySummaryBar(txs, isDark),
          ),
        Expanded(
          child: displayTransactions.isEmpty
              ? _emptyState(
                  isDark,
                  'No transactions found',
                  Icons.search_off_rounded,
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 100),
                  itemCount: displayTransactions.length,
                  itemBuilder: (_, i) =>
                      _txTileWithBalance(displayTransactions[i], isDark),
                ),
        ),
      ],
    );
  }

  Widget _txTileWithBalance(Map<String, dynamic> tx, bool isDark) {
    final isIncome = tx['isIncome'] as bool;
    final id = tx['id'].toString();
    final runningBalance = tx['runningBalance'] as double;
    final acc = _s.accounts.firstWhere(
      (a) => a['id'].toString() == tx['accountId'].toString(),
      orElse: () => {'name': '', 'emoji': ''},
    );
    final catColor = TxCategories.colorFor(tx['category'] as String);
    final catEmoji = TxCategories.emojiFor(tx['category'] as String);

    return Dismissible(
      key: Key(id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        return await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: isDark ? BF.darkCard : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: Text(
                  'Delete Transaction?',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                content: Text(
                  'This action cannot be undone.',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontFamily: 'Poppins', color: BF.accent),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text(
                      'Delete',
                      style: TextStyle(fontFamily: 'Poppins', color: BF.red),
                    ),
                  ),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) async {
        try {
          final amount = tx['amount'] as double;
          final accountIdInt = int.tryParse(tx['accountId'].toString());
          if (accountIdInt == null) return;

          await supabase.from('transactions').delete().eq('id', int.parse(id));

          final account = _s.accounts.firstWhere(
            (a) => a['id'].toString() == tx['accountId'].toString(),
            orElse: () => {},
          );
          if (account.isNotEmpty) {
            final currentBalance = account['balance'] as double;
            final newBalance = isIncome
                ? currentBalance - amount
                : currentBalance + amount;
            await supabase
                .from('accounts')
                .update({'balance': newBalance})
                .eq('id', accountIdInt);
          }

          await _loadData();
          if (mounted) setState(() {});
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
            setState(() {});
          }
        }
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: BF.red,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      child: GestureDetector(
        onTap: () => _showTxSheet(context, existing: tx),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BF.card(isDark),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: isIncome
                          ? BF.green.withOpacity(0.12)
                          : catColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    alignment: Alignment.center,
                    child: isIncome
                        ? const Icon(
                            Icons.arrow_downward_rounded,
                            color: BF.green,
                            size: 20,
                          )
                        : Text(catEmoji, style: const TextStyle(fontSize: 20)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tx['title'] as String,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: catColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                tx['category'] as String,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: catColor,
                                ),
                              ),
                            ),
                            if ((acc['name'] as String? ?? '').isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Text(
                                '${acc['emoji'] ?? ''} ${acc['name']}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'Poppins',
                                  color: isDark
                                      ? Colors.white38
                                      : Colors.black38,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          DateFormat(
                            'dd MMM yyyy · hh:mm a',
                          ).format(tx['date'] as DateTime),
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'Poppins',
                            color: isDark ? Colors.white30 : Colors.black26,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${isIncome ? '+' : '-'}${currency.format(tx['amount'])}',
                        style: TextStyle(
                          color: isIncome ? BF.green : BF.red,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Poppins',
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Icon(
                        Icons.edit_rounded,
                        size: 12,
                        color: isDark ? Colors.white24 : Colors.black26,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.05)
                      : Colors.black.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Running Balance',
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                    Text(
                      currency.format(runningBalance),
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        color: runningBalance >= 0 ? BF.green : BF.red,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _activitySummaryBar(List<Map<String, dynamic>> txs, bool isDark) {
    double inc = 0, exp = 0;
    for (final tx in txs) {
      if (tx['isTransfer'] == true) continue;
      if (tx['isIncome'] as bool) {
        inc += tx['amount'] as double;
      } else {
        exp += tx['amount'] as double;
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: BF.accent.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: BF.accent.withOpacity(0.15)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '${txs.length} transaction${txs.length != 1 ? 's' : ''}',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
          Row(
            children: [
              Text(
                '+${currency.format(inc)}',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: BF.green,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '-${currency.format(exp)}',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: BF.red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PROFILE PAGE
  // ══════════════════════════════════════════════════════════════════════════
  Widget _profilePage() {
    final isDark = _isDarkMode;
    final allStats = _allTimeStats;
    final monthStats = _thisMonthStats;
    final totalIncome = allStats['income']!;
    final totalExpense = allStats['expense']!;
    final netWorth = _balance;
    final savingsRate = totalIncome > 0
        ? ((totalIncome - totalExpense) / totalIncome * 100).clamp(0.0, 100.0)
        : 0.0;
    final txCount = _s.transactions.length;
    final goalCount = _s.savingsGoals.length;
    final accCount = _s.accounts.length;

    final Map<String, double> catMap = {};
    for (final tx in _s.transactions.where((t) => !(t['isIncome'] as bool))) {
      final c = tx['category'] as String;
      catMap[c] = (catMap[c] ?? 0) + (tx['amount'] as double);
    }
    final topCats =
        (catMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .take(3)
            .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF1A2F6E),
                  Color(0xFF3B30C4),
                  Color(0xFF6C63FF),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.all(Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Color(0x4D6C63FF),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap: _pickProfileImage,
                  child: Stack(
                    children: [
                      _avatarWidget(widget.username, size: 84),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF3B30C4),
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.camera_alt_rounded,
                            size: 13,
                            color: Color(0xFF3B30C4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  widget.username,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Poppins',
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'BudgetFlow Member',
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: 'Poppins',
                    color: Colors.white.withOpacity(0.55),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _heroStat('$txCount', 'Transactions'),
                    _heroDivider(),
                    _heroStat('$goalCount', 'Goals'),
                    _heroDivider(),
                    _heroStat('$accCount', 'Accounts'),
                  ],
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => _saveThemePref(!_isDarkMode),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isDark
                              ? Icons.wb_sunny_rounded
                              : Icons.nightlight_round,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isDark
                              ? 'Switch to Light Mode'
                              : 'Switch to Dark Mode',
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _sectionHead('Financial Summary', isDark),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  BF.accent.withOpacity(0.15),
                  BF.accentSoft.withOpacity(0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: BF.accent.withOpacity(0.25)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: BF.accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: BF.accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Net Worth',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.black45,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        currency.format(netWorth),
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w800,
                          fontSize: 22,
                          color: netWorth >= 0 ? BF.green : BF.red,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${savingsRate.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: BF.accent,
                      ),
                    ),
                    Text(
                      'savings rate',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _profileFinCard(
                  'Total Income',
                  currency.format(totalIncome),
                  BF.green,
                  Icons.arrow_downward_rounded,
                  isDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _profileFinCard(
                  'Total Spent',
                  currency.format(totalExpense),
                  BF.red,
                  Icons.arrow_upward_rounded,
                  isDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _profileFinCard(
                  'This Month In',
                  currency.format(monthStats['income']!),
                  BF.green,
                  Icons.calendar_today_rounded,
                  isDark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _profileFinCard(
                  'This Month Out',
                  currency.format(monthStats['expense']!),
                  BF.red,
                  Icons.calendar_today_rounded,
                  isDark,
                ),
              ),
            ],
          ),
          if (topCats.isNotEmpty) ...[
            const SizedBox(height: 18),
            _sectionHead('Top Spending', isDark),
            const SizedBox(height: 12),
            ...topCats.map((e) {
              final pct = totalExpense > 0 ? e.value / totalExpense : 0.0;
              final color = TxCategories.colorFor(e.key);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BF.card(isDark),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          TxCategories.emojiFor(e.key),
                          style: const TextStyle(fontSize: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            e.key,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                        Text(
                          currency.format(e.value),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: pct.clamp(0.0, 1.0),
                        backgroundColor: color.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation(color),
                        minHeight: 5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${(pct * 100).toStringAsFixed(1)}% of spending',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 10,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 18),
          _sectionHead('Features', isDark),
          const SizedBox(height: 12),
          _profileLink(
            isDark,
            Icons.wallet_rounded,
            'Budget Manager',
            const Color(0xFF3B82F6),
            () => _push(const BudgetPage()),
          ),
          _profileLink(
            isDark,
            Icons.bar_chart_rounded,
            'Reports & Analytics',
            BF.green,
            () => _push(const ReportsPage()),
          ),
          _profileLink(
            isDark,
            Icons.repeat_rounded,
            'Recurring Transactions',
            BF.amber,
            () => _push(const RecurringPage()),
          ),
          _profileLink(
            isDark,
            Icons.account_balance_rounded,
            'Accounts & Wallets',
            const Color(0xFFEC4899),
            () => _pushAndReload(const AccountsPage()),
          ),
          _profileLink(
            isDark,
            Icons.savings_rounded,
            'Savings Goals',
            const Color(0xFF8B5CF6),
            () => _pushAndReload(const SavingsPage()),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                await _clearSessionData();
                if (!mounted) return;
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const AuthPage()),
                  (route) => false,
                );
              },
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text(
                'Logout',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: BF.red,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String value, String label) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w800,
          fontSize: 18,
          color: Colors.white,
        ),
      ),
      Text(
        label,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 11,
          color: Colors.white.withOpacity(0.55),
        ),
      ),
    ],
  );

  Widget _heroDivider() =>
      Container(width: 1, height: 32, color: Colors.white.withOpacity(0.2));

  Widget _profileFinCard(
    String label,
    String value,
    Color color,
    IconData icon,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 10,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sheetHandle() => Container(
    width: 40,
    height: 4,
    decoration: BoxDecoration(
      color: _isDarkMode ? Colors.white24 : Colors.black12,
      borderRadius: BorderRadius.circular(10),
    ),
  );

  Widget _avatarWidget(String name, {double size = 44}) {
    if (_profileImagePath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: Image.file(
          File(_profileImagePath!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _avatar(name, size: size),
        ),
      );
    }
    return _avatar(name, size: size);
  }

  Widget _balanceCard(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1A2F6E), Color(0xFF3B30C4), Color(0xFF6C63FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.all(Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Color(0x4D6C63FF),
            blurRadius: 28,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total Balance',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontFamily: 'Poppins',
                  fontSize: 13,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: BF.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Live',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 11,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            currency.format(_balance),
            style: const TextStyle(
              fontSize: 36,
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontFamily: 'Poppins',
              letterSpacing: -1.0,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showTxSheet(context),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text(
                'Add Transaction',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Poppins',
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: BF.primary,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _featureGrid(bool isDark) {
    final features = [
      {
        'label': 'Budget',
        'icon': Icons.wallet_rounded,
        'color': const Color(0xFF3B82F6),
        'page': const BudgetPage(),
      },
      {
        'label': 'Reports',
        'icon': Icons.bar_chart_rounded,
        'color': BF.green,
        'page': const ReportsPage(),
      },
      {
        'label': 'Recurring',
        'icon': Icons.repeat_rounded,
        'color': BF.amber,
        'page': const RecurringPage(),
      },
      {
        'label': 'Accounts',
        'icon': Icons.account_balance_rounded,
        'color': const Color(0xFFEC4899),
        'page': const AccountsPage(),
      },
      {
        'label': 'Savings',
        'icon': Icons.savings_rounded,
        'color': const Color(0xFF8B5CF6),
        'page': const SavingsPage(),
      },
    ];
    return Row(
      children: features.asMap().entries.map((entry) {
        final i = entry.key;
        final f = entry.value;
        final color = f['color'] as Color;
        return Expanded(
          child: GestureDetector(
            onTap: () => _pushAndReload(f['page'] as Widget),
            child: Container(
              margin: EdgeInsets.only(right: i < features.length - 1 ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BF.card(isDark),
              child: Column(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(f['icon'] as IconData, color: color, size: 19),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    f['label'] as String,
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _budgetAlerts(bool isDark) {
    final alerts = _s.budgets.where((b) {
      final spent = _s.spentInCategory(b['category'] as String);
      final limit = b['limit'] as double;
      return limit > 0 && (spent / limit) >= 0.8;
    }).toList();
    if (alerts.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        ...alerts.take(2).map((b) {
          final spent = _s.spentInCategory(b['category'] as String);
          final limit = b['limit'] as double;
          final isOver = spent > limit;
          final c = isOver ? BF.red : BF.amber;
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.withOpacity(0.07),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.withOpacity(0.25)),
            ),
            child: Row(
              children: [
                Icon(
                  isOver
                      ? Icons.warning_rounded
                      : Icons.notifications_active_rounded,
                  color: c,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isOver
                        ? "${b['category']} over budget by ${currency.format(spent - limit)}"
                        : "${b['category']} at ${((spent / limit) * 100).toStringAsFixed(0)}% of budget",
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: c,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _goalMini(Map<String, dynamic> g, bool isDark) {
    final saved = g['saved'] as double;
    final target = g['target'] as double;
    final pct = target > 0 ? (saved / target).clamp(0.0, 1.0) : 0.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BF.card(isDark),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                g['emoji'] as String? ?? '🎯',
                style: const TextStyle(fontSize: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  g['title'] as String,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              Text(
                '${(pct * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: BF.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: BF.accent.withOpacity(0.1),
              valueColor: const AlwaysStoppedAnimation(BF.accent),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                currency.format(saved),
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'Poppins',
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
              Text(
                currency.format(target),
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'Poppins',
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _txTile(Map<String, dynamic> tx, bool isDark) {
    final isIncome = tx['isIncome'] as bool;
    final isTransfer = tx['isTransfer'] as bool? ?? false;
    final id = tx['id'].toString();
    final acc = _s.accounts.firstWhere(
      (a) => a['id'].toString() == tx['accountId'].toString(),
      orElse: () => {'name': '', 'emoji': ''},
    );
    final catColor = TxCategories.colorFor(tx['category'] as String);
    final catEmoji = TxCategories.emojiFor(tx['category'] as String);

    return Dismissible(
      key: Key(id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        return await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: isDark ? BF.darkCard : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: Text(
                  'Delete Transaction?',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                content: Text(
                  'This action cannot be undone.',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(fontFamily: 'Poppins', color: BF.accent),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text(
                      'Delete',
                      style: TextStyle(fontFamily: 'Poppins', color: BF.red),
                    ),
                  ),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) async {
        try {
          final amount = tx['amount'] as double;
          final accountIdInt = int.tryParse(tx['accountId'].toString());
          if (accountIdInt == null) return;

          await supabase.from('transactions').delete().eq('id', int.parse(id));

          final account = _s.accounts.firstWhere(
            (a) => a['id'].toString() == tx['accountId'].toString(),
            orElse: () => {},
          );
          if (account.isNotEmpty) {
            final currentBalance = account['balance'] as double;
            final newBalance = isIncome
                ? currentBalance - amount
                : currentBalance + amount;
            await supabase
                .from('accounts')
                .update({'balance': newBalance})
                .eq('id', accountIdInt);
          }

          await _loadData();
          if (mounted) setState(() {});
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
            setState(() {});
          }
        }
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: BF.red,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      child: GestureDetector(
        onTap: () => _showTxSheet(context, existing: tx),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BF.card(isDark),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: isTransfer
                      ? BF.accent.withOpacity(0.12)
                      : isIncome
                      ? BF.green.withOpacity(0.12)
                      : catColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                alignment: Alignment.center,
                child: isTransfer
                    ? const Text('🔄', style: TextStyle(fontSize: 20))
                    : isIncome
                    ? const Icon(
                        Icons.arrow_downward_rounded,
                        color: BF.green,
                        size: 20,
                      )
                    : Text(catEmoji, style: const TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tx['title'] as String,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isTransfer
                                ? BF.accent.withOpacity(0.12)
                                : catColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isTransfer
                                ? 'Transfer'
                                : (tx['category'] as String),
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isTransfer ? BF.accent : catColor,
                            ),
                          ),
                        ),
                        if ((acc['name'] as String? ?? '').isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Text(
                            '${acc['emoji'] ?? ''} ${acc['name']}',
                            style: TextStyle(
                              fontSize: 10,
                              fontFamily: 'Poppins',
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      DateFormat(
                        'dd MMM yyyy · hh:mm a',
                      ).format(tx['date'] as DateTime),
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'Poppins',
                        color: isDark ? Colors.white30 : Colors.black26,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isTransfer ? '↻' : (isIncome ? '+' : '-')}${currency.format(tx['amount'])}',
                    style: TextStyle(
                      color: isTransfer
                          ? BF.accent
                          : (isIncome ? BF.green : BF.red),
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Poppins',
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Icon(
                    Icons.edit_rounded,
                    size: 12,
                    color: isDark ? Colors.white24 : Colors.black26,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _summaryTile(String label, double amount, bool isIncome, bool isDark) {
    final color = isIncome ? BF.green : BF.red;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BF.card(isDark),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              isIncome
                  ? Icons.arrow_downward_rounded
                  : Icons.arrow_upward_rounded,
              color: color,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'Poppins',
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
                Text(
                  currency.format(amount),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _catChip(String label, String percent, bool isDark) {
    final color = TxCategories.colorFor(label);
    final emoji = TxCategories.emojiFor(label);
    return Container(
      width: 130,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(14),
      decoration: BF.card(isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 14)),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontFamily: 'Poppins',
              fontSize: 12,
              color: isDark ? Colors.white : Colors.black87,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '$percent%',
            style: TextStyle(
              color: isDark ? Colors.white38 : Colors.black38,
              fontSize: 11,
              fontFamily: 'Poppins',
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHead(String title, bool isDark, {Widget? action}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            fontFamily: 'Poppins',
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        if (action != null) action,
      ],
    );
  }

  Widget _viewAll(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: BF.accent,
        ),
      ),
    );
  }

  Widget _emptyState(bool isDark, String msg, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36),
      decoration: BF.card(isDark),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.05)
                  : Colors.black.withOpacity(0.04),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(
              icon,
              size: 28,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            msg,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: isDark ? Colors.white38 : Colors.black38,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(String name, {double size = 44}) {
    final initials = name.trim().isNotEmpty
        ? name.trim().split(' ').map((e) => e[0]).take(2).join().toUpperCase()
        : 'U';
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [BF.accent, BF.accentSoft],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontFamily: 'Poppins',
          fontSize: size * 0.32,
        ),
      ),
    );
  }

  Widget _chip(String label, bool active, bool isDark, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? BF.accent
              : (isDark
                    ? Colors.white.withOpacity(0.07)
                    : Colors.black.withOpacity(0.05)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? BF.accent
                : (isDark ? BF.darkBorder : BF.lightBorder),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active
                ? Colors.white
                : (isDark ? Colors.white60 : Colors.black54),
          ),
        ),
      ),
    );
  }

  Widget _toggle(
    String label,
    bool value,
    bool current,
    bool isDark,
    StateSetter setS,
    VoidCallback fn, {
    bool isSmallScreen = false,
  }) {
    final sel = value == current;
    return Expanded(
      child: GestureDetector(
        onTap: () => setS(() => fn()),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: sel ? (value ? BF.green : BF.red) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: sel
                ? [
                    BoxShadow(
                      color: (value ? BF.green : BF.red).withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: isSmallScreen ? 12 : 14,
              color: sel
                  ? Colors.white
                  : (isDark ? Colors.white54 : Colors.black45),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheetField(
    TextEditingController ctrl,
    String label,
    bool isDark, {
    String? prefix,
    TextInputType? type,
    bool isSmallScreen = false,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      style: TextStyle(
        fontFamily: 'Poppins',
        fontSize: isSmallScreen ? 13 : 14,
        color: isDark ? Colors.white : Colors.black87,
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefix,
        prefixStyle: TextStyle(
          fontFamily: 'Poppins',
          fontSize: isSmallScreen ? 12 : 13,
          color: isDark ? Colors.white54 : Colors.black45,
        ),
        labelStyle: TextStyle(
          fontFamily: 'Poppins',
          fontSize: isSmallScreen ? 11 : 13,
          color: isDark ? Colors.white38 : Colors.black38,
        ),
        filled: true,
        fillColor: isDark ? BF.darkSurface : BF.lightBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? BF.darkBorder : BF.lightBorder,
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: BF.accent, width: 1.5),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: isSmallScreen ? 10 : 14,
        ),
      ),
    );
  }

  Widget _profileLink(
    bool isDark,
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BF.card(isDark),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Custom Donut Chart Painter ───────────────────────────────────────────────
class _DonutChartPainter extends CustomPainter {
  final double incomePercent;
  final double expensePercent;
  final Color incomeColor;
  final Color expenseColor;

  const _DonutChartPainter({
    required this.incomePercent,
    required this.expensePercent,
    required this.incomeColor,
    required this.expenseColor,
  });

  static const double _deg2rad = 3.14159265358979 / 180.0;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final strokeWidth = radius * 0.35;
    final innerRadius = radius - strokeWidth / 2;

    final bgPaint = Paint()
      ..color = Colors.grey.withOpacity(0.1)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, innerRadius, bgPaint);

    final incomeSweep = 360.0 * (incomePercent / 100.0);
    if (incomePercent > 0) {
      final incomePaint = Paint()
        ..color = incomeColor
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: innerRadius),
        -90 * _deg2rad,
        incomeSweep * _deg2rad,
        false,
        incomePaint,
      );
    }

    if (expensePercent > 0) {
      final expenseStart = -90.0 + incomeSweep;
      final expenseSweep = 360.0 * (expensePercent / 100.0);
      final expensePaint = Paint()
        ..color = expenseColor
        ..strokeWidth = strokeWidth
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: innerRadius),
        expenseStart * _deg2rad,
        expenseSweep * _deg2rad,
        false,
        expensePaint,
      );
    }

    final dotPaint = Paint()
      ..color = Colors.white.withOpacity(0.05)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, innerRadius - 15, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter old) =>
      old.incomePercent != incomePercent ||
      old.expensePercent != expensePercent;
}
