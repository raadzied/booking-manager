import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;

enum ChaletReservationStatus {
  awaitingProvider,
  confirmed,
  completed,
  cancelled,
}

enum PaymentReceiptStatus { submitted, verified, rejected }

enum TransferWallet { alKuraimi, jeeb }

enum SettlementStatus { held, ready, settled }

class SeasonalPrice {
  const SeasonalPrice({
    required this.startDate,
    required this.endDate,
    required this.nightlyPrice,
    required this.label,
  });

  final DateTime startDate;
  final DateTime endDate;
  final int nightlyPrice;
  final String label;

  bool appliesTo(DateTime date) {
    final day = _dateOnly(date);
    return !day.isBefore(_dateOnly(startDate)) &&
        day.isBefore(_dateOnly(endDate));
  }

  Map<String, Object?> toJson() => {
        'startDate': _dateOnly(startDate).toIso8601String(),
        'endDate': _dateOnly(endDate).toIso8601String(),
        'nightlyPrice': nightlyPrice,
        'label': label,
      };

  factory SeasonalPrice.fromJson(Map<String, dynamic> json) => SeasonalPrice(
        startDate: DateTime.parse(json['startDate'] as String),
        endDate: DateTime.parse(json['endDate'] as String),
        nightlyPrice: (json['nightlyPrice'] as num).toInt(),
        label: json['label'] as String,
      );
}

class BookingPolicy {
  const BookingPolicy({
    this.depositPercent = 10,
    this.commissionPercent = 2,
    this.providerResponseHours = 12,
    this.disputeWindowHours = 24,
  })  : assert(depositPercent > 0 && depositPercent <= 100),
        assert(commissionPercent >= 0 && commissionPercent < 100),
        assert(providerResponseHours > 0),
        assert(disputeWindowHours > 0);

  final int depositPercent;
  final int commissionPercent;
  final int providerResponseHours;
  final int disputeWindowHours;

  BookingPolicy withDepositPercent(int value) {
    if (value <= 0 || value > 100) {
      throw ArgumentError.value(value, 'value', 'Must be between 1 and 100');
    }
    return BookingPolicy(
      depositPercent: value,
      commissionPercent: commissionPercent,
      providerResponseHours: providerResponseHours,
      disputeWindowHours: disputeWindowHours,
    );
  }

  Map<String, Object?> toJson() => {
        'depositPercent': depositPercent,
        'commissionPercent': commissionPercent,
        'providerResponseHours': providerResponseHours,
        'disputeWindowHours': disputeWindowHours,
      };

  factory BookingPolicy.fromJson(Map<String, dynamic> json) => BookingPolicy(
        depositPercent: (json['depositPercent'] as num).toInt(),
        commissionPercent: (json['commissionPercent'] as num).toInt(),
        providerResponseHours: (json['providerResponseHours'] as num).toInt(),
        disputeWindowHours: (json['disputeWindowHours'] as num).toInt(),
      );
}

class ChaletListing {
  ChaletListing({
    required this.id,
    required this.name,
    required this.city,
    required this.description,
    required this.maxGuests,
    required this.nightlyPrice,
    List<SeasonalPrice> seasonalPrices = const [],
    List<DateTime> unavailableNights = const [],
  })  : seasonalPrices = List.unmodifiable(seasonalPrices),
        unavailableNights = List.unmodifiable(unavailableNights.map(_dateOnly));

  final String id;
  final String name;
  final String city;
  final String description;
  final int maxGuests;
  final int nightlyPrice;
  final List<SeasonalPrice> seasonalPrices;
  final List<DateTime> unavailableNights;

  int priceForNight(DateTime date) {
    for (final season in seasonalPrices) {
      if (season.appliesTo(date)) return season.nightlyPrice;
    }
    return nightlyPrice;
  }

  bool isNightAvailable(
    DateTime date,
    List<ChaletReservation> reservations,
  ) {
    final day = _dateOnly(date);
    if (unavailableNights.any((blocked) => _sameDay(blocked, day))) {
      return false;
    }
    return !reservations.any((reservation) =>
        reservation.chaletId == id &&
        reservation.status != ChaletReservationStatus.cancelled &&
        !day.isBefore(_dateOnly(reservation.checkIn)) &&
        day.isBefore(_dateOnly(reservation.checkOut)));
  }

  bool isRangeAvailable(
    DateTime checkIn,
    DateTime checkOut,
    List<ChaletReservation> reservations,
  ) {
    final start = _dateOnly(checkIn);
    final end = _dateOnly(checkOut);
    if (!end.isAfter(start) || end.difference(start).inDays > 90) {
      return false;
    }
    for (var night = start;
        night.isBefore(end);
        night = night.add(const Duration(days: 1))) {
      if (!isNightAvailable(night, reservations)) return false;
    }
    return true;
  }

  ReservationQuote quote({
    required DateTime checkIn,
    required DateTime checkOut,
    required List<ChaletReservation> reservations,
    required BookingPolicy policy,
  }) {
    if (!isRangeAvailable(checkIn, checkOut, reservations)) {
      throw StateError('الفترة غير متاحة أو تتجاوز الحد المسموح للإقامة');
    }
    var total = 0;
    var nights = 0;
    for (var night = _dateOnly(checkIn);
        night.isBefore(_dateOnly(checkOut));
        night = night.add(const Duration(days: 1))) {
      total += priceForNight(night);
      nights++;
    }
    return ReservationQuote(
      nights: nights,
      totalAmount: total,
      depositAmount: _percentageCeiling(total, policy.depositPercent),
      commissionAmount: _percentageCeiling(total, policy.commissionPercent),
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'city': city,
        'description': description,
        'maxGuests': maxGuests,
        'nightlyPrice': nightlyPrice,
        'seasonalPrices':
            seasonalPrices.map((season) => season.toJson()).toList(),
        'unavailableNights':
            unavailableNights.map((day) => day.toIso8601String()).toList(),
      };

  factory ChaletListing.fromJson(Map<String, dynamic> json) => ChaletListing(
        id: json['id'] as String,
        name: json['name'] as String,
        city: json['city'] as String,
        description: json['description'] as String,
        maxGuests: (json['maxGuests'] as num).toInt(),
        nightlyPrice: (json['nightlyPrice'] as num).toInt(),
        seasonalPrices: (json['seasonalPrices'] as List<dynamic>)
            .map((item) => SeasonalPrice.fromJson(item as Map<String, dynamic>))
            .toList(),
        unavailableNights: (json['unavailableNights'] as List<dynamic>)
            .map((item) => DateTime.parse(item as String))
            .toList(),
      );
}

class ReservationQuote {
  const ReservationQuote({
    required this.nights,
    required this.totalAmount,
    required this.depositAmount,
    required this.commissionAmount,
  });

