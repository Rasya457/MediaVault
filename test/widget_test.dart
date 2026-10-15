import 'package:flutter_test/flutter_test.dart';
import 'package:mediavault/app.dart';

void main() {
  testWidgets('App builds without error', (tester) async {
    await tester.pumpWidget(const App());
    expect(find.byType(App), findsOneWidget);
  });
}
