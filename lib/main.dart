import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'admin_dashboard.dart';
import 'auth_flow.dart';
import 'event_services.dart';
import 'marketplace_experience.dart';
import 'storage.dart';
import 'supabase_config.dart';

const _muted = Color(0xFF7C817B);
const _canvas = Color(0xFFF7F7F3);
const _green = Color.fromARGB(255, 163, 18, 18);
const _gold = Color.fromARGB(255, 204, 40, 40);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (SupabaseConfig.isSupabaseConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.supabaseUrl,
      anonKey: SupabaseConfig.supabaseAnonKey,
      authFlowType: AuthFlowType.pkce,
      authCallbackUrlHostname: 'login-callback',
    );
  }
  runApp(const BookingManagerApp());
}

class BookingManagerApp extends StatelessWidget {
  const BookingManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'مناسباتي',
      debugShowCheckedModeBanner: false,
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      theme: ThemeData(
        useMaterial3: true,
        textTheme: GoogleFonts.cairoTextTheme(),
        scaffoldBackgroundColor: _canvas,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _green,
          primary: _green,
          secondary: _gold,
          background: _canvas,
          surface: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8F9F6),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: Color(0xFFE9EBE6)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: Color(0xFFE9EBE6)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: const BorderSide(color: _green, width: 1.4),
          ),
        ),
        cardTheme: CardTheme(
          color: Colors.white,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
      ),
      home: const HomeShell(),
    );
  }
}

enum BookingStatus { pending, confirmed, completed, cancelled }

class Booking {
  Booking({
    required this.id,
    required this.customer,
    required this.phone,
    required this.service,
    required this.provider,
    required this.date,
    required this.amount,
    this.paid = 0,
    this.depositAmount = 0,
    this.status = BookingStatus.pending,
    this.shiftType = 'evening',
    this.packageName = '',
    this.guestCount,
  });

  final String id;
  final String customer;
  final String phone;
  final String service;
  final String provider;
  final DateTime date;
  final double amount;
  double paid;
  final double depositAmount;
  BookingStatus status;
  final String shiftType;
  final String packageName;
  final int? guestCount;

  double get remaining => (amount - paid).clamp(0, double.infinity).toDouble();

  Map<String, Object?> toJson() => {
        'id': id,
        'customer': customer,
        'phone': phone,
        'service': service,
        'provider': provider,
        'date': date.toIso8601String(),
        'amount': amount,
        'paid': paid,
        'depositAmount': depositAmount,
        'status': status.name,
        'shiftType': shiftType,
        'packageName': packageName,
        'guestCount': guestCount,
      };

  factory Booking.fromJson(Map<String, dynamic> json) => Booking(
        id: json['id'] as String,
        customer: json['customer'] as String,
        phone: json['phone'] as String,
        service: json['service'] as String,
        provider: json['provider'] as String,
        date: DateTime.parse(json['date'] as String),
        amount: (json['amount'] as num).toDouble(),
        paid: (json['paid'] as num).toDouble(),
        depositAmount: (json['depositAmount'] as num?)?.toDouble() ?? 0,
        status: BookingStatus.values
            .firstWhere((status) => status.name == json['status']),
        shiftType: (json['shiftType'] as String?) ?? 'evening',
        packageName: (json['packageName'] as String?) ?? '',
        guestCount: json['guestCount'] as int?,
      );
}

class ProviderAccount {
  ProviderAccount({
    required this.id,
    required this.name,
    required this.category,
    required this.phone,
  });

  final String id;
  final String name;
  final String category;
  final String phone;

  Map<String, Object?> toJson() =>
      {'id': id, 'name': name, 'category': category, 'phone': phone};

  factory ProviderAccount.fromJson(Map<String, dynamic> json) =>
      ProviderAccount(
        id: json['id'] as String,
        name: json['name'] as String,
        category: json['category'] as String,
        phone: json['phone'] as String,
      );
}

class LedgerEntry {
  LedgerEntry({
    required this.id,
    required this.title,
    required this.amount,
    required this.date,
    required this.kind,
    this.note = '',
  });

  final String id;
  final String title;
  final double amount;
  final DateTime date;
  final String kind;
  final String note;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'amount': amount,
        'date': date.toIso8601String(),
        'kind': kind,
        'note': note,
      };

  factory LedgerEntry.fromJson(Map<String, dynamic> json) => LedgerEntry(
        id: json['id'] as String,
        title: json['title'] as String,
        amount: (json['amount'] as num).toDouble(),
        date: DateTime.parse(json['date'] as String),
        kind: json['kind'] as String,
        note: (json['note'] as String?) ?? '',
      );
}

class AppState extends ChangeNotifier {
  final List<Booking> bookings = [];
  final List<ProviderAccount> providers = [];
  final List<LedgerEntry> entries = [];

  Future<void> deleteAllData() async {
    await writeStoredData('');
    bookings.clear();
    providers.clear();
    entries.clear();
    notifyListeners();
  }

  Future<void> load() async {
    final stored = await readStoredData();
    if (stored == null || stored.isEmpty) return;
    final data = jsonDecode(stored) as Map<String, dynamic>;
    bookings
      ..clear()
      ..addAll(((data['bookings'] as List<dynamic>?) ?? const <dynamic>[])
          .map((item) => Booking.fromJson(item as Map<String, dynamic>)));
    providers
      ..clear()
      ..addAll(((data['providers'] as List<dynamic>?) ?? const <dynamic>[]).map(
          (item) => ProviderAccount.fromJson(item as Map<String, dynamic>)));
    entries
      ..clear()
      ..addAll(((data['entries'] as List<dynamic>?) ?? const <dynamic>[])
          .map((item) => LedgerEntry.fromJson(item as Map<String, dynamic>)));

    if (data.containsKey('chaletListings') ||
        data.containsKey('chaletReservations') ||
        data.containsKey('bookingPolicy')) {
      await _save();
    }
  }

