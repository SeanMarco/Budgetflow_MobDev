import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'main.dart' show BF, supabase, isDarkMode;
import 'AppState.dart';
import 'HomePage.dart' show TxCategories;

class RecurringPage extends StatefulWidget {
  const RecurringPage({super.key});

  @override
  State<RecurringPage> createState() => _RecurringPageState();
}

class _RecurringPageState extends State<RecurringPage>
    with TickerProviderStateMixin {
  final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
  bool _isLoading = false;
  bool _isProcessing = false;
  late AppState _appState;
  late AnimationController _pulseCtrl;

  bool get _isDark => isDarkMode.value;

  String get _userId => supabase.auth.currentUser?.id ?? '';

  // ── Theme helpers ─────────────────────────────────────────────────────────
  Color get _bg => _isDark ? BF.darkBg : const Color(0xFFF0F4F8);
  Color get _cardBg => _isDark ? BF.darkCard : Colors.white;
  Color get _primary => _isDark ? Colors.white : const Color(0xFF0F172A);
  Color get _secondary => _isDark ? Colors.white60 : const Color(0xFF64748B);
  Color get _tertiary => _isDark ? Colors.white30 : const Color(0xFF94A3B8);
  Color get _border => _isDark ? BF.darkBorder : const Color(0xFFE2E8F0);
  Color get _surface => _isDark ? BF.darkSurface : const Color(0xFFF8FAFC);

  BoxDecoration _card({Color? accent, double radius = 20}) => BoxDecoration(
    color: _cardBg,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: accent != null ? accent.withOpacity(0.2) : _border,
      width: 1,
    ),
    boxShadow: _isDark
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _appState = AppStateScope.of(context);
  }

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    isDarkMode.addListener(_onTheme);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadAndProcess();
    });
  }

  void _onTheme() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    isDarkMode.removeListener(_onTheme);
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Load + auto-process due recurring ────────────────────────────────────
  Future<void> _loadAndProcess() async {
    await _loadRecurring();
    await _processDueRecurring();
  }

  Future<void> _loadRecurring() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final response = await supabase
          .from('recurring_transactions')
          .select()
          .eq('user_id', _userId)
          .eq('is_active', true)
          .order('next_date', ascending: true);

      if (!mounted) return;
      _appState.recurringTransactions.clear();
      for (final item in (response as List)) {
        _appState.recurringTransactions.add({
          'id': item['id'].toString(),
          'title': item['title'] as String,
          'amount': (item['amount'] as num).toDouble(),
          'isIncome': item['is_income'] as bool,
          'frequency': item['frequency'] as String,
          'emoji': item['emoji'] as String? ?? '🔄',
          'nextDate': DateTime.parse(item['next_date'] as String),
          'category': item['category'] as String? ?? 'General',
          'isActive': item['is_active'] as bool,
          'accountId': item['account_id']?.toString() ?? '',
          'note': item['note'] as String? ?? '',
        });
      }
    } catch (e) {
      debugPrint('Error loading recurring: $e');
      if (mounted) {
        _snack('Failed to load recurring transactions', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Auto-deduct from the linked account when next_date is due
  Future<void> _processDueRecurring() async {
    if (!mounted) return;
    setState(() => _isProcessing = true);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    try {
      final due = await supabase
          .from('recurring_transactions')
          .select()
          .eq('user_id', _userId)
          .eq('is_active', true)
          .lte('next_date', today.toIso8601String());

      for (final item in (due as List)) {
        final recurringId = item['id'] as int;
        final amount = (item['amount'] as num).toDouble();
        final isIncome = item['is_income'] as bool;
        final category = item['category'] as String? ?? 'General';
        final title = item['title'] as String;
        final frequency = item['frequency'] as String;
        final nextDate = DateTime.parse(item['next_date'] as String);
        final accountId = item['account_id'];

        if (accountId == null) continue;

        // Fetch account balance
        final accResp = await supabase
            .from('accounts')
            .select()
            .eq('id', accountId)
            .eq('user_id', _userId)
            .maybeSingle();

        if (accResp == null) continue;
        final currentBalance = (accResp['balance'] as num).toDouble();
        final newBalance = isIncome
            ? currentBalance + amount
            : currentBalance - amount;

        // Insert transaction
        await supabase.from('transactions').insert({
          'user_id': _userId,
          'title': title,
          'amount': amount,
          'is_income': isIncome,
          'category': category,
          'account_id': accountId,
          'note': 'Auto-posted from recurring schedule',
          'date': now.toIso8601String(),
        });

        // Update account balance
        await supabase
            .from('accounts')
            .update({'balance': newBalance})
            .eq('id', accountId);

        // Advance next_date
        final advanced = _advanceDate(nextDate, frequency);
        await supabase
            .from('recurring_transactions')
            .update({'next_date': advanced.toIso8601String()})
            .eq('id', recurringId);
      }
      if ((due as List).isNotEmpty) await _loadRecurring();
    } catch (e) {
      debugPrint('[Recurring] process error: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
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
        final nextMonth = from.month == 12 ? 1 : from.month + 1;
        final nextYear = from.month == 12 ? from.year + 1 : from.year;
        final lastDay = DateTime(nextYear, nextMonth + 1, 0).day;
        return DateTime(
          nextYear,
          nextMonth,
          from.day > lastDay ? lastDay : from.day,
        );
    }
  }

  Future<void> _deleteRecurring(String id) async {
    try {
      await supabase
          .from('recurring_transactions')
          .update({'is_active': false})
          .eq('id', int.parse(id))
          .eq('user_id', _userId);
      _appState.deleteRecurring(id);
      if (mounted) setState(() {});
      _snack('Recurring transaction removed');
    } catch (e) {
      _snack('Error removing: $e', isError: true);
    }
  }

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Poppins')),
        backgroundColor: isError ? BF.red : BF.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // ── Statistics ────────────────────────────────────────────────────────────
  double get _totalMonthlyOutflow {
    double total = 0;
    for (final r in _appState.recurringTransactions) {
      if (r['isIncome'] as bool) continue;
      final freq = r['frequency'] as String;
      final amount = r['amount'] as double;
      switch (freq) {
        case 'Daily':
          total += amount * 30;
          break;
        case 'Weekly':
          total += amount * 4.3;
          break;
        case 'Yearly':
          total += amount / 12;
          break;
        default:
          total += amount;
      }
    }
    return total;
  }

  double get _totalMonthlyInflow {
    double total = 0;
    for (final r in _appState.recurringTransactions) {
      if (!(r['isIncome'] as bool)) continue;
      final freq = r['frequency'] as String;
      final amount = r['amount'] as double;
      switch (freq) {
        case 'Daily':
          total += amount * 30;
          break;
        case 'Weekly':
          total += amount * 4.3;
          break;
        case 'Yearly':
          total += amount / 12;
          break;
        default:
          total += amount;
      }
    }
    return total;
  }

  List<Map<String, dynamic>> get _dueThisWeek {
    final now = DateTime.now();
    return _appState.recurringTransactions.where((r) {
      final next = r['nextDate'] as DateTime;
      return next.difference(now).inDays <= 7 &&
          !next.isBefore(DateTime(now.year, now.month, now.day));
    }).toList();
  }

  List<Map<String, dynamic>> get _overdue {
    final today = DateTime.now();
    return _appState.recurringTransactions.where((r) {
      final next = r['nextDate'] as DateTime;
      return next.isBefore(DateTime(today.year, today.month, today.day));
    }).toList();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final items = _appState.recurringTransactions;

    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: BF.accent,
                strokeWidth: 2,
              ),
            )
          : RefreshIndicator(
              color: BF.accent,
              backgroundColor: _cardBg,
              onRefresh: _loadAndProcess,
              child: items.isEmpty ? _emptyView() : _body(items),
            ),
      floatingActionButton: _fab(),
    );
  }

  PreferredSizeWidget _buildAppBar() => AppBar(
    backgroundColor: _bg,
    elevation: 0,
    centerTitle: true,
    title: Column(
      children: [
        Text(
          'Recurring',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: _primary,
          ),
        ),
        if (_isProcessing)
          Text(
            'Syncing…',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10,
              color: BF.accent,
            ),
          ),
      ],
    ),
    leading: IconButton(
      icon: Icon(Icons.arrow_back_ios_rounded, color: _primary, size: 20),
      onPressed: () => Navigator.pop(context),
    ),
    actions: [
      IconButton(
        icon: Icon(Icons.refresh_rounded, color: _primary, size: 20),
        onPressed: _loadAndProcess,
      ),
    ],
  );

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
      onPressed: () => _showAddSheet(),
      child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
    ),
  );

  Widget _body(List<Map<String, dynamic>> items) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      children: [
        // ── Stats overview ───────────────────────────────────────────────
        _statsRow(),
        const SizedBox(height: 16),

        // ── Overdue alert ────────────────────────────────────────────────
        if (_overdue.isNotEmpty) ...[
          _overdueAlert(),
          const SizedBox(height: 16),
        ],

        // ── Due this week ────────────────────────────────────────────────
        if (_dueThisWeek.isNotEmpty) ...[
          _sectionLabel(
            'Due This Week',
            icon: Icons.schedule_rounded,
            color: BF.amber,
          ),
          const SizedBox(height: 10),
          ..._dueThisWeek.map((r) => _recurringCard(r, highlighted: true)),
          const SizedBox(height: 20),
        ],

        // ── All schedules ────────────────────────────────────────────────
        _sectionLabel(
          'All Schedules',
          icon: Icons.repeat_rounded,
          color: BF.accent,
        ),
        const SizedBox(height: 10),
        ...items.map((r) => _recurringCard(r)),
      ],
    );
  }

  // ── Stats row ─────────────────────────────────────────────────────────────
  Widget _statsRow() {
    return Row(
      children: [
        Expanded(
          child: _statPill(
            label: 'Monthly Out',
            value: currency.format(_totalMonthlyOutflow),
            color: BF.red,
            icon: Icons.arrow_upward_rounded,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _statPill(
            label: 'Monthly In',
            value: currency.format(_totalMonthlyInflow),
            color: BF.green,
            icon: Icons.arrow_downward_rounded,
          ),
        ),
      ],
    );
  }

  Widget _statPill({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _card(accent: color),
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
                    fontSize: 9,
                    color: _secondary,
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

  // ── Overdue alert ─────────────────────────────────────────────────────────
  Widget _overdueAlert() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BF.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BF.red.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, __) => Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: BF.red.withOpacity(0.1 + _pulseCtrl.value * 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: BF.red,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_overdue.length} overdue payment${_overdue.length > 1 ? 's' : ''}',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: BF.red,
                  ),
                ),
                Text(
                  'These will auto-post when synced',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: BF.red.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _processDueRecurring,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: BF.red,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Process',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section label ─────────────────────────────────────────────────────────
  Widget _sectionLabel(String text, {IconData? icon, Color? color}) => Row(
    children: [
      if (icon != null) ...[
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: (color ?? BF.accent).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color ?? BF.accent, size: 14),
        ),
        const SizedBox(width: 10),
      ],
      Text(
        text,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          fontFamily: 'Poppins',
          color: _primary,
        ),
      ),
      const SizedBox(width: 8),
      Expanded(child: Divider(color: _border, height: 1)),
    ],
  );

  // ── Recurring card ────────────────────────────────────────────────────────
  Widget _recurringCard(Map<String, dynamic> r, {bool highlighted = false}) {
    final isIncome = r['isIncome'] as bool;
    final next = r['nextDate'] as DateTime;
    final now = DateTime.now();
    final daysUntil = next
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    final color = isIncome ? BF.green : BF.red;
    final isOverdue = daysUntil < 0;
    final isDueSoon = daysUntil >= 0 && daysUntil <= 3;
    final catColor = TxCategories.colorFor(r['category'] as String);

    // Linked account info
    final accountId = r['accountId'] as String? ?? '';
    final linkedAccount = _appState.accounts.firstWhere(
      (a) => a['id'].toString() == accountId,
      orElse: () => <String, dynamic>{},
    );
    final hasAccount = linkedAccount.isNotEmpty;

    Color borderColor = _border;
    if (isOverdue) borderColor = BF.red.withOpacity(0.5);
    if (isDueSoon && !isOverdue) borderColor = BF.amber.withOpacity(0.5);

    return Dismissible(
      key: Key('${r['id']}_card'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        return await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: _cardBg,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: Text(
                  'Remove Recurring?',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    color: _primary,
                  ),
                ),
                content: Text(
                  'Stop "${r['title']}" from recurring?',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: _secondary,
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
                      'Remove',
                      style: TextStyle(fontFamily: 'Poppins', color: BF.red),
                    ),
                  ),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) => _deleteRecurring(r['id'] as String),
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: BF.red,
          borderRadius: BorderRadius.circular(18),
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
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: borderColor,
            width: (isOverdue || isDueSoon) ? 1.5 : 1,
          ),
          boxShadow: _isDark
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
                ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // ── Emoji icon ─────────────────────────────────────────
                  Stack(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Center(
                          child: Text(
                            r['emoji'] as String? ?? '🔄',
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      ),
                      if (isOverdue)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: const BoxDecoration(
                              color: BF.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.priority_high_rounded,
                              color: Colors.white,
                              size: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  // ── Info ───────────────────────────────────────────────
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r['title'] as String,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontFamily: 'Poppins',
                            fontSize: 15,
                            color: _primary,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _pill(r['frequency'] as String, BF.accent),
                            _pill(r['category'] as String, catColor),
                            _duePill(daysUntil, isOverdue),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // ── Amount ─────────────────────────────────────────────
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${isIncome ? '+' : '-'}${currency.format(r['amount'])}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontFamily: 'Poppins',
                          fontSize: 16,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('MMM dd, yyyy').format(next),
                        style: TextStyle(
                          fontSize: 10,
                          fontFamily: 'Poppins',
                          color: _tertiary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // ── Account footer ───────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: _isDark
                    ? Colors.white.withOpacity(0.03)
                    : const Color(0xFFF8FAFC),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
                border: Border(top: BorderSide(color: _border, width: 1)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 12,
                    color: _tertiary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: hasAccount
                        ? Row(
                            children: [
                              Text(
                                linkedAccount['emoji'] as String? ?? '💰',
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                linkedAccount['name'] as String,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _secondary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '· ${currency.format(linkedAccount['balance'] as double)}',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 10,
                                  color: _tertiary,
                                ),
                              ),
                            ],
                          )
                        : Text(
                            'No account linked',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 11,
                              color: BF.red.withOpacity(0.7),
                            ),
                          ),
                  ),
                  // Next occurrence countdown
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isOverdue
                          ? BF.red.withOpacity(0.1)
                          : BF.accent.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.autorenew_rounded,
                          size: 10,
                          color: isOverdue ? BF.red : BF.accent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _nextOccurrenceLabel(daysUntil),
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: isOverdue ? BF.red : BF.accent,
                          ),
                        ),
                      ],
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

  Widget _pill(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontFamily: 'Poppins',
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: color,
      ),
    ),
  );

  Widget _duePill(int daysUntil, bool isOverdue) {
    Color c;
    String label;
    if (isOverdue) {
      c = BF.red;
      label = 'Overdue';
    } else if (daysUntil == 0) {
      c = BF.red;
      label = 'Due today';
    } else if (daysUntil <= 3) {
      c = BF.amber;
      label = 'In $daysUntil day${daysUntil == 1 ? '' : 's'}';
    } else {
      c = _secondary;
      label = 'In $daysUntil days';
    }
    return _pill(label, c);
  }

  String _nextOccurrenceLabel(int daysUntil) {
    if (daysUntil < 0) return 'Overdue';
    if (daysUntil == 0) return 'Today';
    if (daysUntil == 1) return 'Tomorrow';
    return 'In $daysUntil days';
  }

  // ── Empty state ───────────────────────────────────────────────────────────
  Widget _emptyView() => Center(
    child: SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              gradient: BF.tealGradient,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: BF.accent.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.repeat_rounded,
              size: 40,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No Recurring Transactions',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              fontFamily: 'Poppins',
              color: _primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Automate your bills, subscriptions\nand regular income',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Poppins',
              color: _secondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: _showAddSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              decoration: BoxDecoration(
                gradient: BF.tealGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: BF.accent.withOpacity(0.3),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.add_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Add First Recurring',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
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
  );

  // ══════════════════════════════════════════════════════════════════════════
  // ADD SHEET — DraggableScrollableSheet with chip-based category selector
  // ══════════════════════════════════════════════════════════════════════════
  void _showAddSheet() {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    bool isIncome = false;
    String frequency = 'Monthly';
    String emoji = '🔄';
    DateTime nextDate = DateTime.now().add(const Duration(days: 30));
    String category = 'General';
    String selectedAccountId = _appState.accounts.isNotEmpty
        ? _appState.accounts[0]['id'].toString()
        : '';
    bool isSaving = false;

    const emojis = [
      '🔄',
      '💡',
      '📱',
      '🏠',
      '💳',
      '🎬',
      '🌐',
      '🚗',
      '💊',
      '📚',
      '🎮',
      '✈️',
      '🛒',
      '🎵',
      '🏋️',
      '🍔',
      '☕',
      '🎯',
    ];
    const freqs = ['Daily', 'Weekly', 'Monthly', 'Yearly'];
    const categories = [
      'General',
      'Bills & Utilities',
      'Subscriptions',
      'Entertainment',
      'Transportation',
      'Food',
      'Shopping',
      'Insurance',
      'Health / Medical',
      'Education',
      'Savings',
      'Investments',
    ];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => DraggableScrollableSheet(
          initialChildSize: 0.78,
          minChildSize: 0.5,
          maxChildSize: 0.92,
          expand: false,
          builder: (sheetCtx, scrollCtrl) => Container(
            decoration: BoxDecoration(
              color: _isDark ? BF.darkCard : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              border: Border(top: BorderSide(color: _border, width: 1)),
            ),
            child: Column(
              children: [
                // ── Fixed header (handle + title) ────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: _border,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              gradient: BF.tealGradient,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.repeat_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'New Recurring',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'Poppins',
                              color: _primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: _border),

                // ── Scrollable form body ─────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollCtrl,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.only(
                      left: 20,
                      right: 20,
                      top: 16,
                      bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 28,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Emoji picker ─────────────────────────────────
                        _sheetLabel('Choose Icon'),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 48,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: emojis.length,
                            itemBuilder: (_, i) => GestureDetector(
                              onTap: () => setS(() => emoji = emojis[i]),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 44,
                                height: 44,
                                margin: const EdgeInsets.only(right: 8),
                                decoration: BoxDecoration(
                                  color: emoji == emojis[i]
                                      ? BF.accent.withOpacity(0.15)
                                      : _surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: emoji == emojis[i]
                                        ? BF.accent
                                        : _border,
                                    width: emoji == emojis[i] ? 1.5 : 1,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    emojis[i],
                                    style: const TextStyle(fontSize: 20),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Income / Expense toggle ───────────────────────
                        Container(
                          height: 50,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: _surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _border),
                          ),
                          child: Row(
                            children: [
                              for (final isInc in [false, true])
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => setS(() => isIncome = isInc),
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      margin: const EdgeInsets.all(3),
                                      decoration: BoxDecoration(
                                        gradient: isIncome == isInc
                                            ? (isInc
                                                  ? const LinearGradient(
                                                      colors: [
                                                        Color(0xFF00C9A7),
                                                        Color(0xFF00E5A0),
                                                      ],
                                                    )
                                                  : const LinearGradient(
                                                      colors: [
                                                        Color(0xFFFF5A5F),
                                                        Color(0xFFFF8A65),
                                                      ],
                                                    ))
                                            : null,
                                        color: isIncome == isInc
                                            ? null
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(10),
                                        boxShadow: isIncome == isInc
                                            ? [
                                                BoxShadow(
                                                  color:
                                                      (isInc
                                                              ? BF.green
                                                              : BF.red)
                                                          .withOpacity(0.3),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 3),
                                                ),
                                              ]
                                            : [],
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        isInc ? 'Income' : 'Expense',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                          color: isIncome == isInc
                                              ? Colors.white
                                              : _tertiary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // ── Title & Amount ────────────────────────────────
                        _sheetField(titleCtrl, 'Title', isDark: _isDark),
                        const SizedBox(height: 12),
                        _sheetField(
                          amountCtrl,
                          'Amount',
                          isDark: _isDark,
                          prefix: '₱ ',
                          type: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _sheetField(
                          noteCtrl,
                          'Note (optional)',
                          isDark: _isDark,
                        ),
                        const SizedBox(height: 16),

                        // ── Account selector ──────────────────────────────
                        _sheetLabel('Deduct / Credit From Account'),
                        const SizedBox(height: 8),
                        if (_appState.accounts.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: BF.red.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: BF.red.withOpacity(0.25),
                              ),
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
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration: BoxDecoration(
                              color: _surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: _border),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: selectedAccountId.isNotEmpty
                                    ? selectedAccountId
                                    : null,
                                isExpanded: true,
                                dropdownColor: _isDark
                                    ? BF.darkCard
                                    : Colors.white,
                                hint: Text(
                                  'Select account',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 13,
                                    color: _secondary,
                                  ),
                                ),
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 14,
                                  color: _primary,
                                ),
                                icon: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: _secondary,
                                ),
                                items: _appState.accounts.map((a) {
                                  final balance = a['balance'] as double;
                                  return DropdownMenuItem<String>(
                                    value: a['id'].toString(),
                                    child: Row(
                                      children: [
                                        Text(
                                          a['emoji'] as String? ?? '💰',
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                a['name'] as String,
                                                style: const TextStyle(
                                                  fontFamily: 'Poppins',
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              Text(
                                                '${a['type']} · ${currency.format(balance)}',
                                                style: TextStyle(
                                                  fontFamily: 'Poppins',
                                                  fontSize: 10,
                                                  color: _tertiary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: (v) {
                                  if (v != null) {
                                    setS(() => selectedAccountId = v);
                                  }
                                },
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),

                        // ── Category chips ────────────────────────────────
                        _sheetLabel('Category'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: categories.map((c) {
                            final sel = category == c;
                            final catColor = TxCategories.colorFor(c);
                            return GestureDetector(
                              onTap: () => setS(() => category = c),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: sel
                                      ? catColor.withOpacity(0.15)
                                      : _surface,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: sel ? catColor : _border,
                                    width: sel ? 1.5 : 1,
                                  ),
                                  boxShadow: sel
                                      ? [
                                          BoxShadow(
                                            color: catColor.withOpacity(0.2),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ]
                                      : [],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      TxCategories.emojiFor(c),
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      c,
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: sel ? catColor : _secondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),

                        // ── Frequency ─────────────────────────────────────
                        _sheetLabel('Frequency'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: freqs.map((f) {
                            final sel = frequency == f;
                            return GestureDetector(
                              onTap: () => setS(() => frequency = f),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  color: sel ? BF.accent : _surface,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: sel ? BF.accent : _border,
                                  ),
                                  boxShadow: sel
                                      ? [
                                          BoxShadow(
                                            color: BF.accent.withOpacity(0.25),
                                            blurRadius: 8,
                                            offset: const Offset(0, 3),
                                          ),
                                        ]
                                      : [],
                                ),
                                child: Text(
                                  f,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: sel ? Colors.white : _secondary,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),

                        // ── Start date picker ─────────────────────────────
                        _sheetLabel('Start Date'),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: nextDate,
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365 * 5),
                              ),
                              builder: (context, child) => Theme(
                                data: Theme.of(context).copyWith(
                                  colorScheme: ColorScheme.fromSeed(
                                    seedColor: BF.accent,
                                    brightness: _isDark
                                        ? Brightness.dark
                                        : Brightness.light,
                                  ),
                                ),
                                child: child!,
                              ),
                            );
                            if (picked != null && ctx.mounted) {
                              setS(() => nextDate = picked);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: _surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: _border),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: BF.accent.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: const Icon(
                                    Icons.calendar_today_rounded,
                                    size: 15,
                                    color: BF.accent,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Next occurrence',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 10,
                                        color: _tertiary,
                                      ),
                                    ),
                                    Text(
                                      DateFormat(
                                        'EEEE, MMM dd, yyyy',
                                      ).format(nextDate),
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: _primary,
                                      ),
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                Icon(
                                  Icons.edit_rounded,
                                  size: 14,
                                  color: _tertiary,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ── Save button ───────────────────────────────────
                        GestureDetector(
                          onTap: isSaving
                              ? null
                              : () async {
                                  final amount =
                                      double.tryParse(amountCtrl.text.trim()) ??
                                      0;
                                  final title = titleCtrl.text.trim();
                                  if (title.isEmpty || amount <= 0) {
                                    _snack(
                                      'Please enter a title and valid amount',
                                      isError: true,
                                    );
                                    return;
                                  }
                                  if (selectedAccountId.isEmpty) {
                                    _snack(
                                      'Please select an account',
                                      isError: true,
                                    );
                                    return;
                                  }
                                  setS(() => isSaving = true);
                                  try {
                                    final accountIdInt = int.tryParse(
                                      selectedAccountId,
                                    );
                                    final response = await supabase
                                        .from('recurring_transactions')
                                        .insert({
                                          'user_id': _userId,
                                          'title': title,
                                          'amount': amount,
                                          'is_income': isIncome,
                                          'frequency': frequency,
                                          'emoji': emoji,
                                          'next_date': nextDate
                                              .toIso8601String(),
                                          'category': category,
                                          'is_active': true,
                                          'account_id': accountIdInt,
                                          'note': noteCtrl.text.trim(),
                                        })
                                        .select();

                                    if (!ctx.mounted) return;
                                    if ((response as List).isNotEmpty) {
                                      _appState.addRecurring({
                                        'id': response[0]['id'].toString(),
                                        'title': title,
                                        'amount': amount,
                                        'isIncome': isIncome,
                                        'frequency': frequency,
                                        'emoji': emoji,
                                        'nextDate': nextDate,
                                        'category': category,
                                        'isActive': true,
                                        'accountId': selectedAccountId,
                                        'note': noteCtrl.text.trim(),
                                      });
                                      if (mounted) setState(() {});
                                      Navigator.pop(ctx);
                                      _snack('Recurring transaction added!');
                                    }
                                  } catch (e) {
                                    _snack('Error: $e', isError: true);
                                  } finally {
                                    if (ctx.mounted) {
                                      setS(() => isSaving = false);
                                    }
                                  }
                                },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: double.infinity,
                            height: 56,
                            decoration: BoxDecoration(
                              gradient: isSaving ? null : BF.tealGradient,
                              color: isSaving ? _surface : null,
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
                                  ? SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        valueColor:
                                            const AlwaysStoppedAnimation<Color>(
                                              BF.accent,
                                            ),
                                      ),
                                    )
                                  : const Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.add_rounded,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Add Recurring',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontFamily: 'Poppins',
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sheetLabel(String text) => Text(
    text,
    style: TextStyle(
      fontFamily: 'Poppins',
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: _secondary,
    ),
  );

  Widget _sheetField(
    TextEditingController ctrl,
    String label, {
    required bool isDark,
    String? prefix,
    TextInputType? type,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      style: TextStyle(fontFamily: 'Poppins', fontSize: 14, color: _primary),
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefix,
        prefixStyle: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          color: _secondary,
        ),
        labelStyle: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 13,
          color: _secondary,
        ),
        filled: true,
        fillColor: _surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: BF.accent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}
