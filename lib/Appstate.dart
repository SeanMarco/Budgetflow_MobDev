import 'package:flutter/material.dart';

// ─── AppState ─────────────────────────────────────────────────────────────────

class AppState extends ChangeNotifier {
  List<Map<String, dynamic>> transactions = [];
  List<Map<String, dynamic>> budgets = [];
  List<Map<String, dynamic>> accounts = [];
  List<Map<String, dynamic>> recurringTransactions = [];
  List<Map<String, dynamic>> savingsGoals = [];

  // Flag to track if the notifier is disposed
  bool _isDisposed = false;

  AppState();

  @override
  void dispose() {
    _isDisposed = true;
    // Clear all lists to free memory
    transactions.clear();
    budgets.clear();
    accounts.clear();
    recurringTransactions.clear();
    savingsGoals.clear();
    super.dispose();
  }

  double get totalBalance =>
      accounts.fold(0.0, (sum, a) => sum + (a['balance'] as double));

  // Safe notify helper
  void _safeNotify() {
    if (!_isDisposed && hasListeners) {
      notifyListeners();
    }
  }

  // ── Transactions ─────────────────────────────────────────────────────────

  void addTransaction(Map<String, dynamic> tx) {
    if (_isDisposed) return;
    transactions.insert(0, tx);
    _applyToAccount(
      tx['accountId'] as String?,
      tx['isIncome'] as bool,
      tx['amount'] as double,
    );
    _safeNotify();
  }

  void deleteTransaction(String id) {
    if (_isDisposed) return;
    final idx = transactions.indexWhere((t) => t['id'] == id);
    if (idx < 0) return;
    final tx = transactions[idx];
    _applyToAccount(
      tx['accountId'] as String?,
      !(tx['isIncome'] as bool),
      tx['amount'] as double,
    );
    transactions.removeAt(idx);
    _safeNotify();
  }

  void editTransaction(String id, Map<String, dynamic> updated) {
    if (_isDisposed) return;
    final idx = transactions.indexWhere((t) => t['id'] == id);
    if (idx < 0) return;
    final old = transactions[idx];
    // Reverse old effect
    _applyToAccount(
      old['accountId'] as String?,
      !(old['isIncome'] as bool),
      old['amount'] as double,
    );
    // Apply new effect
    _applyToAccount(
      updated['accountId'] as String?,
      updated['isIncome'] as bool,
      updated['amount'] as double,
    );
    transactions[idx] = updated;
    _safeNotify();
  }

  void _applyToAccount(String? accountId, bool isCredit, double amount) {
    if (_isDisposed) return;
    if (accountId == null) return;
    final idx = accounts.indexWhere((a) => a['id'].toString() == accountId);
    if (idx < 0) return;
    final acc = Map<String, dynamic>.from(accounts[idx]);
    acc['balance'] = (acc['balance'] as double) + (isCredit ? amount : -amount);
    accounts[idx] = acc;
  }

  // ── Transfers ────────────────────────────────────────────────────────────

  void transfer(String fromId, String toId, double amount) {
    if (_isDisposed) return;
    _applyToAccount(fromId, false, amount);
    _applyToAccount(toId, true, amount);
    final now = DateTime.now();
    final fromAcc = accounts.firstWhere(
      (a) => a['id'].toString() == fromId,
      orElse: () => {'name': ''},
    );
    final toAcc = accounts.firstWhere(
      (a) => a['id'].toString() == toId,
      orElse: () => {'name': ''},
    );
    transactions.insertAll(0, [
      {
        'id': UniqueKey().toString(),
        'title': 'Transfer to ${toAcc['name']}',
        'amount': amount,
        'isIncome': false,
        'isTransfer': true,
        'category': 'Transfer',
        'accountId': fromId,
        'date': now,
        'note': '',
      },
      {
        'id': UniqueKey().toString(),
        'title': 'Transfer from ${fromAcc['name']}',
        'amount': amount,
        'isIncome': true,
        'isTransfer': true,
        'category': 'Transfer',
        'accountId': toId,
        'date': now,
        'note': '',
      },
    ]);
    _safeNotify();
  }

  // ── Budgets ───────────────────────────────────────────────────────────────

