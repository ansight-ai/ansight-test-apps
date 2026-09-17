import 'package:ansight_example/main.dart'
    show AnsightHarnessApp, ansightHarnessCaptureController;
import 'package:ansight_flutter/ansight.dart';
import 'package:flutter/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    AnsightFlutterCaptureBoundary(
      controller: ansightHarnessCaptureController,
      child: const AnsightHarnessApp(),
    ),
  );
}
