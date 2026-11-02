import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:booking_manager/chalet_booking.dart';
import 'package:booking_manager/main.dart';

ChaletListing _listing() => ChaletListing(
      id: 'chalet-1',
      name: 'مكان تجريبي',
      city: 'صنعاء',
      description: 'وصف',
      maxGuests: 8,
      nightlyPrice: 1000,
      seasonalPrices: [
        SeasonalPrice(
          startDate: DateTime(2026, 7, 1),
          endDate: DateTime(2026, 7, 3),
          nightlyPrice: 2000,
          label: 'الصيف',
        ),
      ],
    );

ChaletReservation _reservation({
  required ChaletListing listing,
  required DateTime checkIn,
  required DateTime checkOut,
  ChaletReservationStatus status = ChaletReservationStatus.confirmed,
  List<PaymentReceipt> receipts = const [],
  DateTime? completedAt,
  String? disputeReason,
}) {
  const policy = BookingPolicy();
  final quote = listing.quote(
    checkIn: checkIn,
    checkOut: checkOut,
    reservations: const [],
    policy: policy,
  );
  return ChaletReservation(
    id: 'reservation-1',
    chaletId: listing.id,
    chaletName: listing.name,
    customerName: 'عميل',
    phone: '777000000',
    checkIn: checkIn,
    checkOut: checkOut,
    guests: 2,
    totalAmount: quote.totalAmount,
    depositAmount: quote.depositAmount,
    commissionAmount: quote.commissionAmount,
    depositPercent: policy.depositPercent,
    commissionPercent: policy.commissionPercent,
    responseHours: policy.providerResponseHours,
    disputeWindowHours: policy.disputeWindowHours,
    createdAt: DateTime(2026, 6, 1),
    status: status,
    receipts: receipts,
    completedAt: completedAt,
    disputeReason: disputeReason,
  );
}

