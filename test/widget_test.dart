import 'package:flutter_test/flutter_test.dart';

import 'package:booking_manager/event_services.dart';
import 'package:booking_manager/main.dart';

void main() {
  test('seasonal pricing includes both boundary dates', () {
    final season = SeasonalRate(
      startDate: DateTime(2026, 12, 1, 23),
      endDate: DateTime(2026, 12, 3, 1),
      multiplier: 1.2,
    );

    expect(season.appliesTo(DateTime(2026, 12, 1)), isTrue);
    expect(season.appliesTo(DateTime(2026, 12, 3)), isTrue);
    expect(season.appliesTo(DateTime(2026, 11, 30)), isFalse);
    expect(season.appliesTo(DateTime(2026, 12, 4)), isFalse);
  });

  test('booking tracks remaining balance and survives serialization', () {
    final booking = Booking(
      id: 'booking-1',
      customer: 'عميل',
      phone: '123456',
      service: 'قاعة',
      provider: 'قاعة النخيل',
      date: DateTime(2026, 12, 1),
      amount: 1200,
      paid: 300,
    );

    expect(booking.remaining, 900);
    final restored = Booking.fromJson(booking.toJson());
    expect(restored.customer, booking.customer);
    expect(restored.amount, booking.amount);
    expect(restored.paid, booking.paid);
    expect(restored.status, BookingStatus.pending);
  });

  test('financial totals exclude cancelled bookings from booked value', () {
    final state = AppState();
    state.bookings.addAll([
      Booking(
        id: 'active',
        customer: 'عميل',
        phone: '1',
        service: 'تصوير',
        provider: 'مصور',
        date: DateTime(2026, 12, 1),
        amount: 1000,
        paid: 200,
      ),
      Booking(
        id: 'cancelled',
        customer: 'عميل آخر',
        phone: '2',
        service: 'قاعة',
        provider: 'قاعة',
        date: DateTime(2026, 12, 2),
        amount: 500,
        paid: 50,
        status: BookingStatus.cancelled,
      ),
    ]);

    expect(state.bookingValue, 1000);
    expect(state.bookingPayments, 250);
    expect(state.outstanding, 800);
  });

  test('manual income and expenses are kept separate from booking payments',
      () {
    final state = AppState();
    state.entries.addAll([
      LedgerEntry(
        id: 'income',
        title: 'دخل إضافي',
        amount: 90,
        date: DateTime(2026, 11, 2),
        kind: 'income',
      ),
      LedgerEntry(
        id: 'expense',
        title: 'مصروف',
        amount: 30,
        date: DateTime(2026, 11, 2),
        kind: 'expense',
      ),
    ]);

    expect(state.totalIncome, 90);
    expect(state.expenses, 30);
  });
}
