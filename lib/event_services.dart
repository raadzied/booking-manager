enum EventShift { morning, evening, fullDay }

class EventPackage {
  const EventPackage({
    required this.name,
    required this.price,
    this.includedGuests = 0,
    this.additionalGuestPrice = 0,
  });

  final String name;
  final double price;
  final int includedGuests;
  final double additionalGuestPrice;
}

class SeasonalRate {
  const SeasonalRate({
    required this.startDate,
    required this.endDate,
    required this.multiplier,
    this.id,
  });

  final DateTime startDate;
  final DateTime endDate;
  final double multiplier;
  final String? id;

  bool appliesTo(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }
}

class EventQuote {
  const EventQuote({
    required this.totalAmount,
    required this.depositAmount,
    required this.seasonalMultiplier,
  });

  final double totalAmount;
  final double depositAmount;
  final double seasonalMultiplier;
}

class EventService {
  const EventService({
    required this.id,
    required this.name,
    required this.category,
    required this.city,
    required this.basePrice,
    this.maxGuests,
    this.depositPercent = 20,
    this.packages = const [],
    this.seasonalRates = const [],
  });

  final String id;
  final String name;
  final String category;
  final String city;
  final double basePrice;
  final int? maxGuests;
  final double depositPercent;
  final List<EventPackage> packages;
  final List<SeasonalRate> seasonalRates;

  EventQuote quote({
    required DateTime date,
    required EventShift shift,
    String? packageName,
    int guestCount = 0,
  }) {
    if (!basePrice.isFinite ||
        basePrice <= 0 ||
        !depositPercent.isFinite ||
        depositPercent < 0 ||
        depositPercent > 100) {
      throw StateError('بيانات التسعير غير صالحة.');
    }

    if (maxGuests != null && guestCount > maxGuests!) {
      throw StateError('عدد الضيوف يتجاوز سعة المكان.');
    }
    if (maxGuests != null && guestCount < 1) {
      throw StateError('أدخل عدد الضيوف.');
    }

    final selectedPackage = packages.isEmpty
        ? null
        : packages.cast<EventPackage?>().firstWhere(
              (item) => item?.name == packageName,
              orElse: () => null,
            );
    if (packages.isNotEmpty && selectedPackage == null) {
      throw StateError('اختر باقة صالحة للخدمة.');
    }

    var seasonalMultiplier = 1.0;
    for (final rate in seasonalRates) {
      if (rate.appliesTo(date) && rate.multiplier > seasonalMultiplier) {
        seasonalMultiplier = rate.multiplier;
      }
    }
    if (!seasonalMultiplier.isFinite || seasonalMultiplier <= 0) {
      throw StateError('معامل التسعير الموسمي غير صالح.');
    }

    final base = selectedPackage?.price ?? basePrice;
    final includedGuests = selectedPackage?.includedGuests ?? 0;
    final extraGuests =
        guestCount > includedGuests ? guestCount - includedGuests : 0;
    final extraGuestCost =
        extraGuests * (selectedPackage?.additionalGuestPrice ?? 0);
    final double shiftMultiplier;
    switch (shift) {
      case EventShift.morning:
        shiftMultiplier = 0.8;
        break;
      case EventShift.evening:
        shiftMultiplier = 1.0;
        break;
      case EventShift.fullDay:
        shiftMultiplier = 1.5;
        break;
    }
    final total =
        ((base * shiftMultiplier + extraGuestCost) * seasonalMultiplier * 100)
                .roundToDouble() /
            100;
    return EventQuote(
      totalAmount: total,
      depositAmount: (total * depositPercent).roundToDouble() / 100,
      seasonalMultiplier: seasonalMultiplier,
    );
  }
}

const sampleEventServices = <EventService>[
  EventService(
    id: 'sanaa-hall-1',
    name: 'قاعة ليالي صنعاء',
    category: 'قاعات أفراح',
    city: 'صنعاء',
    basePrice: 180000,
    maxGuests: 400,
    packages: [
      EventPackage(
        name: 'الباقة الأساسية',
        price: 180000,
        includedGuests: 150,
        additionalGuestPrice: 500,
      ),
      EventPackage(
        name: 'الباقة المميزة',
        price: 250000,
        includedGuests: 250,
        additionalGuestPrice: 450,
      ),
    ],
  ),
  EventService(
    id: 'photographer-1',
    name: 'عدسة المصور',
    category: 'مصورين واستوديوهات',
    city: 'صنعاء',
    basePrice: 65000,
  ),
  EventService(
    id: 'artist-1',
    name: 'الفنان سامي',
    category: 'فنانين وزفات',
    city: 'صنعاء',
    basePrice: 120000,
  ),
  EventService(
    id: 'decor-1',
    name: 'لمسة ورد للكوش',
    category: 'تنسيق كوش وضيافة',
    city: 'صنعاء',
    basePrice: 95000,
  ),
  EventService(
    id: 'sound-1',
    name: 'أنغام للصوت والإضاءة',
    category: 'صوتيات وإضاءة',
    city: 'صنعاء',
    basePrice: 80000,
  ),
];
