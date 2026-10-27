import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The text inside the button with [key] (its icon left out), its lines
/// joined by " | ".
String buttonText(WidgetTester tester, Key key) => tester
    .widgetList<RichText>(
      find.descendant(of: find.byKey(key), matching: find.byType(RichText)),
    )
    .map((t) => t.text.toPlainText())
    .where(
      (t) => t.trim().isNotEmpty && t.codeUnitAt(0) < 0xE000,
    ) // not an icon
    .join(' | ');
