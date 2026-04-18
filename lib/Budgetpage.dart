import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'main.dart' show BF, supabase;
import 'AppState.dart';

class BudgetPage extends StatefulWidget {
  const BudgetPage({super.key});

  @override
  State<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends State<BudgetPage> {
  final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
  bool _isLoading = false;
  late AppState _appState;

  String get _userId => supabase.auth.currentUser?.id ?? '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _appState = AppStateScope.of(context);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadBudgets();
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadBudgets() async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      final response = await supabase
          .from('budgets')
          .select()
          .eq('user_id', _userId);

      if (!mounted) return;

      _appState.budgets.clear();
      for (final budget in (response as List)) {
        _appState.budgets.add({
          'id': budget['id'].toString(),
          'category': budget['category'] as String,
          'limit': (budget['budget_limit'] as num).toDouble(),
          'period': 'Monthly',
          'emoji': _getEmojiForCategory(budget['category'] as String),
        });
      }
    } catch (e) {
      debugPrint('Error loading budgets: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to load budgets. Pull to refresh.',
              style: const TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: BF.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _getEmojiForCategory(String category) {
    const emojiMap = {
      'Food': '🍔',
      'Transportation': '🚗',
      'Bills & Utilities': '💡',
      'Rent / Housing': '🏠',
      'Entertainment': '🎮',
      'Shopping': '👕',
      'Health / Medical': '💊',
      'Education': '📚',
      'Savings': '💰',
      'Investments': '📈',
      'Debt / Loans': '💳',
      'Insurance': '🛡️',
      'Subscriptions': '🔄',
      'Travel': '✈️',
      'Personal Care': '🧴',
      'Gifts / Donations': '🎁',
      'Family / Kids': '👨‍👩‍👧',
      'Emergency': '🚨',
      'Others': '✏️',
      'General': '📌',
    };
    return emojiMap[category] ?? '💰';
  }

  double _getSpentForCategory(String category) {
    final now = DateTime.now();
    return _appState.transactions
        .where(
          (tx) =>
              tx['category'] == category &&
              !(tx['isIncome'] as bool) &&
              (tx['date'] as DateTime).month == now.month &&
              (tx['date'] as DateTime).year == now.year,
        )
        .fold(0.0, (sum, tx) => sum + (tx['amount'] as double));
  }

  double _getTotalSpent() => _appState.budgets.fold(
    0.0,
    (sum, b) => sum + _getSpentForCategory(b['category'] as String),
  );

  double _getTotalLimit() =>
      _appState.budgets.fold(0.0, (sum, b) => sum + (b['limit'] as double));

  double _getRemainingForCategory(String category, double limit) =>
      limit - _getSpentForCategory(category);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: isDark ? BF.darkBg : BF.lightBg,
        appBar: _appBar(isDark),
        body: const Center(child: CircularProgressIndicator(color: BF.accent)),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? BF.darkBg : BF.lightBg,
      appBar: _appBar(isDark),
      body: _appState.budgets.isEmpty
          ? _emptyView(isDark)
          : RefreshIndicator(
              color: BF.accent,
              onRefresh: _loadBudgets,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _overviewCard(isDark),
                  const SizedBox(height: 20),
                  _sectionLabel('Your Budgets', isDark),
                  const SizedBox(height: 12),
                  ..._appState.budgets.map((b) => _budgetCard(b, isDark)),
                  const SizedBox(height: 80),
                ],
              ),
            ),
      floatingActionButton: _fab(isDark),
    );
  }

  Widget _fab(bool isDark) => Container(
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
      onPressed: () =>
          _showSheet(Theme.of(context).brightness == Brightness.dark),
      child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
    ),
  );

  PreferredSizeWidget _appBar(bool isDark) => AppBar(
    backgroundColor: isDark ? BF.darkBg : BF.lightBg,
    elevation: 0,
    centerTitle: true,
    title: Text(
      'Budget Manager',
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
  );

  Widget _sectionLabel(String text, bool isDark) => Text(
    text,
    style: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      fontFamily: 'Poppins',
      color: isDark ? Colors.white : Colors.black87,
    ),
  );

  Widget _overviewCard(bool isDark) {
    final totalLimit = _getTotalLimit();
    final totalSpent = _getTotalSpent();
    final remaining = totalLimit - totalSpent;
    final progress = totalLimit > 0
        ? (totalSpent / totalLimit).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A2F6E), Color(0xFF3B30C4), BF.accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: BF.accent.withOpacity(0.3),
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
                'Monthly Overview',
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
                child: Text(
                  DateFormat('MMMM yyyy').format(DateTime.now()),
                  style: const TextStyle(
                    color: Colors.white,
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            currency.format(remaining),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w700,
              fontFamily: 'Poppins',
              letterSpacing: -0.8,
            ),
          ),
          Text(
            'remaining of ${currency.format(totalLimit)}',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontFamily: 'Poppins',
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withOpacity(0.18),
              valueColor: AlwaysStoppedAnimation<Color>(
                progress > 0.85 ? Colors.redAccent : Colors.white,
              ),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Spent: ${currency.format(totalSpent)}',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontFamily: 'Poppins',
                  fontSize: 12,
                ),
              ),
              Text(
                '${(progress * 100).toStringAsFixed(0)}% used',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontFamily: 'Poppins',
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _budgetCard(Map<String, dynamic> budget, bool isDark) {
    final category = budget['category'] as String;
    final limit = budget['limit'] as double;
    final spent = _getSpentForCategory(category);
    final remaining = _getRemainingForCategory(category, limit);
    final progress = limit > 0 ? (spent / limit).clamp(0.0, 1.0) : 0.0;
    final isOver = spent > limit;
    final isNear = progress >= 0.8 && !isOver;

    Color barColor = BF.green;
    if (isOver) barColor = BF.red;
    if (isNear) barColor = BF.amber;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? BF.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isOver
              ? BF.red.withOpacity(0.35)
              : isNear
              ? BF.amber.withOpacity(0.35)
              : (isDark ? BF.darkBorder : BF.lightBorder),
          width: isOver || isNear ? 1.5 : 1,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: BF.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Center(
                  child: Text(
                    budget['emoji'] as String? ?? '💰',
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Poppins',
                        fontSize: 15,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    Text(
                      budget['period'] as String? ?? 'Monthly',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'Poppins',
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                color: isDark ? BF.darkCard : Colors.white,
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                itemBuilder: (_) => [
                  PopupMenuItem<String>(
                    value: 'edit',
                    child: _menuRow(Icons.edit_rounded, 'Edit', isDark),
                  ),
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: _menuRow(
                      Icons.delete_rounded,
                      'Delete',
                      isDark,
                      danger: true,
                    ),
                  ),
                ],
                onSelected: (String val) async {
                  if (val == 'delete') await _deleteBudget(budget);
                  if (val == 'edit') _showSheet(isDark, existing: budget);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currency.format(spent),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Poppins',
                      fontSize: 20,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    'spent of ${currency.format(limit)}',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${(progress * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Poppins',
                      fontSize: 20,
                      color: barColor,
                    ),
                  ),
                  Text(
                    '${currency.format(remaining)} left',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: remaining >= 0 ? BF.green : BF.red,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: isDark
                  ? Colors.white.withOpacity(0.07)
                  : Colors.black.withOpacity(0.05),
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
              minHeight: 8,
            ),
          ),
          if (isOver || isNear) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: barColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(
                    isOver
                        ? Icons.warning_rounded
                        : Icons.notifications_active_rounded,
                    size: 13,
                    color: barColor,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isOver
                          ? 'Over budget by ${currency.format(spent - limit)}'
                          : 'Nearing limit — ${currency.format(remaining)} remaining',
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'Poppins',
                        color: barColor,
                      ),
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

  Future<void> _deleteBudget(Map<String, dynamic> budget) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? BF.darkCard : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete Budget?',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        content: Text(
          'Are you sure you want to delete the budget for ${budget['category']}?',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
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
    );

    if (confirmed != true || !mounted) return;

    try {
      await supabase
          .from('budgets')
          .delete()
          .eq('id', int.parse(budget['id'] as String))
          .eq('user_id', _userId);

      _appState.deleteBudget(budget['id'] as String);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Budget deleted successfully',
              style: TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: BF.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error deleting budget: $e',
              style: const TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: BF.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _emptyView(bool isDark) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: BF.accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Icon(Icons.wallet_rounded, size: 36, color: BF.accent),
        ),
        const SizedBox(height: 16),
        Text(
          'No Budgets Set',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            fontFamily: 'Poppins',
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tap + to create your first budget',
          style: TextStyle(
            fontFamily: 'Poppins',
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
      ],
    ),
  );

  Widget _menuRow(
    IconData icon,
    String label,
    bool isDark, {
    bool danger = false,
  }) {
    final color = danger ? BF.red : (isDark ? Colors.white : Colors.black87);
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(fontFamily: 'Poppins', color: color),
        ),
      ],
    );
  }

  // Add/Edit Budget Sheet - FIXED VERSION
  void _showSheet(bool isDark, {Map<String, dynamic>? existing}) {
    // Create controllers
    final categoryCtrl = TextEditingController(
      text: existing?['category'] as String? ?? '',
    );
    final limitCtrl = TextEditingController(
      text: existing != null
          ? (existing['limit'] as double).toStringAsFixed(0)
          : '',
    );

    String period = existing?['period'] as String? ?? 'Monthly';
    String emoji = existing?['emoji'] as String? ?? '💰';
    bool isSaving = false;

    // Track if the bottom sheet is still active
    bool _isSheetActive = true;

    const emojis = [
      '💰',
      '🍔',
      '🚗',
      '🏠',
      '💊',
      '📚',
      '🎮',
      '✈️',
      '👕',
      '💡',
      '📱',
      '🎬',
    ];

    // Use a GlobalKey to track the sheet's state
    final sheetStateKey = GlobalKey<State<StatefulWidget>>();

    void disposeControllers() {
      if (_isSheetActive) {
        _isSheetActive = false;
        // Add a small delay to ensure no pending rebuilds
        Future.microtask(() {
          if (!categoryCtrl.hasListeners) {
            categoryCtrl.dispose();
          }
          if (!limitCtrl.hasListeners) {
            limitCtrl.dispose();
          }
        });
      }
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          key: sheetStateKey,
          builder: (ctx, setS) {
            return PopScope(
              canPop: true,
              onPopInvoked: (didPop) {
                if (didPop && _isSheetActive) {
                  disposeControllers();
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? BF.darkCard : Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(28),
                  ),
                ),
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  top: 20,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sheetHandle(isDark),
                    const SizedBox(height: 20),
                    Text(
                      existing != null ? 'Edit Budget' : 'New Budget',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Poppins',
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 44,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: emojis.length,
                        itemBuilder: (_, i) => GestureDetector(
                          onTap: () => setS(() => emoji = emojis[i]),
                          child: _emojiBtn(
                            emojis[i],
                            emoji == emojis[i],
                            isDark,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _field(categoryCtrl, 'Category name', isDark),
                    const SizedBox(height: 12),
                    _field(
                      limitCtrl,
                      'Budget limit',
                      isDark,
                      prefix: '₱ ',
                      type: TextInputType.number,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: ['Monthly', 'Weekly'].map((p) {
                        final sel = period == p;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => setS(() => period = p),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: EdgeInsets.only(
                                right: p == 'Monthly' ? 8 : 0,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              decoration: BoxDecoration(
                                color: sel
                                    ? BF.accent
                                    : (isDark ? BF.darkSurface : BF.lightBg),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: sel
                                      ? BF.accent
                                      : (isDark
                                            ? BF.darkBorder
                                            : BF.lightBorder),
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                p,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: sel
                                      ? Colors.white
                                      : (isDark
                                            ? Colors.white54
                                            : Colors.black45),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: BF.accent,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        onPressed: isSaving
                            ? null
                            : () async {
                                final limit =
                                    double.tryParse(limitCtrl.text.trim()) ?? 0;
                                final category = categoryCtrl.text.trim();

                                if (category.isEmpty || limit <= 0) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Please enter a category and valid limit',
                                        style: TextStyle(fontFamily: 'Poppins'),
                                      ),
                                      backgroundColor: BF.red,
                                    ),
                                  );
                                  return;
                                }

                                setS(() => isSaving = true);

                                try {
                                  if (existing != null) {
                                    await supabase
                                        .from('budgets')
                                        .update({
                                          'category': category,
                                          'budget_limit': limit,
                                        })
                                        .eq(
                                          'id',
                                          int.parse(existing['id'] as String),
                                        )
                                        .eq('user_id', _userId);

                                    // Use addPostFrameCallback to update after sheet closes
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                          if (mounted && _appState != null) {
                                            _appState.updateBudget(
                                              existing['id'] as String,
                                              {
                                                ...existing,
                                                'category': category,
                                                'limit': limit,
                                                'period': period,
                                                'emoji': emoji,
                                              },
                                            );
                                          }
                                        });
                                  } else {
                                    final response =
                                        await supabase.from('budgets').insert({
                                          'user_id': _userId,
                                          'category': category,
                                          'budget_limit': limit,
                                        }).select();

                                    if (!ctx.mounted) return;
                                    if ((response as List).isNotEmpty) {
                                      // Use addPostFrameCallback to update after sheet closes
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                            if (mounted && _appState != null) {
                                              _appState.addBudget({
                                                'id': response[0]['id']
                                                    .toString(),
                                                'category': category,
                                                'limit': limit,
                                                'period': period,
                                                'emoji': emoji,
                                              });
                                            }
                                          });
                                    }
                                  }

                                  if (!ctx.mounted) return;

                                  // Close the sheet first
                                  Navigator.pop(ctx);

                                  // Show snackbar after sheet is closed
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          existing != null
                                              ? 'Budget updated successfully'
                                              : 'Budget created successfully',
                                          style: const TextStyle(
                                            fontFamily: 'Poppins',
                                          ),
                                        ),
                                        backgroundColor: BF.green,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Error: $e',
                                          style: const TextStyle(
                                            fontFamily: 'Poppins',
                                          ),
                                        ),
                                        backgroundColor: BF.red,
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
                                    : 'Create Budget',
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      // Only dispose if sheet hasn't been disposed already
      if (_isSheetActive) {
        disposeControllers();
      }
    });
  }

  Widget _sheetHandle(bool isDark) => Center(
    child: Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: isDark ? Colors.white24 : Colors.black12,
        borderRadius: BorderRadius.circular(10),
      ),
    ),
  );

  Widget _emojiBtn(String emoji, bool selected, bool isDark) => Container(
    width: 44,
    height: 44,
    margin: const EdgeInsets.only(right: 8),
    decoration: BoxDecoration(
      color: selected
          ? BF.accent.withOpacity(0.15)
          : (isDark ? BF.darkSurface : BF.lightBg),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: selected ? BF.accent : (isDark ? BF.darkBorder : BF.lightBorder),
        width: selected ? 1.5 : 1,
      ),
    ),
    child: Center(child: Text(emoji, style: const TextStyle(fontSize: 20))),
  );

  Widget _field(
    TextEditingController ctrl,
    String label,
    bool isDark, {
    String? prefix,
    TextInputType? type,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      style: TextStyle(
        fontFamily: 'Poppins',
        fontSize: 14,
        color: isDark ? Colors.white : Colors.black87,
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefix,
        prefixStyle: TextStyle(
          fontFamily: 'Poppins',
          color: isDark ? Colors.white54 : Colors.black45,
        ),
        labelStyle: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 13,
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}