  final int nights;
  final int totalAmount;
  final int depositAmount;
  final int commissionAmount;

  int get providerPayout => totalAmount - commissionAmount;
}

class PaymentReceipt {
  const PaymentReceipt({
    required this.id,
    required this.wallet,
    required this.amount,
    required this.reference,
    required this.submittedAt,
    this.proofBase64,
    this.proofFileName,
    this.status = PaymentReceiptStatus.submitted,
  });

  final String id;
  final TransferWallet wallet;
  final int amount;
  final String reference;
  final DateTime submittedAt;
  final String? proofBase64;
  final String? proofFileName;
  final PaymentReceiptStatus status;

  PaymentReceipt copyWith({PaymentReceiptStatus? status}) => PaymentReceipt(
        id: id,
        wallet: wallet,
        amount: amount,
        reference: reference,
        submittedAt: submittedAt,
        proofBase64: proofBase64,
        proofFileName: proofFileName,
        status: status ?? this.status,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'wallet': wallet.name,
        'amount': amount,
        'reference': reference,
        'submittedAt': submittedAt.toIso8601String(),
        'proofBase64': proofBase64,
        'proofFileName': proofFileName,
        'status': status.name,
      };

  factory PaymentReceipt.fromJson(Map<String, dynamic> json) => PaymentReceipt(
        id: json['id'] as String,
        wallet: TransferWallet.values
            .firstWhere((value) => value.name == json['wallet']),
        amount: (json['amount'] as num).toInt(),
        reference: json['reference'] as String,
        submittedAt: DateTime.parse(json['submittedAt'] as String),
        proofBase64: json['proofBase64'] as String?,
        proofFileName: json['proofFileName'] as String?,
        status: PaymentReceiptStatus.values
            .firstWhere((value) => value.name == json['status']),
      );
}

class ChaletReservation {
  ChaletReservation({
    required this.id,
    required this.chaletId,
    required this.chaletName,
    required this.customerName,
    required this.phone,
    required this.checkIn,
    required this.checkOut,
    required this.guests,
    required this.totalAmount,
    required this.depositAmount,
    required this.commissionAmount,
    required this.depositPercent,
    required this.commissionPercent,
    required this.responseHours,
    required this.disputeWindowHours,
    required this.createdAt,
    this.status = ChaletReservationStatus.awaitingProvider,
    List<PaymentReceipt> receipts = const [],
    this.settlementStatus = SettlementStatus.held,
    this.completedAt,
    this.settledAt,
    this.disputeReason,
    this.disputedAt,
  }) : receipts = List.unmodifiable(receipts);

  final String id;
  final String chaletId;
  final String chaletName;
  final String customerName;
  final String phone;
  final DateTime checkIn;
  final DateTime checkOut;
  final int guests;
  final int totalAmount;
  final int depositAmount;
  final int commissionAmount;
  final int depositPercent;
  final int commissionPercent;
  final int responseHours;
  final int disputeWindowHours;
  final DateTime createdAt;
  final ChaletReservationStatus status;
  final List<PaymentReceipt> receipts;
  final SettlementStatus settlementStatus;
  final DateTime? completedAt;
  final DateTime? settledAt;
  final String? disputeReason;
  final DateTime? disputedAt;

  int get nights => _dateOnly(checkOut).difference(_dateOnly(checkIn)).inDays;

  int get verifiedAmount => receipts
      .where((receipt) => receipt.status == PaymentReceiptStatus.verified)
      .fold(0, (total, receipt) => total + receipt.amount);

  int get pendingReceiptAmount => receipts
      .where((receipt) => receipt.status == PaymentReceiptStatus.submitted)
      .fold(0, (total, receipt) => total + receipt.amount);

  int get outstandingAmount =>
      (totalAmount - verifiedAmount).clamp(0, totalAmount).toInt();

  int get availableForReceipt =>
      (totalAmount - verifiedAmount - pendingReceiptAmount)
          .clamp(0, totalAmount)
          .toInt();

  int get remainingDeposit =>
      (depositAmount - verifiedAmount - pendingReceiptAmount)
          .clamp(0, depositAmount)
          .toInt();

  bool get isFullyPaid => verifiedAmount >= totalAmount;

  bool isProviderResponseOverdue(DateTime now) =>
      status == ChaletReservationStatus.awaitingProvider &&
      now.isAfter(createdAt.add(Duration(hours: responseHours)));

  ReservationPaymentState get paymentState {
    if (disputeReason != null) return ReservationPaymentState.disputed;
    if (settlementStatus == SettlementStatus.settled) {
      return ReservationPaymentState.settled;
    }
    if (settlementStatus == SettlementStatus.ready) {
      return ReservationPaymentState.settlementReady;
    }
    if (pendingReceiptAmount > 0) return ReservationPaymentState.receiptReview;
    if (isFullyPaid) return ReservationPaymentState.fundsHeld;
    if (verifiedAmount > 0) return ReservationPaymentState.partiallyPaid;
    return ReservationPaymentState.depositDue;
  }

