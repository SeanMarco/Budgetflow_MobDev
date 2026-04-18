import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
// FIXED: Removed duplicate `final supabase = Supabase.instance.client;`
// Import supabase from main.dart to avoid duplicate-global-variable warnings.
import 'main.dart' show BF, supabase;
import 'AppState.dart';

class SavingsPage extends StatefulWidget {
  const SavingsPage({super.key});
  @override
  State<SavingsPage> createState() => _SavingsPageState();
}

class _SavingsPageState extends State<SavingsPage> {
  final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
  bool _isLoading = false;

  AppState get _s => AppStateScope.of(context);

  String get _userId => supabase.auth.currentUser?.id ?? '';

  final _goalColors = [
    BF.accent,
    BF.green,
    const Color(0xFF3B82F6),
    BF.amber,
    const Color(0xFFEC4899),
  ];

  @override
  void initState() {
    super.initState();
    // FIXED: Use addPostFrameCallback so context is available before first call
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSavingsGoals());
  }

  Future<void> _loadSavingsGoals() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final response = await supabase
          .from('savings_goals')
          .select()
          .eq('user_id', _userId);

      if (!mounted) return;
      _s.savingsGoals.clear();
      for (final goal in (response as List)) {
        _s.savingsGoals.add({
          'id': goal['id'].toString(),
          // FIXED: Explicit cast to String for all string fields
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
      debugPrint('Error loading savings goals: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to load goals. Pull to refresh.',
              style: const TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: BF.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      // FIXED: Guard setState with mounted check
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final goals = _s.savingsGoals;

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
      body: goals.isEmpty
          ? _emptyView(isDark)
          : RefreshIndicator(
              color: BF.accent,
              onRefresh: _loadSavingsGoals,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _banner(goals, isDark),
                  const SizedBox(height: 22),
                  _sectionLabel('Your Goals', isDark),
                  const SizedBox(height: 12),
                  ...goals.asMap().entries.map(
                    (e) => _goalCard(e.value, e.key, isDark),
                  ),
                  // Bottom padding so FAB doesn't overlap last card
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
      // FIXED: Pass isDark from build context, not re-read Theme here
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
      'Savings Goals',
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

  Widget _banner(List<Map<String, dynamic>> goals, bool isDark) {
    final completed = goals
        .where((g) => (g['saved'] as double) >= (g['target'] as double))
        .length;
    final totalSaved = goals.fold(0.0, (s, g) => s + (g['saved'] as double));

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
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Saved',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontFamily: 'Poppins',
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  currency.format(totalSaved),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Poppins',
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${goals.length} goal${goals.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: BF.green.withOpacity(0.25),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '$completed completed',
                        style: const TextStyle(
                          color: BF.green,
                          fontFamily: 'Poppins',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.emoji_events_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
        ],
      ),
    );
  }

  Widget _goalCard(Map<String, dynamic> goal, int index, bool isDark) {
    final saved = goal['saved'] as double;
    final target = goal['target'] as double;
    final progress = target > 0 ? (saved / target).clamp(0.0, 1.0) : 0.0;
    final isCompleted = saved >= target;
    final color = _goalColors[index % _goalColors.length];

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? BF.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isCompleted
              ? BF.green.withOpacity(0.3)
              : (isDark ? BF.darkBorder : BF.lightBorder),
          width: isCompleted ? 1.5 : 1,
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
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Center(
                  child: Text(
                    goal['emoji'] as String? ?? '🎯',
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      goal['title'] as String,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Poppins',
                        fontSize: 15,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    if (goal['deadline'] != null)
                      Text(
                        'By ${DateFormat('MMM dd, yyyy').format(goal['deadline'] as DateTime)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'Poppins',
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                  ],
                ),
              ),
              if (isCompleted)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: BF.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    '✓ Done',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: BF.green,
                    ),
                  ),
                )
              else
                PopupMenuButton<String>(
                  color: isDark ? BF.darkCard : Colors.white,
                  icon: Icon(
                    Icons.more_vert_rounded,
                    color: isDark ? Colors.white38 : Colors.black38,
                    size: 20,
                  ),
                  // FIXED: Explicit type parameter <String> avoids type-inference warning
                  itemBuilder: (_) => [
                    PopupMenuItem<String>(
                      value: 'add',
                      child: _menuRow(Icons.add_rounded, 'Add Funds', isDark),
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
                    if (val == 'add') _showAddFundsSheet(goal, isDark);
                    if (val == 'delete') await _deleteGoal(goal, isDark);
                  },
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currency.format(saved),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Poppins',
                      fontSize: 22,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    'saved of ${currency.format(target)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'Poppins',
                      color: isDark ? Colors.white38 : Colors.black45,
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
                      fontSize: 22,
                      color: color,
                    ),
                  ),
                  if (!isCompleted)
                    Text(
                      '${currency.format(target - saved)} to go',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'Poppins',
                        color: isDark ? Colors.white38 : Colors.black45,
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: color.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation<Color>(
                isCompleted ? BF.green : color,
              ),
              minHeight: 10,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteGoal(Map<String, dynamic> goal, bool isDark) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? BF.darkCard : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete Goal?',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        content: Text(
          'Are you sure you want to delete "${goal['title']}"?',
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
      // FIXED: Added .eq('user_id', _userId) for RLS safety (matches schema)
      await supabase
          .from('savings_goals')
          .delete()
          .eq('id', int.parse(goal['id'] as String))
          .eq('user_id', _userId);

      _s.deleteGoal(goal['id'] as String);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Goal deleted successfully',
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
              'Error deleting goal: $e',
              style: const TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: BF.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _menuRow(
    IconData icon,
    String label,
    bool isDark, {
    bool danger = false,
  }) {
    final c = danger ? BF.red : (isDark ? Colors.white : Colors.black87);
    return Row(
      children: [
        Icon(icon, size: 16, color: c),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(fontFamily: 'Poppins', color: c),
        ),
      ],
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
          child: const Icon(Icons.savings_rounded, size: 36, color: BF.accent),
        ),
        const SizedBox(height: 16),
        Text(
          'No Savings Goals',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            fontFamily: 'Poppins',
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Set a goal and track your progress',
          style: TextStyle(
            fontFamily: 'Poppins',
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
      ],
    ),
  );

  // ── Add Funds Sheet ─────────────────────────────────────────────────────────
  void _showAddFundsSheet(Map<String, dynamic> goal, bool isDark) {
    // FIXED: Controller disposed in finally/pop flow via StatefulBuilder lifecycle
    final ctrl = TextEditingController();
    bool isSaving = false;

    showModalBottomSheet<void>(
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
              left: 24,
              right: 24,
              top: 20,
              // FIXED: Use ctx.viewInsets (the sheet's context) not outer context
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _handle(isDark),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Text(
                      goal['emoji'] as String? ?? '🎯',
                      style: const TextStyle(fontSize: 24),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Add Funds to ${goal['title']}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Poppins',
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _field(
                  ctrl,
                  'Amount to add',
                  isDark,
                  prefix: '₱ ',
                  type: TextInputType.number,
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
                            final amt = double.tryParse(ctrl.text.trim()) ?? 0;
                            if (amt <= 0) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Please enter a valid amount',
                                    style: TextStyle(fontFamily: 'Poppins'),
                                  ),
                                  backgroundColor: BF.red,
                                ),
                              );
                              return;
                            }

                            setS(() => isSaving = true);

                            try {
                              final newSaved = (goal['saved'] as double) + amt;

                              await supabase
                                  .from('savings_goals')
                                  .update({'saved': newSaved})
                                  .eq('id', int.parse(goal['id'] as String))
                                  .eq('user_id', _userId);

                              _s.addFundsToGoal(goal['id'] as String, amt);

                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Added ${currency.format(amt)} to ${goal['title']}',
                                      style: const TextStyle(
                                        fontFamily: 'Poppins',
                                      ),
                                    ),
                                    backgroundColor: BF.green,
                                    behavior: SnackBarBehavior.floating,
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
                                      ),
                                    ),
                                    backgroundColor: BF.red,
                                  ),
                                );
                              }
                            } finally {
                              // FIXED: dispose controller after sheet closes
                              if (ctx.mounted) {
                                setS(() => isSaving = false);
                              } else {
                                ctrl.dispose();
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
                        : const Text('Add Funds'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    ).whenComplete(ctrl.dispose);
    // FIXED: .whenComplete(ctrl.dispose) guarantees TextEditingController
    // is always disposed when the sheet is dismissed, even on back-swipe.
  }

  // ── New Goal Sheet ──────────────────────────────────────────────────────────
  void _showSheet(bool isDark) {
    final titleCtrl = TextEditingController();
    final targetCtrl = TextEditingController();
    final savedCtrl = TextEditingController();
    String emoji = '🎯';
    DateTime? deadline;
    bool isSaving = false;

    const emojis = [
      '🎯',
      '🏠',
      '✈️',
      '🚗',
      '💍',
      '📱',
      '💻',
      '🎓',
      '🏖️',
      '💰',
      '🎮',
      '🏋️',
    ];

    // FIXED: Dispose all 3 controllers when sheet is dismissed
    void disposeControllers() {
      titleCtrl.dispose();
      targetCtrl.dispose();
      savedCtrl.dispose();
    }

    showModalBottomSheet<void>(
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
                    'New Savings Goal',
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
                  _field(titleCtrl, 'Goal name', isDark),
                  const SizedBox(height: 12),
                  _field(
                    targetCtrl,
                    'Target amount',
                    isDark,
                    prefix: '₱ ',
                    type: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    savedCtrl,
                    'Already saved (optional)',
                    isDark,
                    prefix: '₱ ',
                    type: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: DateTime.now().add(
                          const Duration(days: 30),
                        ),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(
                          const Duration(days: 365 * 10),
                        ),
                      );
                      if (picked != null && ctx.mounted) {
                        setS(() => deadline = picked);
                      }
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
                          color: deadline != null
                              ? BF.accent
                              : (isDark ? BF.darkBorder : BF.lightBorder),
                          width: deadline != null ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today_rounded,
                            size: 16,
                            color: deadline != null
                                ? BF.accent
                                : (isDark ? Colors.white38 : Colors.black38),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            deadline != null
                                ? DateFormat('MMM dd, yyyy').format(deadline!)
                                : 'Set deadline (optional)',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              color: deadline != null
                                  ? (isDark ? Colors.white : Colors.black87)
                                  : (isDark ? Colors.white38 : Colors.black38),
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
                              final target =
                                  double.tryParse(targetCtrl.text.trim()) ?? 0;
                              final title = titleCtrl.text.trim();

                              if (title.isEmpty || target <= 0) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Please enter a title and valid target amount',
                                      style: TextStyle(fontFamily: 'Poppins'),
                                    ),
                                    backgroundColor: BF.red,
                                  ),
                                );
                                return;
                              }

                              setS(() => isSaving = true);

                              try {
                                final saved =
                                    double.tryParse(savedCtrl.text.trim()) ??
                                    0.0;

                                final response = await supabase
                                    .from('savings_goals')
                                    .insert({
                                      'user_id': _userId,
                                      'title': title,
                                      'emoji': emoji,
                                      'target': target,
                                      'saved': saved,
                                      'deadline': deadline?.toIso8601String(),
                                    })
                                    .select();

                                if (!ctx.mounted) return;

                                if ((response as List).isNotEmpty) {
                                  _s.addGoal({
                                    'id': response[0]['id'].toString(),
                                    'title': title,
                                    'target': target,
                                    'saved': saved,
                                    'emoji': emoji,
                                    'deadline': deadline,
                                  });

                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Goal created successfully',
                                        style: TextStyle(fontFamily: 'Poppins'),
                                      ),
                                      backgroundColor: BF.green,
                                      behavior: SnackBarBehavior.floating,
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
                          : const Text('Create Goal'),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(disposeControllers);
  }

  // ── Shared small widgets ────────────────────────────────────────────────────

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