  Future<void> _save() async {
    await writeStoredData(jsonEncode({
      'bookings': bookings.map((item) => item.toJson()).toList(),
      'providers': providers.map((item) => item.toJson()).toList(),
      'entries': entries.map((item) => item.toJson()).toList(),
    }));
    notifyListeners();
  }

  Future<void> addBooking(Booking booking) async {
    if (booking.id.isEmpty || bookings.any((item) => item.id == booking.id)) {
      throw StateError('رقم الحجز غير صالح أو مستخدم مسبقاً.');
    }
    if (booking.customer.trim().isEmpty ||
        booking.phone.trim().isEmpty ||
        booking.provider.trim().isEmpty ||
        booking.service.trim().isEmpty ||
        !booking.amount.isFinite ||
        booking.amount <= 0 ||
        !booking.paid.isFinite ||
        booking.paid < 0 ||
        booking.paid > booking.amount) {
      throw StateError('بيانات الحجز غير مكتملة.');
    }
    bookings.add(booking);
    try {
      await _save();
    } catch (_) {
      bookings.remove(booking);
      rethrow;
    }
  }

  Future<void> changeBookingStatus(
    Booking booking,
    BookingStatus status,
  ) async {
    final oldStatus = booking.status;
    booking.status = status;
    try {
      await _save();
    } catch (_) {
      booking.status = oldStatus;
      rethrow;
    }
  }

  Future<void> recordPayment(Booking booking, double amount) async {
    if (!amount.isFinite || amount <= 0 || amount > booking.remaining) {
      throw StateError('مبلغ الدفعة غير صالح أو يتجاوز المبلغ المتبقي.');
    }
    final oldPaid = booking.paid;
    final oldStatus = booking.status;
    booking.paid += amount;
    if (booking.remaining == 0) booking.status = BookingStatus.confirmed;
    try {
      await _save();
    } catch (_) {
      booking.paid = oldPaid;
      booking.status = oldStatus;
      rethrow;
    }
  }

  Future<void> addProvider(ProviderAccount provider) async {
    if (provider.name.trim().isEmpty || provider.phone.trim().isEmpty) {
      throw StateError('اسم المزود ورقم الهاتف مطلوبان.');
    }
    providers.add(provider);
    try {
      await _save();
    } catch (_) {
      providers.remove(provider);
      rethrow;
    }
  }

  Future<void> removeProvider(ProviderAccount provider) async {
    final index = providers.indexOf(provider);
    if (index < 0) return;
    providers.removeAt(index);
    try {
      await _save();
    } catch (_) {
      providers.insert(index, provider);
      rethrow;
    }
  }

  Future<void> addEntry(LedgerEntry entry) async {
    if (entry.title.trim().isEmpty ||
        !entry.amount.isFinite ||
        entry.amount <= 0) {
      throw StateError('بيانات الحركة المالية غير صالحة.');
    }
    entries.add(entry);
    try {
      await _save();
    } catch (_) {
      entries.remove(entry);
      rethrow;
    }
  }

  double get bookingValue => bookings
      .where((item) => item.status != BookingStatus.cancelled)
      .fold(0.0, (total, item) => total + item.amount);

  double get bookingPayments =>
      bookings.fold(0.0, (total, item) => total + item.paid);

  double get otherIncome => entries
      .where((entry) => entry.kind == 'income')
      .fold(0.0, (total, entry) => total + entry.amount);

  double get expenses => entries
      .where((entry) => entry.kind == 'expense')
      .fold(0.0, (total, entry) => total + entry.amount);

  double get totalIncome => bookingPayments + otherIncome;

  double get outstanding => bookings
      .where((item) => item.status != BookingStatus.cancelled)
      .fold(0.0, (total, item) => total + item.remaining);
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _state = AppState();
  late Future<void> _loaded;
  int _tab = 0;
  MarketplaceRole _role = MarketplaceRole.customer;

