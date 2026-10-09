import 'package:flutter_test/flutter_test.dart';
import 'package:krishi_saathi/app_state.dart';
import 'package:krishi_saathi/main.dart';

void main() {
  testWidgets('KrishiApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(KrishiApp(state: AppState()));
    expect(find.text('Krishi Saathi'), findsOneWidget);
  });
}
