import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main.dart' show BF;
import 'AppState.dart';

final supabase = Supabase.instance.client;

class RecurringPage extends StatefulWidget {
  const RecurringPage({super.key});
  @override
  State<RecurringPage> createState() => _RecurringPageState();
}

class _RecurringPageState extends State<RecurringPage> {
  final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
  bool _isLoading = false;

  AppState get _s => AppStateScope.of(context);

  String get _userId => supabase.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _loadRecurringTransactions();
  }

  Future<void> _loadRecurringTransactions() async {
    setState(() => _isLoading = true);
    try {
      final response = await supabase
          .from('recurring_transactions')
          .select()
          .eq('user_id', _userId)
          .eq('is_active', true)
          .order('next_date', ascending: true);

      _s.recurringTransactions.clear();
      for (var item in response) {
        _s.recurringTransactions.add({
          'id': item['id'].toString(),
          'title': item['title'],
          'amount': (item['amount'] as num).toDouble(),
          'isIncome': item['is_income'] as bool,
          'frequency': item['frequency'],
          'emoji': item['emoji'] ?? '🔄',
          'nextDate': DateTime.parse(item['next_date']),
          'category': item['category'] ?? 'General',
          'isActive': item['is_active'] as bool,
        });
      }
    } catch (e) {
      debugPrint('Error loading recurring transactions: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading recurring transactions: $e'),
            backgroundColor: BF.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteRecurringTransaction(String id) async {
    try {
      await supabase
          .from('recurring_transactions')
          .update({'is_active': false})
          .eq('id', int.parse(id))
          .eq('user_id', _userId);

      _s.deleteRecurring(id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Recurring transaction deleted'),
            backgroundColor: BF.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting: $e'),
            backgroundColor: BF.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = _s.recurringTransactions;

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
      body: items.isEmpty
          ? _emptyView(isDark)
          : RefreshIndicator(
              color: BF.accent,
              onRefresh: _loadRecurringTransactions,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _upcomingBanner(isDark),
                  const SizedBox(height: 14),
                  _sectionLabel("Active Schedules", isDark),
                  const SizedBox(height: 12),
                  ...items.map((r) => _card(r, isDark)),
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
      onPressed: () => _showSheet(isDark),
      child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
    ),
  );

  PreferredSizeWidget _appBar(bool isDark) => AppBar(
    backgroundColor: isDark ? BF.darkBg : BF.lightBg,
    elevation: 0,
    centerTitle: true,
    title: Text(
      "Recurring Transactions",
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

  Widget _upcomingBanner(bool isDark) {
    final upcoming = _s.recurringTransactions.where((r) {
      final next = r['nextDate'] as DateTime;
      return next.difference(DateTime.now()).inDays <= 3;
    }).toList();
    if (upcoming.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BF.amber.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BF.amber.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: BF.amber.withOpacity(0.15),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.notifications_active_rounded,
              color: BF.amber,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "${upcoming.length} upcoming payment${upcoming.length > 1 ? 's' : ''}",
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: BF.amber,
                  ),
                ),
                Text(
                  "Due within the next 3 days",
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: BF.amber.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> r, bool isDark) {
    final isIncome = r['isIncome'] as bool;
    final next = r['nextDate'] as DateTime;
    final daysUntil = next.difference(DateTime.now()).inDays;
    final color = isIncome ? BF.green : BF.red;

    return Dismissible(
      key: Key(r['id'] as String),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _deleteRecurringTransaction(r['id'] as String),
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: BF.red,
          borderRadius: BorderRadius.circular(18),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete_rounded, color: Colors.white),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? BF.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: daysUntil <= 3
                ? BF.amber.withOpacity(0.4)
                : (isDark ? BF.darkBorder : BF.lightBorder),
            width: daysUntil <= 3 ? 1.5 : 1,
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
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Center(
                child: Text(
                  r['emoji'] ?? '🔄',
                  style: const TextStyle(fontSize: 22),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r['title'],
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: BF.accent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          r['frequency'],
                          style: const TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: BF.accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: daysUntil <= 0
                              ? BF.red.withOpacity(0.1)
                              : daysUntil <= 3
                              ? BF.amber.withOpacity(0.1)
                              : (isDark
                                    ? Colors.white.withOpacity(0.05)
                                    : Colors.black.withOpacity(0.04)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          daysUntil == 0
                              ? "Due today"
                              : daysUntil < 0
                              ? "Overdue"
                              : "In $daysUntil day${daysUntil == 1 ? '' : 's'}",
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            color: daysUntil <= 0
                                ? BF.red
                                : daysUntil <= 3
                                ? BF.amber
                                : (isDark ? Colors.white54 : Colors.black45),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  "${isIncome ? '+' : '-'}${currency.format(r['amount'])}",
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    color: color,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  DateFormat('MMM dd').format(next),
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
      ),
    );
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
          child: const Icon(Icons.repeat_rounded, size: 36, color: BF.accent),
        ),
        const SizedBox(height: 16),
        Text(
          "No Recurring Transactions",
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            fontFamily: 'Poppins',
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "Automate your bills & subscriptions",
          style: TextStyle(
            fontFamily: 'Poppins',
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
      ],
    ),
  );

  void _showSheet(bool isDark) {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    bool isIncome = false;
    String frequency = 'Monthly';
    String emoji = '🔄';
    DateTime nextDate = DateTime.now().add(const Duration(days: 30));
    String category = 'General';
    bool isSaving = false;

    final emojis = [
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
    ];
    final freqs = ['Daily', 'Weekly', 'Monthly', 'Yearly'];
    final categories = [
      'General',
      'Bills & Utilities',
      'Subscriptions',
      'Entertainment',
      'Transportation',
      'Food',
      'Shopping',
      'Insurance',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => Container(
          decoration: BoxDecoration(
            color: isDark ? BF.darkCard : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                _handle(isDark),
                const SizedBox(height: 20),
                Text(
                  "New Recurring Transaction",
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
                      child: _emojiBtn(emojis[i], emoji == emojis[i], isDark),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                // Income/Expense toggle
                Container(
                  height: 50,
                  decoration: BoxDecoration(
                    color: isDark ? BF.darkSurface : BF.lightBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [false, true].map((v) {
                      final sel = isIncome == v;
                      final label = v ? "Income" : "Expense";
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => setS(() => isIncome = v),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: sel
                                  ? (v ? BF.green : BF.red)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: sel
                                  ? [
                                      BoxShadow(
                                        color: (v ? BF.green : BF.red)
                                            .withOpacity(0.3),
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
                ),
                const SizedBox(height: 12),
                _field(titleCtrl, "Title", isDark),
                const SizedBox(height: 12),
                _field(
                  amountCtrl,
                  "Amount",
                  isDark,
                  prefix: "₱ ",
                  type: TextInputType.number,
                ),
                const SizedBox(height: 12),
                // Category dropdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: isDark ? BF.darkSurface : BF.lightBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? BF.darkBorder : BF.lightBorder,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: category,
                      isExpanded: true,
                      dropdownColor: isDark ? BF.darkCard : Colors.white,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      items: categories.map((c) {
                        return DropdownMenuItem<String>(
                          value: c,
                          child: Text(c),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) setS(() => category = v);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: freqs.map((f) {
                    final sel = frequency == f;
                    return GestureDetector(
                      onTap: () => setS(() => frequency = f),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: sel
                              ? BF.accent
                              : (isDark ? BF.darkSurface : BF.lightBg),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: sel
                                ? BF.accent
                                : (isDark ? BF.darkBorder : BF.lightBorder),
                          ),
                        ),
                        child: Text(
                          f,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: sel
                                ? Colors.white
                                : (isDark ? Colors.white54 : Colors.black45),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                // Next date picker
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: nextDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(
                        const Duration(days: 365 * 5),
                      ),
                    );
                    if (picked != null) setS(() => nextDate = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: isDark ? BF.darkSurface : BF.lightBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark ? BF.darkBorder : BF.lightBorder,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_today_rounded,
                          size: 16,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          "Next: ${DateFormat('MMM dd, yyyy').format(nextDate)}",
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
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
                            final amount =
                                double.tryParse(amountCtrl.text) ?? 0;
                            final title = titleCtrl.text.trim();

                            if (title.isEmpty || amount <= 0) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Please enter title and valid amount',
                                  ),
                                  backgroundColor: BF.red,
                                ),
                              );
                              return;
                            }

                            setS(() => isSaving = true);

                            try {
                              final response = await supabase
                                  .from('recurring_transactions')
                                  .insert({
                                    'user_id': _userId,
                                    'title': title,
                                    'amount': amount,
                                    'is_income': isIncome,
                                    'frequency': frequency,
                                    'emoji': emoji,
                                    'next_date': nextDate.toIso8601String(),
                                    'category': category,
                                    'is_active': true,
                                  })
                                  .select();

                              if (response.isNotEmpty) {
                                _s.addRecurring({
                                  'id': response[0]['id'].toString(),
                                  'title': title,
                                  'amount': amount,
                                  'isIncome': isIncome,
                                  'frequency': frequency,
                                  'emoji': emoji,
                                  'nextDate': nextDate,
                                  'category': category,
                                  'isActive': true,
                                });

                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Recurring transaction added',
                                      ),
                                      backgroundColor: BF.green,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                  Navigator.pop(ctx);
                                }
                              }
                            } catch (e) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    content: Text('Error: $e'),
                                    backgroundColor: BF.red,
                                  ),
                                );
                              }
                            } finally {
                              if (ctx.mounted) setS(() => isSaving = false);
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
                        : const Text("Add Recurring"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _handle(bool isDark) => Center(
    child: Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: isDark ? Colors.white24 : Colors.black12,
        borderRadius: BorderRadius.circular(10),
      ),
    ),
  );

  Widget _emojiBtn(String e, bool selected, bool isDark) => Container(
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
    child: Center(child: Text(e, style: const TextStyle(fontSize: 20))),
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
