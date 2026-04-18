import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'main.dart' show BF, supabase;
import 'AppState.dart';

class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
  bool loading = false;
  late AppState _appState;

  final _accountColors = [
    BF.green,
    BF.accent,
    const Color(0xFF3B82F6),
    BF.amber,
    const Color(0xFFEC4899),
    const Color(0xFF8B5CF6),
  ];

  String get _userId => supabase.auth.currentUser?.id ?? '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _appState = AppStateScope.of(context);
  }

  String _colorToHex(Color c) =>
      '#${c.red.toRadixString(16).padLeft(2, '0')}'
      '${c.green.toRadixString(16).padLeft(2, '0')}'
      '${c.blue.toRadixString(16).padLeft(2, '0')}';

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

  Future<void> _refreshAccounts() async {
    try {
      final response = await supabase
          .from('accounts')
          .select()
          .eq('user_id', _userId);

      if (!mounted) return;
      _appState.accounts.clear();
      for (final acc in (response as List)) {
        _appState.accounts.add({
          'id': acc['id'].toString(),
          'name': acc['name'] as String,
          'type': acc['type'] as String,
          'emoji': acc['emoji'] as String? ?? '💰',
          'balance': (acc['balance'] as num).toDouble(),
          'color': acc['color'] as String? ?? '#0EA974',
        });
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error refreshing accounts: $e');
    }
  }

  Future<void> _deleteAccount(String accountId) async {
    final hasTransactions = _appState.transactions.any(
      (tx) => tx['accountId'].toString() == accountId,
    );

    if (hasTransactions) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Cannot delete account with existing transactions.',
            style: TextStyle(fontFamily: 'Poppins'),
          ),
          backgroundColor: BF.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? BF.darkCard : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete Account?',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        content: Text(
          'Are you sure you want to delete this account? This cannot be undone.',
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
      final accountIdInt = int.tryParse(accountId);
      if (accountIdInt == null) throw Exception('Invalid account ID');

      await supabase
          .from('accounts')
          .delete()
          .eq('id', accountIdInt)
          .eq('user_id', _userId);

      _appState.deleteAccount(accountId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Account deleted successfully',
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
              'Error deleting account: $e',
              style: const TextStyle(fontFamily: 'Poppins'),
            ),
            backgroundColor: BF.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? BF.darkBg : BF.lightBg,
      appBar: _appBar(isDark),
      body: RefreshIndicator(
        color: BF.accent,
        onRefresh: _refreshAccounts,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _totalCard(isDark),
            const SizedBox(height: 24),
            _sectionLabel('Your Accounts', isDark),
            const SizedBox(height: 12),
            ..._appState.accounts.asMap().entries.map(
              (e) => _accountCard(e.value, e.key, isDark),
            ),
            const SizedBox(height: 10),
            _addBtn(isDark),
            if (_appState.accounts.length >= 2) ...[
              const SizedBox(height: 12),
              _transferBtn(isDark),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar(bool isDark) => AppBar(
    backgroundColor: isDark ? BF.darkBg : BF.lightBg,
    elevation: 0,
    centerTitle: true,
    title: Text(
      'Accounts & Wallets',
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

  Widget _totalCard(bool isDark) {
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
                  'Net Worth',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontFamily: 'Poppins',
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  currency.format(_appState.totalBalance),
                  style: const TextStyle(
                    fontSize: 34,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'Poppins',
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_appState.accounts.length} account${_appState.accounts.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontFamily: 'Poppins',
                    fontSize: 13,
                  ),
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
              Icons.account_balance_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountCard(Map<String, dynamic> account, int index, bool isDark) {
    final color = _parseColor(
      account['color'],
      _accountColors[index % _accountColors.length],
    );
    final balance = account['balance'] as double;

    final hasTransactions = _appState.transactions.any(
      (tx) => tx['accountId'].toString() == account['id'].toString(),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BF.card(isDark),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Text(
                account['emoji'] as String? ?? '💰',
                style: const TextStyle(fontSize: 24),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  account['name'] as String,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    account['type'] as String,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                currency.format(balance),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Poppins',
                  fontSize: 16,
                  color: balance >= 0 ? BF.green : BF.red,
                ),
              ),
              if (!hasTransactions) ...[
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => _deleteAccount(account['id'].toString()),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: BF.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      size: 15,
                      color: BF.red,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _addBtn(bool isDark) => GestureDetector(
    onTap: () => _showAddSheet(isDark),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BF.accent.withOpacity(0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: BF.accent.withOpacity(0.2), width: 1.5),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_circle_outline_rounded, color: BF.accent, size: 20),
          SizedBox(width: 8),
          Text(
            'Add New Account',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: BF.accent,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _transferBtn(bool isDark) => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      gradient: const LinearGradient(
        colors: [BF.accent, BF.accentSoft],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      boxShadow: [
        BoxShadow(
          color: BF.accent.withOpacity(0.35),
          blurRadius: 16,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: ElevatedButton.icon(
      onPressed: () => _showTransferSheet(isDark),
      icon: const Icon(Icons.swap_horiz_rounded, size: 18),
      label: const Text(
        'Transfer Between Accounts',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );

  void _showAddSheet(bool isDark) {
    final nameCtrl = TextEditingController();
    final balanceCtrl = TextEditingController();
    String type = 'Bank';
    String emoji = '🏦';
    Color color = _accountColors[0];
    const types = ['Cash', 'Bank', 'E-Wallet', 'Credit Card', 'Savings'];
    const emojis = ['🏦', '💵', '📱', '💳', '🏧', '💰', '🪙', '💎'];
    bool isSaving = false;
    bool _isSheetActive = true;

    void disposeControllers() {
      if (_isSheetActive) {
        _isSheetActive = false;
        Future.microtask(() {
          if (!nameCtrl.hasListeners) nameCtrl.dispose();
          if (!balanceCtrl.hasListeners) balanceCtrl.dispose();
        });
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
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
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _handle(isDark),
                      const SizedBox(height: 20),
                      Text(
                        'Add Account',
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
                      _field(nameCtrl, 'Account name', isDark),
                      const SizedBox(height: 12),
                      _field(
                        balanceCtrl,
                        'Initial balance',
                        isDark,
                        prefix: '₱ ',
                        type: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: types.map((t) {
                          final sel = type == t;
                          return GestureDetector(
                            onTap: () => setS(() => type = t),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
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
                                      : (isDark
                                            ? BF.darkBorder
                                            : BF.lightBorder),
                                ),
                              ),
                              child: Text(
                                t,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: sel
                                      ? Colors.white
                                      : (isDark
                                            ? Colors.white54
                                            : Colors.black45),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: _accountColors.map((c) {
                          return GestureDetector(
                            onTap: () => setS(() => color = c),
                            child: Container(
                              width: 34,
                              height: 34,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: color == c
                                    ? Border.all(
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black,
                                        width: 2.5,
                                      )
                                    : null,
                                boxShadow: color == c
                                    ? [
                                        BoxShadow(
                                          color: c.withOpacity(0.4),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ]
                                    : [],
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
                                  final name = nameCtrl.text.trim();
                                  if (name.isEmpty) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Please enter an account name',
                                        ),
                                        backgroundColor: BF.red,
                                      ),
                                    );
                                    return;
                                  }
                                  final balance =
                                      double.tryParse(
                                        balanceCtrl.text.trim(),
                                      ) ??
                                      0.0;
                                  final colorHex = _colorToHex(color);

                                  setS(() => isSaving = true);

                                  try {
                                    final response =
                                        await supabase.from('accounts').insert({
                                          'user_id': _userId,
                                          'name': name,
                                          'type': type,
                                          'emoji': emoji,
                                          'balance': balance,
                                          'color': colorHex,
                                        }).select();

                                    if (!ctx.mounted) return;
                                    if ((response as List).isNotEmpty) {
                                      final newAccountId = response[0]['id']
                                          .toString();

                                      _appState.addAccount({
                                        'id': newAccountId,
                                        'name': name,
                                        'type': type,
                                        'emoji': emoji,
                                        'balance': balance,
                                        'color': colorHex,
                                      });

                                      // ADD INITIAL BALANCE TRANSACTION
                                      if (balance > 0) {
                                        final now = DateTime.now()
                                            .toIso8601String();
                                        final accountIdInt = int.tryParse(
                                          newAccountId,
                                        );

                                        if (accountIdInt != null) {
                                          await supabase
                                              .from('transactions')
                                              .insert({
                                                'user_id': _userId,
                                                'title':
                                                    'Initial Balance: $name',
                                                'amount': balance,
                                                'is_income': true,
                                                'category': 'Savings',
                                                'account_id': accountIdInt,
                                                'note':
                                                    'Initial account balance',
                                                'date': now,
                                              });

                                          // Refresh transactions
                                          final transactionsResponse =
                                              await supabase
                                                  .from('transactions')
                                                  .select()
                                                  .eq('user_id', _userId)
                                                  .order(
                                                    'date',
                                                    ascending: false,
                                                  );

                                          if (ctx.mounted &&
                                              (transactionsResponse as List)
                                                  .isNotEmpty) {
                                            _appState.transactions.clear();
                                            for (final tx
                                                in transactionsResponse) {
                                              _appState.transactions.add({
                                                'id': tx['id'].toString(),
                                                'title': tx['title'] as String,
                                                'amount': (tx['amount'] as num)
                                                    .toDouble(),
                                                'isIncome':
                                                    tx['is_income'] as bool,
                                                'category':
                                                    tx['category'] as String? ??
                                                    'General',
                                                'note':
                                                    tx['note'] as String? ?? '',
                                                'date': DateTime.parse(
                                                  tx['date'] as String,
                                                ),
                                                'accountId': tx['account_id']
                                                    .toString(),
                                              });
                                            }
                                          }
                                        }
                                      }

                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Account added successfully',
                                          ),
                                          backgroundColor: BF.green,
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                      if (mounted) setState(() {});
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
                              : const Text('Add Account'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      if (_isSheetActive) {
        disposeControllers();
      }
    });
  }

  void _showTransferSheet(bool isDark) {
    final accounts = _appState.accounts;
    if (accounts.length < 2) return;

    String fromId = accounts[0]['id'].toString();
    String toId = accounts[1]['id'].toString();
    final amountCtrl = TextEditingController();
    bool isProcessing = false;
    bool _isSheetActive = true;

    void disposeControllers() {
      if (_isSheetActive) {
        _isSheetActive = false;
        Future.microtask(() {
          if (!amountCtrl.hasListeners) amountCtrl.dispose();
        });
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return StatefulBuilder(
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
                    _handle(isDark),
                    const SizedBox(height: 20),
                    Text(
                      'Transfer Funds',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Poppins',
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _dropdown(
                      'From Account',
                      fromId,
                      accounts,
                      isDark,
                      (v) => setS(() => fromId = v!),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: BF.accent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.swap_vert_rounded,
                          color: BF.accent,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _dropdown(
                      'To Account',
                      toId,
                      accounts,
                      isDark,
                      (v) => setS(() => toId = v!),
                    ),
                    const SizedBox(height: 12),
                    _field(
                      amountCtrl,
                      'Amount',
                      isDark,
                      prefix: '₱ ',
                      type: const TextInputType.numberWithOptions(
                        decimal: true,
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
                        onPressed: isProcessing
                            ? null
                            : () async {
                                final amount =
                                    double.tryParse(amountCtrl.text.trim()) ??
                                    0;
                                if (amount <= 0) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Please enter a valid amount',
                                      ),
                                      backgroundColor: BF.red,
                                    ),
                                  );
                                  return;
                                }
                                if (fromId == toId) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Cannot transfer to the same account',
                                      ),
                                      backgroundColor: BF.red,
                                    ),
                                  );
                                  return;
                                }

                                setS(() => isProcessing = true);

                                try {
                                  final fromAccount = accounts.firstWhere(
                                    (a) => a['id'].toString() == fromId,
                                  );
                                  final toAccount = accounts.firstWhere(
                                    (a) => a['id'].toString() == toId,
                                  );
                                  final fromBalance =
                                      fromAccount['balance'] as double;

                                  if (fromBalance < amount) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      const SnackBar(
                                        content: Text('Insufficient funds'),
                                        backgroundColor: BF.red,
                                      ),
                                    );
                                    setS(() => isProcessing = false);
                                    return;
                                  }

                                  final fromIdInt = int.tryParse(fromId);
                                  final toIdInt = int.tryParse(toId);
                                  if (fromIdInt == null || toIdInt == null) {
                                    throw Exception('Invalid account IDs');
                                  }

                                  // Update account balances
                                  await supabase
                                      .from('accounts')
                                      .update({'balance': fromBalance - amount})
                                      .eq('id', fromIdInt);

                                  final toBalance =
                                      toAccount['balance'] as double;
                                  await supabase
                                      .from('accounts')
                                      .update({'balance': toBalance + amount})
                                      .eq('id', toIdInt);

                                  final now = DateTime.now().toIso8601String();

                                  // Create transfer transactions WITHOUT is_transfer flag
                                  // For FROM account - use a special category "Transfer-Out"
                                  await supabase.from('transactions').insert({
                                    'user_id': _userId,
                                    'title': 'Transfer to ${toAccount['name']}',
                                    'amount': amount,
                                    'is_income': false,
                                    'category': 'Transfer-Out',
                                    'account_id': fromIdInt,
                                    'note': 'Transfer to ${toAccount['name']}',
                                    'date': now,
                                  });

                                  // For TO account - use a special category "Transfer-In"
                                  await supabase.from('transactions').insert({
                                    'user_id': _userId,
                                    'title':
                                        'Transfer from ${fromAccount['name']}',
                                    'amount': amount,
                                    'is_income': true,
                                    'category': 'Transfer-In',
                                    'account_id': toIdInt,
                                    'note':
                                        'Transfer from ${fromAccount['name']}',
                                    'date': now,
                                  });

                                  // Refresh accounts
                                  final accountsResponse = await supabase
                                      .from('accounts')
                                      .select()
                                      .eq('user_id', _userId);

                                  if (!ctx.mounted) return;
                                  _appState.accounts.clear();
                                  for (final acc
                                      in (accountsResponse as List)) {
                                    _appState.accounts.add({
                                      'id': acc['id'].toString(),
                                      'name': acc['name'] as String,
                                      'type': acc['type'] as String,
                                      'emoji': acc['emoji'] as String? ?? '💰',
                                      'balance': (acc['balance'] as num)
                                          .toDouble(),
                                      'color':
                                          acc['color'] as String? ?? '#0EA974',
                                    });
                                  }

                                  // Refresh transactions
                                  final transactionsResponse = await supabase
                                      .from('transactions')
                                      .select()
                                      .eq('user_id', _userId)
                                      .order('date', ascending: false);

                                  if (ctx.mounted &&
                                      (transactionsResponse as List)
                                          .isNotEmpty) {
                                    _appState.transactions.clear();
                                    for (final tx in transactionsResponse) {
                                      _appState.transactions.add({
                                        'id': tx['id'].toString(),
                                        'title': tx['title'] as String,
                                        'amount': (tx['amount'] as num)
                                            .toDouble(),
                                        'isIncome': tx['is_income'] as bool,
                                        'category':
                                            tx['category'] as String? ??
                                            'General',
                                        'note': tx['note'] as String? ?? '',
                                        'date': DateTime.parse(
                                          tx['date'] as String,
                                        ),
                                        'accountId': tx['account_id']
                                            .toString(),
                                      });
                                    }
                                  }

                                  if (mounted) {
                                    setState(() {});
                                  }

                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Transfer completed successfully',
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
                                        content: Text('Transfer failed: $e'),
                                        backgroundColor: BF.red,
                                      ),
                                    );
                                  }
                                } finally {
                                  if (ctx.mounted) {
                                    setS(() => isProcessing = false);
                                  }
                                }
                              },
                        child: isProcessing
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Transfer'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      if (_isSheetActive) {
        disposeControllers();
      }
    });
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

  Widget _dropdown(
    String label,
    String value,
    List<Map<String, dynamic>> accounts,
    bool isDark,
    ValueChanged<String?> onChanged,
  ) {
    final validValue = accounts.any((a) => a['id'].toString() == value)
        ? value
        : (accounts.isNotEmpty ? accounts[0]['id'].toString() : null);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? BF.darkSurface : BF.lightBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? BF.darkBorder : BF.lightBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: validValue,
          isExpanded: true,
          dropdownColor: isDark ? BF.darkCard : Colors.white,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            color: isDark ? Colors.white : Colors.black87,
          ),
          items: accounts.map((a) {
            return DropdownMenuItem<String>(
              value: a['id'].toString(),
              child: Row(
                children: [
                  Text(
                    a['emoji'] as String? ?? '💰',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    a['name'] as String,
                    style: const TextStyle(fontFamily: 'Poppins'),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

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
