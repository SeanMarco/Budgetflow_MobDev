import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main.dart' show BF;
import 'AppState.dart';

final supabase = Supabase.instance.client;

class AccountsPage extends StatefulWidget {
  const AccountsPage({super.key});

  @override
  State<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends State<AccountsPage> {
  final currency = NumberFormat.currency(locale: 'en_PH', symbol: '₱');
  bool loading = false;

  final _accountColors = [
    BF.green,
    BF.accent,
    const Color(0xFF3B82F6),
    BF.amber,
    const Color(0xFFEC4899),
    const Color(0xFF8B5CF6),
  ];

  AppState get _s => AppStateScope.of(context);

  String get _userId => supabase.auth.currentUser?.id ?? '';

  // Convert Color to hex string for Supabase
  String _colorToHex(Color c) =>
      '#${c.red.toRadixString(16).padLeft(2, '0')}'
      '${c.green.toRadixString(16).padLeft(2, '0')}'
      '${c.blue.toRadixString(16).padLeft(2, '0')}';

  // Convert hex string to Color
  Color _hexToColor(String hex) {
    final hexColor = hex.replaceFirst('#', '');
    return Color(int.parse('FF$hexColor', radix: 16));
  }

  Future<void> _deleteAccount(String accountId) async {
    // Check if any transactions use this account
    final hasTransactions = _s.transactions.any(
      (tx) => tx['accountId'].toString() == accountId,
    );

    if (hasTransactions) {
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

    // Confirm delete
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? BF.darkCard
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          "Delete Account?",
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : Colors.black87,
          ),
        ),
        content: Text(
          "Are you sure you want to delete this account? This cannot be undone.",
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white54
                : Colors.black54,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              "Cancel",
              style: TextStyle(fontFamily: 'Poppins', color: BF.accent),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              "Delete",
              style: TextStyle(fontFamily: 'Poppins', color: BF.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Delete from Supabase
      await supabase
          .from('accounts')
          .delete()
          .eq('id', int.parse(accountId))
          .eq('user_id', _userId);

      // Delete from local state
      _s.deleteAccount(accountId);

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
    } catch (e) {
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? BF.darkBg : BF.lightBg,
      appBar: _appBar(isDark),
      body: RefreshIndicator(
        color: BF.accent,
        onRefresh: () async {
          // Refresh accounts from Supabase
          try {
            final response = await supabase
                .from('accounts')
                .select()
                .eq('user_id', _userId);

            _s.accounts.clear();
            for (var acc in response) {
              _s.accounts.add({
                'id': acc['id'].toString(),
                'name': acc['name'],
                'type': acc['type'],
                'emoji': acc['emoji'],
                'balance': (acc['balance'] as num).toDouble(),
                'color': acc['color'],
              });
            }
          } catch (e) {
            debugPrint('Error refreshing accounts: $e');
          }
        },
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _totalCard(isDark),
            const SizedBox(height: 24),
            _sectionLabel("Your Accounts", isDark),
            const SizedBox(height: 12),
            ..._s.accounts.asMap().entries.map(
              (e) => _accountCard(e.value, e.key, isDark),
            ),
            const SizedBox(height: 10),
            _addBtn(isDark),
            if (_s.accounts.length >= 2) ...[
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
      "Accounts & Wallets",
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
                  "Net Worth",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontFamily: 'Poppins',
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  currency.format(_s.totalBalance),
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
                  "${_s.accounts.length} account${_s.accounts.length == 1 ? '' : 's'}",
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
    final color = account['color'] is Color
        ? account['color'] as Color
        : (account['color'] != null
              ? _hexToColor(account['color'].toString())
              : _accountColors[index % _accountColors.length]);
    final balance = account['balance'] as double;

    // Check if account has transactions
    final hasTransactions = _s.transactions.any(
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
                account['emoji'] ?? '💰',
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
                  account['name'],
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
                    account['type'],
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.add_circle_outline_rounded, color: BF.accent, size: 20),
          SizedBox(width: 8),
          Text(
            "Add New Account",
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
        "Transfer Between Accounts",
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
    final types = ['Cash', 'Bank', 'E-Wallet', 'Credit Card', 'Savings'];
    final emojis = ['🏦', '💵', '📱', '💳', '🏧', '💰', '🪙', '💎'];
    bool isSaving = false;

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
                  "Add Account",
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
                _field(nameCtrl, "Account name", isDark),
                const SizedBox(height: 12),
                _field(
                  balanceCtrl,
                  "Initial balance",
                  isDark,
                  prefix: "₱ ",
                  type: TextInputType.number,
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
                                : (isDark ? BF.darkBorder : BF.lightBorder),
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
                                : (isDark ? Colors.white54 : Colors.black45),
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
                                  color: isDark ? Colors.white : Colors.black,
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
                            if (nameCtrl.text.trim().isEmpty) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(
                                  content: Text('Please enter an account name'),
                                  backgroundColor: BF.red,
                                ),
                              );
                              return;
                            }
                            setS(() => isSaving = true);

                            final balance =
                                double.tryParse(balanceCtrl.text) ?? 0.0;
                            final colorHex = _colorToHex(color);

                            try {
                              // Save to Supabase
                              final response =
                                  await supabase.from('accounts').insert({
                                    'user_id': _userId,
                                    'name': nameCtrl.text.trim(),
                                    'type': type,
                                    'emoji': emoji,
                                    'balance': balance,
                                    'color': colorHex,
                                  }).select();

                              if (response.isNotEmpty) {
                                // Add to local state
                                _s.addAccount({
                                  'id': response[0]['id'].toString(),
                                  'name': nameCtrl.text.trim(),
                                  'type': type,
                                  'emoji': emoji,
                                  'balance': balance,
                                  'color': color,
                                });

                                if (ctx.mounted) Navigator.pop(ctx);

                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text('Account added successfully'),
                                    backgroundColor: BF.green,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
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
                        : const Text("Add Account"),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showTransferSheet(bool isDark) {
    final accounts = _s.accounts;
    if (accounts.length < 2) return;

    String fromId = accounts[0]['id'].toString();
    String toId = accounts[1]['id'].toString();
    final amountCtrl = TextEditingController();
    bool isProcessing = false;

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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _handle(isDark),
              const SizedBox(height: 20),
              Text(
                "Transfer Funds",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Poppins',
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              _dropdown(
                "From Account",
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
                "To Account",
                toId,
                accounts,
                isDark,
                (v) => setS(() => toId = v!),
              ),
              const SizedBox(height: 12),
              _field(
                amountCtrl,
                "Amount",
                isDark,
                prefix: "₱ ",
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
                  onPressed: isProcessing
                      ? null
                      : () async {
                          final amount = double.tryParse(amountCtrl.text) ?? 0;
                          if (amount <= 0) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('Please enter a valid amount'),
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

                            // Update from account (subtract)
                            await supabase
                                .from('accounts')
                                .update({'balance': fromBalance - amount})
                                .eq('id', int.parse(fromId));

                            // Update to account (add)
                            final toBalance = toAccount['balance'] as double;
                            await supabase
                                .from('accounts')
                                .update({'balance': toBalance + amount})
                                .eq('id', int.parse(toId));

                            // Create transfer transaction records
                            final now = DateTime.now().toIso8601String();

                            // Outgoing transaction
                            await supabase.from('transactions').insert({
                              'user_id': _userId,
                              'title': 'Transfer to ${toAccount['name']}',
                              'amount': amount,
                              'is_income': false,
                              'category': 'Transfer',
                              'account_id': int.parse(fromId),
                              'note': 'Transfer to ${toAccount['name']}',
                              'date': now,
                            });

                            // Incoming transaction
                            await supabase.from('transactions').insert({
                              'user_id': _userId,
                              'title': 'Transfer from ${fromAccount['name']}',
                              'amount': amount,
                              'is_income': true,
                              'category': 'Transfer',
                              'account_id': int.parse(toId),
                              'note': 'Transfer from ${fromAccount['name']}',
                              'date': now,
                            });

                            // Refresh data
                            final accountsResponse = await supabase
                                .from('accounts')
                                .select()
                                .eq('user_id', _userId);

                            _s.accounts.clear();
                            for (var acc in accountsResponse) {
                              _s.accounts.add({
                                'id': acc['id'].toString(),
                                'name': acc['name'],
                                'type': acc['type'],
                                'emoji': acc['emoji'],
                                'balance': (acc['balance'] as num).toDouble(),
                                'color': acc['color'],
                              });
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
                            if (ctx.mounted) setS(() => isProcessing = false);
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
                      : const Text("Transfer"),
                ),
              ),
            ],
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

  Widget _dropdown(
    String label,
    String value,
    List<Map<String, dynamic>> accounts,
    bool isDark,
    ValueChanged<String?> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? BF.darkSurface : BF.lightBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? BF.darkBorder : BF.lightBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
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
                    a['emoji'] ?? '💰',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    a['name'],
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
