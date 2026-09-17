import 'package:ansight_example/main.dart' show AnsightHarnessApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the desktop harness', (WidgetTester tester) async {
    await tester.pumpWidget(
      const AnsightHarnessApp(
        autoInitialize: false,
        enableSceneAnimation: false,
      ),
    );
    await tester.pump();

    expect(find.text('Ansight Flutter Harness'), findsOneWidget);
    expect(find.byKey(const Key('fixture-dashboard')), findsOneWidget);
  });
}
