import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sloth/todo_theme.dart';
import 'package:sloth/widgets/about_dialog.dart';

Widget host() => MaterialApp(
  theme: buildTodoTheme(TodoColors.gruvboxLight),
  home: const Scaffold(body: SlothAboutDialog()),
);

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Sloth',
      packageName: 'io.github.kurobeats.sloth',
      version: '1.2.3',
      buildNumber: '42',
      buildSignature: '',
    );
  });

  testWidgets('the version comes from the build, not a constant', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('Version 1.2.3'), findsOneWidget);
  });

  testWidgets('the repository link is shown and tappable', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text(repoUrl), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });
}
