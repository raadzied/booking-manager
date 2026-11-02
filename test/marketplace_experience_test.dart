import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:booking_manager/marketplace_experience.dart';

void main() {
  testWidgets('customer can open a provider profile and inspect availability',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CustomerExperience(
          bookings: const [],
          onCreateBooking: (_) async {},
          onRoleChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('اكتشف خدمات مناسبتك'), findsOneWidget);
    expect(find.text('قاعات'), findsOneWidget);
    expect(find.text('الأعلى تقييماً'), findsOneWidget);

    await tester.drag(
        find.byType(CustomScrollView).first, const Offset(0, -600));
    await tester.pumpAndSettle();
    final providerName = find.text('قاعة ليالي صنعاء').first;
    await tester.ensureVisible(providerName);
    await tester.pumpAndSettle();
    await tester.tap(providerName);
    await tester.pumpAndSettle();

    expect(find.text('قاعة ليالي صنعاء'), findsWidgets);
    final bookAction = find.text('احجز الآن');
    await tester.ensureVisible(bookAction);
    await tester.pumpAndSettle();
    expect(bookAction, findsOneWidget);
    await tester.tap(find.byIcon(Icons.calendar_month_outlined).first);
    await tester.pumpAndSettle();

    expect(find.text('اختر موعداً'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('محجوز'), findsOneWidget);
    expect(find.text('متابعة الحجز'), findsOneWidget);
  });

  testWidgets('provider can confirm a matching booking request',
      (tester) async {
    final booking = MarketplaceBooking(
      id: 'booking-1',
      customerName: 'عميل تجريبي',
      providerName: 'قاعة ليالي صنعاء',
      serviceName: 'قاعات',
      date: DateTime.now().add(const Duration(days: 3)),
      amount: 180000,
      status: 'pending',
    );
    String? updatedId;
    bool? confirmed;

    await tester.pumpWidget(
      MaterialApp(
        home: ProviderExperience(
          bookings: [booking],
          onUpdateBooking: (id, value) async {
            updatedId = id;
            confirmed = value;
          },
          onRoleChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('الحجوزات').last);
    await tester.pumpAndSettle();
    expect(find.text('عميل تجريبي'), findsOneWidget);

    await tester.tap(find.text('تأكيد الحجز'));
    await tester.pumpAndSettle();

    expect(updatedId, 'booking-1');
    expect(confirmed, isTrue);
  });
}
