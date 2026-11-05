import 'package:flutter_test/flutter_test.dart';
import 'package:booking_manager/event_services.dart';

void main() {
  test('seasonal rate includes both its start and end dates', () {
    final service = EventService(
      id: 'hall',
      name: 'Test Hall',
      category: 'قاعات أفراح',
      city: 'صنعاء',
      basePrice: 100000,
      maxGuests: 300,
      packages: const [
        EventPackage(
          name: 'Base',
          price: 100000,
          includedGuests: 100,
          additionalGuestPrice: 250,
        ),
      ],
      seasonalRates: [
        SeasonalRate(
          startDate: DateTime(2026, 12, 1),
          endDate: DateTime(2026, 12, 5),
          multiplier: 1.2,
        ),
      ],
    );

    for (final date in [
      DateTime(2026, 12, 1),
      DateTime(2026, 12, 5),
    ]) {
      final quote = service.quote(
        date: date,
        shift: EventShift.evening,
        packageName: 'Base',
        guestCount: 120,
      );
      expect(quote.totalAmount, 126000);
      expect(quote.depositAmount, 25200);
    }
  });

  test('rejects guests above capacity and applies shift pricing', () {
    final service = sampleEventServices.first;
    expect(
      () => service.quote(
        date: DateTime(2026, 8, 12),
        shift: EventShift.evening,
        packageName: 'الباقة الأساسية',
        guestCount: 401,
      ),
      throwsStateError,
    );

    final morning = service.quote(
      date: DateTime(2026, 8, 12),
      shift: EventShift.morning,
      packageName: 'الباقة الأساسية',
      guestCount: 150,
    );
    final evening = service.quote(
      date: DateTime(2026, 8, 12),
      shift: EventShift.evening,
      packageName: 'الباقة الأساسية',
      guestCount: 150,
    );
    expect(morning.totalAmount, 144000);
    expect(evening.totalAmount, 180000);
    expect(evening.depositAmount, 36000);
  });

  test('rounds totals and deposits to two decimal places', () {
    const service = EventService(
      id: 'photo',
      name: 'Photographer',
      category: 'مصورين',
      city: 'صنعاء',
      basePrice: 100.25,
      depositPercent: 12.5,
    );
    final quote = service.quote(
      date: DateTime(2026, 8, 12),
      shift: EventShift.evening,
    );
    expect(quote.totalAmount, 100.25);
    expect(quote.depositAmount, 12.53);
  });
}
