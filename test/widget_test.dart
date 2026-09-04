// Smoke test: app khoi dong khong crash, hien thi man hinh loading/dang nhap
// ban dau (khong goi API that trong test).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:van_test/main.dart';

void main() {
  testWidgets('App boots and shows startup gate', (WidgetTester tester) async {
    await tester.pumpWidget(const VanApp());
    await tester.pump();

    // Ngay sau khi khoi dong (truoc khi tryRestoreSession() hoan tat) phai
    // thay indicator loading, khong bi crash/exception.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
