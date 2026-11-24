import 'package:flutter/material.dart';

import 'app.dart';
import 'src/app_controller.dart';
import 'src/platform/gatekeeper_platform.dart';
import 'src/update/update_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final platform = PigeonGateKeeperPlatform();
  runApp(GateKeeperApp(controller: AppController(platform), updates: UpdateController(platform)));
}
