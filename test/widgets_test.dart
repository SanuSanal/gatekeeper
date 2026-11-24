import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatekeeper/app.dart';
import 'package:gatekeeper/src/app_controller.dart';
import 'package:gatekeeper/src/features/permissions/permission_service.dart';
import 'package:gatekeeper/src/platform/gatekeeper_platform.dart';
import 'package:gatekeeper/src/update/update_controller.dart';
import 'package:gatekeeper/src/update/update_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes/fake_platform.dart';

class FakePermissions extends PermissionService {
  const FakePermissions();

  @override
  Future<Map<String, bool>> statusAll() async => {for (final i in PermissionService.items) i.id: true};

  @override
  Future<bool> isGranted(PermissionItem item) async => true;
}

Future<FakePlatform> pumpApp(WidgetTester tester, {void Function(FakePlatform)? setup}) async {
  final platform = FakePlatform();
  setup?.call(platform);
  SharedPreferences.setMockInitialValues({'update_auto_check': false});
  final updates = UpdateController(
    platform,
    service: UpdateService(client: MockClient((_) async => http.Response('', 404))),
  );
  await tester.pumpWidget(GateKeeperApp(
    controller: AppController(platform),
    updates: updates,
    permissions: const FakePermissions(),
  ));
  await tester.pump();
  await tester.pump();
  return platform;
}

void main() {
  testWidgets('home shows branding, stopped status and start button', (tester) async {
    await pumpApp(tester);
    expect(find.text('GateKeeper'), findsWidgets);
    expect(find.text('Not monitoring'), findsOneWidget);
    expect(find.text('Start monitoring'), findsOneWidget);
    expect(find.text('Parking geofence'), findsOneWidget);
    expect(find.text('Android Auto'), findsOneWidget);
  });

  testWidgets('starting monitoring updates status', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Start monitoring'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Monitoring'), findsOneWidget);
    expect(find.text('Stop monitoring'), findsOneWidget);
    expect(find.text('Outside'), findsOneWidget);
  });

  testWidgets('start failure lists blocking problems', (tester) async {
    await pumpApp(tester, setup: (p) => p.startProblems = ['SIM_UNAVAILABLE']);
    await tester.tap(find.text('Start monitoring'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('Selected SIM is not available'), findsOneWidget);
  });

  testWidgets('live status push updates the geofence tile', (tester) async {
    final platform = await pumpApp(tester);
    platform.push(StatusMessage(
      monitoring: true,
      phase: 'PENDING_DELAYED_CALL',
      geofence: 'INSIDE',
      vehicle: 'ACTIVE',
      androidAuto: 'INACTIVE',
      carBluetoothConnected: false,
      testMode: true,
      problems: const [],
      lastTriggerAt: DateTime.now().millisecondsSinceEpoch,
      lastTriggerSource: 'ACTIVITY_IN_VEHICLE',
      lastTriggerDecision: 'pending 5s revalidation',
    ));
    await tester.pump(); // deliver the stream event
    await tester.pump(); // rebuild
    expect(find.text('Inside'), findsOneWidget);
    expect(find.text('In vehicle'), findsOneWidget);
    expect(find.text('TEST MODE'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('In vehicle inside parking'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('In vehicle inside parking'), findsOneWidget);
  });

  testWidgets('settings shows masked number and missing SIM warning', (tester) async {
    await pumpApp(tester, setup: (p) {
      p.settings.gateNumber = '+919876543210';
      p.settings.simSubscriptionId = 7; // not present
      p.settings.simLabel = 'SIM 1 · Old Carrier';
    });
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('••• 3210'), findsOneWidget);
    expect(find.textContaining('+919876543210'), findsNothing);
    expect(find.textContaining('is not available'), findsOneWidget);
  });

  testWidgets('test mode reveals the simulator and sends events', (tester) async {
    final platform = await pumpApp(tester, setup: (p) => p.settings.testMode = true);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Enter geofence'), 300, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Enter geofence'));
    await tester.pump();
    expect(platform.simulated, ['enter']);
  });

  testWidgets('onboarding is shown until completed', (tester) async {
    await pumpApp(tester, setup: (p) => p.settings.onboardingComplete = false);
    expect(find.text('Welcome to GateKeeper'), findsOneWidget);
  });
}