  bool canOpenSettlement(DateTime now) {
    final completion = completedAt;
    return status == ChaletReservationStatus.completed &&
        settlementStatus == SettlementStatus.held &&
        disputeReason == null &&
        isFullyPaid &&
        completion != null &&
        !now.isBefore(completion.add(Duration(hours: disputeWindowHours)));
  }

  ChaletReservation copyWith({
    ChaletReservationStatus? status,
    List<PaymentReceipt>? receipts,
    SettlementStatus? settlementStatus,
    DateTime? completedAt,
    DateTime? settledAt,
    String? disputeReason,
    DateTime? disputedAt,
  }) =>
      ChaletReservation(
        id: id,
        chaletId: chaletId,
        chaletName: chaletName,
        customerName: customerName,
        phone: phone,
        checkIn: checkIn,
        checkOut: checkOut,
        guests: guests,
        totalAmount: totalAmount,
        depositAmount: depositAmount,
        commissionAmount: commissionAmount,
        depositPercent: depositPercent,
        commissionPercent: commissionPercent,
        responseHours: responseHours,
        disputeWindowHours: disputeWindowHours,
        createdAt: createdAt,
        status: status ?? this.status,
        receipts: receipts ?? this.receipts,
        settlementStatus: settlementStatus ?? this.settlementStatus,
        completedAt: completedAt ?? this.completedAt,
        settledAt: settledAt ?? this.settledAt,
        disputeReason: disputeReason ?? this.disputeReason,
        disputedAt: disputedAt ?? this.disputedAt,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'chaletId': chaletId,
        'chaletName': chaletName,
        'customerName': customerName,
        'phone': phone,
        'checkIn': _dateOnly(checkIn).toIso8601String(),
        'checkOut': _dateOnly(checkOut).toIso8601String(),
        'guests': guests,
        'totalAmount': totalAmount,
        'depositAmount': depositAmount,
        'commissionAmount': commissionAmount,
        'depositPercent': depositPercent,
        'commissionPercent': commissionPercent,
        'responseHours': responseHours,
        'disputeWindowHours': disputeWindowHours,
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
        'receipts': receipts.map((receipt) => receipt.toJson()).toList(),
        'settlementStatus': settlementStatus.name,
        'completedAt': completedAt?.toIso8601String(),
        'settledAt': settledAt?.toIso8601String(),
        'disputeReason': disputeReason,
        'disputedAt': disputedAt?.toIso8601String(),
      };

  factory ChaletReservation.fromJson(Map<String, dynamic> json) =>
      ChaletReservation(
        id: json['id'] as String,
        chaletId: json['chaletId'] as String,
        chaletName: json['chaletName'] as String,
        customerName: json['customerName'] as String,
        phone: json['phone'] as String,
        checkIn: DateTime.parse(json['checkIn'] as String),
        checkOut: DateTime.parse(json['checkOut'] as String),
        guests: (json['guests'] as num).toInt(),
        totalAmount: (json['totalAmount'] as num).toInt(),
        depositAmount: (json['depositAmount'] as num).toInt(),
        commissionAmount: (json['commissionAmount'] as num).toInt(),
        depositPercent: (json['depositPercent'] as num).toInt(),
        commissionPercent: (json['commissionPercent'] as num).toInt(),
        responseHours: (json['responseHours'] as num).toInt(),
        disputeWindowHours: (json['disputeWindowHours'] as num).toInt(),
        createdAt: DateTime.parse(json['createdAt'] as String),
        status: ChaletReservationStatus.values
            .firstWhere((value) => value.name == json['status']),
        receipts: (json['receipts'] as List<dynamic>)
            .map(
                (item) => PaymentReceipt.fromJson(item as Map<String, dynamic>))
            .toList(),
        settlementStatus: SettlementStatus.values
            .firstWhere((value) => value.name == json['settlementStatus']),
        completedAt: json['completedAt'] == null
            ? null
            : DateTime.parse(json['completedAt'] as String),
        settledAt: json['settledAt'] == null
            ? null
            : DateTime.parse(json['settledAt'] as String),
        disputeReason: json['disputeReason'] as String?,
        disputedAt: json['disputedAt'] == null
            ? null
            : DateTime.parse(json['disputedAt'] as String),
      );
}

enum ReservationPaymentState {
  depositDue,
  receiptReview,
  partiallyPaid,
  fundsHeld,
  disputed,
  settlementReady,
  settled,
}

class ChaletReservationRequest {
  ChaletReservationRequest({
    required this.id,
    required this.listing,
    required this.customerName,
    required this.phone,
    required this.checkIn,
    required this.checkOut,
    required this.guests,
    required BookingPolicy policy,
    required List<ChaletReservation> existingReservations,
    required this.createdAt,
  }) {
    final quote = listing.quote(
      checkIn: checkIn,
      checkOut: checkOut,
      reservations: existingReservations,
      policy: policy,
    );
    reservation = ChaletReservation(
      id: id,
      chaletId: listing.id,
      chaletName: listing.name,
      customerName: customerName.trim(),
      phone: phone.trim(),
      checkIn: _dateOnly(checkIn),
      checkOut: _dateOnly(checkOut),
      guests: guests,
      totalAmount: quote.totalAmount,
      depositAmount: quote.depositAmount,
      commissionAmount: quote.commissionAmount,
      depositPercent: policy.depositPercent,
      commissionPercent: policy.commissionPercent,
      responseHours: policy.providerResponseHours,
      disputeWindowHours: policy.disputeWindowHours,
      createdAt: createdAt,
    );
  }