void main() {
  test('quotes each occupied night using its seasonal rate', () {
    final listing = _listing();
    final quote = listing.quote(
      checkIn: DateTime(2026, 6, 30),
      checkOut: DateTime(2026, 7, 3),
      reservations: const [],
      policy: const BookingPolicy(),
    );

    expect(quote.nights, 3);
    expect(quote.totalAmount, 5000);
    expect(quote.depositAmount, 500);
    expect(quote.commissionAmount, 100);
    expect(quote.providerPayout, 4900);
  });

  test('availability uses checkout-exclusive ranges and ignores cancellations',
      () {
    final listing = _listing();
    final existing = _reservation(
      listing: listing,
      checkIn: DateTime(2026, 7, 5),
      checkOut: DateTime(2026, 7, 7),
    );

    expect(
      listing.isRangeAvailable(
        DateTime(2026, 7, 4),
        DateTime(2026, 7, 5),
        [existing],
      ),
      isTrue,
    );
    expect(
      listing.isRangeAvailable(
        DateTime(2026, 7, 6),
        DateTime(2026, 7, 8),
        [existing],
      ),
      isFalse,
    );
    expect(
      listing.isRangeAvailable(
        DateTime(2026, 7, 5),
        DateTime(2026, 7, 7),
        [
          existing.copyWith(status: ChaletReservationStatus.cancelled),
        ],
      ),
      isTrue,
    );
  });

  test('receipt and reservation states survive JSON round-trip', () {
    final listing = _listing();
    final reservation = _reservation(
      listing: listing,
      checkIn: DateTime(2026, 7, 5),
      checkOut: DateTime(2026, 7, 7),
      status: ChaletReservationStatus.completed,
      receipts: [
        PaymentReceipt(
          id: 'receipt-1',
          wallet: TransferWallet.jeeb,
          amount: 1000,
          reference: 'TX-001',
          submittedAt: DateTime(2026, 7, 1),
          proofBase64: 'AA==',
          proofFileName: 'receipt.png',
          status: PaymentReceiptStatus.verified,
        ),
      ],
      completedAt: DateTime(2026, 7, 7),
    );

    final restored = ChaletReservation.fromJson(reservation.toJson());
    expect(restored.status, ChaletReservationStatus.completed);
    expect(restored.paymentState, ReservationPaymentState.partiallyPaid);
    expect(restored.verifiedAmount, 1000);
    expect(restored.receipts.single.wallet, TransferWallet.jeeb);
    expect(restored.receipts.single.proofFileName, 'receipt.png');
    expect(restored.receipts.single.proofBase64, 'AA==');
    expect(restored.canOpenSettlement(DateTime(2026, 7, 8)), isFalse);
  });

  test('settlement waits for full payment and the 24-hour dispute window', () {
    final listing = _listing();
    final fullPayment = PaymentReceipt(
      id: 'receipt-full',
      wallet: TransferWallet.alKuraimi,
      amount: 2000,
      reference: 'TX-002',
      submittedAt: DateTime(2026, 7, 1),
      status: PaymentReceiptStatus.verified,
    );
    final reservation = _reservation(
      listing: listing,
      checkIn: DateTime(2026, 7, 5),
      checkOut: DateTime(2026, 7, 7),
      status: ChaletReservationStatus.completed,
      receipts: [fullPayment],
      completedAt: DateTime(2026, 7, 7),
    );

    expect(
        reservation.canOpenSettlement(DateTime(2026, 7, 7, 23, 59)), isFalse);
    expect(reservation.canOpenSettlement(DateTime(2026, 7, 8)), isTrue);
    expect(
      reservation
          .copyWith(disputeReason: 'اعتراض تجريبي')
          .canOpenSettlement(DateTime(2026, 7, 9)),
      isFalse,
    );
  });

  test('deposit changes affect new policy but not stored reservation terms',
      () {
    final previous = _reservation(
      listing: _listing(),
      checkIn: DateTime(2026, 6, 30),
      checkOut: DateTime(2026, 7, 3),
    );
    final changed = const BookingPolicy().withDepositPercent(15);

    expect(changed.depositPercent, 15);
    expect(previous.depositPercent, 10);
    expect(previous.depositAmount, 500);
  });

  test('provider response deadline warns without cancelling automatically', () {
    final reservation = _reservation(
      listing: _listing(),
      checkIn: DateTime(2026, 7, 5),
      checkOut: DateTime(2026, 7, 7),
      status: ChaletReservationStatus.awaitingProvider,
    );

    expect(
      reservation.isProviderResponseOverdue(DateTime(2026, 6, 1, 12)),
      isFalse,
    );
    expect(
      reservation.isProviderResponseOverdue(DateTime(2026, 6, 1, 12, 0, 1)),
      isTrue,
    );
    expect(reservation.status, ChaletReservationStatus.awaitingProvider);
  });

  test('account totals include chalet reservations and verified receipts only',
      () {
    final listing = _listing();
    final reservation = _reservation(
      listing: listing,
      checkIn: DateTime(2026, 7, 5),
      checkOut: DateTime(2026, 7, 7),
    );
    final state = AppState()..chaletReservations.add(reservation);

    expect(state.bookingValue, 2000);
    expect(state.bookingPayments, 0);
    expect(state.outstanding, 2000);

    final submitted = PaymentReceipt(
      id: 'receipt-pending',
      wallet: TransferWallet.jeeb,
      amount: reservation.depositAmount,
      reference: 'TX-PENDING',
      submittedAt: DateTime(2026, 6, 1),
    );
    state.chaletReservations[0] = reservation.copyWith(receipts: [submitted]);
    expect(state.bookingPayments, 0);

    final verified = submitted.copyWith(status: PaymentReceiptStatus.verified);
    state.chaletReservations[0] = reservation.copyWith(receipts: [verified]);
    expect(state.bookingPayments, 0);
    expect(state.heldChaletFunds, reservation.depositAmount);
    expect(state.totalIncome, 0);
    expect(
      state.outstanding,
      (reservation.totalAmount - reservation.depositAmount).toDouble(),
    );

    state.chaletReservations[0] = reservation.copyWith(
      receipts: [
        PaymentReceipt(
          id: 'receipt-full',
          wallet: TransferWallet.jeeb,
          amount: reservation.totalAmount,
          reference: 'TX-FULL',
          submittedAt: DateTime(2026, 6, 1),
          status: PaymentReceiptStatus.verified,
        ),
      ],
      status: ChaletReservationStatus.completed,
      completedAt: DateTime(2026, 7, 7),
      settlementStatus: SettlementStatus.settled,
      settledAt: DateTime(2026, 7, 8),
    );
    expect(state.heldChaletFunds, 0);
    expect(state.totalIncome, reservation.commissionAmount.toDouble());
  });

  testWidgets('chalet page shows sample listings and the manual-payment policy',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: ChaletBookingPage(
              listings: sampleChaletListings(),
              reservations: const [],
              policy: const BookingPolicy(),
              onCreateReservation: (_) async {},
              onSubmitReceipt: (_, __) async {},
              onReviewReceipt: (_, __, ___) async {},
              onConfirmProvider: (_) async {},
              onCompleteStay: (_) async {},
              onRaiseDispute: (_, __) async {},
              onOpenSettlement: (_) async {},
              onSettle: (_) async {},
              onUpdatePolicy: (_) async {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('حجوزات الشاليهات'), findsOneWidget);
    expect(find.text('استراحة السكون'), findsOneWidget);
    expect(find.text('نموذج تجريبي — لا توجد بوابة دفع فعلية'), findsOneWidget);
  });
}
