import 'package:flutter/material.dart';

// ─── AppState ─────────────────────────────────────────────────────────────────

class AppState extends ChangeNotifier {
  List<Map<String, dynamic>> transactions = [];
  List<Map<String, dynamic>> budgets = [];
  List<Map<String, dynamic>> accounts = [];
  List<Map<String, dynamic>> recurringTransactions = [];
  List<Map<String, dynamic>> savingsGoals = [];

  AppState() {
    accounts.add({
      'id': 'cash_default',
      'name': 'Cash',
      'type': 'Cash',
      'emoji': '💵',
      'balance': 0.0,
      'color': const Color(0xFF0EA974),
    });
  }

  double get totalBalance =>
      accounts.fold(0.0, (sum, a) => sum + (a['balance'] as double));

  // ── Transactions ─────────────────────────────────────────────────────────

  void addTransaction(Map<String, dynamic> tx) {
    transactions.insert(0, tx);
    _applyToAccount(
      tx['accountId'],
      tx['isIncome'] as bool,
      tx['amount'] as double,
    );
    notifyListeners();
  }

  void deleteTransaction(String id) {
    final tx = transactions.firstWhere((t) => t['id'] == id, orElse: () => {});
    if (tx.isEmpty) return;
    _applyToAccount(
      tx['accountId'],
      !(tx['isIncome'] as bool),
      tx['amount'] as double,
    );
    transactions.removeWhere((t) => t['id'] == id);
    notifyListeners();
  }

  void editTransaction(String id, Map<String, dynamic> updated) {
    final idx = transactions.indexWhere((t) => t['id'] == id);
    if (idx < 0) return;
    final old = transactions[idx];
    _applyToAccount(
      old['accountId'],
      !(old['isIncome'] as bool),
      old['amount'] as double,
    );
    _applyToAccount(
      updated['accountId'],
      updated['isIncome'] as bool,
      updated['amount'] as double,
    );
    transactions[idx] = updated;
    notifyListeners();
  }

  void _applyToAccount(String? accountId, bool isCredit, double amount) {
    if (accountId == null) return;
    final idx = accounts.indexWhere((a) => a['id'] == accountId);
    if (idx < 0) return;
    final acc = accounts[idx];
    accounts[idx] = {
      ...acc,
      'balance': (acc['balance'] as double) + (isCredit ? amount : -amount),
    };
  }

  // ── Transfers ────────────────────────────────────────────────────────────

  void transfer(String fromId, String toId, double amount) {
    _applyToAccount(fromId, false, amount);
    _applyToAccount(toId, true, amount);
    final now = DateTime.now();
    final fromAcc = accounts.firstWhere(
      (a) => a['id'] == fromId,
      orElse: () => {'name': ''},
    );
    final toAcc = accounts.firstWhere(
      (a) => a['id'] == toId,
      orElse: () => {'name': ''},
    );
    transactions.insertAll(0, [
      {
        'id': UniqueKey().toString(),
        'title': 'Transfer to ${toAcc['name']}',
        'amount': amount,
        'isIncome': false,
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
        'category': 'Transfer',
        'accountId': toId,
        'date': now,
        'note': '',
      },
    ]);
    notifyListeners();
  }

  // ── Budgets ───────────────────────────────────────────────────────────────

  void addBudget(Map<String, dynamic> budget) {
    budgets.add(budget);
    notifyListeners();
  }

  void updateBudget(String id, Map<String, dynamic> updated) {
    final idx = budgets.indexWhere((b) => b['id'] == id);
    if (idx >= 0) budgets[idx] = updated;
    notifyListeners();
  }

  void deleteBudget(String id) {
    budgets.removeWhere((b) => b['id'] == id);
    notifyListeners();
  }

  // ── Accounts ─────────────────────────────────────────────────────────────

  void addAccount(Map<String, dynamic> account) {
    accounts.add(account);
    notifyListeners();
  }

  void deleteAccount(String id) {
    accounts.removeWhere((a) => a['id'] == id);
    notifyListeners();
  }

  // ── Recurring ────────────────────────────────────────────────────────────

  void addRecurring(Map<String, dynamic> r) {
    recurringTransactions.add(r);
    notifyListeners();
  }

  void deleteRecurring(String id) {
    recurringTransactions.removeWhere((r) => r['id'] == id);
    notifyListeners();
  }

  // ── Savings Goals ─────────────────────────────────────────────────────────

  void addGoal(Map<String, dynamic> goal) {
    savingsGoals.add(goal);
    notifyListeners();
  }

  void addFundsToGoal(String id, double amount) {
    final idx = savingsGoals.indexWhere((g) => g['id'] == id);
    if (idx >= 0) {
      savingsGoals[idx] = {
        ...savingsGoals[idx],
        'saved': (savingsGoals[idx]['saved'] as double) + amount,
      };
    }
    notifyListeners();
  }

  void deleteGoal(String id) {
    savingsGoals.removeWhere((g) => g['id'] == id);
    notifyListeners();
  }

  // ── Helper ────────────────────────────────────────────────────────────────

  double spentInCategory(String category) => transactions
      .where((t) => !(t['isIncome'] as bool) && t['category'] == category)
      .fold(0.0, (s, t) => s + (t['amount'] as double));
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