  final String id;
  final ChaletListing listing;
  final String customerName;
  final String phone;
  final DateTime checkIn;
  final DateTime checkOut;
  final int guests;
  final DateTime createdAt;
  late final ChaletReservation reservation;
}

List<ChaletListing> sampleChaletListings() => [
      ChaletListing(
        id: 'demo-chalet-1',
        name: 'استراحة السكون',
        city: 'صنعاء',
        description: 'مساحة هادئة للعائلات مع جلسة خارجية ومطبخ.',
        maxGuests: 8,
        nightlyPrice: 35000,
        seasonalPrices: [
          SeasonalPrice(
            startDate: DateTime(2026, 7, 1),
            endDate: DateTime(2026, 9, 1),
            nightlyPrice: 50000,
            label: 'موسم الصيف',
          ),
        ],
        unavailableNights: [DateTime(2026, 6, 10)],
      ),
      ChaletListing(
        id: 'demo-chalet-2',
        name: 'مزرعة الوادي',
        city: 'صنعاء',
        description: 'مزرعة عائلية بمساحة خارجية ومرافق للأطفال.',
        maxGuests: 12,
        nightlyPrice: 55000,
        seasonalPrices: [
          SeasonalPrice(
            startDate: DateTime(2026, 7, 1),
            endDate: DateTime(2026, 9, 1),
            nightlyPrice: 70000,
            label: 'موسم الصيف',
          ),
        ],
      ),
    ];

typedef CreateChaletReservation = Future<void> Function(
  ChaletReservation reservation,
);
typedef SubmitPaymentReceipt = Future<void> Function(
  String reservationId,
  PaymentReceipt receipt,
);
typedef ReviewPaymentReceipt = Future<void> Function(
  String reservationId,
  String receiptId,
  bool approved,
);
typedef ReservationAction = Future<void> Function(String reservationId);
typedef RaiseReservationDispute = Future<void> Function(
  String reservationId,
  String reason,
);
typedef UpdateBookingPolicy = Future<void> Function(BookingPolicy policy);

class ChaletBookingPage extends StatefulWidget {
  const ChaletBookingPage({
    super.key,
    required this.listings,
    required this.reservations,
    required this.policy,
    required this.onCreateReservation,
    required this.onSubmitReceipt,
    required this.onReviewReceipt,
    required this.onConfirmProvider,
    required this.onCompleteStay,
    required this.onRaiseDispute,
    required this.onOpenSettlement,
    required this.onSettle,
    required this.onUpdatePolicy,
  });

  final List<ChaletListing> listings;
  final List<ChaletReservation> reservations;
  final BookingPolicy policy;
  final CreateChaletReservation onCreateReservation;
  final SubmitPaymentReceipt onSubmitReceipt;
  final ReviewPaymentReceipt onReviewReceipt;
  final ReservationAction onConfirmProvider;
  final ReservationAction onCompleteStay;
  final RaiseReservationDispute onRaiseDispute;
  final ReservationAction onOpenSettlement;
  final ReservationAction onSettle;
  final UpdateBookingPolicy onUpdatePolicy;

  @override
  State<ChaletBookingPage> createState() => _ChaletBookingPageState();
}

class _ChaletBookingPageState extends State<ChaletBookingPage> {
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('حجوزات الشاليهات',
                        style: TextStyle(
                            fontSize: 24, fontWeight: FontWeight.w700)),
                    SizedBox(height: 5),
                    Text('التوفر والتسعير الموسمي وطلبات الإقامة',
                        style: TextStyle(color: Colors.black54)),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _editPolicy,
                icon: const Icon(Icons.policy_outlined),
                label: const Text('سياسة الحجز'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _policyBanner(widget.policy),
          const SizedBox(height: 22),
          const Text('أماكن الإقامة',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (widget.listings.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text('لا توجد أماكن متاحة في هذا النموذج المحلي.'),
              ),
            )
          else
            ...widget.listings.map(_listingCard),
          const SizedBox(height: 22),
          Row(
            children: [
              const Expanded(
                child: Text('طلبات الإقامة',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              Text('${widget.reservations.length} طلب',
                  style: const TextStyle(color: Colors.black54)),
            ],
          ),
          const SizedBox(height: 10),
          if (widget.reservations.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                    'لم تُنشأ طلبات بعد. ابدأ باختيار مكان وتواريخ متاحة.'),
              ),
            )
          else
            ...widget.reservations.reversed.map(_reservationCard),
        ],
      );