  void addBudget(Map<String, dynamic> budget) {
    if (_isDisposed) return;
    budgets.add(budget);
    _safeNotify();
  }

  void updateBudget(String id, Map<String, dynamic> updated) {
    if (_isDisposed) return;
    final idx = budgets.indexWhere((b) => b['id'] == id);
    if (idx >= 0) budgets[idx] = updated;
    _safeNotify();
  }

  void deleteBudget(String id) {
    if (_isDisposed) return;
    budgets.removeWhere((b) => b['id'] == id);
    _safeNotify();
  }

  // ── Accounts ─────────────────────────────────────────────────────────────

  void addAccount(Map<String, dynamic> account) {
    if (_isDisposed) return;
    accounts.add(account);
    _safeNotify();
  }

  void updateAccount(String id, Map<String, dynamic> updated) {
    if (_isDisposed) return;
    final idx = accounts.indexWhere((a) => a['id'].toString() == id);
    if (idx >= 0) accounts[idx] = updated;
    _safeNotify();
  }

  void deleteAccount(String id) {
    if (_isDisposed) return;
    accounts.removeWhere((a) => a['id'].toString() == id);
    _safeNotify();
  }

  // ── Recurring ────────────────────────────────────────────────────────────

  void addRecurring(Map<String, dynamic> r) {
    if (_isDisposed) return;
    recurringTransactions.add(r);
    _safeNotify();
  }

  void deleteRecurring(String id) {
    if (_isDisposed) return;
    recurringTransactions.removeWhere((r) => r['id'] == id);
    _safeNotify();
  }

  // ── Savings Goals ─────────────────────────────────────────────────────────

  void addGoal(Map<String, dynamic> goal) {
    if (_isDisposed) return;
    savingsGoals.add(goal);
    _safeNotify();
  }

  void addFundsToGoal(String id, double amount) {
    if (_isDisposed) return;
    final idx = savingsGoals.indexWhere((g) => g['id'] == id);
    if (idx >= 0) {
      final updated = Map<String, dynamic>.from(savingsGoals[idx]);
      updated['saved'] = (updated['saved'] as double) + amount;
      savingsGoals[idx] = updated;
    }
    _safeNotify();
  }

  void deleteGoal(String id) {
    if (_isDisposed) return;
    savingsGoals.removeWhere((g) => g['id'] == id);
    _safeNotify();
  }

  // ── Helper ────────────────────────────────────────────────────────────────

  /// Returns total expenses for a category across ALL time (used by BudgetPage
  /// for monthly calc — BudgetPage filters by month itself).
  /// This excludes transfer transactions
  double spentInCategory(String category) => transactions
      .where(
        (t) =>
            !(t['isIncome'] as bool) &&
            t['category'] == category &&
            (t['isTransfer'] != true),
      )
      .fold(0.0, (s, t) => s + (t['amount'] as double));

  /// Returns total income (excluding transfers)
  double get totalIncome => transactions
      .where((t) => (t['isIncome'] as bool) && (t['isTransfer'] != true))
      .fold(0.0, (s, t) => s + (t['amount'] as double));

  /// Returns total expenses (excluding transfers)
  double get totalExpense => transactions
      .where((t) => !(t['isIncome'] as bool) && (t['isTransfer'] != true))
      .fold(0.0, (s, t) => s + (t['amount'] as double));

  /// Returns transactions filtered to exclude transfers (for UI display)
  List<Map<String, dynamic>> get nonTransferTransactions =>
      transactions.where((t) => t['isTransfer'] != true).toList();

  /// Returns only transfer transactions
  List<Map<String, dynamic>> get transferTransactions =>
      transactions.where((t) => t['isTransfer'] == true).toList();
}

// ─── AppStateScope ────────────────────────────────────────────────────────────

class AppStateScope extends InheritedNotifier<AppState> {
  const AppStateScope({
    super.key,
    required AppState state,
    required super.child,
  }) : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppStateScope>();
    assert(scope != null, 'No AppStateScope found in context');
    return scope!.notifier!;
  }

  static AppState read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppStateScope>();
    assert(scope != null, 'No AppStateScope found in context');
    return scope!.notifier!;
  }
}
