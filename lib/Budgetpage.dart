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

  // ── Filters (same as transactions) ───────────────────────────────────────
  String _searchQuery = '';
  String _filterStatus = 'All'; // All | Over Budget | Near Limit | On Track
  String _filterCategory = 'All';
  DateTimeRange? _filterDateRange;

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
      if (mounted) _loadBudgets();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ── Normalises DB values like "weekly"/"monthly" → "Weekly"/"Monthly"
  // so they match the period toggle labels in the sheet.
  String _normalisePeriod(String raw) {
    if (raw.isEmpty) return 'Monthly';
    return raw[0].toUpperCase() + raw.substring(1).toLowerCase();
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
          // ✅ FIX: read from DB; normalise capitalisation; fall back to 'Monthly'
          'period': _normalisePeriod(budget['period'] as String? ?? 'Monthly'),
          'emoji': _getEmojiForCategory(budget['category'] as String),
          'createdAt': budget['created_at'] != null
              ? DateTime.parse(budget['created_at'] as String)
              : DateTime(2000),
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
      if (mounted) setState(() => _isLoading = false);
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

  /// Returns spending for [category] that occurred STRICTLY AFTER the budget
  /// was created, and (when no date-range filter is active) within the current
  /// calendar month.
  double _getSpentForCategory(String category, {DateTime? budgetCreatedAt}) {
    final now = DateTime.now();
    final createdAt = budgetCreatedAt ?? DateTime(2000);

    if (_filterDateRange != null) {
      // Respect whichever is later: the budget creation time or the filter start
      final rangeStart = _filterDateRange!.start.isAfter(createdAt)
          ? _filterDateRange!.start
          : createdAt;
      return _appState.transactions
          .where(
            (tx) =>
                tx['category'] == category &&
                !(tx['isIncome'] as bool) &&
                (tx['date'] as DateTime).isAfter(createdAt) &&
                !(tx['date'] as DateTime).isBefore(rangeStart) &&
                (tx['date'] as DateTime).isBefore(
                  _filterDateRange!.end.add(const Duration(days: 1)),
                ),
          )
          .fold(0.0, (sum, tx) => sum + (tx['amount'] as double));
    }

    return _appState.transactions
        .where(
          (tx) =>
              tx['category'] == category &&
              !(tx['isIncome'] as bool) &&
              // STRICTLY after creation — no pre-existing transactions counted
              (tx['date'] as DateTime).isAfter(createdAt) &&
              // Current month only
              (tx['date'] as DateTime).month == now.month &&
              (tx['date'] as DateTime).year == now.year,
        )
        .fold(0.0, (sum, tx) => sum + (tx['amount'] as double));
  }

  double _getTotalSpent() => _filteredBudgets.fold(
    0.0,
    (sum, b) =>
        sum +
        _getSpentForCategory(
          b['category'] as String,
          budgetCreatedAt: b['createdAt'] as DateTime?,
        ),
  );

  double _getTotalLimit() =>
      _filteredBudgets.fold(0.0, (sum, b) => sum + (b['limit'] as double));

  double _getRemainingForCategory(Map<String, dynamic> budget) {
    final spent = _getSpentForCategory(
      budget['category'] as String,
      budgetCreatedAt: budget['createdAt'] as DateTime?,
    );
    return (budget['limit'] as double) - spent;
  }

  // ── Filtered budgets ──────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _filteredBudgets {
    return _appState.budgets.where((b) {
      final category = b['category'] as String;
      final limit = b['limit'] as double;
      final spent = _getSpentForCategory(
        category,
        budgetCreatedAt: b['createdAt'] as DateTime?,
      );
      final progress = limit > 0 ? spent / limit : 0.0;
      final isOver = spent > limit;
      final isNear = progress >= 0.8 && !isOver;

      if (_searchQuery.isNotEmpty) {
        if (!category.toLowerCase().contains(_searchQuery.toLowerCase())) {
          return false;
        }
      }

      if (_filterCategory != 'All' && category != _filterCategory) {
        return false;
      }

      if (_filterStatus == 'Over Budget' && !isOver) return false;
      if (_filterStatus == 'Near Limit' && !isNear) return false;
      if (_filterStatus == 'On Track' && (isOver || isNear)) return false;

      return true;
    }).toList();
  }

  List<String> get _categoryOptions => [
    'All',
    ..._appState.budgets.map((b) => b['category'] as String).toSet(),
  ];

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
              child: Column(
                children: [
                  // ── Filter bar ────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Column(
                      children: [
                        // Search field
                        Container(
                          height: 48,
                          decoration: BF
                              .card(isDark)
                              .copyWith(
                                borderRadius: BorderRadius.circular(14),
                              ),
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
                                  onChanged: (v) =>
                                      setState(() => _searchQuery = v),
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: 14,
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Search budgets…',
                                    hintStyle: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 14,
                                      color: isDark
                                          ? Colors.white38
                                          : Colors.black38,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                  ),
                                ),
                              ),
                              if (_searchQuery.isNotEmpty)
                                GestureDetector(
                                  onTap: () =>
                                      setState(() => _searchQuery = ''),
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 12),
                                    child: Icon(
                                      Icons.close_rounded,
                                      color: isDark
                                          ? Colors.white38
                                          : Colors.black38,
                                      size: 18,
                                    ),
                                  ),
                                )
                              else
                                const SizedBox(width: 12),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Filter chips
                        SizedBox(
                          height: 34,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              _chip(
                                'All',
                                _filterStatus == 'All' &&
                                    _filterCategory == 'All',
                                isDark,
                                () => setState(() {
                                  _filterStatus = 'All';
                                  _filterCategory = 'All';
                                  _filterDateRange = null;
                                }),
                              ),
                              _chip(
                                'Over Budget',
                                _filterStatus == 'Over Budget',
                                isDark,
                                () => setState(
                                  () => _filterStatus =
                                      _filterStatus == 'Over Budget'
                                      ? 'All'
                                      : 'Over Budget',
                                ),
                              ),
                              _chip(
                                'Near Limit',
                                _filterStatus == 'Near Limit',
                                isDark,
                                () => setState(
                                  () => _filterStatus =
                                      _filterStatus == 'Near Limit'
                                      ? 'All'
                                      : 'Near Limit',
                                ),
                              ),
                              _chip(
                                'On Track',
                                _filterStatus == 'On Track',
                                isDark,
                                () => setState(
                                  () => _filterStatus =
                                      _filterStatus == 'On Track'
                                      ? 'All'
                                      : 'On Track',
                                ),
                              ),
                              ..._categoryOptions
                                  .where((c) => c != 'All')
                                  .map(
                                    (c) => _chip(
                                      c,
                                      _filterCategory == c,
                                      isDark,
                                      () => setState(
                                        () => _filterCategory =
                                            _filterCategory == c ? 'All' : c,
                                      ),
                                    ),
                                  ),
                              _chip(
                                _filterDateRange != null
                                    ? '📅 Date ✓'
                                    : '📅 Date',
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
                  // ── Summary bar ───────────────────────────────────────────
                  if (_appState.budgets.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: _summaryBar(isDark),
                    ),
                  // ── Budget list ───────────────────────────────────────────
                  Expanded(
                    child: _filteredBudgets.isEmpty
                        ? _emptyFilterView(isDark)
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(20, 14, 20, 100),
                            children: [
                              _overviewCard(isDark),
                              const SizedBox(height: 20),
                              _sectionLabel('Your Budgets', isDark),
                              const SizedBox(height: 12),
                              ..._filteredBudgets.map(
                                (b) => _budgetCard(b, isDark),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
      floatingActionButton: _fab(isDark),
    );
  }

  // ── Summary bar ───────────────────────────────────────────────────────────
  Widget _summaryBar(bool isDark) {
    final filtered = _filteredBudgets;
    final overCount = filtered.where((b) {
      final spent = _getSpentForCategory(
        b['category'] as String,
        budgetCreatedAt: b['createdAt'] as DateTime?,
      );
      return spent > (b['limit'] as double);
    }).length;

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
            '${filtered.length} budget${filtered.length != 1 ? 's' : ''}',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
          Row(
            children: [
              Text(
                'Limit: ${currency.format(_getTotalLimit())}',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: BF.accent,
                ),
              ),
              if (overCount > 0) ...[
                const SizedBox(width: 10),
                Text(
                  '$overCount over',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: BF.red,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
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

    final periodLabel = _filterDateRange != null
        ? '${DateFormat('MMM d').format(_filterDateRange!.start)} – ${DateFormat('MMM d').format(_filterDateRange!.end)}'
        : DateFormat('MMMM yyyy').format(DateTime.now());

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
                'Overview',
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
                  periodLabel,
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
    final spent = _getSpentForCategory(
      category,
      budgetCreatedAt: budget['createdAt'] as DateTime?,
    );
    final remaining = _getRemainingForCategory(budget);
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
                    // ✅ FIX: now shows the actual period read from DB
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

  Widget _emptyFilterView(bool isDark) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
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
            Icons.search_off_rounded,
            size: 28,
            color: isDark ? Colors.white24 : Colors.black26,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'No budgets match your filters',
          style: TextStyle(
            fontFamily: 'Poppins',
            color: isDark ? Colors.white38 : Colors.black38,
            fontSize: 14,
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

  // ── Add / Edit Budget Sheet ───────────────────────────────────────────────
  static const List<Map<String, dynamic>> _budgetCategories = [
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

  void _showSheet(bool isDark, {Map<String, dynamic>? existing}) {
    final limitCtrl = TextEditingController(
      text: existing != null
          ? (existing['limit'] as double).toStringAsFixed(0)
          : '',
    );
    final customCategoryCtrl = TextEditingController();

    // ✅ FIX: seed period from the existing budget's persisted value
    String period = existing?['period'] as String? ?? 'Monthly';
    String selectedCategory = existing?['category'] as String? ?? '';
    bool isCustomCategory =
        selectedCategory.isNotEmpty &&
        !_budgetCategories.any((c) => c['label'] == selectedCategory);
    bool isSaving = false;
    bool _isSheetActive = true;

    void disposeControllers() {
      if (_isSheetActive) {
        _isSheetActive = false;
        Future.microtask(() {
          if (!limitCtrl.hasListeners) limitCtrl.dispose();
          if (!customCategoryCtrl.hasListeners) customCategoryCtrl.dispose();
        });
      }
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (ctx, setS) {
            return PopScope(
              canPop: true,
              onPopInvoked: (didPop) {
                if (didPop && _isSheetActive) disposeControllers();
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
                child: SingleChildScrollView(
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
                      const SizedBox(height: 20),
                      Text(
                        'Category',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (selectedCategory.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _categoryColor(
                              selectedCategory,
                            ).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _categoryColor(
                                selectedCategory,
                              ).withOpacity(0.35),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _categoryEmoji(selectedCategory),
                                style: const TextStyle(fontSize: 14),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                selectedCategory,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: _categoryColor(selectedCategory),
                                ),
                              ),
                              const SizedBox(width: 4),
                              GestureDetector(
                                onTap: () => setS(() {
                                  selectedCategory = '';
                                  isCustomCategory = false;
                                  customCategoryCtrl.clear();
                                }),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 12,
                                  color: _categoryColor(selectedCategory),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _budgetCategories.map((cat) {
                          final label = cat['label'] as String;
                          final emoji = cat['emoji'] as String;
                          final color = cat['color'] as Color;
                          final isSelected = selectedCategory == label;

                          if (label == 'Others') {
                            return GestureDetector(
                              onTap: () => setS(() {
                                selectedCategory = 'Others';
                                isCustomCategory = true;
                                customCategoryCtrl.text = '';
                              }),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 7,
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
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: isSelected
                                            ? Colors.white
                                            : color,
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
                              customCategoryCtrl.clear();
                            }),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 7,
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
                                    label,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 12,
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
                        _field(
                          customCategoryCtrl,
                          'Type your category…',
                          isDark,
                        ),
                      ],
                      const SizedBox(height: 14),
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
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
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
                                      double.tryParse(limitCtrl.text.trim()) ??
                                      0;

                                  final String finalCategory;
                                  if (isCustomCategory ||
                                      selectedCategory == 'Others') {
                                    final custom = customCategoryCtrl.text
                                        .trim();
                                    finalCategory = custom.isEmpty
                                        ? 'Others'
                                        : custom;
                                  } else {
                                    finalCategory = selectedCategory;
                                  }

                                  if (finalCategory.isEmpty || limit <= 0) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Please select a category and enter a valid limit',
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                          ),
                                        ),
                                        backgroundColor: BF.red,
                                      ),
                                    );
                                    return;
                                  }

                                  setS(() => isSaving = true);

                                  final resolvedEmoji = _categoryEmoji(
                                    finalCategory,
                                  );

                                  try {
                                    if (existing != null) {
                                      // ✅ FIX: include 'period' in update payload
                                      await supabase
                                          .from('budgets')
                                          .update({
                                            'category': finalCategory,
                                            'budget_limit': limit,
                                            'period': period.toLowerCase(),
                                          })
                                          .eq(
                                            'id',
                                            int.parse(existing['id'] as String),
                                          )
                                          .eq('user_id', _userId);

                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                            if (mounted) {
                                              _appState.updateBudget(
                                                existing['id'] as String,
                                                {
                                                  ...existing,
                                                  'category': finalCategory,
                                                  'limit': limit,
                                                  'period': period,
                                                  'emoji': resolvedEmoji,
                                                },
                                              );
                                            }
                                          });
                                    } else {
                                      // Capture creation time so the budget
                                      // starts with zero spending
                                      final now = DateTime.now();
                                      // ✅ FIX: include 'period' in insert payload
                                      final response = await supabase
                                          .from('budgets')
                                          .insert({
                                            'user_id': _userId,
                                            'category': finalCategory,
                                            'budget_limit': limit,
                                            'period': period.toLowerCase(),
                                            'created_at': now.toIso8601String(),
                                          })
                                          .select();

                                      if (!ctx.mounted) return;
                                      if ((response as List).isNotEmpty) {
                                        // Use the server-returned created_at
                                        // so the cutoff is precise
                                        final serverCreatedAt =
                                            response[0]['created_at'] != null
                                            ? DateTime.parse(
                                                response[0]['created_at']
                                                    as String,
                                              )
                                            : now;
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                              if (mounted) {
                                                _appState.addBudget({
                                                  'id': response[0]['id']
                                                      .toString(),
                                                  'category': finalCategory,
                                                  'limit': limit,
                                                  'period': period,
                                                  'emoji': resolvedEmoji,
                                                  'createdAt': serverCreatedAt,
                                                });
                                              }
                                            });
                                      }
                                    }

                                    if (!ctx.mounted) return;
                                    Navigator.pop(ctx);

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
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      if (_isSheetActive) disposeControllers();
    });
  }

  // ── Category helpers ──────────────────────────────────────────────────────
  Color _categoryColor(String label) {
    try {
      return _budgetCategories.firstWhere((c) => c['label'] == label)['color']
          as Color;
    } catch (_) {
      return BF.accent;
    }
  }

  String _categoryEmoji(String label) {
    try {
      return _budgetCategories.firstWhere((c) => c['label'] == label)['emoji']
          as String;
    } catch (_) {
      return '📌';
    }
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