  @override
  void initState() {
    super.initState();
    _loaded = _state.load();
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
        future: _loaded,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _LoadError(error: snapshot.error!, onRetry: _retry);
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator(color: _green)));
          }
          return AnimatedBuilder(
            animation: _state,
            builder: (context, _) => _buildShell(context),
          );
        },
      );

  void _retry() {
    setState(() => _loaded = _state.load());
  }

  Widget _buildShell(BuildContext context) {
    if (_role == MarketplaceRole.auth) {
      return AuthFlow(
        onComplete: (userId, role, verificationStatus) {
          if (!mounted) return;
          if (role == 'provider') {
            if (verificationStatus == 'approved') {
              setState(() => _role = MarketplaceRole.provider);
              return;
            }
            setState(() => _role = MarketplaceRole.customer);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(verificationStatus == 'pending'
                  ? 'تم استلام طلب مقدم الخدمة، وهو بانتظار التحقق.'
                  : 'حالة حساب مقدم الخدمة: ${verificationStatus ?? 'غير معروفة'}'),
            ));
            return;
          }
          if (role == 'admin') {
            setState(() => _role = MarketplaceRole.admin);
            return;
          }
          setState(() => _role = MarketplaceRole.customer);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('تم تسجيل الدخول بنجاح.'),
          ));
        },
        onGuest: () => setState(() => _role = MarketplaceRole.customer),
      );
    }

    final marketplaceBookings = _state.bookings
        .map((booking) => MarketplaceBooking(
              id: booking.id,
              customerName: booking.customer,
              customerPhone: booking.phone,
              providerName: booking.provider,
              serviceName: booking.service,
              date: booking.date,
              amount: booking.amount,
              depositAmount: booking.depositAmount,
              status: booking.status.name,
              shiftType: EventShift.values.firstWhere(
                (shift) => shift.name == booking.shiftType,
                orElse: () => EventShift.evening,
              ),
              packageName: booking.packageName,
              guestCount: booking.guestCount,
            ))
        .toList();

    if (_role == MarketplaceRole.customer) {
      return CustomerExperience(
        state: _state,
        bookings: marketplaceBookings,
        onCreateBooking: (draft) async {
          if (SupabaseConfig.isSupabaseConfigured) {
            final user = Supabase.instance.client.auth.currentUser;
            if (user == null) {
              throw StateError('سجّل الدخول قبل إرسال طلب الحجز.');
            }
            await Supabase.instance.client.rpc('create_event_booking', params: {
              'target_provider_id': draft.providerId,
              'event_day': '${draft.date.year.toString().padLeft(4, '0')}-'
                  '${draft.date.month.toString().padLeft(2, '0')}-'
                  '${draft.date.day.toString().padLeft(2, '0')}',
              'selected_shift': draft.shiftType.name,
              'selected_package': draft.packageName,
              'number_of_guests': draft.guestCount,
            });
            return;
          }
          await _state.addBooking(
            Booking(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              customer: draft.customerName,
              phone: draft.phone,
              service: draft.serviceName,
              provider: draft.providerName,
              date: draft.date,
              amount: draft.amount,
              depositAmount: draft.depositAmount,
              shiftType: draft.shiftType.name,
              packageName: draft.packageName,
              guestCount: draft.guestCount,
            ),
          );
        },
        onRoleChanged: _selectRole,
      );
    }

    if (_role == MarketplaceRole.provider) {
      return ProviderExperience(
        state: _state,
        bookings: marketplaceBookings,
        onUpdateBooking: (id, confirmed) async {
          if (SupabaseConfig.isSupabaseConfigured) {
            await Supabase.instance.client.from('bookings').update(
                {'status': confirmed ? 'confirmed' : 'cancelled'}).eq('id', id);
            return;
          }
          final index =
              _state.bookings.indexWhere((booking) => booking.id == id);
          if (index < 0) throw StateError('طلب الحجز غير موجود');
          return _state.changeBookingStatus(
            _state.bookings[index],
            confirmed ? BookingStatus.confirmed : BookingStatus.cancelled,
          );
        },
        onRoleChanged: _selectRole,
      );
    }

    if (_role == MarketplaceRole.admin) {
      return AdminDashboard(
        onExit: () => setState(() {
          _role = MarketplaceRole.customer;
          _tab = 0;
        }),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 900;
        final pages = [
          DashboardPage(
              state: _state,
              onNavigate: (index) => setState(() => _tab = index)),
          BookingsPage(state: _state),
          AccountsPage(state: _state),
          ProvidersPage(state: _state),
        ];
        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                if (desktop)
                  _Sidebar(
                      selected: _tab,
                      onSelect: (index) {
                        setState(() => _tab = index);
                      }),
                Expanded(
                  child: Column(
                    children: [
                      _TopBar(
                        onAddBooking: () => _openBookingForm(context, _state),
                        onRoleChanged: _selectRole,
                      ),
                      Expanded(
                          child: IndexedStack(index: _tab, children: pages)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: desktop
              ? null
              : NavigationBar(
                  selectedIndex: _tab,
                  onDestinationSelected: (index) =>
                      setState(() => _tab = index),
                  destinations: const [
                    NavigationDestination(
                        icon: Icon(Icons.space_dashboard_outlined),
                        selectedIcon: Icon(Icons.space_dashboard),
                        label: 'الرئيسية'),
                    NavigationDestination(
                        icon: Icon(Icons.event_note_outlined),
                        selectedIcon: Icon(Icons.event_note),
                        label: 'الحجوزات'),
                    NavigationDestination(
                        icon: Icon(Icons.account_balance_wallet_outlined),
                        selectedIcon: Icon(Icons.account_balance_wallet),
                        label: 'الحسابات'),
                    NavigationDestination(
                        icon: Icon(Icons.storefront_outlined),
                        selectedIcon: Icon(Icons.storefront),
                        label: 'مزودو الخدمة'),
                  ],
                ),
        );
      },
    );
  }

  void _selectRole(MarketplaceRole role) {
    if (role == MarketplaceRole.admin) {
      _checkAdminAndEnter();
      return;
    }
    if (role == MarketplaceRole.provider &&
        SupabaseConfig.isSupabaseConfigured) {
      _checkProviderAndEnter();
      return;
    }
    setState(() {
      _role = role;
      _tab = 0;
    });
  }

  Future<void> _checkProviderAndEnter() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() => _role = MarketplaceRole.auth);
      return;
    }
    try {
      final status = await Supabase.instance.client
          .rpc('get_current_provider_status') as String?;
      if (!mounted) return;
      if (status != 'approved') {
        _showAccessMessage(
          status == 'pending'
              ? 'حساب مقدم الخدمة بانتظار التحقق.'
              : 'هذا الحساب غير مخول لواجهة مقدم الخدمة.',
        );
        return;
      }
      setState(() {
        _role = MarketplaceRole.provider;
        _tab = 0;
      });
    } catch (error) {
      _showAccessMessage('تعذر التحقق من حالة مقدم الخدمة: $error');
    }
  }

  Future<void> _checkAdminAndEnter() async {
    if (!SupabaseConfig.isSupabaseConfigured) {
      _showAccessMessage('لوحة الإدارة تتطلب حساب Supabase بصلاحية admin.');
      return;
    }
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() => _role = MarketplaceRole.auth);
      return;
    }
    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();
      if (!mounted) return;
      if (profile?['role'] != 'admin') {
        _showAccessMessage('هذا الحساب لا يملك صلاحية الإدارة.');
        return;
      }
      setState(() {
        _role = MarketplaceRole.admin;
        _tab = 0;
      });
    } catch (error) {
      _showAccessMessage('تعذر التحقق من صلاحيات الإدارة: $error');
    }
  }

  void _showAccessMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 44, color: _muted),
                const SizedBox(height: 16),
                const Text('تعذر فتح بيانات التطبيق'),
                const SizedBox(height: 8),
                Text('$error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _muted)),
                const SizedBox(height: 18),
                ElevatedButton(
                    onPressed: onRetry, child: const Text('إعادة المحاولة')),
              ],
            ),
          ),
        ),
      );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    const labels = [
      'لوحة التحكم',
      'الحجوزات',
      'الحسابات',
      'مزودو الخدمة',
    ];
    const icons = [
      Icons.space_dashboard_outlined,
      Icons.event_note_outlined,
      Icons.account_balance_wallet_outlined,
      Icons.storefront_outlined,
    ];
    return Container(
      width: 250,
      color: const Color(0xFF1F3028),
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                    color: _gold.withOpacity(.16),
                    borderRadius: BorderRadius.circular(13)),
                child: const Icon(Icons.auto_awesome, color: _gold),
              ),
              const SizedBox(width: 11),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('مناسباتي',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700)),
                  Text('إدارة أعمالك بسهولة',
                      style: TextStyle(color: Color(0xFFB9C4BB), fontSize: 11)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 38),
          const Padding(
            padding: EdgeInsets.only(right: 12, bottom: 10),
            child: Text('القائمة الرئيسية',
                style: TextStyle(color: Color(0xFF9EADA3), fontSize: 12)),
          ),
          for (var index = 0; index < labels.length; index++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _SideLink(
                icon: icons[index],
                label: labels[index],
                selected: selected == index,
                onTap: () => onSelect(index),
              ),
            ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(.07),
                borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: const [
                Icon(Icons.shield_outlined, color: Color(0xFFCFD8D1), size: 19),
                SizedBox(width: 9),
                Expanded(
                  child: Text('بياناتك محفوظة على هذا الجهاز',
                      style: TextStyle(color: Color(0xFFCFD8D1), fontSize: 11)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SideLink extends StatelessWidget {
  const _SideLink({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? const Color(0xFF3B5949) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
            child: Row(
              children: [
                Icon(icon,
                    color: selected ? const Color(0xFFE0C28F) : Colors.white70,
                    size: 20),
                const SizedBox(width: 12),
                Text(label,
                    style: TextStyle(
                        color:
                            selected ? Colors.white : const Color(0xFFD0D8D2),
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400)),
              ],
            ),
          ),
        ),
      );
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onAddBooking,
    required this.onRoleChanged,
  });

  final VoidCallback onAddBooking;
  final ValueChanged<MarketplaceRole> onRoleChanged;

  @override
  Widget build(BuildContext context) => Container(
        height: 76,
        padding: const EdgeInsets.symmetric(horizontal: 26),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFECEDE9))),
        ),
        child: Row(
          children: [
            const CircleAvatar(
                radius: 19,
                backgroundColor: Color(0xFFF1F2ED),
                child: Icon(Icons.person_outline, color: _green, size: 20)),
            const SizedBox(width: 10),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('مساحة الإدارة',
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text('مرحباً بك',
                    style: TextStyle(fontSize: 11, color: _muted)),
              ],
            ),
            const Spacer(),
            PopupMenuButton<MarketplaceRole>(
              tooltip: 'تبديل الواجهة',
              onSelected: onRoleChanged,
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: MarketplaceRole.customer,
                  child: Text('واجهة العميل'),
                ),
                PopupMenuItem(
                  value: MarketplaceRole.provider,
                  child: Text('واجهة مقدم الخدمة'),
                ),
              ],
              icon: const Icon(Icons.swap_horiz_rounded, color: _muted),
            ),
            ElevatedButton.icon(
              onPressed: onAddBooking,
              icon: const Icon(Icons.add, size: 19),
              label: const Text('حجز جديد'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );
}