  Widget _policyBanner(BookingPolicy policy) => Card(
        color: const Color(0xFFFFF8E8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.info_outline, color: Color(0xFF8A6423)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('نموذج تجريبي — لا توجد بوابة دفع فعلية',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'عربون ${policy.depositPercent}%، عمولة ${policy.commissionPercent}% بعد تنفيذ الإقامة، '
                'مهلة رد المزود ${policy.providerResponseHours} ساعة، '
                'ومهلة الاعتراض ${policy.disputeWindowHours} ساعة بعد التنفيذ. '
                'التحويل إلى الكريمي أو جيب يُسجل للمطابقة اليدوية فقط.',
                style: const TextStyle(height: 1.5),
              ),
              const SizedBox(height: 5),
              const Text(
                'سياسة الإلغاء والاسترداد قيد الاعتماد؛ لا تستخدم هذه النسخة لاستقبال أموال حقيقية.',
                style: TextStyle(
                    color: Color(0xFF8A6423),
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );

  Widget _listingCard(ChaletListing listing) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 540;
              final details = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(listing.name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  Text('${listing.city} · حتى ${listing.maxGuests} ضيوف',
                      style: const TextStyle(color: Colors.black54)),
                  const SizedBox(height: 7),
                  Text(listing.description),
                  const SizedBox(height: 7),
                  Text(
                    '${_moneyYER(listing.nightlyPrice)} لليلة · الأسعار الموسمية تظهر عند تحديد التواريخ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (listing.seasonalPrices.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        listing.seasonalPrices
                            .map((season) =>
                                '${season.label}: ${_moneyYER(season.nightlyPrice)} / ليلة')
                            .join(' · '),
                        style: const TextStyle(
                            color: Colors.black54, fontSize: 12),
                      ),
                    ),
                  if (listing.unavailableNights.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 5),
                      child: Text(
                        'توجد ليلة صيانة غير متاحة، وتُستبعد عند اختيار الفترة.',
                        style: TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ),
                ],
              );
              final bookButton = ElevatedButton.icon(
                onPressed: () => _startReservation(listing),
                icon: const Icon(Icons.calendar_month_outlined),
                label: const Text('اختر التواريخ'),
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    details,
                    const SizedBox(height: 12),
                    bookButton,
                  ],
                );
              }
              return Row(
                children: [
                  const Icon(Icons.cabin_outlined,
                      size: 38, color: Color(0xFF52685B)),
                  const SizedBox(width: 14),
                  Expanded(child: details),
                  const SizedBox(width: 12),
                  bookButton,
                ],
              );
            },
          ),
        ),
      );

  Widget _reservationCard(ChaletReservation reservation) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(reservation.chaletName,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  _stateBadge(
                      _reservationStatusLabel(reservation.status),
                      reservation.status == ChaletReservationStatus.cancelled
                          ? const Color(0xFFFCE9E7)
                          : const Color(0xFFEAF1EB)),
                  _stateBadge(
                    _paymentStatusLabel(reservation.paymentState),
                    reservation.paymentState == ReservationPaymentState.disputed
                        ? const Color(0xFFFCE9E7)
                        : const Color(0xFFF1F2EF),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${reservation.customerName} · ${reservation.phone} · ${reservation.guests} ضيوف',
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 4),
              Text(
                '${_dateLabel(reservation.checkIn)} إلى ${_dateLabel(reservation.checkOut)} '
                '· ${reservation.nights} ليلة',
                style: const TextStyle(color: Colors.black54),
              ),
              if (reservation.isProviderResponseOverdue(DateTime.now()))
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'انتهت مهلة رد المزود؛ يلزم تنبيه الإدارة والمتابعة يدوياً دون إلغاء الطلب تلقائياً.',
                    style: TextStyle(
                        color: Color(0xFF9A2E26),
                        fontWeight: FontWeight.w600,
                        fontSize: 12),
                  ),
                ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  Text('الإجمالي ${_moneyYER(reservation.totalAmount)}'),
                  Text('العربون ${_moneyYER(reservation.depositAmount)}'),
                  Text('المطابق ${_moneyYER(reservation.verifiedAmount)}'),
                  Text('المتبقي ${_moneyYER(reservation.outstandingAmount)}'),
                ],
              ),
              if (reservation.disputeReason != null) ...[
                const SizedBox(height: 8),
                Text('النزاع: ${reservation.disputeReason}',
                    style: const TextStyle(color: Color(0xFF9A2E26))),
              ],
              if (reservation.receipts.isNotEmpty) ...[
                const Divider(height: 22),
                for (final receipt in reservation.receipts)
                  _receiptLine(reservation, receipt),
              ],
              const Divider(height: 22),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _reservationActions(reservation),
              ),
            ],
          ),
        ),
      );

  Widget _receiptLine(
    ChaletReservation reservation,
    PaymentReceipt receipt,
  ) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            const Icon(Icons.receipt_long_outlined, size: 18),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                '${_walletLabel(receipt.wallet)} · ${_moneyYER(receipt.amount)} · '
                'مرجع ${receipt.reference} · ${_receiptStatusLabel(receipt.status)}'
                '${receipt.proofFileName == null ? '' : ' · ${receipt.proofFileName}'}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            if (receipt.proofBase64 != null)
              IconButton(
                tooltip: 'عرض صورة الإيصال',
                onPressed: () => _viewReceiptProof(receipt),
                icon: const Icon(Icons.image_outlined, size: 19),
              ),
            if (receipt.status == PaymentReceiptStatus.submitted) ...[
              TextButton(
                onPressed: () => _runAction(
                  () =>
                      widget.onReviewReceipt(reservation.id, receipt.id, true),
                  successMessage: 'تمت مطابقة الإيصال محلياً.',
                ),
                child: const Text('مطابقة'),
              ),
              TextButton(
                onPressed: () => _runAction(
                  () =>
                      widget.onReviewReceipt(reservation.id, receipt.id, false),
                  successMessage: 'تم رفض الإيصال محلياً.',
                ),
                child: const Text('رفض'),
              ),
            ],
          ],
        ),
      );

  List<Widget> _reservationActions(ChaletReservation reservation) {
    final actions = <Widget>[];
    if (reservation.status != ChaletReservationStatus.cancelled &&
        reservation.outstandingAmount > 0) {
      actions.add(OutlinedButton.icon(
        onPressed: () => _submitReceipt(reservation),
        icon: const Icon(Icons.upload_file_outlined),
        label: const Text('تسجيل تحويل يدوي'),
      ));
    }
    if (reservation.status == ChaletReservationStatus.awaitingProvider) {
      actions.add(OutlinedButton(
        onPressed: () => _runAction(
          () => widget.onConfirmProvider(reservation.id),
          successMessage: 'تم تحديث حالة المزود محلياً.',
        ),
        child: const Text('تأكيد توفر المزود'),
      ));
    }
    if (reservation.status == ChaletReservationStatus.confirmed) {
      actions.add(OutlinedButton(
        onPressed: () => _runAction(
          () => widget.onCompleteStay(reservation.id),
          successMessage: 'تم تسجيل انتهاء الإقامة.',
        ),
        child: const Text('تسجيل تنفيذ الإقامة'),
      ));
    }
    if (reservation.canOpenSettlement(DateTime.now())) {
      actions.add(ElevatedButton(
        onPressed: () => _runAction(
          () => widget.onOpenSettlement(reservation.id),
          successMessage: 'أصبح المبلغ جاهزاً للتسوية اليدوية.',
        ),
        child: const Text('فتح التسوية اليدوية'),
      ));
    }
    if (reservation.settlementStatus == SettlementStatus.ready) {
      actions.add(ElevatedButton(
        onPressed: () => _runAction(
          () => widget.onSettle(reservation.id),
          successMessage: 'تم تسجيل التسوية محلياً.',
        ),
        child: const Text('تسجيل التحويل للمزود'),
      ));
    }
    if (reservation.status == ChaletReservationStatus.completed &&
        reservation.disputeReason == null &&
        reservation.settlementStatus != SettlementStatus.settled &&
        reservation.completedAt != null &&
        DateTime.now().isBefore(reservation.completedAt!
            .add(Duration(hours: reservation.disputeWindowHours)))) {
      actions.add(TextButton(
        onPressed: () => _raiseDispute(reservation),
        child: const Text('فتح نزاع'),
      ));
    }
    return actions;
  }

  Future<void> _startReservation(ChaletListing listing) async {
    final request = await showDialog<ChaletReservationRequest>(
      context: context,
      builder: (context) => _ChaletReservationDialog(
        listing: listing,
        reservations: widget.reservations,
        policy: widget.policy,
      ),
    );
    if (request == null) return;
    await _runAction(
      () => widget.onCreateReservation(request.reservation),
      successMessage: 'تم إنشاء الطلب محلياً بانتظار رد المزود.',
    );
  }

  Future<void> _submitReceipt(ChaletReservation reservation) async {
    final receipt = await showDialog<PaymentReceipt>(
      context: context,
      builder: (context) => _ReceiptDialog(reservation: reservation),
    );
    if (receipt == null) return;
    await _runAction(
      () => widget.onSubmitReceipt(reservation.id, receipt),
      successMessage: 'سُجل مرجع التحويل بانتظار المطابقة اليدوية.',
    );
  }

  Future<void> _viewReceiptProof(PaymentReceipt receipt) async {
    try {
      final bytes = base64Decode(receipt.proofBase64!);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(receipt.proofFileName ?? 'صورة الإيصال'),
          content: SizedBox(
            width: 520,
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر قراءة صورة الإيصال: $error')),
        );
      }
    }
  }

  Future<void> _raiseDispute(ChaletReservation reservation) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _DisputeDialog(),
    );
    if (reason == null) return;
    await _runAction(
      () => widget.onRaiseDispute(reservation.id, reason),
      successMessage: 'تم إيقاف تسوية هذا الحجز لمراجعته.',
    );
  }

  Future<void> _editPolicy() async {
    final depositPercent = await showDialog<int>(
      context: context,
      builder: (context) => _DepositPolicyDialog(
        currentPercent: widget.policy.depositPercent,
      ),
    );
    if (depositPercent == null) return;
    await _runAction(
      () => widget
          .onUpdatePolicy(widget.policy.withDepositPercent(depositPercent)),
      successMessage: 'تم حفظ نسبة العربون للحجوزات الجديدة.',
    );
  }

  Future<void> _runAction(
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تنفيذ الإجراء: $error')),
        );
      }
    }
  }
}

