import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'main.dart' show BF, supabase;
import 'AppState.dart';

class BudgetPage extends StatefulWidget {
  const BudgetPage({super.key});

  @override
  State<BudgetPage> createState() => _BudgetPageState();
}

class _BudgetPageState extends State<BudgetPage>
    with SingleTickerProviderStateMixin {
  final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
  bool _isLoading = false;
  late AppState _appState;

  // Tab controller for active/completed budgets
  late TabController _tabController;

  // ── Filters ───────────────────────────────────────────────────────────────
  String _searchQuery = '';
  String _filterStatus = 'All'; // All | Near Limit | On Track
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
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadBudgets();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

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
          'period': _normalisePeriod(budget['period'] as String? ?? 'Monthly'),
          'emoji': _getEmojiForCategory(budget['category'] as String),
          'createdAt': budget['created_at'] != null
              ? DateTime.parse(budget['created_at'] as String)
              : DateTime(2000),
          'isCompleted': budget['is_completed'] as bool? ?? false,
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

  double _getSpentForCategory(String category, {DateTime? budgetCreatedAt}) {
    final now = DateTime.now();
    final createdAt = budgetCreatedAt ?? DateTime(2000);

    if (_filterDateRange != null) {
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
              (tx['date'] as DateTime).isAfter(createdAt) &&
              (tx['date'] as DateTime).month == now.month &&
              (tx['date'] as DateTime).year == now.year,
        )
        .fold(0.0, (sum, tx) => sum + (tx['amount'] as double));
  }

  bool _isBudgetCompleted(Map<String, dynamic> budget) {
    final spent = _getSpentForCategory(
      budget['category'] as String,
      budgetCreatedAt: budget['createdAt'] as DateTime?,
    );
    final limit = budget['limit'] as double;
    return spent >= limit;
  }

  Future<void> _markBudgetCompleted(Map<String, dynamic> budget) async {
    if (budget['isCompleted'] as bool? ?? false) return;

    try {
      await supabase
          .from('budgets')
          .update({'is_completed': true})
          .eq('id', int.parse(budget['id'] as String))
          .eq('user_id', _userId);

      _appState.updateBudget(budget['id'] as String, {
        ...budget,
        'isCompleted': true,
      });
    } catch (e) {
      debugPrint('Error marking budget as completed: $e');
    }
  }

  Future<void> _unmarkBudgetCompleted(Map<String, dynamic> budget) async {
    if (!(budget['isCompleted'] as bool? ?? false)) return;

    try {
      await supabase
          .from('budgets')
          .update({'is_completed': false})
          .eq('id', int.parse(budget['id'] as String))
          .eq('user_id', _userId);

      _appState.updateBudget(budget['id'] as String, {
        ...budget,
        'isCompleted': false,
      });
    } catch (e) {
      debugPrint('Error unmarking budget completion: $e');
    }
  }

  Future<void> _checkAndUpdateBudgetCompletions() async {
    for (final budget in _appState.budgets) {
      final isCompleted = budget['isCompleted'] as bool? ?? false;
      final shouldBeCompleted = _isBudgetCompleted(budget);

      if (shouldBeCompleted && !isCompleted) {
        await _markBudgetCompleted(budget);
      } else if (!shouldBeCompleted && isCompleted) {
        await _unmarkBudgetCompleted(budget);
      }
    }
    if (mounted) setState(() {});
  }

  double _getTotalSpent() => _filteredActiveBudgets.fold(
    0.0,
    (sum, b) =>
        sum +
        _getSpentForCategory(
          b['category'] as String,
          budgetCreatedAt: b['createdAt'] as DateTime?,
        ),
  );

  double _getTotalLimit() => _filteredActiveBudgets.fold(
    0.0,
    (sum, b) => sum + (b['limit'] as double),
  );

  List<Map<String, dynamic>> get _activeBudgets {
    return _appState.budgets.where((b) {
      return !(b['isCompleted'] as bool? ?? false);
    }).toList();
  }

  List<Map<String, dynamic>> get _completedBudgets {
    return _appState.budgets.where((b) {
      return (b['isCompleted'] as bool? ?? false);
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredActiveBudgets {
    return _activeBudgets.where((b) {
      final category = b['category'] as String;
      final limit = b['limit'] as double;
      final spent = _getSpentForCategory(
        category,
        budgetCreatedAt: b['createdAt'] as DateTime?,
      );
      final progress = limit > 0 ? spent / limit : 0.0;
      final isNear = progress >= 0.8 && progress < 1.0;

      if (_searchQuery.isNotEmpty) {
        if (!category.toLowerCase().contains(_searchQuery.toLowerCase())) {
          return false;
        }
      }

      if (_filterCategory != 'All' && category != _filterCategory) {
        return false;
      }

      if (_filterStatus == 'Near Limit' && !isNear) return false;
      if (_filterStatus == 'On Track' && isNear) return false;

      return true;
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredCompletedBudgets {
    return _completedBudgets.where((b) {
      final category = b['category'] as String;

      if (_searchQuery.isNotEmpty) {
        if (!category.toLowerCase().contains(_searchQuery.toLowerCase())) {
          return false;
        }
      }

      if (_filterCategory != 'All' && category != _filterCategory) {
        return false;
      }

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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndUpdateBudgetCompletions();
    });

    if (_isLoading) {
      return Scaffold(
        backgroundColor: isDark ? BF.darkBg : BF.lightBg,
        appBar: _appBar(isDark),
        body: const Center(child: CircularProgressIndicator(color: BF.accent)),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? BF.darkBg : BF.lightBg,
      appBar: _appBarWithTabs(isDark),
      body: _appState.budgets.isEmpty
          ? _emptyView(isDark)
          : RefreshIndicator(
              color: BF.accent,
              onRefresh: _loadBudgets,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Column(
                      children: [
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
                        if (_tabController.index == 0)
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
                                    if (mounted)
                                      setState(() => _filterDateRange = r);
                                  },
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    decoration: BoxDecoration(
                      color: isDark ? BF.darkSurface : BF.lightBg,
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        color: BF.accent,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: isDark
                          ? Colors.white54
                          : Colors.black54,
                      labelStyle: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      tabs: [
                        Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.trending_up_rounded, size: 16),
                              const SizedBox(width: 6),
                              Text('Active (${_activeBudgets.length})'),
                            ],
                          ),
                        ),
                        Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_rounded, size: 16),
                              const SizedBox(width: 6),
                              Text('Completed (${_completedBudgets.length})'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_tabController.index == 0 && _activeBudgets.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: _summaryBar(isDark),
                    ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _activeBudgets.isEmpty
                            ? _emptyActiveView(isDark)
                            : _filteredActiveBudgets.isEmpty
                            ? _emptyFilterView(isDark)
                            : ListView(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  14,
                                  20,
                                  100,
                                ),
                                children: [
                                  _overviewCard(isDark),
                                  const SizedBox(height: 20),
                                  _sectionLabel('Active Budgets', isDark),
                                  const SizedBox(height: 12),
                                  ..._filteredActiveBudgets.map(
                                    (b) => _budgetCard(b, isDark),
                                  ),
                                ],
                              ),
                        _completedBudgets.isEmpty
                            ? _emptyCompletedView(isDark)
                            : _filteredCompletedBudgets.isEmpty
                            ? _emptyFilterView(isDark)
                            : ListView(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  14,
                                  20,
                                  100,
                                ),
                                children: [
                                  _completedOverviewCard(isDark),
                                  const SizedBox(height: 20),
                                  _sectionLabel('Completed Plans', isDark),
                                  const SizedBox(height: 12),
                                  ..._filteredCompletedBudgets.map(
                                    (b) => _completedBudgetCard(b, isDark),
                                  ),
                                ],
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

  Widget _completedOverviewCard(bool isDark) {
    final totalCompleted = _filteredCompletedBudgets.length;
    final totalOriginalLimit = _filteredCompletedBudgets.fold(
      0.0,
      (sum, b) => sum + (b['limit'] as double),
    );

    final totalOverspent = _filteredCompletedBudgets.fold(0.0, (sum, b) {
      final spent = _getSpentForCategory(
        b['category'] as String,
        budgetCreatedAt: b['createdAt'] as DateTime?,
      );
      final limit = b['limit'] as double;
      final overAmount = spent - limit;
      return sum + (overAmount > 0 ? overAmount : 0);
    });

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [BF.green.withOpacity(0.8), BF.accentSoft.withOpacity(0.6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: BF.green.withOpacity(0.3),
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
                '🏆 Achievements',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$totalCompleted Completed',
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
            currency.format(totalOriginalLimit),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w700,
              fontFamily: 'Poppins',
              letterSpacing: -0.8,
            ),
          ),
          Text(
            'original budget limit${totalCompleted != 1 ? 's' : ''} achieved',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontFamily: 'Poppins',
              fontSize: 13,
            ),
          ),
          if (totalOverspent > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '⚠️ Total overspent: ${currency.format(totalOverspent)} across completed budgets',
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'Poppins',
                        fontSize: 11,
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

  Widget _completedBudgetCard(Map<String, dynamic> budget, bool isDark) {
    final category = budget['category'] as String;
    final limit = budget['limit'] as double;
    final spent = _getSpentForCategory(
      category,
      budgetCreatedAt: budget['createdAt'] as DateTime?,
    );
    final overspent = spent - limit;
    final period = budget['period'] as String? ?? 'Monthly';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? BF.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: BF.green.withOpacity(0.35), width: 1.5),
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
                  color: BF.green.withOpacity(0.1),
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
                      period,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'Poppins',
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: BF.green.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.check_circle, size: 14, color: BF.green),
                    SizedBox(width: 4),
                    Text(
                      'Completed',
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        color: BF.green,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                color: isDark ? BF.darkCard : Colors.white,
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                itemBuilder: (_) => [
                  PopupMenuItem<String>(
                    value: 'restart',
                    child: _menuRow(
                      Icons.refresh_rounded,
                      'Restart Plan',
                      isDark,
                    ),
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
                  if (val == 'restart') await _restartBudgetPlan(budget);
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
                  Row(
                    children: [
                      Text(
                        currency.format(spent),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Poppins',
                          fontSize: 20,
                          color: overspent > 0 ? BF.red : BF.green,
                        ),
                      ),
                      if (overspent > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: BF.red.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${currency.format(overspent)} over',
                            style: TextStyle(
                              fontSize: 10,
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              color: BF.red,
                            ),
                          ),
                        ),
                      ],
                    ],
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
                    '🏆 Completed',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: BF.green,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Target reached!',
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
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: 1.0,
              backgroundColor: isDark
                  ? Colors.white.withOpacity(0.07)
                  : Colors.black.withOpacity(0.05),
              valueColor: const AlwaysStoppedAnimation<Color>(BF.green),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: overspent > 0
                  ? BF.red.withOpacity(0.08)
                  : BF.green.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  overspent > 0
                      ? Icons.warning_rounded
                      : Icons.celebration_rounded,
                  size: 13,
                  color: overspent > 0 ? BF.red : BF.green,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    overspent > 0
                        ? 'Target reached but overspent by ${currency.format(overspent)}'
                        : '🎉 Congratulations! Budget target achieved!',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'Poppins',
                      color: overspent > 0 ? BF.red : BF.green,
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

  Future<void> _restartBudgetPlan(Map<String, dynamic> budget) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? BF.darkCard : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Restart Budget Plan?',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        content: Text(
          'Restarting "${budget['category']}" will mark it as active again. This will not delete past transactions.',
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
              'Restart',
              style: TextStyle(fontFamily: 'Poppins', color: BF.accent),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await supabase
          .from('budgets')
          .update({'is_completed': false})
          .eq('id', int.parse(budget['id'] as String))
          .eq('user_id', _userId);

      _appState.updateBudget(budget['id'] as String, {
        ...budget,
        'isCompleted': false,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Budget plan restarted!',
              style: TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: BF.accent,
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error restarting budget: $e',
              style: const TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: BF.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _summaryBar(bool isDark) {
    final filtered = _filteredActiveBudgets;
    final nearCount = filtered.where((b) {
      final spent = _getSpentForCategory(
        b['category'] as String,
        budgetCreatedAt: b['createdAt'] as DateTime?,
      );
      final progress = spent / (b['limit'] as double);
      return progress >= 0.8 && progress < 1.0;
    }).length;
    final completedCount = filtered.where((b) => _isBudgetCompleted(b)).length;

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
            '${filtered.length} active budget${filtered.length != 1 ? 's' : ''}',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
          Row(
            children: [
              if (completedCount > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, size: 12, color: BF.green),
                      const SizedBox(width: 4),
                      Text(
                        '$completedCount completed',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: BF.green,
                        ),
                      ),
                    ],
                  ),
                ),
              if (nearCount > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 12,
                        color: BF.amber,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$nearCount near limit',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: BF.amber,
                        ),
                      ),
                    ],
                  ),
                ),
              Text(
                'Limit: ${currency.format(_getTotalLimit())}',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: BF.accent,
                ),
              ),
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

  PreferredSizeWidget _appBarWithTabs(bool isDark) => AppBar(
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
    bottom: const PreferredSize(
      preferredSize: Size.fromHeight(0),
      child: SizedBox(),
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
    final completedCount = _filteredActiveBudgets
        .where((b) => _isBudgetCompleted(b))
        .length;

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
                progress >= 0.85 ? Colors.redAccent : Colors.white,
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
          if (completedCount > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.celebration, size: 14, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(
                    '$completedCount budget${completedCount != 1 ? 's' : ''} completed! 🎉',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
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

  Widget _budgetCard(Map<String, dynamic> budget, bool isDark) {
    final category = budget['category'] as String;
    final limit = budget['limit'] as double;
    final spent = _getSpentForCategory(
      category,
      budgetCreatedAt: budget['createdAt'] as DateTime?,
    );
    final remaining = limit - spent;
    final progress = limit > 0 ? (spent / limit).clamp(0.0, 1.0) : 0.0;
    final isNear = progress >= 0.8 && progress < 1.0;
    final isCompleted = progress >= 1.0;

    Color barColor = BF.green;
    if (isNear) barColor = BF.amber;
    if (isCompleted) barColor = BF.green;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? BF.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isNear
              ? BF.amber.withOpacity(0.35)
              : isCompleted
              ? BF.green.withOpacity(0.5)
              : (isDark ? BF.darkBorder : BF.lightBorder),
          width: isNear || isCompleted ? 1.5 : 1,
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
              if (isCompleted)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: BF.green.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.check_circle, size: 12, color: BF.green),
                      SizedBox(width: 4),
                      Text(
                        'Done!',
                        style: TextStyle(
                          fontSize: 10,
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          color: BF.green,
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
                    isCompleted
                        ? 'Target reached! 🎉'
                        : '${currency.format(remaining)} left',
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
          if (isNear || isCompleted) ...[
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
                    isCompleted
                        ? Icons.celebration_rounded
                        : Icons.notifications_active_rounded,
                    size: 13,
                    color: barColor,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isCompleted
                          ? '🎉 Congratulations! Budget target achieved!'
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

  Widget _emptyActiveView(bool isDark) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: BF.accent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(
            Icons.trending_up_rounded,
            size: 28,
            color: BF.accent,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'No active budgets',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Completed budgets appear in the Completed tab',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
      ],
    ),
  );

  Widget _emptyCompletedView(bool isDark) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: BF.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(
            Icons.celebration_rounded,
            size: 28,
            color: BF.green,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'No completed budgets yet',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Budgets will appear here when they reach 100%',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
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
                                      await supabase
                                          .from('budgets')
                                          .update({
                                            'category': finalCategory,
                                            'budget_limit': limit,
                                            'period': period.toLowerCase(),
                                            'is_completed': false,
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
                                                  'isCompleted': false,
                                                },
                                              );
                                            }
                                          });
                                    } else {
                                      final now = DateTime.now();
                                      final response = await supabase
                                          .from('budgets')
                                          .insert({
                                            'user_id': _userId,
                                            'category': finalCategory,
                                            'budget_limit': limit,
                                            'period': period.toLowerCase(),
                                            'created_at': now.toIso8601String(),
                                            'is_completed': false,
                                          })
                                          .select();

                                      if (!ctx.mounted) return;
                                      if ((response as List).isNotEmpty) {
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
                                                  'isCompleted': false,
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
                                    if (ctx.mounted)
                                      setS(() => isSaving = false);
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
          borderSide: BorderSide(color: BF.accent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}