class DashboardPage extends StatelessWidget {
  const DashboardPage(
      {super.key, required this.state, required this.onNavigate});

  final AppState state;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final upcoming = state.bookings
        .where((item) =>
            item.status != BookingStatus.cancelled &&
            item.date.isAfter(DateTime.now().subtract(const Duration(days: 1))))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return _PageScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PageHeading(
              title: 'لوحة التحكم',
              subtitle: 'نظرة سريعة على حجوزاتك وحساباتك'),
          _WelcomeCard(onNewBooking: () => _openBookingForm(context, state)),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 860
                  ? 4
                  : constraints.maxWidth > 520
                      ? 2
                      : 1;
              return GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: columns == 1
                    ? 3.2
                    : columns == 2
                        ? 2.1
                        : 1.7,
                children: [
                  _MetricCard(
                      title: 'إجمالي الحجوزات',
                      value: '${state.bookings.length}',
                      hint:
                          '${state.bookings.where((b) => b.status == BookingStatus.pending).length} بانتظار التأكيد',
                      icon: Icons.event_available_outlined,
                      color: _green),
                  _MetricCard(
                      title: 'إجمالي قيمة الحجوزات',
                      value: _money(state.bookingValue),
                      hint: 'قبل خصم المصروفات',
                      icon: Icons.receipt_long_outlined,
                      color: const Color(0xFFB1843B)),
                  _MetricCard(
                      title: 'المبالغ المستلمة',
                      value: _money(state.totalIncome),
                      hint: 'دفعات الحجوزات والإيرادات',
                      icon: Icons.payments_outlined,
                      color: const Color(0xFF487B68)),
                  _MetricCard(
                      title: 'المبالغ المتبقية',
                      value: _money(state.outstanding),
                      hint: 'على الحجوزات غير الملغاة',
                      icon: Icons.pending_actions_outlined,
                      color: const Color(0xFFBF7955)),
                ],
              );
            },
          ),
          const SizedBox(height: 27),
          Row(
            children: [
              const Expanded(
                  child: Text('الحجوزات القادمة',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700))),
              TextButton(
                  onPressed: () => onNavigate(1),
                  child: const Text('عرض الكل')),
            ],
          ),
          const SizedBox(height: 8),
          if (upcoming.isEmpty)
            _EmptyState(
              icon: Icons.calendar_month_outlined,
              title: 'لا توجد حجوزات قادمة',
              subtitle: 'أضف أول حجز لتبدأ بترتيب أعمالك',
              actionLabel: 'إضافة حجز',
              onAction: () => _openBookingForm(context, state),
            )
          else
            ...upcoming.take(4).map((booking) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _BookingTile(booking: booking, state: state),
                )),
        ],
      ),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.onNewBooking});

  final VoidCallback onNewBooking;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF315B48), Color(0xFF243E32)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 18,
          children: [
            SizedBox(
              width: 470,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('كل تفاصيل مناسبتك، في مكان واحد',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700)),
                  SizedBox(height: 8),
                  Text(
                      'تابع الحجوزات والمدفوعات ومواعيد عمل مزودي الخدمة بسهولة.',
                      style: TextStyle(color: Color(0xFFD6E0D9), height: 1.6)),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed: onNewBooking,
              icon: const Icon(Icons.add),
              label: const Text('إنشاء حجز'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE2C796),
                foregroundColor: const Color(0xFF29382F),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(
      {required this.title,
      required this.value,
      required this.hint,
      required this.icon,
      required this.color});

  final String title;
  final String value;
  final String hint;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: const Color(0xFFEAEBE7)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                      color: color.withOpacity(.1),
                      borderRadius: BorderRadius.circular(11)),
                  child: Icon(icon, size: 19, color: color),
                ),
                const Spacer(),
                const Icon(Icons.more_horiz, size: 20, color: _muted),
              ],
            ),
            Text(title, style: const TextStyle(color: _muted, fontSize: 12)),
            Text(value,
                style:
                    const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            Text(hint, style: const TextStyle(color: _muted, fontSize: 10)),
          ],
        ),
      );
}

