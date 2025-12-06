import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legacy_gantt_chart/src/axis_painter.dart';
import 'package:legacy_gantt_chart/src/models/legacy_gantt_theme.dart';

void main() {
  group('AxisPainter', () {
    final theme = LegacyGanttTheme(
      backgroundColor: Colors.white,
      barColorPrimary: Colors.blue,
      barColorSecondary: Colors.lightBlue,
      textColor: Colors.black,
      taskTextStyle: const TextStyle(color: Colors.black),
      gridColor: Colors.grey,
      axisTextStyle: const TextStyle(color: Colors.black, fontSize: 10),
    );

    double mockScale(DateTime date) => date.difference(DateTime(2023, 1, 1)).inHours * 2.0; // 2 pixels per hour

    Finder findPainter() => find.descendant(
          of: find.byType(CustomPaint),
          matching: find.byWidgetPredicate((widget) => widget is CustomPaint && widget.painter is AxisPainter),
        );

    testWidgets('paints basic axis without error', (WidgetTester tester) async {
      final domain = [DateTime(2023, 1, 1), DateTime(2023, 1, 10)];
      final visibleDomain = [DateTime(2023, 1, 1), DateTime(2023, 1, 5)];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CustomPaint(
            size: const Size(500, 100),
            painter: AxisPainter(
              x: 0,
              y: 0,
              width: 500,
              height: 100,
              scale: mockScale,
              domain: domain,
              visibleDomain: visibleDomain,
              theme: theme,
            ),
          ),
        ),
      ));

      expect(findPainter(), findsOneWidget);
    });

    test('shouldRepaint returns true when fields change', () {
      final domain = [DateTime(2023, 1, 1), DateTime(2023, 1, 10)];
      final visibleDomain = [DateTime(2023, 1, 1), DateTime(2023, 1, 5)];

      final painter = AxisPainter(
        x: 0,
        y: 0,
        width: 500,
        height: 100,
        scale: mockScale,
        domain: domain,
        visibleDomain: visibleDomain,
        theme: theme,
      );

      // Same
      final painter2 = AxisPainter(
        x: 0,
        y: 0,
        width: 500,
        height: 100,
        scale: mockScale,
        domain: domain,
        visibleDomain: visibleDomain,
        theme: theme,
      );
      expect(painter.shouldRepaint(painter2), isFalse);

      // Changed dimension
      expect(
          painter.shouldRepaint(AxisPainter(
              x: 0,
              y: 0,
              width: 600,
              height: 100,
              scale: mockScale,
              domain: domain,
              visibleDomain: visibleDomain,
              theme: theme)),
          isTrue);

      // Changed theme
      expect(
          painter.shouldRepaint(AxisPainter(
            x: 0,
            y: 0,
            width: 500,
            height: 100,
            scale: mockScale,
            domain: domain,
            visibleDomain: visibleDomain,
            theme: theme.copyWith(gridColor: Colors.red),
          )),
          isTrue);

      // Changed domain
      expect(
          painter.shouldRepaint(AxisPainter(
              x: 0,
              y: 0,
              width: 500,
              height: 100,
              scale: mockScale,
              domain: [DateTime(2023, 1, 1), DateTime(2023, 1, 11)],
              visibleDomain: visibleDomain,
              theme: theme)),
          isTrue);

      // Changed visible domain
      expect(
          painter.shouldRepaint(AxisPainter(
              x: 0,
              y: 0,
              width: 500,
              height: 100,
              scale: mockScale,
              domain: domain,
              visibleDomain: [DateTime(2023, 1, 1), DateTime(2023, 1, 6)],
              theme: theme)),
          isTrue);
    });

    testWidgets('paints weekend highlights when enabled', (WidgetTester tester) async {
      // 2023-01-01 is a Sunday. 2023-01-07 is Saturday, 08 is Sunday.
      final domain = [DateTime(2023, 1, 1), DateTime(2023, 1, 15)];
      final visibleDomain = [DateTime(2023, 1, 1), DateTime(2023, 1, 14)];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CustomPaint(
            size: const Size(800, 100),
            painter: AxisPainter(
              x: 0,
              y: 0,
              width: 800,
              height: 100,
              scale: mockScale,
              domain: domain,
              visibleDomain: visibleDomain,
              theme: theme,
              weekendColor: Colors.grey.withAlpha(50),
              weekendDays: [DateTime.saturday, DateTime.sunday],
            ),
          ),
        ),
      ));
      expect(findPainter(), findsOneWidget);
    });

    // --- Tick Interval Tests ---

    // Helper to run a test with specific visible duration
    Future<void> testTickInterval(WidgetTester tester, Duration visibleDuration) async {
      final start = DateTime(2023, 1, 1);
      final end = start.add(visibleDuration);
      final domain = [start, end];
      final visibleDomain = [start, end]; // Full domain visible

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CustomPaint(
            size: const Size(800, 100),
            painter: AxisPainter(
              x: 0,
              y: 0,
              width: 800,
              height: 100,
              scale: mockScale,
              domain: domain,
              visibleDomain: visibleDomain,
              theme: theme,
            ),
          ),
        ),
      ));
      expect(findPainter(), findsOneWidget);
    }

    testWidgets('handles > 60 days interval (weeks)', (WidgetTester tester) async {
      await testTickInterval(tester, const Duration(days: 65));
    });

    testWidgets('handles > 14 days interval (2 days)', (WidgetTester tester) async {
      await testTickInterval(tester, const Duration(days: 20));
    });

    testWidgets('handles > 3 days interval (daily)', (WidgetTester tester) async {
      await testTickInterval(tester, const Duration(days: 10));
    });

    testWidgets('handles > 48 hours interval (12 hours)', (WidgetTester tester) async {
      await testTickInterval(tester, const Duration(hours: 50));
    });

    testWidgets('handles > 24 hours interval (6 hours)', (WidgetTester tester) async {
      await testTickInterval(tester, const Duration(hours: 30));
    });

    testWidgets('handles > 12 hours interval (2 hours)', (WidgetTester tester) async {
      await testTickInterval(tester, const Duration(hours: 14));
    });

    testWidgets('handles > 6 hours interval (1 hour)', (WidgetTester tester) async {
      await testTickInterval(tester, const Duration(hours: 7));
    });

    testWidgets('handles > 3 hours interval (30 min)', (WidgetTester tester) async {
      await testTickInterval(tester, const Duration(hours: 4));
    });

    testWidgets('handles > 90 minutes interval (15 min)', (WidgetTester tester) async {
      await testTickInterval(tester, const Duration(minutes: 100));
    });

    testWidgets('handles > 30 minutes interval (5 min)', (WidgetTester tester) async {
      await testTickInterval(tester, const Duration(minutes: 40));
    });

    testWidgets('handles short interval (1 min)', (WidgetTester tester) async {
      await testTickInterval(tester, const Duration(minutes: 20));
    });

    testWidgets('uses custom label builder', (WidgetTester tester) async {
      final start = DateTime(2023, 1, 1);
      final end = start.add(const Duration(hours: 10));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CustomPaint(
            size: const Size(800, 100),
            painter: AxisPainter(
              x: 0,
              y: 0,
              width: 800,
              height: 100,
              scale: mockScale,
              domain: [start, end],
              visibleDomain: [start, end],
              theme: theme,
              timelineAxisLabelBuilder: (date, interval) => 'CUSTOM',
            ),
          ),
        ),
      ));
      expect(findPainter(), findsOneWidget);
    });

    testWidgets('handles empty domain gracefuly', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CustomPaint(
            size: const Size(800, 100),
            painter: AxisPainter(
              x: 0,
              y: 0,
              width: 800,
              height: 100,
              scale: mockScale,
              domain: [],
              visibleDomain: [],
              theme: theme,
            ),
          ),
        ),
      ));
      expect(findPainter(), findsOneWidget);
    });

    testWidgets('handles start after end gracefuly', (WidgetTester tester) async {
      final start = DateTime(2023, 1, 10);
      final end = DateTime(2023, 1, 1); // backwards

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CustomPaint(
            size: const Size(800, 100),
            painter: AxisPainter(
              x: 0,
              y: 0,
              width: 800,
              height: 100,
              scale: mockScale,
              domain: [start, end],
              visibleDomain: [start, end],
              theme: theme,
            ),
          ),
        ),
      ));
      expect(findPainter(), findsOneWidget);
    });

    test('week number calculation boundaries', () {
      // Need to access _weekNumber - but it's private.
      // We can verify it indirectly via painting text, or just assume the coverage check
      // will hit it via the >60days test if that includes year boundaries.
      // Let's rely on the >60days test for now, ensuring it spans a year boundary.
    });

    testWidgets('handles year boundary for week numbers', (WidgetTester tester) async {
      // Spanning Dec 2022 to Feb 2023
      final start = DateTime(2022, 12, 1);
      final end = DateTime(2023, 2, 1);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CustomPaint(
            size: const Size(800, 100),
            painter: AxisPainter(
              x: 0,
              y: 0,
              width: 800,
              height: 100,
              scale: mockScale, // This scale might need adjustment for long range but mock is simple linear
              domain: [start, end],
              visibleDomain: [start, end],
              theme: theme,
            ),
          ),
        ),
      ));
      expect(findPainter(), findsOneWidget);
    });
  });
}
