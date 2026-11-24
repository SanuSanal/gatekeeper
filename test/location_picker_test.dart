import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatekeeper/src/features/location_picker/location_picker_screen.dart';
import 'package:gatekeeper/src/settings/validators.dart';
import 'package:latlong2/latlong.dart';

import 'fakes/fake_platform.dart';

void main() {
  group('parseCoordinates', () {
    test('plain pairs', () {
      expect(Validators.parseCoordinates('12.9716, 77.5946'), (12.9716, 77.5946));
      expect(Validators.parseCoordinates('12.9716 77.5946'), (12.9716, 77.5946));
      expect(Validators.parseCoordinates(' -33.8688,151.2093 '), (-33.8688, 151.2093));
    });

    test('Google Maps links and geo URIs', () {
      expect(
        Validators.parseCoordinates('https://www.google.com/maps/place/X/@12.9716,77.5946,17z/data=!3m1'),
        (12.9716, 77.5946),
      );
      expect(Validators.parseCoordinates('https://maps.google.com/?q=12.9716,77.5946'), (12.9716, 77.5946));
      expect(Validators.parseCoordinates('https://www.google.com/maps/search/?api=1&query=12.9716%2C77.5946'),
          (12.9716, 77.5946));
      expect(Validators.parseCoordinates('geo:12.9716,77.5946?z=17'), (12.9716, 77.5946));
    });

    test('rejects text without a valid pair', () {
      expect(Validators.parseCoordinates(''), isNull);
      expect(Validators.parseCoordinates('MG Road, Bengaluru'), isNull);
      expect(Validators.parseCoordinates('95.0, 10.0'), isNull);
      expect(Validators.parseCoordinates('0, 0'), isNull);
    });
  });

  group('LocationPickerScreen', () {
    Future<void> pump(WidgetTester tester, {LatLng? initial}) async {
      await tester.pumpWidget(MaterialApp(
        home: LocationPickerScreen(platform: FakePlatform(), initial: initial, radiusMeters: 150, showTiles: false),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the initial location and enables saving', (tester) async {
      await pump(tester, initial: const LatLng(12.5, 77.25));
      expect(find.text('12.500000, 77.250000'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Use this location')).onPressed, isNotNull);
    });

    testWidgets('without a saved spot it centres on the current location', (tester) async {
      await pump(tester);
      expect(find.text('12.970000, 77.590000'), findsOneWidget); // FakePlatform.getCurrentLocation
    });

    testWidgets('pasting coordinates in search jumps there', (tester) async {
      await pump(tester, initial: const LatLng(1, 1));
      await tester.enterText(find.byType(TextField).first, 'https://maps.google.com/?q=10.5,76.25');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('10.500000, 76.250000'), findsOneWidget);
    });

    testWidgets('address search lists places and picking one moves the pin', (tester) async {
      await pump(tester, initial: const LatLng(1, 1));
      await tester.enterText(find.byType(TextField).first, 'Gate Road');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gate Road, Bengaluru'));
      await tester.pumpAndSettle();
      expect(find.text('12.971600, 77.594600'), findsOneWidget);
    });
  });
}