class BookingsPage extends StatefulWidget {
  const BookingsPage({super.key, required this.state});

  final AppState state;

  @override
  State<BookingsPage> createState() => _BookingsPageState();
}

class _BookingsPageState extends State<BookingsPage> {
  String _query = '';
  BookingStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final bookings = widget.state.bookings.where((booking) {
      final searchable =
          '${booking.customer} ${booking.phone} ${booking.service} ${booking.provider}'
              .toLowerCase();
      return searchable.contains(_query.toLowerCase()) &&
          (_filter == null || booking.status == _filter);
    }).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return _PageScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PageHeading(
              title: 'الحجوزات',
              subtitle: 'إدارة الطلبات ومواعيد المناسبات والمدفوعات'),
          Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    hintText: 'ابحث بالاسم أو الخدمة أو رقم الهاتف',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                  onPressed: () => _openBookingForm(context, widget.state),
                  icon: const Icon(Icons.add),
                  label: const Text('حجز جديد')),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              _FilterChip(
                  label: 'الكل',
                  selected: _filter == null,
                  onTap: () => setState(() => _filter = null)),
              for (final status in BookingStatus.values)
                _FilterChip(
                    label: _statusLabel(status),
                    selected: _filter == status,
                    onTap: () => setState(() => _filter = status)),
            ],
          ),
          const SizedBox(height: 14),
          if (bookings.isEmpty)
            _EmptyState(
              icon: Icons.event_busy_outlined,
              title: _query.isEmpty ? 'لا توجد حجوزات بعد' : 'لا توجد نتائج',
              subtitle: _query.isEmpty
                  ? 'أنشئ حجزاً جديداً لتظهر تفاصيله هنا'
                  : 'جرّب البحث بكلمات أخرى',
              actionLabel: _query.isEmpty ? 'إضافة حجز' : null,
              onAction: _query.isEmpty
                  ? () => _openBookingForm(context, widget.state)
                  : null,
            )
          else
            ...bookings.map((booking) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _BookingTile(booking: booking, state: widget.state),
                )),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: const Color(0xFFE2EBE4),
        checkmarkColor: _green,
        side: BorderSide(
            color:
                selected ? const Color(0xFFC5D6C9) : const Color(0xFFE5E7E2)),
      );
}

class _BookingTile extends StatelessWidget {
  const _BookingTile({required this.booking, required this.state});