class _ChaletReservationDialog extends StatefulWidget {
  const _ChaletReservationDialog({
    required this.listing,
    required this.reservations,
    required this.policy,
  });

  final ChaletListing listing;
  final List<ChaletReservation> reservations;
  final BookingPolicy policy;

  @override
  State<_ChaletReservationDialog> createState() =>
      _ChaletReservationDialogState();
}

class _ChaletReservationDialogState extends State<_ChaletReservationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  DateTimeRange? _stay;
  int _guests = 2;
  bool _acceptedNotice = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ReservationQuote? quote;
    if (_stay != null) {
      quote = widget.listing.quote(
        checkIn: _stay!.start,
        checkOut: _stay!.end,
        reservations: widget.reservations,
        policy: widget.policy,
      );
    }
    return AlertDialog(
      title: Text('طلب حجز ${widget.listing.name}'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: _chooseStay,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(_stay == null
                      ? 'اختيار الوصول والمغادرة'
                      : '${_dateLabel(_stay!.start)} إلى ${_dateLabel(_stay!.end)}'
                          ' · ${quote!.nights} ليلة'),
                ),
                if (quote != null) ...[
                  const SizedBox(height: 10),
                  _quoteSummary(quote),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'اسم العميل'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'أدخل اسم العميل'
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'رقم الهاتف'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'أدخل رقم الهاتف'
                      : null,
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  value: _guests,
                  decoration: const InputDecoration(labelText: 'عدد الضيوف'),
                  items: List.generate(
                    widget.listing.maxGuests,
                    (index) => DropdownMenuItem(
                      value: index + 1,
                      child: Text('${index + 1}'),
                    ),
                  ),
                  onChanged: (value) =>
                      setState(() => _guests = value ?? _guests),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _acceptedNotice,
                  onChanged: (value) =>
                      setState(() => _acceptedNotice = value ?? false),
                  title: const Text(
                    'أفهم أن الطلب ينتظر رد المزود وأن سياسة الإلغاء قيد الاعتماد.',
                    style: TextStyle(fontSize: 12),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const Text(
                  'هذا نموذج محلي تجريبي؛ لا يرسل دفعة ولا يحجز المكان فعلياً.',
                  style: TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _stay == null || !_acceptedNotice
              ? null
              : () {
                  if (!_formKey.currentState!.validate()) return;
                  final request = ChaletReservationRequest(
                    id: DateTime.now().microsecondsSinceEpoch.toString(),
                    listing: widget.listing,
                    customerName: _name.text,
                    phone: _phone.text,
                    checkIn: _stay!.start,
                    checkOut: _stay!.end,
                    guests: _guests,
                    policy: widget.policy,
                    existingReservations: widget.reservations,
                    createdAt: DateTime.now(),
                  );
                  Navigator.pop(context, request);
                },
          child: const Text('إرسال طلب الحجز'),
        ),
      ],
    );
  }

  Widget _quoteSummary(ReservationQuote quote) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F6F2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'الإجمالي ${_moneyYER(quote.totalAmount)} · ${quote.nights} ليلة'),
            Text(
              'العربون المطلوب ${_moneyYER(quote.depositAmount)} '
              '(${widget.policy.depositPercent}%)',
            ),
            Text(
              'عمولة المنصة عند إتمام الخدمة ${_moneyYER(quote.commissionAmount)} '
              '(${widget.policy.commissionPercent}%)',
            ),
          ],
        ),
      );

  Future<void> _chooseStay() async {
    final stay = await showDialog<DateTimeRange>(
      context: context,
      builder: (context) => _AvailableDateRangeDialog(
        listing: widget.listing,
        reservations: widget.reservations,
      ),
    );
    if (stay != null && mounted) setState(() => _stay = stay);
  }
}

