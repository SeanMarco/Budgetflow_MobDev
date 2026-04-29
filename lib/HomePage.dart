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
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;

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
  late AnimationController _cardAnimCtrl;

  final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱');

  String _searchQuery = '';
  String _filterCategory = 'All';
  String _filterType = 'All';
  DateTimeRange? _filterDateRange;

  AppState get _s => AppStateScope.of(context);

  double get _balance =>
      _s.accounts.fold(0.0, (s, a) => s + (a['balance'] as double));

  String get _userId => supabase.auth.currentUser?.id ?? '';

  // ── Theme helpers ──────────────────────────────────────────────────────────
  Color _bg(bool isDark) => isDark ? BF.darkBg : const Color(0xFFF5F7FA);
  Color _cardBg(bool isDark) => isDark ? BF.darkCard : Colors.white;
  Color _primaryText(bool isDark) =>
      isDark ? Colors.white : const Color(0xFF0F172A);
  Color _secondaryText(bool isDark) =>
      isDark ? Colors.white60 : const Color(0xFF64748B);
  Color _tertiaryText(bool isDark) =>
      isDark ? Colors.white30 : const Color(0xFF94A3B8);
  Color _border(bool isDark) =>
      isDark ? BF.darkBorder : const Color(0xFFE2E8F0);

  BoxDecoration _card(bool isDark, {Color? accent}) => BoxDecoration(
    color: _cardBg(isDark),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(
      color: accent != null ? accent.withOpacity(0.18) : _border(isDark),
      width: 1,
    ),
    boxShadow: isDark
        ? [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ]
        : [
            BoxShadow(
              color: const Color(0xFF64748B).withOpacity(0.07),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
            BoxShadow(
              color: const Color(0xFF64748B).withOpacity(0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
  );

  @override
  void initState() {
    super.initState();
    _fabAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();
    _cardAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    isDarkMode.addListener(_onThemeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
    _loadPrefs();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    isDarkMode.removeListener(_onThemeChanged);
    _fabAnimCtrl.dispose();
    _cardAnimCtrl.dispose();
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
      // Process recurring transactions first
      await _processRecurringTransactions();

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
          // ── FIX: read persisted period instead of hardcoding 'Monthly' ──
          'period': bud['period'] as String? ?? 'Monthly',
          'createdAt': bud['created_at'] != null
              ? DateTime.parse(bud['created_at'] as String)
              : DateTime(2000),
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
            content: Row(
              children: [
                const Icon(
                  Icons.wifi_off_rounded,
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Failed to load data. Pull to refresh.',
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 13),
                  ),
                ),
              ],
            ),
            backgroundColor: BF.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _processRecurringTransactions() async {
    if (!mounted) return;
    final s = AppStateScope.read(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    try {
      // Fetch all active recurring transactions that are due
      final due = await supabase
          .from('recurring_transactions')
          .select()
          .eq('user_id', _userId)
          .eq('is_active', true)
          .lte('next_date', today.toIso8601String());

      if ((due as List).isEmpty) return;

      for (final item in due) {
        final recurringId = item['id'] as int;
        final amount = (item['amount'] as num).toDouble();
        final isIncome = item['is_income'] as bool;
        final category = item['category'] as String? ?? 'General';
        final title = item['title'] as String;
        final frequency = item['frequency'] as String;
        final nextDate = DateTime.parse(item['next_date'] as String);

        // Find the account — use first account as default
        if (s.accounts.isEmpty) continue;
        final account = s.accounts.first;
        final accountIdInt = int.tryParse(account['id'].toString());
        if (accountIdInt == null) continue;

        final currentBalance = account['balance'] as double;
        final newBalance = isIncome
            ? currentBalance + amount
            : currentBalance - amount;

        // 1. Insert the transaction
        await supabase.from('transactions').insert({
          'user_id': _userId,
          'title': title,
          'amount': amount,
          'is_income': isIncome,
          'category': category,
          'account_id': accountIdInt,
          'note': 'Auto-posted from recurring schedule',
          'date': now.toIso8601String(),
        });

        // 2. Update account balance
        await supabase
            .from('accounts')
            .update({'balance': newBalance})
            .eq('id', accountIdInt);

        // 3. Advance next_date based on frequency
        final DateTime advancedDate = _advanceDate(nextDate, frequency);

        await supabase
            .from('recurring_transactions')
            .update({'next_date': advancedDate.toIso8601String()})
            .eq('id', recurringId);
      }

      debugPrint('[Recurring] Processed ${due.length} due item(s)');
    } catch (e) {
      debugPrint('[Recurring] Error processing recurring transactions: $e');
    }
  }

  DateTime _advanceDate(DateTime from, String frequency) {
    switch (frequency) {
      case 'Daily':
        return from.add(const Duration(days: 1));
      case 'Weekly':
        return from.add(const Duration(days: 7));
      case 'Yearly':
        return DateTime(from.year + 1, from.month, from.day);
      case 'Monthly':
      default:
        // Handle month overflow (e.g. Jan 31 → Feb 28)
        final nextMonth = from.month == 12 ? 1 : from.month + 1;
        final nextYear = from.month == 12 ? from.year + 1 : from.year;
        final lastDayOfNextMonth = DateTime(nextYear, nextMonth + 1, 0).day;
        final day = from.day > lastDayOfNextMonth
            ? lastDayOfNextMonth
            : from.day;
        return DateTime(nextYear, nextMonth, day);
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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: _border(isDark), width: 1)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
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
                color: _primaryText(isDark),
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
                        if (mounted) setState(() => _profileImagePath = null);
                      },
                    ),
                  ),
                ],
              ],
            ),
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
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withOpacity(0.2), width: 1),
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 12,
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

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isDark = _isDarkMode;

    if (_loading) {
      return Scaffold(
        backgroundColor: _bg(isDark),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: BF.tealGradient,
                  boxShadow: [
                    BoxShadow(
                      color: BF.accent.withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.waterfall_chart_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: BF.accent,
                  strokeWidth: 2,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Loading…',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: _secondaryText(isDark),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bg(isDark),
      body: SafeArea(child: _page()),
      bottomNavigationBar: _navBar(isDark),
      floatingActionButton: ScaleTransition(
        scale: CurvedAnimation(parent: _fabAnimCtrl, curve: Curves.elasticOut),
        child: _fab(),
      ),
    );
  }

  // ── FAB ───────────────────────────────────────────────────────────────────
  Widget _fab() => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(18),
      gradient: BF.tealGradient,
      boxShadow: [
        BoxShadow(
          color: BF.accent.withOpacity(0.4),
          blurRadius: 20,
          offset: const Offset(0, 8),
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

  // ── BOTTOM NAV BAR ────────────────────────────────────────────────────────
  Widget _navBar(bool isDark) {
    final items = [
      {'icon': Icons.home_rounded, 'label': 'Home'},
      {'icon': Icons.receipt_long_rounded, 'label': 'Activity'},
      {'icon': Icons.person_rounded, 'label': 'Profile'},
    ];
    return Container(
      height: 68,
      decoration: BoxDecoration(
        color: isDark ? BF.darkSurface : Colors.white,
        border: Border(top: BorderSide(color: _border(isDark), width: 1)),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: const Color(0xFF0F172A).withOpacity(0.06),
                  blurRadius: 16,
                  offset: const Offset(0, -4),
                ),
              ],
      ),
      child: Row(
        children: List.generate(items.length, (i) {
          final active = _tab == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _tab = i),
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: active
                          ? BF.accent.withOpacity(0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      items[i]['icon'] as IconData,
                      color: active
                          ? BF.accent
                          : (isDark
                                ? Colors.white.withOpacity(0.3)
                                : const Color(0xFFCBD5E1)),
                      size: 22,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    items[i]['label'] as String,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 10,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active
                          ? BF.accent
                          : (isDark
                                ? Colors.white.withOpacity(0.3)
                                : const Color(0xFFCBD5E1)),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
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
  // TRANSACTION SHEET
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
              border: Border(top: BorderSide(color: _border(isDark), width: 1)),
            ),
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
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
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          gradient: BF.tealGradient,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          existing != null
                              ? Icons.edit_rounded
                              : Icons.add_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        existing != null
                            ? 'Edit Transaction'
                            : 'New Transaction',
                        style: TextStyle(
                          fontSize: isSmallScreen ? 18 : 20,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Poppins',
                          color: _primaryText(isDark),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: isSmallScreen ? 14 : 20),
                  Container(
                    height: isSmallScreen ? 44 : 50,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.05)
                          : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _border(isDark), width: 1),
                    ),
                    child: Row(
                      children: [
                        _txToggle(
                          'Income',
                          true,
                          isIncome,
                          isDark,
                          setS,
                          () => setS(() => isIncome = true),
                          isSmallScreen: isSmallScreen,
                        ),
                        _txToggle(
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
                  SizedBox(height: isSmallScreen ? 12 : 16),
                  _sheetField(
                    amountCtrl,
                    'Amount',
                    isDark,
                    prefix: '₱ ',
                    type: const TextInputType.numberWithOptions(decimal: true),
                    isSmallScreen: isSmallScreen,
                  ),
                  SizedBox(height: isSmallScreen ? 10 : 12),
                  _sheetField(
                    noteCtrl,
                    'Title / Note',
                    isDark,
                    isSmallScreen: isSmallScreen,
                  ),
                  SizedBox(height: isSmallScreen ? 12 : 16),
                  Text(
                    'Category',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: isSmallScreen ? 12 : 13,
                      fontWeight: FontWeight.w600,
                      color: _secondaryText(isDark),
                    ),
                  ),
                  SizedBox(height: isSmallScreen ? 8 : 10),
                  if (selectedCategory.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: TxCategories.colorFor(
                          selectedCategory,
                        ).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: TxCategories.colorFor(
                            selectedCategory,
                          ).withOpacity(0.3),
                          width: 1,
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
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => setS(() {
                              selectedCategory = '';
                              isCustomCategory = false;
                              categoryCtrl.clear();
                            }),
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: TxCategories.colorFor(
                                  selectedCategory,
                                ).withOpacity(0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.close_rounded,
                                size: 10,
                                color: TxCategories.colorFor(selectedCategory),
                              ),
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
                              horizontal: isSmallScreen ? 9 : 12,
                              vertical: isSmallScreen ? 5 : 7,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? color
                                  : color.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected
                                    ? color
                                    : color.withOpacity(0.22),
                                width: 1,
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
                            horizontal: isSmallScreen ? 9 : 12,
                            vertical: isSmallScreen ? 5 : 7,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected ? color : color.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isSelected
                                  ? color
                                  : color.withOpacity(0.22),
                              width: 1,
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
                    const SizedBox(height: 10),
                    _sheetField(
                      categoryCtrl,
                      'Type your category…',
                      isDark,
                      isSmallScreen: isSmallScreen,
                    ),
                  ],
                  SizedBox(height: isSmallScreen ? 12 : 16),
                  if (appState.accounts.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? BF.darkSurface
                            : const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _border(isDark), width: 1),
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
                              color: _secondaryText(isDark),
                            ),
                          ),
                          dropdownColor: isDark ? BF.darkCard : Colors.white,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: isSmallScreen ? 12 : 14,
                            color: _primaryText(isDark),
                          ),
                          icon: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: _secondaryText(isDark),
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
                                  const SizedBox(width: 8),
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
                                    currency.format(a['balance'] as double),
                                    style: TextStyle(
                                      fontSize: isSmallScreen ? 10 : 11,
                                      fontFamily: 'Poppins',
                                      color: _tertiaryText(isDark),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (v) {
                            if (v != null) setS(() => localAccountId = v);
                          },
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: BF.red.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: BF.red.withOpacity(0.25)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: BF.red,
                            size: 16,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'No accounts found. Please create an account first.',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                color: BF.red,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(height: isSmallScreen ? 18 : 22),
                  GestureDetector(
                    onTap: isSaving
                        ? null
                        : () async {
                            final rawAmount = amountCtrl.text.trim();
                            final amount = double.tryParse(rawAmount) ?? 0;
                            if (amount <= 0) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                    'Please enter a valid positive amount',
                                    style: TextStyle(fontFamily: 'Poppins'),
                                  ),
                                  backgroundColor: BF.red,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  margin: const EdgeInsets.all(16),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                              return;
                            }
                            if (localAccountId.isEmpty) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: const Text(
                                    'Please select an account',
                                    style: TextStyle(fontFamily: 'Poppins'),
                                  ),
                                  backgroundColor: BF.red,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  margin: const EdgeInsets.all(16),
                                  duration: const Duration(seconds: 2),
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
                              if (mounted) setState(() {});
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    content: Row(
                                      children: [
                                        const Icon(
                                          Icons.check_circle_rounded,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          existing != null
                                              ? 'Transaction updated!'
                                              : 'Transaction added!',
                                          style: const TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                    backgroundColor: BF.green,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    margin: const EdgeInsets.all(16),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                                Navigator.pop(ctx);
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Error: $e',
                                      style: const TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 13,
                                      ),
                                    ),
                                    backgroundColor: BF.red,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    margin: const EdgeInsets.all(16),
                                    duration: const Duration(seconds: 3),
                                  ),
                                );
                              }
                            } finally {
                              if (ctx.mounted) setS(() => isSaving = false);
                            }
                          },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: double.infinity,
                      height: isSmallScreen ? 50 : 56,
                      decoration: BoxDecoration(
                        gradient: isSaving ? null : BF.tealGradient,
                        color: isSaving
                            ? (isDark
                                  ? Colors.white.withOpacity(0.08)
                                  : const Color(0xFFE2E8F0))
                            : null,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: isSaving
                            ? []
                            : [
                                BoxShadow(
                                  color: BF.accent.withOpacity(0.35),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                      ),
                      child: Center(
                        child: isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    BF.accent,
                                  ),
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    existing != null
                                        ? Icons.check_rounded
                                        : Icons.add_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    existing != null
                                        ? 'Save Changes'
                                        : 'Add Transaction',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ],
                              ),
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
  // DASHBOARD — clean financial layout
  // ══════════════════════════════════════════════════════════════════════════
  Widget _dashboard() {
    final isDark = _isDarkMode;
    final monthStats = _thisMonthStats;

    return RefreshIndicator(
      color: BF.accent,
      backgroundColor: isDark ? BF.darkCard : Colors.white,
      onRefresh: _loadData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Top header bar ────────────────────────────────────────────
            _dashboardHeader(isDark),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 20),

                  // ── Balance hero card ──────────────────────────────────
                  _balanceCard(isDark, monthStats),
                  const SizedBox(height: 20),

                  // ── Month income / expense pills ───────────────────────
                  _monthFlowRow(isDark, monthStats),
                  const SizedBox(height: 24),

                  // ── Wallets horizontal scroll ──────────────────────────
                  if (_s.accounts.isNotEmpty) ...[
                    _sectionHeader(
                      'Accounts',
                      isDark,
                      action: _seeAllBtn(
                        'Manage',
                        () => _pushAndReload(const AccountsPage()),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 100,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _s.accounts.length,
                        itemBuilder: (_, i) =>
                            _accountPill(_s.accounts[i], isDark),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // ── Budget progress section ────────────────────────────

                  // ── Savings goals ──────────────────────────────────────
                  if (_s.savingsGoals.isNotEmpty) ...[
                    _sectionHeader(
                      'Savings Goals',
                      isDark,
                      action: _seeAllBtn(
                        'View All',
                        () => _pushAndReload(const SavingsPage()),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._s.savingsGoals
                        .take(2)
                        .map((g) => _savingsGoalRow(g, isDark)),
                    const SizedBox(height: 24),
                  ],

                  // ── Navigation shortcuts ───────────────────────────────
                  _featureRow(isDark),
                  const SizedBox(height: 24),

                  // ── Recent transactions ────────────────────────────────
                  _sectionHeader(
                    'Recent Transactions',
                    isDark,
                    action: _s.transactions.isNotEmpty
                        ? _seeAllBtn('See All', () => setState(() => _tab = 1))
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
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top greeting bar ──────────────────────────────────────────────────────
  Widget _dashboardHeader(bool isDark) {
    final firstName = widget.username.isNotEmpty
        ? widget.username.split(' ')[0]
        : 'User';
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: isDark ? BF.darkBg : const Color(0xFFF5F7FA),
        border: Border(bottom: BorderSide(color: _border(isDark), width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_getGreeting()}, $firstName 👋',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: _primaryText(isDark),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                DateFormat('EEEE, MMM d').format(DateTime.now()),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: _secondaryText(isDark),
                ),
              ),
            ],
          ),
          Row(
            children: [
              GestureDetector(
                onTap: () => _saveThemePref(!_isDarkMode),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.07)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: _border(isDark), width: 1),
                  ),
                  child: Icon(
                    isDark ? Icons.wb_sunny_rounded : Icons.nightlight_round,
                    color: isDark ? Colors.amber : BF.accent,
                    size: 17,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => setState(() => _tab = 2),
                child: _avatarWidget(widget.username, size: 38),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Balance hero card ─────────────────────────────────────────────────────
  Widget _balanceCard(bool isDark, Map<String, double> monthStats) {
    final net = monthStats['income']! - monthStats['expense']!;
    final isPositive = net >= 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D1442), Color(0xFF0A1870), Color(0xFF0E2060)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D1442).withOpacity(0.35),
            blurRadius: 28,
            offset: const Offset(0, 10),
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
                'TOTAL BALANCE',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withOpacity(0.45),
                  letterSpacing: 1.5,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: BF.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: BF.green.withOpacity(0.25),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: BF.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Live',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            currency.format(_balance),
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -1.0,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: (isPositive ? BF.green : BF.red).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (isPositive ? BF.green : BF.red).withOpacity(0.2),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isPositive
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  color: isPositive ? BF.green : BF.red,
                  size: 15,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isPositive
                        ? 'Saving ${currency.format(net)} this ${DateFormat('MMMM').format(DateTime.now())}'
                        : 'Over budget by ${currency.format(net.abs())} this ${DateFormat('MMMM').format(DateTime.now())}',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isPositive ? BF.green : BF.red,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _showTxSheet(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      gradient: BF.tealGradient,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Text(
                      '+ Add',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Monthly income / expense row ──────────────────────────────────────────
  Widget _monthFlowRow(bool isDark, Map<String, double> monthStats) {
    final month = DateFormat('MMM').format(DateTime.now());
    return Row(
      children: [
        Expanded(
          child: _flowPill(
            label: '$month Income',
            value: monthStats['income']!,
            color: BF.green,
            icon: Icons.arrow_downward_rounded,
            isDark: isDark,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _flowPill(
            label: '$month Expenses',
            value: monthStats['expense']!,
            color: BF.red,
            icon: Icons.arrow_upward_rounded,
            isDark: isDark,
          ),
        ),
      ],
    );
  }

  Widget _flowPill({
    required String label,
    required double value,
    required Color color,
    required IconData icon,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(isDark, accent: color),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
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
                    fontSize: 9,
                    color: _secondaryText(isDark),
                    letterSpacing: 0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  currency.format(value),
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

  // ── Account pill ──────────────────────────────────────────────────────────
  Widget _accountPill(Map<String, dynamic> acc, bool isDark) {
    final Color baseColor = _parseColor(acc['color'], BF.accent);
    final balance = acc['balance'] as double;
    return GestureDetector(
      onTap: () => _pushAndReload(const AccountsPage()),
      child: Container(
        width: 160,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? BF.darkCard : Colors.white,
          gradient: isDark
              ? LinearGradient(
                  colors: [
                    baseColor.withOpacity(0.18),
                    baseColor.withOpacity(0.06),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isDark
                ? baseColor.withOpacity(0.25)
                : baseColor.withOpacity(0.18),
            width: 1,
          ),
          boxShadow: isDark
              ? []
              : [
                  BoxShadow(
                    color: baseColor.withOpacity(0.1),
                    blurRadius: 14,
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
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: baseColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    acc['emoji'] as String? ?? '💰',
                    style: const TextStyle(fontSize: 15),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        acc['name'] as String,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Colors.white70
                              : const Color(0xFF374151),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        acc['type'] as String? ?? 'Wallet',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 9,
                          color: baseColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Text(
              currency.format(balance),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: balance < 0
                    ? BF.red
                    : (isDark ? Colors.white : const Color(0xFF0F172A)),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ── Budget progress list ──────────────────────────────────────────────────
  // ── Budget progress list (only show ACTIVE budgets, hide completed) ──────
  // ── Budget progress list (HIDE completed budgets completely) ──────────────
  Widget _budgetProgressList(bool isDark) {
    final now = DateTime.now();
    // ✅ CRITICAL: Only show budgets that are NOT completed
    final activeBudgets = _s.budgets
        .where((b) => (b['isCompleted'] as bool? ?? false) == false)
        .take(3)
        .toList();

    // If no active budgets, show nothing (or a small message)
    if (activeBudgets.isEmpty) {
      return const SizedBox.shrink(); // Completely hide the section
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: _card(isDark),
      child: Column(
        children: activeBudgets.asMap().entries.map((entry) {
          final i = entry.key;
          final b = entry.value;
          final category = b['category'] as String;
          final limit = b['limit'] as double;
          final createdAt = b['createdAt'] as DateTime? ?? DateTime(2000);
          final spent = _s.transactions
              .where(
                (tx) =>
                    tx['category'] == category &&
                    !(tx['isIncome'] as bool) &&
                    (tx['date'] as DateTime).isAfter(createdAt) &&
                    (tx['date'] as DateTime).month == now.month &&
                    (tx['date'] as DateTime).year == now.year,
              )
              .fold(0.0, (s, tx) => s + (tx['amount'] as double));
          final progress = limit > 0 ? (spent / limit).clamp(0.0, 1.0) : 0.0;
          final isNear = progress >= 0.8 && progress < 1.0;
          final barColor = isNear ? BF.amber : BF.green;

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Text(
                          TxCategories.emojiFor(category),
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                category,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _primaryText(isDark),
                                ),
                              ),
                              Text(
                                '${currency.format(spent)} of ${currency.format(limit)}',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11,
                                  color: _secondaryText(isDark),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${(progress * 100).toStringAsFixed(0)}%',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: barColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress,
                        backgroundColor: barColor.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(barColor),
                        minHeight: 5,
                      ),
                    ),
                  ],
                ),
              ),
              if (i < activeBudgets.length - 1)
                Divider(
                  height: 1,
                  color: _border(isDark),
                  indent: 16,
                  endIndent: 16,
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  // ── Savings goal row ──────────────────────────────────────────────────────
  Widget _savingsGoalRow(Map<String, dynamic> g, bool isDark) {
    final saved = g['saved'] as double;
    final target = g['target'] as double;
    final pct = target > 0 ? (saved / target).clamp(0.0, 1.0) : 0.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: _card(isDark),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: BF.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              g['emoji'] as String? ?? '🎯',
              style: const TextStyle(fontSize: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  g['title'] as String,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: _primaryText(isDark),
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: pct,
                    backgroundColor: BF.accent.withOpacity(0.1),
                    valueColor: const AlwaysStoppedAnimation<Color>(BF.accent),
                    minHeight: 5,
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      currency.format(saved),
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: BF.accent,
                      ),
                    ),
                    Text(
                      currency.format(target),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 11,
                        color: _tertiaryText(isDark),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${(pct * 100).toStringAsFixed(0)}%',
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: BF.accent,
            ),
          ),
        ],
      ),
    );
  }

  // ── Feature row (compact nav links) ───────────────────────────────────────
  Widget _featureRow(bool isDark) {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Quick Access', isDark),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: _card(isDark),
          child: Row(
            children: features.asMap().entries.map((entry) {
              final i = entry.key;
              final f = entry.value;
              final color = f['color'] as Color;
              return Expanded(
                child: GestureDetector(
                  onTap: () => _pushAndReload(f['page'] as Widget),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          f['icon'] as IconData,
                          color: color,
                          size: 18,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        f['label'] as String,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: _secondaryText(isDark),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
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
        Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            color: isDark ? BF.darkBg : Colors.white,
            border: Border(
              bottom: BorderSide(color: _border(isDark), width: 1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Transactions',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                      color: _primaryText(isDark),
                    ),
                  ),
                  if (_s.transactions.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: BF.accent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: BF.accent.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        '${_s.transactions.length} total',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: BF.accent,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                height: 48,
                decoration: BoxDecoration(
                  color: isDark ? BF.darkCard : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _border(isDark), width: 1),
                  boxShadow: isDark
                      ? []
                      : [
                          BoxShadow(
                            color: const Color(0xFF0F172A).withOpacity(0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 14),
                    Icon(
                      Icons.search_rounded,
                      color: _secondaryText(isDark),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        onChanged: (v) => setState(() => _searchQuery = v),
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          color: _primaryText(isDark),
                        ),
                        decoration: InputDecoration(
                          hintText: 'Search transactions…',
                          hintStyle: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            color: _secondaryText(isDark),
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
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withOpacity(0.1)
                                  : const Color(0xFFE2E8F0),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              color: _secondaryText(isDark),
                              size: 12,
                            ),
                          ),
                        ),
                      )
                    else
                      const SizedBox(width: 12),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 34,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _filterChip(
                      'All',
                      _filterType == 'All' && _filterCategory == 'All',
                      isDark,
                      () => setState(() {
                        _filterType = 'All';
                        _filterCategory = 'All';
                        _filterDateRange = null;
                      }),
                    ),
                    _filterChip(
                      'Income',
                      _filterType == 'Income',
                      isDark,
                      () => setState(() {
                        _filterType = _filterType == 'Income'
                            ? 'All'
                            : 'Income';
                      }),
                    ),
                    _filterChip(
                      'Expense',
                      _filterType == 'Expense',
                      isDark,
                      () => setState(() {
                        _filterType = _filterType == 'Expense'
                            ? 'All'
                            : 'Expense';
                      }),
                    ),
                    ..._categories
                        .where((c) => c != 'All')
                        .map(
                          (c) => _filterChip(
                            c,
                            _filterCategory == c,
                            isDark,
                            () => setState(() {
                              _filterCategory = _filterCategory == c
                                  ? 'All'
                                  : c;
                            }),
                          ),
                        ),
                    _filterChip(
                      _filterDateRange != null ? '📅 Date ✓' : '📅 Date',
                      _filterDateRange != null,
                      isDark,
                      () async {
                        final r = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          initialDateRange: _filterDateRange,
                          builder: (context, child) => Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.fromSeed(
                                seedColor: BF.accent,
                                brightness: isDark
                                    ? Brightness.dark
                                    : Brightness.light,
                              ),
                            ),
                            child: child!,
                          ),
                        );
                        if (mounted) setState(() => _filterDateRange = r);
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
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
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
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
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
                    fontSize: 16,
                    color: _primaryText(isDark),
                  ),
                ),
                content: Text(
                  'This action cannot be undone.',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: _secondaryText(isDark),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        color: BF.accent,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text(
                      'Delete',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        color: BF.red,
                      ),
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Delete failed: $e',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                ),
                backgroundColor: BF.red,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                margin: const EdgeInsets.all(16),
              ),
            );
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.delete_rounded, color: Colors.white, size: 20),
            const SizedBox(height: 4),
            Text(
              'Delete',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
      child: GestureDetector(
        onTap: () => _showTxSheet(context, existing: tx),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          decoration: _card(isDark),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isIncome
                          ? BF.green.withOpacity(0.1)
                          : catColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: isIncome
                        ? const Icon(
                            Icons.arrow_downward_rounded,
                            color: BF.green,
                            size: 18,
                          )
                        : Text(catEmoji, style: const TextStyle(fontSize: 18)),
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
                            color: _primaryText(isDark),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: catColor.withOpacity(0.1),
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
                            color: _tertiaryText(isDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${isIncome ? '+' : '-'}${currency.format(tx['amount'])}',
                    style: TextStyle(
                      color: isIncome ? BF.green : BF.red,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Poppins',
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.04)
                      : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withOpacity(0.06)
                        : const Color(0xFFE2E8F0),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.account_balance_wallet_outlined,
                          size: 11,
                          color: _tertiaryText(isDark),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Running Balance',
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'Poppins',
                            color: _secondaryText(isDark),
                          ),
                        ),
                      ],
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
        color: BF.accent.withOpacity(isDark ? 0.06 : 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: BF.accent.withOpacity(isDark ? 0.12 : 0.15),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                Icons.receipt_long_rounded,
                size: 13,
                color: _secondaryText(isDark),
              ),
              const SizedBox(width: 6),
              Text(
                '${txs.length} transaction${txs.length != 1 ? 's' : ''}',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: _secondaryText(isDark),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Text(
                '+${currency.format(inc)}',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: BF.green,
                ),
              ),
              Container(
                width: 1,
                height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: _border(isDark),
              ),
              Text(
                '-${currency.format(exp)}',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
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
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
      child: Column(
        children: [
          // ── Profile card ────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF1A2F6E),
                  Color(0xFF3B30C4),
                  Color(0xFF6C63FF),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: BF.violet.withOpacity(isDark ? 0.3 : 0.2),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap: _pickProfileImage,
                  child: Stack(
                    children: [
                      _avatarWidget(widget.username, size: 80),
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
                            size: 12,
                            color: Color(0xFF3B30C4),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'BudgetFlow Member',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.1),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _profileStat('$txCount', 'Transactions'),
                      Container(
                        width: 1,
                        height: 30,
                        color: Colors.white.withOpacity(0.15),
                      ),
                      _profileStat('$goalCount', 'Goals'),
                      Container(
                        width: 1,
                        height: 30,
                        color: Colors.white.withOpacity(0.15),
                      ),
                      _profileStat('$accCount', 'Accounts'),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: () => _saveThemePref(!_isDarkMode),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.15),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isDark
                              ? Icons.wb_sunny_rounded
                              : Icons.nightlight_round,
                          size: 14,
                          color: isDark ? Colors.amber : Colors.white,
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

          const SizedBox(height: 16),

          // ── Net worth / savings rate ──────────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? BF.darkCard : Colors.white,
              gradient: isDark
                  ? null
                  : LinearGradient(
                      colors: [
                        BF.accent.withOpacity(0.05),
                        BF.accentSoft.withOpacity(0.02),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? BF.darkBorder : BF.accent.withOpacity(0.18),
                width: 1,
              ),
              boxShadow: isDark
                  ? []
                  : [
                      BoxShadow(
                        color: BF.accent.withOpacity(0.07),
                        blurRadius: 18,
                        offset: const Offset(0, 5),
                      ),
                    ],
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: BF.accent.withOpacity(0.12),
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
                          color: _secondaryText(isDark),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        currency.format(netWorth),
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
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
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: BF.accent,
                      ),
                    ),
                    Text(
                      'savings rate',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 10,
                        color: _tertiaryText(isDark),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

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
              const SizedBox(width: 12),
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

          const SizedBox(height: 24),
          _sectionHeader('Features', isDark),
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

          const SizedBox(height: 24),

          GestureDetector(
            onTap: () async {
              await _clearSessionData();
              if (!mounted) return;
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const AuthPage()),
                (route) => false,
              );
            },
            child: Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                color: BF.red.withOpacity(0.07),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: BF.red.withOpacity(0.22), width: 1),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.logout_rounded, color: BF.red, size: 18),
                  const SizedBox(width: 10),
                  const Text(
                    'Sign Out',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: BF.red,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared small widgets ──────────────────────────────────────────────────
  Widget _profileStat(String value, String label) => Column(
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
          fontSize: 10,
          color: Colors.white.withOpacity(0.5),
        ),
      ),
    ],
  );

  Widget _profileFinCard(
    String label,
    String value,
    Color color,
    IconData icon,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? BF.darkCard : color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? BF.darkBorder : color.withOpacity(0.15),
          width: 1,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: color.withOpacity(0.07),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 15),
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
                    color: _secondaryText(isDark),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: _card(isDark),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
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
                  color: _primaryText(isDark),
                ),
              ),
            ),
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.05)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.chevron_right_rounded,
                color: _tertiaryText(isDark),
                size: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetHandle() => Container(
    width: 38,
    height: 4,
    decoration: BoxDecoration(
      color: _isDarkMode
          ? Colors.white.withOpacity(0.15)
          : const Color(0xFFCBD5E1),
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
                    fontSize: 16,
                    color: _primaryText(isDark),
                  ),
                ),
                content: Text(
                  'This action cannot be undone.',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: _secondaryText(isDark),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        color: BF.accent,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text(
                      'Delete',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        color: BF.red,
                      ),
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
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Delete failed: $e',
                  style: const TextStyle(fontFamily: 'Poppins', fontSize: 13),
                ),
                backgroundColor: BF.red,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                margin: const EdgeInsets.all(16),
              ),
            );
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.delete_rounded, color: Colors.white, size: 20),
            const SizedBox(height: 4),
            Text(
              'Delete',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
      child: GestureDetector(
        onTap: () => _showTxSheet(context, existing: tx),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: _card(isDark),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isTransfer
                      ? BF.accent.withOpacity(0.1)
                      : isIncome
                      ? BF.green.withOpacity(0.1)
                      : catColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: isTransfer
                    ? const Text('🔄', style: TextStyle(fontSize: 18))
                    : isIncome
                    ? const Icon(
                        Icons.arrow_downward_rounded,
                        color: BF.green,
                        size: 18,
                      )
                    : Text(catEmoji, style: const TextStyle(fontSize: 18)),
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
                        color: _primaryText(isDark),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isTransfer
                                ? BF.accent.withOpacity(0.1)
                                : catColor.withOpacity(0.1),
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
                              color: _tertiaryText(isDark),
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
                        color: _tertiaryText(isDark),
                      ),
                    ),
                  ],
                ),
              ),
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, bool isDark, {Widget? action}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: _primaryText(isDark),
          ),
        ),
        if (action != null) action,
      ],
    );
  }

  Widget _seeAllBtn(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: BF.accent,
            ),
          ),
          const SizedBox(width: 2),
          const Icon(Icons.chevron_right_rounded, color: BF.accent, size: 16),
        ],
      ),
    );
  }

  Widget _emptyState(bool isDark, String msg, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36),
      decoration: _card(isDark),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.04)
                  : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              size: 26,
              color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            msg,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w500,
              color: _secondaryText(isDark),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            'Tap + to get started',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: _tertiaryText(isDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(
    String label,
    bool active,
    bool isDark,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? BF.accent
              : (isDark ? Colors.white.withOpacity(0.07) : Colors.white),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? BF.accent
                : (isDark ? BF.darkBorder : const Color(0xFFE2E8F0)),
            width: 1,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: BF.accent.withOpacity(0.22),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            color: active
                ? Colors.white
                : (isDark ? Colors.white60 : const Color(0xFF475569)),
          ),
        ),
      ),
    );
  }

  Widget _txToggle(
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
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            gradient: sel
                ? (value
                      ? const LinearGradient(
                          colors: [Color(0xFF00C9A7), Color(0xFF00E5A0)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        )
                      : const LinearGradient(
                          colors: [Color(0xFFFF5A5F), Color(0xFFFF8A65)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ))
                : null,
            color: sel ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: sel
                ? [
                    BoxShadow(
                      color: (value ? BF.green : BF.red).withOpacity(0.25),
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
                  : (isDark ? Colors.white38 : const Color(0xFF94A3B8)),
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
        color: _primaryText(isDark),
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefix,
        prefixStyle: TextStyle(
          fontFamily: 'Poppins',
          fontSize: isSmallScreen ? 12 : 14,
          fontWeight: FontWeight.w600,
          color: _secondaryText(isDark),
        ),
        labelStyle: TextStyle(
          fontFamily: 'Poppins',
          fontSize: isSmallScreen ? 11 : 13,
          color: _secondaryText(isDark),
        ),
        filled: true,
        fillColor: isDark ? BF.darkSurface : const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _border(isDark), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: BF.accent, width: 1.5),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: isSmallScreen ? 10 : 14,
        ),
      ),
    );
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }
}