  final Booking booking;
  final AppState state;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 560;
              final details = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(booking.customer,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15)),
                      ),
                      const SizedBox(width: 9),
                      _StatusBadge(status: booking.status),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text('${booking.service} · ${booking.provider}',
                      style: const TextStyle(color: _muted, fontSize: 12)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 13,
                    runSpacing: 6,
                    children: [
                      _InlineIconText(
                          icon: Icons.calendar_today_outlined,
                          text: _formatDate(booking.date)),
                      _InlineIconText(
                          icon: Icons.phone_outlined, text: booking.phone),
                    ],
                  ),
                ],
              );
              final financial = Column(
                crossAxisAlignment:
                    compact ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                children: [
                  Text(_money(booking.amount),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 5),
                  Text('متبقي ${_money(booking.remaining)}',
                      style: const TextStyle(color: _muted, fontSize: 11)),
                ],
              );
              final actions = Wrap(
                spacing: 4,
                children: [
                  TextButton.icon(
                    onPressed: booking.status == BookingStatus.cancelled ||
                            booking.remaining <= 0
                        ? null
                        : () => _showPaymentDialog(context, state, booking),
                    icon: const Icon(Icons.add_card, size: 17),
                    label: Text(
                        booking.remaining <= 0 ? 'مكتمل السداد' : 'تسجيل دفعة'),
                  ),
                  PopupMenuButton<BookingStatus>(
                    tooltip: 'تغيير حالة الحجز',
                    onSelected: (status) async {
                      await _persist(context,
                          () => state.changeBookingStatus(booking, status));
                    },
                    itemBuilder: (_) => BookingStatus.values
                        .map((status) => PopupMenuItem(
                              value: status,
                              child: Text('تغيير إلى ${_statusLabel(status)}'),
                            ))
                        .toList(),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.more_horiz, color: _muted),
                    ),
                  ),
                ],
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    details,
                    const Divider(height: 24),
                    Row(
                      children: [
                        Expanded(child: financial),
                        actions,
                      ],
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(flex: 5, child: details),
                  const SizedBox(width: 18),
                  Expanded(flex: 2, child: financial),
                  const SizedBox(width: 8),
                  actions,
                ],
              );
            },
          ),
        ),
      );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final BookingStatus status;

  @override
  Widget build(BuildContext context) {
    late final Color color;
    switch (status) {
      case BookingStatus.pending:
        color = const Color(0xFFB1843B);
        break;
      case BookingStatus.confirmed:
        color = _green;
        break;
      case BookingStatus.completed:
        color = const Color(0xFF53728B);
        break;
      case BookingStatus.cancelled:
        color = const Color(0xFFB46155);
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
          color: color.withOpacity(.1),
          borderRadius: BorderRadius.circular(20)),
      child: Text(_statusLabel(status),
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}

class AccountsPage extends StatelessWidget {
  const AccountsPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final lines = <_AccountLine>[
      for (final booking in state.bookings)
        if (booking.paid > 0)
          _AccountLine(
            title: 'دفعة حجز · ${booking.customer}',
            subtitle: '${booking.service} · ${_formatDate(booking.date)}',
            amount: booking.paid,
            income: true,
            icon: Icons.event_available_outlined,
            date: booking.date,
          ),
      for (final entry in state.entries)
        _AccountLine(
          title: entry.title,
          subtitle:
              '${_formatDate(entry.date)}${entry.note.isEmpty ? '' : ' · ${entry.note}'}',
          amount: entry.amount,
          income: entry.kind == 'income',
          icon:
              entry.kind == 'income' ? Icons.trending_up : Icons.trending_down,
          date: entry.date,
        ),
    ]..sort((a, b) => b.date.compareTo(a.date));
    return _PageScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PageHeading(
            title: 'الحسابات',
            subtitle: 'ملخص الإيرادات والمصروفات وحركة الأموال',
            action: ElevatedButton.icon(
              onPressed: () => _openDialog(context, LedgerForm(state: state)),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('إضافة حركة'),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 1000
                  ? 4
                  : constraints.maxWidth > 650
                      ? 2
                      : 1;
              return GridView.count(
                crossAxisCount: columns,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 13,
                mainAxisSpacing: 13,
                childAspectRatio: columns == 1 ? 3.7 : 2.1,
                children: [
                  _MetricCard(
                      title: 'إجمالي الإيرادات',
                      value: _money(state.totalIncome),
                      hint: 'يشمل الحركات والعمولات التي تمت تسويتها',
                      icon: Icons.arrow_downward,
                      color: _green),
                  _MetricCard(
                      title: 'إجمالي المصروفات',
                      value: _money(state.expenses),
                      hint: 'الحركات المسجلة يدوياً',
                      icon: Icons.arrow_upward,
                      color: const Color(0xFFBF7955)),
                  _MetricCard(
                      title: 'صافي الحركة',
                      value: _money(state.totalIncome - state.expenses),
                      hint: 'الإيرادات ناقص المصروفات',
                      icon: Icons.account_balance_outlined,
                      color: const Color(0xFFB1843B)),
                  _MetricCard(
                      title: 'المبالغ المتبقية على الحجوزات',
                      value: '${_money(state.outstanding)} ر.ي',
                      hint: 'تُحتسب من الطلبات غير الملغاة',
                      icon: Icons.event_busy_outlined,
                      color: const Color(0xFF667C8A)),
                ],
              );
            },
          ),
          const SizedBox(height: 25),
          const Text('سجل الحركات',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (lines.isEmpty)
            const _EmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'لا توجد حركات مالية',
                subtitle: 'سجّل إيراداً أو مصروفاً لمتابعة حساباتك')
          else
            Card(
              child: Column(
                children: [
                  for (var index = 0; index < lines.length; index++) ...[
                    _LedgerTile(line: lines[index]),
                    if (index != lines.length - 1)
                      const Divider(height: 1, indent: 18, endIndent: 18),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AccountLine {
  _AccountLine({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.income,
    required this.icon,
    required this.date,
  });

  final String title;
  final String subtitle;
  final double amount;
  final bool income;
  final IconData icon;
  final DateTime date;
}

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({required this.line});

  final _AccountLine line;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: CircleAvatar(
          backgroundColor:
              (line.income ? _green : const Color(0xFFBF7955)).withOpacity(.1),
          child: Icon(line.icon,
              size: 19, color: line.income ? _green : const Color(0xFFBF7955)),
        ),
        title: Text(line.title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Text(line.subtitle,
            style: const TextStyle(color: _muted, fontSize: 11)),
        trailing: Text(
          '${line.income ? '+' : '−'} ${_money(line.amount)}',
          style: TextStyle(
              color: line.income ? _green : const Color(0xFFBF7955),
              fontWeight: FontWeight.w700,
              fontSize: 13),
        ),
      );
}

class ProvidersPage extends StatelessWidget {
  const ProvidersPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) => _PageScroll(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PageHeading(
              title: 'مزودو الخدمة',
              subtitle: 'إدارة بيانات الفنانين والقاعات وبقية الخدمات',
              action: ElevatedButton.icon(
                  onPressed: () =>
                      _openDialog(context, ProviderForm(state: state)),
                  icon: const Icon(Icons.person_add_alt_1, size: 18),
                  label: const Text('إضافة مزود')),
            ),
            if (state.providers.isEmpty)
              _EmptyState(
                icon: Icons.storefront_outlined,
                title: 'قائمة مزودي الخدمة فارغة',
                subtitle: 'أضف مزودي الخدمة لتسهيل ربطهم بالحجوزات',
                actionLabel: 'إضافة مزود',
                onAction: () =>
                    _openDialog(context, ProviderForm(state: state)),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth > 850
                      ? 3
                      : constraints.maxWidth > 550
                          ? 2
                          : 1;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: state.providers.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: columns == 1 ? 3.4 : 1.8,
                    ),
                    itemBuilder: (context, index) {
                      final provider = state.providers[index];
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: const Color(0xFFE9EFE9),
                                    child: Text(provider.name.isEmpty
                                        ? '؟'
                                        : provider.name[0]),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                      child: Text(provider.name,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700))),
                                  IconButton(
                                    tooltip: 'حذف المزود',
                                    onPressed: () => _confirmRemove(
                                        context, state, provider),
                                    icon: const Icon(Icons.delete_outline,
                                        color: _muted, size: 20),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Text(provider.category,
                                  style: const TextStyle(
                                      color: _green,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12)),
                              const SizedBox(height: 6),
                              _InlineIconText(
                                  icon: Icons.phone_outlined,
                                  text: provider.phone),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
          ],
        ),
      );
}

class _PageScroll extends StatelessWidget {
  const _PageScroll({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(26, 22, 26, 30),
        child: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180), child: child),
        ),
      );
}