class _AvailableDateRangeDialog extends StatefulWidget {
  const _AvailableDateRangeDialog({
    required this.listing,
    required this.reservations,
  });

  final ChaletListing listing;
  final List<ChaletReservation> reservations;

  @override
  State<_AvailableDateRangeDialog> createState() =>
      _AvailableDateRangeDialogState();
}

class _AvailableDateRangeDialogState extends State<_AvailableDateRangeDialog> {
  DateTime? _checkIn;
  bool _choosingCheckout = false;

  @override
  Widget build(BuildContext context) {
    final today = _dateOnly(DateTime.now());
    final lastDate = today.add(const Duration(days: 365));
    final firstDate =
        _choosingCheckout ? _checkIn!.add(const Duration(days: 1)) : today;
    DateTime? initialDate;
    for (var day = firstDate;
        !day.isAfter(lastDate);
        day = day.add(const Duration(days: 1))) {
      if (_isSelectable(day)) {
        initialDate = day;
        break;
      }
    }
    return AlertDialog(
      title: Text(_choosingCheckout ? 'اختر يوم المغادرة' : 'اختر يوم الوصول'),
      content: SizedBox(
        width: 360,
        height: 390,
        child: Column(
          children: [
            if (_checkIn != null)
              Row(
                children: [
                  Expanded(
                    child: Text('الوصول: ${_dateLabel(_checkIn!)}'),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _checkIn = null;
                      _choosingCheckout = false;
                    }),
                    child: const Text('تغييره'),
                  ),
                ],
              ),
            Expanded(
              child: initialDate == null
                  ? Center(
                      child: Text(
                        _choosingCheckout
                            ? 'لا توجد فترة مغادرة متاحة لهذا الوصول خلال 90 يوماً.'
                            : 'لا توجد ليالٍ متاحة في الفترة المعروضة.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : CalendarDatePicker(
                      key: ValueKey(
                          '${_choosingCheckout}_${_checkIn?.toIso8601String()}'),
                      initialDate: initialDate,
                      firstDate: firstDate,
                      lastDate: lastDate,
                      selectableDayPredicate: _isSelectable,
                      onDateChanged: (date) {
                        if (!_choosingCheckout) {
                          setState(() {
                            _checkIn = _dateOnly(date);
                            _choosingCheckout = true;
                          });
                          return;
                        }
                        final checkIn = _checkIn!;
                        Navigator.pop(
                          context,
                          DateTimeRange(
                            start: checkIn,
                            end: _dateOnly(date),
                          ),
                        );
                      },
                    ),
            ),
            const Text(
              'الأيام المحجوزة وليالي الصيانة غير قابلة للاختيار. المغادرة لا تُحتسب ليلة.',
              style: TextStyle(fontSize: 11, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
      ],
    );
  }

  bool _isSelectable(DateTime date) => _choosingCheckout
      ? widget.listing.isRangeAvailable(_checkIn!, date, widget.reservations)
      : widget.listing.isNightAvailable(date, widget.reservations);
}

class _ReceiptDialog extends StatefulWidget {
  const _ReceiptDialog({required this.reservation});

  final ChaletReservation reservation;

  @override
  State<_ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends State<_ReceiptDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  TransferWallet _wallet = TransferWallet.alKuraimi;
  Uint8List? _proofBytes;
  String? _proofFileName;
  String? _pickerError;
  bool _isPicking = false;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('تسجيل تحويل للمطابقة'),
        content: SizedBox(
          width: 380,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<TransferWallet>(
                  value: _wallet,
                  decoration: const InputDecoration(labelText: 'وسيلة التحويل'),
                  items: const [
                    DropdownMenuItem(
                        value: TransferWallet.alKuraimi,
                        child: Text('الكريمي')),
                    DropdownMenuItem(
                        value: TransferWallet.jeeb, child: Text('جيب')),
                  ],
                  onChanged: (value) =>
                      setState(() => _wallet = value ?? _wallet),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'المبلغ بالريال اليمني',
                    helperText:
                        'العربون المتبقي ${_moneyYER(widget.reservation.remainingDeposit)}'
                        ' · أقصى مبلغ ${_moneyYER(widget.reservation.availableForReceipt)}',
                  ),
                  validator: (value) {
                    final amount = int.tryParse((value ?? '').trim());
                    if (amount == null || amount <= 0) {
                      return 'أدخل مبلغاً صحيحاً';
                    }
                    if (amount > widget.reservation.availableForReceipt) {
                      return 'المبلغ يتجاوز غير المسجل';
                    }
                    if (amount < widget.reservation.remainingDeposit) {
                      return 'يجب استكمال العربون المتفق عليه أولاً';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _reference,
                  decoration:
                      const InputDecoration(labelText: 'رقم مرجع العملية'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'أدخل مرجع العملية'
                      : null,
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _isPicking ? null : _pickProof,
                  icon: const Icon(Icons.attach_file),
                  label: Text(_proofFileName ?? 'إرفاق صورة الإيصال'),
                ),
                if (_proofBytes != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Image.memory(
                      _proofBytes!,
                      height: 110,
                      fit: BoxFit.contain,
                    ),
                  ),
                if (_pickerError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _pickerError!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'تُحفظ الصورة على هذا الجهاز للمراجعة اليدوية فقط؛ لا يتم تنفيذ التحويل أو التحقق منه آلياً.',
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: _isPicking
                ? null
                : () {
                    if (!_formKey.currentState!.validate()) return;
                    if (_proofBytes == null) {
                      setState(
                          () => _pickerError = 'أرفق صورة الإيصال للمتابعة');
                      return;
                    }
                    Navigator.pop(
                      context,
                      PaymentReceipt(
                        id: DateTime.now().microsecondsSinceEpoch.toString(),
                        wallet: _wallet,
                        amount: int.parse(_amount.text.trim()),
                        reference: _reference.text.trim(),
                        submittedAt: DateTime.now(),
                        proofBase64: base64Encode(_proofBytes!),
                        proofFileName: _proofFileName,
                      ),
                    );
                  },
            child: const Text('إرسال للمراجعة'),
          ),
        ],
      );

  Future<void> _pickProof() async {
    setState(() {
      _isPicking = true;
      _pickerError = null;
    });
    try {
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (selection == null || !mounted) return;
      final file = selection.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        setState(() {
          _proofBytes = null;
          _proofFileName = null;
          _pickerError = 'تعذر قراءة الملف المختار';
        });
      } else if (bytes.lengthInBytes > 512 * 1024) {
        setState(() {
          _proofBytes = null;
          _proofFileName = null;
          _pickerError = 'حجم الصورة يتجاوز 512 كيلوبايت';
        });
      } else {
        setState(() {
          _proofBytes = bytes;
          _proofFileName = file.name;
          _pickerError = null;
        });
      }
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() =>
            _pickerError = 'تعذر فتح الملفات: ${error.message ?? error.code}');
      }
    } on MissingPluginException catch (error) {
      if (mounted) {
        setState(() => _pickerError = 'أداة اختيار الملف غير متاحة: $error');
      }
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }
}

class _DepositPolicyDialog extends StatefulWidget {
  const _DepositPolicyDialog({required this.currentPercent});

  final int currentPercent;

  @override
  State<_DepositPolicyDialog> createState() => _DepositPolicyDialogState();
}

class _DepositPolicyDialogState extends State<_DepositPolicyDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _percent;

  @override
  void initState() {
    super.initState();
    _percent = TextEditingController(text: '${widget.currentPercent}');
  }

  @override
  void dispose() {
    _percent.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('سياسة العربون'),
        content: SizedBox(
          width: 340,
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _percent,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'نسبة العربون للحجوزات الجديدة',
                    suffixText: '%',
                  ),
                  validator: (value) {
                    final amount = int.tryParse((value ?? '').trim());
                    if (amount == null || amount < 1 || amount > 100) {
                      return 'اختر نسبة من 1 إلى 100';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                const Text(
                  'تبقى العمولة 2% بعد التنفيذ، ورد المزود خلال 12 ساعة، ومهلة الاعتراض 24 ساعة. تتغير النسبة الجديدة دون تعديل الطلبات القائمة.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              if (!_formKey.currentState!.validate()) return;
              Navigator.pop(context, int.parse(_percent.text.trim()));
            },
            child: const Text('حفظ'),
          ),
        ],
      );
}

class _DisputeDialog extends StatefulWidget {
  const _DisputeDialog();

