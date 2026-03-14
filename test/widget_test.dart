import 'package:flutter_test/flutter_test.dart';

import 'package:bingo/main.dart';

void main() {
  testWidgets('App renders home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const BingoApp());
    expect(find.text('Bingo Assistant'), findsOneWidget);
  });
}
