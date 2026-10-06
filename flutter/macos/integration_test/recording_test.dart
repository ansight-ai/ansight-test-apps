import 'package:ansight_example/harness_fixtures.dart';
import 'package:ansight_example/main.dart';
import 'package:ansight_flutter/ansight.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('records the Flutter desktop harness in Ansight', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      AnsightFlutterCaptureBoundary(
        controller: ansightHarnessCaptureController,
        automaticCaptureOptions: null,
        child: const AnsightHarnessApp(enableSceneAnimation: false),
      ),
    );
    await tester.pump();

    AnsightDebugSnapshot? initial;
    AnsightHostConnectionStatus? connection;
    for (var attempt = 0; attempt < 120; attempt += 1) {
      await tester.pump(const Duration(milliseconds: 100));
      try {
        final candidate = await Ansight.instance.snapshot();
        final candidateConnection = await Ansight.instance
            .hostConnectionStatus();
        if (candidate.initialized &&
            candidate.active &&
            candidateConnection.isConnected &&
            Ansight.instance.registeredToolIds.contains(
              'harness.database_summary',
            )) {
          initial = candidate;
          connection = candidateConnection;
          break;
        }
      } on Object {
        // Native startup can still be crossing the Flutter bridge.
      }
    }

    expect(initial, isNotNull, reason: 'Harness did not initialize in time.');
    expect(
      connection?.isConnected,
      isTrue,
      reason: 'Harness did not connect to the Ansight host in time.',
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('run-e2e-scenario')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    for (var attempt = 0; attempt < 80; attempt += 1) {
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('run-e2e-scenario')),
      );
      if (button.onPressed != null) {
        break;
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byKey(const Key('run-e2e-scenario')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    final updated = await Ansight.instance.snapshot();
    expect(updated.metricsRecorded, greaterThan(initial!.metricsRecorded));
    expect(updated.eventsRecorded, greaterThan(initial.eventsRecorded));
    expect(
      Ansight.instance.registeredToolIds,
      containsAll(<String>[
        'flutter.get_widget_tree',
        'flutter.inspect_widget',
        'flutter.find_widgets',
        'harness.echo',
        'harness.inspect_state',
        'harness.database_summary',
      ]),
    );
    expect(Ansight.instance.registeredArtifactProviderIds, contains('harness'));

    await Ansight.instance.enableTouchCapture();
    final beforeTouch = await Ansight.instance.snapshot();
    await tester.tapAt(const Offset(400, 100));
    await tester.pump(const Duration(milliseconds: 300));
    final afterTouch = await Ansight.instance.snapshot();
    expect(
      afterTouch.touchesCaptured,
      greaterThan(beforeTouch.touchesCaptured ?? 0),
      reason: 'Flutter pointer input did not reach native touch capture.',
    );

    final store = HarnessFixtureStore();
    await store.initialize();
    final database = await store.summary();
    expect(database.itemCount, greaterThanOrEqualTo(5));
    expect(database.eventCount, greaterThanOrEqualTo(2));

    final capture = await ansightHarnessCaptureController.capture(
      includeVisualTree: true,
    );
    expect(capture.success, isTrue, reason: capture.message);

    await Ansight.instance.sendClientLog(
      'Flutter desktop recording harness completed',
    );
    for (var frame = 0; frame < 120; frame += 1) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  });
}