  @override
  State<_DisputeDialog> createState() => _DisputeDialogState();
}

class _DisputeDialogState extends State<_DisputeDialog> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('فتح نزاع على هذا الحجز'),
        content: Form(
          key: _formKey,
          child: TextFormField(
            controller: _reason,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'سبب الاعتراض'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'اكتب سبب الاعتراض'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              if (!_formKey.currentState!.validate()) return;
              Navigator.pop(context, _reason.text.trim());
            },
            child: const Text('إيقاف التسوية'),
          ),
        ],
      );
}

Widget _stateBadge(String label, Color background) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );

String _reservationStatusLabel(ChaletReservationStatus status) {
  switch (status) {
    case ChaletReservationStatus.awaitingProvider:
      return 'بانتظار رد المزود';
    case ChaletReservationStatus.confirmed:
      return 'مؤكد';
    case ChaletReservationStatus.completed:
      return 'تم التنفيذ';
    case ChaletReservationStatus.cancelled:
      return 'ملغي للمراجعة';
  }
}

String _paymentStatusLabel(ReservationPaymentState status) {
  switch (status) {
    case ReservationPaymentState.depositDue:
      return 'بانتظار العربون';
    case ReservationPaymentState.receiptReview:
      return 'الإيصال قيد المطابقة';
    case ReservationPaymentState.partiallyPaid:
      return 'دفعة محتجزة';
    case ReservationPaymentState.fundsHeld:
      return 'المبلغ محتجز';
    case ReservationPaymentState.disputed:
      return 'التسوية موقوفة بنزاع';
    case ReservationPaymentState.settlementReady:
      return 'جاهز للتسوية';
    case ReservationPaymentState.settled:
      return 'تمت التسوية';
  }
}

String _receiptStatusLabel(PaymentReceiptStatus status) {
  switch (status) {
    case PaymentReceiptStatus.submitted:
      return 'بانتظار المطابقة';
    case PaymentReceiptStatus.verified:
      return 'تمت المطابقة';
    case PaymentReceiptStatus.rejected:
      return 'مرفوض';
  }
}

String _walletLabel(TransferWallet wallet) {
  switch (wallet) {
    case TransferWallet.alKuraimi:
      return 'الكريمي';
    case TransferWallet.jeeb:
      return 'جيب';
  }
}

String _dateLabel(DateTime date) =>
    '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';

String _moneyYER(int amount) {
  final digits = amount.toString();
  final grouped = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) grouped.write(',');
    grouped.write(digits[index]);
  }
  return '${grouped.toString()} ر.ي';
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _sameDay(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

int _percentageCeiling(int amount, int percent) =>
    (amount * percent + 99) ~/ 100;