class _PageHeading extends StatelessWidget {
  const _PageHeading(
      {required this.title, required this.subtitle, this.action});

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 24, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  Text(subtitle,
                      style: const TextStyle(color: _muted, fontSize: 13)),
                ],
              ),
            ),
            if (action != null) action!,
          ],
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 35),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xFFEAEBE7)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Icon(icon, size: 34, color: const Color(0xFF91A097)),
            const SizedBox(height: 12),
            Text(title,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, fontSize: 12)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 15),
              OutlinedButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(actionLabel!)),
            ],
          ],
        ),
      );
}

class _InlineIconText extends StatelessWidget {
  const _InlineIconText({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _muted),
          const SizedBox(width: 5),
          Text(text,
              style: const TextStyle(fontSize: 11, color: _muted),
              overflow: TextOverflow.ellipsis),
        ],
      );
}

class BookingForm extends StatefulWidget {
  const BookingForm({super.key, required this.state});

  final AppState state;

  @override
  State<BookingForm> createState() => _BookingFormState();
}

class _BookingFormState extends State<BookingForm> {
  final _formKey = GlobalKey<FormState>();
  final _customer = TextEditingController();
  final _phone = TextEditingController();
  final _service = TextEditingController();
  final _provider = TextEditingController();
  final _amount = TextEditingController();
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  bool _saving = false;

  @override
  void dispose() {
    _customer.dispose();
    _phone.dispose();
    _service.dispose();
    _provider.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _FormDialog(
        formKey: _formKey,
        title: 'إنشاء حجز',
        subtitle: 'أدخل بيانات العميل والخدمة وموعد المناسبة',
        saving: _saving,
        onSave: _save,
        children: [
          _FormField(
              controller: _customer,
              label: 'اسم العميل',
              icon: Icons.person_outline,
              validator: _required),
          _FormField(
              controller: _phone,
              label: 'رقم الهاتف',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              validator: _required),
          _FormField(
              controller: _service,
              label: 'نوع الخدمة (قاعة، تصوير...)',
              icon: Icons.category_outlined,
              validator: _required),
          _FormField(
              controller: _provider,
              label: 'اسم مزود الخدمة',
              icon: Icons.storefront_outlined,
              validator: _required),
          _FormField(
              controller: _amount,
              label: 'قيمة الحجز',
              icon: Icons.payments_outlined,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: _amountValidator),
          OutlinedButton.icon(
            onPressed: _chooseDate,
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text('موعد المناسبة: ${_formatDate(_date)}'),
            style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                alignment: Alignment.centerRight),
          ),
        ],
      );

  Future<void> _chooseDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
    );
    if (selected != null) setState(() => _date = selected);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final booking = Booking(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      customer: _customer.text.trim(),
      phone: _phone.text.trim(),
      service: _service.text.trim(),
      provider: _provider.text.trim(),
      date: _date,
      amount: double.parse(_amount.text.trim()),
    );
    final saved =
        await _persist(context, () => widget.state.addBooking(booking));
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() => _saving = false);
    }
  }
}

class ProviderForm extends StatefulWidget {
  const ProviderForm({super.key, required this.state});

  final AppState state;

  @override
  State<ProviderForm> createState() => _ProviderFormState();
}

class _ProviderFormState extends State<ProviderForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _category = TextEditingController();
  final _phone = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _category.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _FormDialog(
        formKey: _formKey,
        title: 'إضافة مزود خدمة',
        subtitle: 'احفظ بيانات التواصل لتسهيل إدارة الحجوزات',
        saving: _saving,
        onSave: _save,
        children: [
          _FormField(
              controller: _name,
              label: 'اسم المزود أو المنشأة',
              icon: Icons.person_outline,
              validator: _required),
          _FormField(
              controller: _category,
              label: 'نوع الخدمة',
              icon: Icons.category_outlined,
              validator: _required),
          _FormField(
              controller: _phone,
              label: 'رقم الهاتف',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              validator: _required),
        ],
      );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final provider = ProviderAccount(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: _name.text.trim(),
      category: _category.text.trim(),
      phone: _phone.text.trim(),
    );
    final saved =
        await _persist(context, () => widget.state.addProvider(provider));
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() => _saving = false);
    }
  }
}

class LedgerForm extends StatefulWidget {
  const LedgerForm({super.key, required this.state});

  final AppState state;

  @override
  State<LedgerForm> createState() => _LedgerFormState();
}

