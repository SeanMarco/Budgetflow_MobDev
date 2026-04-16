import 'package:flutter_test/flutter_test.dart';
import 'package:budgetflow/main.dart';

void main() {
  testWidgets('App loads', (WidgetTester tester) async {
    // Remove 'const' here because BudgetFlowApp uses runtime ValueListenableBuilder
    await tester.pumpWidget(BudgetFlowApp());

    expect(find.text('BudgetFlow'), findsOneWidget);
  });
}