class _LedgerFormState extends State<LedgerForm> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _kind = 'expense';
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _FormDialog(
        formKey: _formKey,
        title: 'إضافة حركة مالية',
        subtitle: 'سجّل إيراداً أو مصروفاً في سجل الحسابات',
        saving: _saving,
        onSave: _save,
        children: [
          DropdownButtonFormField<String>(
            value: _kind,
            decoration: const InputDecoration(
                labelText: 'نوع الحركة', prefixIcon: Icon(Icons.swap_vert)),
            items: const [
              DropdownMenuItem(value: 'income', child: Text('إيراد')),
              DropdownMenuItem(value: 'expense', child: Text('مصروف')),
            ],
            onChanged: (value) => setState(() => _kind = value ?? 'expense'),
          ),
          _FormField(
              controller: _title,
              label: 'وصف الحركة',
              icon: Icons.edit_note,
              validator: _required),
          _FormField(
              controller: _amount,
              label: 'المبلغ',
              icon: Icons.payments_outlined,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              validator: _amountValidator),
          _FormField(
              controller: _note,
              label: 'ملاحظة (اختياري)',
              icon: Icons.notes_outlined),
        ],
      );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final entry = LedgerEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: _title.text.trim(),
      amount: double.parse(_amount.text.trim()),
      date: DateTime.now(),
      kind: _kind,
      note: _note.text.trim(),
    );
    final saved = await _persist(context, () => widget.state.addEntry(entry));
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
    } else {
      setState(() => _saving = false);
    }
  }
}

class _FormDialog extends StatelessWidget {
  const _FormDialog({
    required this.formKey,
    required this.title,
    required this.subtitle,
    required this.children,
    required this.onSave,
    required this.saving,
  });

  final GlobalKey<FormState> formKey;
  final String title;
  final String subtitle;
  final List<Widget> children;
  final Future<void> Function() onSave;
  final bool saving;

  @override
  Widget build(BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.all(18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 700),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  Text(subtitle,
                      style: const TextStyle(color: _muted, fontSize: 12)),
                  const SizedBox(height: 18),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          for (var index = 0;
                              index < children.length;
                              index++) ...[
                            children[index],
                            if (index != children.length - 1)
                              const SizedBox(height: 11),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed:
                              saving ? null : () => Navigator.pop(context),
                          child: const Text('إلغاء'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: saving ? null : onSave,
                          child: saving
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Text('حفظ'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _FormField extends StatelessWidget {
  const _FormField({
    required this.controller,
    required this.label,
    required this.icon,
    this.validator,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        decoration:
            InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 19)),
      );
}

Future<void> _showPaymentDialog(
    BuildContext context, AppState state, Booking booking) async {
  final amount = TextEditingController();
  final formKey = GlobalKey<FormState>();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('تسجيل دفعة'),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'المبلغ المتبقي ${_money(booking.remaining)}',
            prefixIcon: const Icon(Icons.payments_outlined),
          ),
          validator: (value) {
            final parsed = double.tryParse((value ?? '').trim());
            if (parsed == null || !parsed.isFinite || parsed <= 0) {
              return 'أدخل مبلغاً صحيحاً';
            }
            if (parsed > booking.remaining) return 'المبلغ أكبر من المتبقي';
            return null;
          },
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء')),
        ElevatedButton(
          onPressed: () async {
            if (!formKey.currentState!.validate()) return;
            final navigator = Navigator.of(dialogContext);
            final saved = await _persist(
              dialogContext,
              () => state.recordPayment(
                  booking, double.parse(amount.text.trim())),
            );
            if (saved) navigator.pop();
          },
          child: const Text('حفظ الدفعة'),
        ),
      ],
    ),
  );
  amount.dispose();
}

Future<void> _openBookingForm(BuildContext context, AppState state) async {
  await _openDialog(context, BookingForm(state: state));
}

Future<void> _openDialog(BuildContext context, Widget child) async {
  await showDialog<void>(context: context, builder: (_) => child);
}

Future<bool> _persist(
    BuildContext context, Future<void> Function() action) async {
  try {
    await action();
    return true;
  } catch (error) {
    _showMessage(context, 'تعذر حفظ البيانات: $error');
    return false;
  }
}

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<void> _confirmRemove(
    BuildContext context, AppState state, ProviderAccount provider) async {
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('حذف مزود الخدمة؟'),
      content: Text('سيتم حذف ${provider.name} من قائمة المزودين.'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء')),
        ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('حذف')),
      ],
    ),
  );
  if (confirmed == true) {
    try {
      await state.removeProvider(provider);
    } catch (error) {
      messenger
          .showSnackBar(SnackBar(content: Text('تعذر حفظ البيانات: $error')));
    }
  }
}

String? _required(String? value) =>
    (value == null || value.trim().isEmpty) ? 'هذا الحقل مطلوب' : null;

String? _amountValidator(String? value) {
  final amount = double.tryParse((value ?? '').trim());
  if (amount == null || !amount.isFinite || amount <= 0) {
    return 'أدخل مبلغاً أكبر من صفر';
  }
  return null;
}

String _statusLabel(BookingStatus status) {
  switch (status) {
    case BookingStatus.pending:
      return 'بانتظار التأكيد';
    case BookingStatus.confirmed:
      return 'مؤكد';
    case BookingStatus.completed:
      return 'مكتمل';
    case BookingStatus.cancelled:
      return 'ملغي';
  }
}

String _formatDate(DateTime date) =>
    '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';

String _money(double amount) {
  final rounded = amount == amount.roundToDouble()
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2);
  final parts = rounded.split('.');
  final whole = parts.first;
  final buffer = StringBuffer();
  for (var index = 0; index < whole.length; index++) {
    if (index > 0 && (whole.length - index) % 3 == 0) buffer.write(',');
    buffer.write(whole[index]);
  }
  return parts.length == 1
      ? buffer.toString()
      : '${buffer.toString()}.${parts[1]}';
}

// ---------------------------------------------------------------------------
// Identity & Theming (Luxury Dark Theme - Unified)
const String kFontFamily = 'Cairo';
const Color kMarketplaceBg = Color(0xFF141417);
const Color kMarketplaceSurface = Color(0xFF1E1E22);
const Color kMarketplaceSurfaceRaised = Color(0xFF25252A);
const Color kAccent = Color(0xFFED143B);
