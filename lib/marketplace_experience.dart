import 'package:flutter/material.dart';

enum MarketplaceRole { customer, provider, admin }

class MarketplaceBooking {
  const MarketplaceBooking({
    required this.id,
    required this.customerName,
    required this.providerName,
    required this.serviceName,
    required this.date,
    required this.amount,
    required this.status,
  });

  final String id;
  final String customerName;
  final String providerName;
  final String serviceName;
  final DateTime date;
  final double amount;
  final String status;
}

class MarketplaceBookingDraft {
  const MarketplaceBookingDraft({
    required this.customerName,
    required this.phone,
    required this.providerName,
    required this.serviceName,
    required this.date,
    required this.amount,
  });

  final String customerName;
  final String phone;
  final String providerName;
  final String serviceName;
  final DateTime date;
  final double amount;
}

typedef CreateMarketplaceBooking = Future<void> Function(
  MarketplaceBookingDraft draft,
);
typedef UpdateMarketplaceBooking = Future<void> Function(
  String id,
  bool confirmed,
);

const _background = Color(0xFF141417);
const _surface = Color(0xFF1E1E22);
const _surfaceRaised = Color(0xFF25252A);
const _accent = Color(0xFFED143B);
const _muted = Color(0xFF96969D);
const _white = Color(0xFFF8F8FA);

class CustomerExperience extends StatefulWidget {
  const CustomerExperience({
    super.key,
    required this.bookings,
    required this.onCreateBooking,
    required this.onRoleChanged,
  });

  final List<MarketplaceBooking> bookings;
  final CreateMarketplaceBooking onCreateBooking;
  final ValueChanged<MarketplaceRole> onRoleChanged;

  @override
  State<CustomerExperience> createState() => _CustomerExperienceState();
}

class _CustomerExperienceState extends State<CustomerExperience> {
  int _tab = 0;
  String _category = 'الكل';
  String _sort = 'الأعلى تقييماً';
  String _city = 'كل المدن';
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final pages = [
      _home(),
      _customerBookings(),
      const _InboxPage(),
      const _CustomerProfilePage(),
    ];
    return Theme(
      data: _darkTheme,
      child: Scaffold(
        backgroundColor: _background,
        body: SafeArea(child: IndexedStack(index: _tab, children: pages)),
        bottomNavigationBar: _MarketplaceNavigation(
          selectedIndex: _tab,
          items: const [
            _NavItem(Icons.home_outlined, Icons.home_rounded, 'الرئيسية'),
            _NavItem(Icons.event_note_outlined, Icons.event_note, 'حجوزاتي'),
            _NavItem(Icons.chat_bubble_outline, Icons.chat_bubble, 'الرسائل'),
            _NavItem(Icons.person_outline, Icons.person, 'حسابي'),
          ],
          onSelected: (index) => setState(() => _tab = index),
        ),
      ),
    );
  }

  Widget _home() {
    final filtered = _providers.where((provider) {
      final matchesCategory =
          _category == 'الكل' || provider.category == _category;
      final matchesCity = _city == 'كل المدن' || provider.city == _city;
      final matchesQuery = _query.isEmpty ||
          provider.name.contains(_query) ||
          provider.category.contains(_query) ||
          provider.city.contains(_query);
      return matchesCategory && matchesCity && matchesQuery;
    }).toList()
      ..sort((a, b) => _sort == 'الأعلى تقييماً'
          ? b.rating.compareTo(a.rating)
          : a.distance.compareTo(b.distance));

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _customerHeader()),
        SliverToBoxAdapter(child: _searchBox()),
        SliverToBoxAdapter(child: _offerBanner()),
        SliverToBoxAdapter(child: _categories()),
        SliverToBoxAdapter(child: _sectionHeader('اكتشف الخدمات', 'عرض الكل')),
        SliverToBoxAdapter(child: _filters()),
        if (filtered.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child:
                  Text('لا توجد نتائج مطابقة', style: TextStyle(color: _muted)),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _ProviderCard(
                  provider: filtered[index],
                  onTap: () => _openProvider(filtered[index]),
                ),
                childCount: filtered.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _customerHeader() => Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 22,
              backgroundColor: _surfaceRaised,
              child: Icon(Icons.person, color: _white),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('مساء الخير',
                      style: TextStyle(color: _muted, fontSize: 12)),
                  SizedBox(height: 2),
                  Text('اكتشف خدمات مناسبتك',
                      style: TextStyle(
                          color: _white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            _RoleMenu(onChanged: widget.onRoleChanged),
            const SizedBox(width: 5),
            _RoundAction(
              icon: Icons.notifications_none_rounded,
              badge: true,
              onTap: () => _showMessage(context, 'لا توجد إشعارات جديدة'),
            ),
            const SizedBox(width: 7),
            _RoundAction(
              icon: Icons.chat_bubble_outline_rounded,
              onTap: () => setState(() => _tab = 2),
            ),
          ],
        ),
      );

  Widget _searchBox() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: TextField(
          style: const TextStyle(color: _white),
          decoration: InputDecoration(
            hintText: 'ابحث عن قاعة، مصور، فنان...',
            hintStyle: const TextStyle(color: _muted),
            prefixIcon: const Icon(Icons.search, color: _muted),
            filled: true,
            fillColor: _surface,
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: (value) => setState(() => _query = value.trim()),
        ),
      );

  Widget _offerBanner() => Container(
        height: 154,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 22),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [Color(0xFF711226), Color(0xFFED143B), Color(0xFF9B102B)],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Text('كل تفاصيل مناسبتك',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800)),
                  SizedBox(height: 7),
                  Text('خدمات موثوقة في مكان واحد',
                      style: TextStyle(color: Color(0xFFFFDDE3))),
                  SizedBox(height: 12),
                  Text('اكتشف العروض الآن  ←',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const Icon(Icons.celebration_rounded,
                color: Color(0xFFFFC7D0), size: 72),
          ],
        ),
      );

  Widget _categories() {
    const categories = [
      _CategoryOption('الكل', Icons.grid_view_rounded),
      _CategoryOption('قاعات', Icons.apartment_rounded),
      _CategoryOption('فنانين', Icons.mic_external_on_rounded),
      _CategoryOption('مصورين', Icons.camera_alt_rounded),
      _CategoryOption('كوش', Icons.local_florist_rounded),
      _CategoryOption('خدمات', Icons.auto_awesome_rounded),
    ];
    return SizedBox(
      height: 112,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 15),
        itemBuilder: (context, index) {
          final item = categories[index];
          final selected = _category == item.label;
          return GestureDetector(
            onTap: () => setState(() => _category = item.label),
            child: SizedBox(
              width: 63,
              child: Column(
                children: [
                  Container(
                    width: 59,
                    height: 59,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _surface,
                      border: Border.all(
                          color: selected ? _accent : const Color(0xFF44444A),
                          width: selected ? 2 : 1),
                    ),
                    child: Icon(item.icon,
                        color: selected ? _accent : const Color(0xFFD8D8DC),
                        size: 25),
                  ),
                  const SizedBox(height: 7),
                  Text(item.label,
                      maxLines: 1,
                      style: TextStyle(
                        color: selected ? _white : _muted,
                        fontSize: 11,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w400,
                      )),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sectionHeader(String title, String action) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      color: _white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700)),
            ),
            Text(action, style: const TextStyle(color: _accent, fontSize: 12)),
          ],
        ),
      );

  Widget _filters() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('ترتيب الخدمات',
                      style: TextStyle(color: _muted, fontSize: 10)),
                  const SizedBox(height: 4),
                  _DarkDropdown<String>(
                    value: _sort,
                    items: const ['الأعلى تقييماً', 'الأقرب'],
                    label: (value) => value,
                    onChanged: (value) => setState(() => _sort = value),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('الموقع',
                      style: TextStyle(color: _muted, fontSize: 10)),
                  const SizedBox(height: 4),
                  _DarkDropdown<String>(
                    value: _city,
                    items: const ['كل المدن', 'صنعاء'],
                    label: (value) => value,
                    onChanged: (value) => setState(() => _city = value),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _customerBookings() {
    final items = widget.bookings.reversed.toList();
    return _SimplePage(
      title: 'حجوزاتي',
      subtitle: 'تابع طلبات الحجز وحالتها',
      child: items.isEmpty
          ? const _EmptyMarketplace(
              icon: Icons.event_available_outlined,
              title: 'لا توجد حجوزات بعد',
              subtitle: 'ابدأ باكتشاف الخدمات المناسبة لمناسبتك',
            )
          : Column(
              children: items
                  .map((booking) => _BookingTile(booking: booking))
                  .toList(),
            ),
    );
  }

  void _openProvider(_ServiceProvider provider) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ProviderProfilePage(
          provider: provider,
          onBook: (date) => _createBooking(provider, date),
        ),
      ),
    );
  }

  Future<void> _createBooking(_ServiceProvider provider, DateTime date) async {
    final customerName = TextEditingController();
    final phone = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _surface,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 22, 20, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('تأكيد طلب الحجز',
                  style: TextStyle(
                      color: _white,
                      fontSize: 19,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 7),
              Text(
                '${provider.name} · ${_formatDate(date)} · ${_money(provider.price)} ر.ي',
                style: const TextStyle(color: _muted),
              ),
              const SizedBox(height: 18),
              _darkField(
                controller: customerName,
                label: 'اسمك',
                validator: (value) =>
                    value == null || value.trim().isEmpty ? 'أدخل الاسم' : null,
              ),
              const SizedBox(height: 11),
              _darkField(
                controller: phone,
                label: 'رقم الهاتف',
                keyboardType: TextInputType.phone,
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'أدخل رقم الهاتف'
                    : null,
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _accent, foregroundColor: Colors.white),
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      Navigator.pop(context, true);
                    }
                  },
                  child: const Text('إرسال طلب الحجز'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    try {
      if (accepted == true) {
        await widget.onCreateBooking(MarketplaceBookingDraft(
          customerName: customerName.text.trim(),
          phone: phone.text.trim(),
          providerName: provider.name,
          serviceName: provider.category,
          date: date,
          amount: provider.price.toDouble(),
        ));
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
          setState(() => _tab = 1);
          _showMessage(context, 'تم إرسال طلب الحجز إلى ${provider.name}');
        }
      }
    } catch (error) {
      if (mounted) _showMessage(context, 'تعذر إرسال طلب الحجز: $error');
    } finally {
      customerName.dispose();
      phone.dispose();
    }
  }
}

class ProviderExperience extends StatefulWidget {
  const ProviderExperience({
    super.key,
    required this.bookings,
    required this.onUpdateBooking,
    required this.onRoleChanged,
  });

  final List<MarketplaceBooking> bookings;
  final UpdateMarketplaceBooking onUpdateBooking;
  final ValueChanged<MarketplaceRole> onRoleChanged;

  @override
  State<ProviderExperience> createState() => _ProviderExperienceState();
}

class _ProviderExperienceState extends State<ProviderExperience> {
  int _tab = 0;
  _ServiceProvider _provider = _providers.first;

  @override
  Widget build(BuildContext context) => Theme(
        data: _darkTheme,
        child: Scaffold(
          backgroundColor: _background,
          body: SafeArea(
            child: IndexedStack(
              index: _tab,
              children: [
                _profile(),
                _requests(),
                const _InboxPage(),
                const _NotificationPage(),
              ],
            ),
          ),
          bottomNavigationBar: _MarketplaceNavigation(
            selectedIndex: _tab,
            items: const [
              _NavItem(Icons.person_outline, Icons.person, 'ملفي'),
              _NavItem(Icons.event_note_outlined, Icons.event_note, 'الحجوزات'),
              _NavItem(Icons.chat_bubble_outline, Icons.chat_bubble, 'الرسائل'),
              _NavItem(
                  Icons.notifications_none, Icons.notifications, 'التنبيهات'),
            ],
            onSelected: (index) => setState(() => _tab = index),
          ),
        ),
      );

  Widget _profile() => CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('ملف مقدم الخدمة',
                        style: TextStyle(
                            color: _white,
                            fontSize: 19,
                            fontWeight: FontWeight.w700)),
                  ),
                  PopupMenuButton<_ServiceProvider>(
                    tooltip: 'تبديل حساب مقدم الخدمة',
                    color: _surfaceRaised,
                    onSelected: (provider) =>
                        setState(() => _provider = provider),
                    icon: const Icon(Icons.storefront_outlined, color: _white),
                    itemBuilder: (context) => _providers
                        .map((provider) => PopupMenuItem(
                              value: provider,
                              child: Text(provider.name),
                            ))
                        .toList(),
                  ),
                  _RoleMenu(onChanged: widget.onRoleChanged),
                  IconButton(
                    onPressed: () => _showMessage(context, 'إعدادات الحساب'),
                    icon: const Icon(Icons.settings_outlined, color: _white),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _ProfileSummary(
              provider: _provider,
              isOwner: true,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
              child: Row(
                children: const [
                  Expanded(
                      child: _ProfileMetric(value: '4.9', label: 'التقييم')),
                  Expanded(
                      child: _ProfileMetric(value: '128', label: 'مراجعاً')),
                  Expanded(child: _ProfileMetric(value: '86', label: 'حجزاً')),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  Expanded(
                    child: _FilledAction(
                      label: 'تعديل الملف',
                      onTap: () => _showMessage(context, 'تعديل الملف الشخصي'),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: _OutlineAction(
                      label: 'إضافة منشور',
                      onTap: () =>
                          _showMessage(context, 'إضافة الصور والفيديوهات'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(
            child: _StoriesRow(
              labels: ['الأعمال', 'العروض', 'آراء العملاء', 'الموقع'],
            ),
          ),
          const SliverToBoxAdapter(
            child: _ProfileSectionTabs(active: 'المنشورات'),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(3),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _MediaTile(index: index),
                childCount: 9,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 3,
                mainAxisSpacing: 3,
                childAspectRatio: 0.9,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _OutlineAction(
                label: 'عرض جدول التوفر',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _ProviderCalendarPage(
                      provider: _provider,
                      ownerMode: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );

  Widget _requests() {
    final pending = widget.bookings
        .where((booking) =>
            booking.providerName == _provider.name &&
            booking.status == 'pending')
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final current = widget.bookings
        .where((booking) =>
            booking.providerName == _provider.name &&
            booking.status != 'pending')
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return _SimplePage(
      title: 'الحجوزات',
      subtitle: 'راجع الطلبات وأكد المناسب منها',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('طلبات بانتظار التأكيد'),
          if (pending.isEmpty)
            const _EmptyMarketplace(
              icon: Icons.event_busy_outlined,
              title: 'لا توجد طلبات جديدة',
              subtitle: 'ستظهر هنا طلبات العملاء فور إرسالها',
            )
          else
            ...pending.map((booking) => _ProviderRequestTile(
                  booking: booking,
                  onConfirm: () => _changeStatus(booking, true),
                  onCancel: () => _changeStatus(booking, false),
                )),
          const SizedBox(height: 18),
          const _SectionLabel('الحجوزات السابقة'),
          if (current.isEmpty)
            const Text('لا توجد حجوزات سابقة', style: TextStyle(color: _muted))
          else
            ...current.map((booking) => _BookingTile(booking: booking)),
        ],
      ),
    );
  }

  Future<void> _changeStatus(MarketplaceBooking booking, bool confirmed) async {
    try {
      await widget.onUpdateBooking(booking.id, confirmed);
      if (mounted) {
        _showMessage(
          context,
          confirmed ? 'تم تأكيد الحجز' : 'تم إلغاء طلب الحجز',
        );
      }
    } catch (error) {
      if (mounted) _showMessage(context, 'تعذر تحديث الحجز: $error');
    }
  }
}

class _ProviderProfilePage extends StatefulWidget {
  const _ProviderProfilePage({
    required this.provider,
    required this.onBook,
  });

  final _ServiceProvider provider;
  final ValueChanged<DateTime> onBook;

  @override
  State<_ProviderProfilePage> createState() => _ProviderProfilePageState();
}

class _ProviderProfilePageState extends State<_ProviderProfilePage> {
  String _activeTab = 'المنشورات';

  @override
  Widget build(BuildContext context) => Theme(
        data: _darkTheme,
        child: Scaffold(
          backgroundColor: _background,
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: _background,
                foregroundColor: _white,
                title: Text(widget.provider.name,
                    style: const TextStyle(fontSize: 17)),
                actions: [
                  IconButton(
                    onPressed: () =>
                        _showMessage(context, 'خيارات مقدم الخدمة'),
                    icon: const Icon(Icons.more_vert),
                  ),
                ],
              ),
              SliverToBoxAdapter(
                  child: _ProfileSummary(provider: widget.provider)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                  child: Row(
                    children: [
                      Expanded(
                          child: _ProfileMetric(
                              value: widget.provider.rating.toStringAsFixed(1),
                              label: 'التقييم')),
                      Expanded(
                          child: _ProfileMetric(
                              value: '${widget.provider.reviews}',
                              label: 'التقييمات')),
                      Expanded(
                          child: _ProfileMetric(
                              value: '${widget.provider.completedBookings}',
                              label: 'حجزاً')),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: _FilledAction(
                          label: 'احجز الآن',
                          onTap: () => _openCalendar(),
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: _OutlineAction(
                          label: 'مراسلة',
                          onTap: () => _showMessage(
                              context, 'بدء محادثة مع مقدم الخدمة'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _StoriesRow(labels: widget.provider.highlights),
              ),
              SliverToBoxAdapter(
                child: _ProfileSectionTabs(
                  active: _activeTab,
                  onChanged: (value) {
                    if (value == 'التوفر') {
                      _openCalendar();
                    } else {
                      setState(() => _activeTab = value);
                    }
                  },
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(3),
                sliver: SliverGrid(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _MediaTile(index: index),
                    childCount: 9,
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 3,
                    mainAxisSpacing: 3,
                    childAspectRatio: 0.9,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 25),
                  child: _PriceCard(provider: widget.provider),
                ),
              ),
            ],
          ),
        ),
      );

  Future<void> _openCalendar() async {
    final selectedDate = await Navigator.of(context).push<DateTime>(
      MaterialPageRoute<DateTime>(
        builder: (_) => _ProviderCalendarPage(provider: widget.provider),
      ),
    );
    if (selectedDate != null) widget.onBook(selectedDate);
  }
}

class _ProviderCalendarPage extends StatefulWidget {
  const _ProviderCalendarPage({
    required this.provider,
    this.ownerMode = false,
  });

  final _ServiceProvider provider;
  final bool ownerMode;

  @override
  State<_ProviderCalendarPage> createState() => _ProviderCalendarPageState();
}

class _ProviderCalendarPageState extends State<_ProviderCalendarPage> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDate;
  final Set<DateTime> _bookedDays = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    for (final day in [4, 9, 15, 21, 27]) {
      final date = DateTime(now.year, now.month, day);
      if (!date.isBefore(DateTime(now.year, now.month, now.day))) {
        _bookedDays.add(date);
      }
    }
  }

  bool _isBooked(DateTime date) =>
      _bookedDays.any((day) => _sameDay(day, date));

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(_month.year, _month.month, 1);
    final leadingDays = (firstOfMonth.weekday + 1) % 7;
    final dayCount = DateTime(_month.year, _month.month + 1, 0).day;
    return Theme(
      data: _darkTheme,
      child: Scaffold(
        backgroundColor: _background,
        appBar: AppBar(
          backgroundColor: _background,
          foregroundColor: _white,
          title: Text(widget.ownerMode ? 'جدول الحجوزات' : 'اختر موعداً'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            _ProfileSummary(provider: widget.provider),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: _surface, borderRadius: BorderRadius.circular(18)),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => setState(() =>
                            _month = DateTime(_month.year, _month.month - 1)),
                        icon: const Icon(Icons.chevron_right, color: _white),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            '${_arabicMonth(_month.month)} ${_month.year}',
                            style: const TextStyle(
                                color: _white,
                                fontWeight: FontWeight.w700,
                                fontSize: 17),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() =>
                            _month = DateTime(_month.year, _month.month + 1)),
                        icon: const Icon(Icons.chevron_left, color: _white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: ['س', 'ح', 'ن', 'ث', 'ر', 'خ', 'ج']
                        .map((day) => Expanded(
                              child: Center(
                                child: Text(day,
                                    style: const TextStyle(
                                        color: _muted, fontSize: 12)),
                              ),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 9),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: 42,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      mainAxisSpacing: 5,
                      crossAxisSpacing: 5,
                    ),
                    itemBuilder: (context, index) {
                      final dayNumber = index - leadingDays + 1;
                      if (dayNumber < 1 || dayNumber > dayCount) {
                        return const SizedBox.shrink();
                      }
                      final date =
                          DateTime(_month.year, _month.month, dayNumber);
                      final booked = _isBooked(date);
                      final past = date.isBefore(DateTime(DateTime.now().year,
                          DateTime.now().month, DateTime.now().day));
                      final selected = _selectedDate != null &&
                          _sameDay(_selectedDate!, date);
                      return GestureDetector(
                        onTap: widget.ownerMode || booked || past
                            ? null
                            : () => setState(() => _selectedDate = date),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected ? _accent : Colors.transparent,
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Text(
                                '$dayNumber',
                                style: TextStyle(
                                  color: booked
                                      ? const Color(0xFFFF667D)
                                      : past
                                          ? const Color(0xFF55555B)
                                          : selected
                                              ? Colors.white
                                              : _white,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                ),
                              ),
                              if (booked)
                                Transform.rotate(
                                  angle: -0.55,
                                  child: Container(
                                    height: 1.5,
                                    width: 25,
                                    color: _accent,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 13),
            Row(
              children: const [
                _CalendarLegend(color: Color(0xFF44444A), label: 'متاح'),
                SizedBox(width: 18),
                _CalendarLegend(color: _accent, label: 'محجوز'),
                SizedBox(width: 18),
                _CalendarLegend(color: Color(0xFFFF667D), label: 'اختيارك'),
              ],
            ),
            const SizedBox(height: 18),
            _PriceCard(provider: widget.provider),
            if (!widget.ownerMode) ...[
              const SizedBox(height: 15),
              SizedBox(
                height: 51,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _accent, foregroundColor: Colors.white),
                  onPressed: _selectedDate == null
                      ? null
                      : () => Navigator.pop(context, _selectedDate),
                  child: const Text('متابعة الحجز'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ServiceProvider {
  const _ServiceProvider({
    required this.name,
    required this.category,
    required this.city,
    required this.rating,
    required this.reviews,
    required this.price,
    required this.distance,
    required this.icon,
    required this.colors,
    required this.completedBookings,
    required this.description,
    required this.highlights,
  });

  final String name;
  final String category;
  final String city;
  final double rating;
  final int reviews;
  final int price;
  final double distance;
  final IconData icon;
  final List<Color> colors;
  final int completedBookings;
  final String description;
  final List<String> highlights;
}

const _providers = <_ServiceProvider>[
  _ServiceProvider(
    name: 'قاعة ليالي صنعاء',
    category: 'قاعات',
    city: 'صنعاء',
    rating: 4.9,
    reviews: 128,
    price: 180000,
    distance: 2.4,
    icon: Icons.apartment_rounded,
    colors: [Color(0xFF744225), Color(0xFFCE8F5A)],
    completedBookings: 86,
    description:
        'قاعة أنيقة للمناسبات العائلية، مع تجهيز كامل وخيارات متعددة للضيافة.',
    highlights: ['أعمالنا', 'العروض', 'آراء العملاء', 'الموقع'],
  ),
  _ServiceProvider(
    name: 'عدسة المصور',
    category: 'مصورين',
    city: 'صنعاء',
    rating: 4.8,
    reviews: 94,
    price: 65000,
    distance: 1.2,
    icon: Icons.camera_alt_rounded,
    colors: [Color(0xFF31566A), Color(0xFF68A4AF)],
    completedBookings: 72,
    description:
        'تصوير مناسبات بجودة عالية، صور وفيديو وتغطية لحظاتكم الجميلة.',
    highlights: ['صور الزفاف', 'فيديو', 'آراء العملاء', 'المعدات'],
  ),
  _ServiceProvider(
    name: 'الفنان سامي',
    category: 'فنانين',
    city: 'صنعاء',
    rating: 4.7,
    reviews: 76,
    price: 120000,
    distance: 4.8,
    icon: Icons.mic_rounded,
    colors: [Color(0xFF582C67), Color(0xFFAA689F)],
    completedBookings: 61,
    description: 'فقرات فنية وصوتيات تناسب مناسبتكم، مع تنسيق مسبق للأغاني.',
    highlights: ['حفلاتنا', 'الصوتيات', 'آراء العملاء', 'العروض'],
  ),
  _ServiceProvider(
    name: 'لمسة ورد للكوش',
    category: 'كوش',
    city: 'صنعاء',
    rating: 4.6,
    reviews: 58,
    price: 95000,
    distance: 3.1,
    icon: Icons.local_florist_rounded,
    colors: [Color(0xFF6D3C4B), Color(0xFFD17D91)],
    completedBookings: 49,
    description: 'تنسيق كوش وباقات ورد بتصاميم خاصة وألوان حسب اختياركم.',
    highlights: ['تصاميم', 'باقات ورد', 'آراء العملاء', 'العروض'],
  ),
  _ServiceProvider(
    name: 'استراحة السكون',
    category: 'خدمات',
    city: 'صنعاء',
    rating: 4.8,
    reviews: 43,
    price: 50000,
    distance: 7.5,
    icon: Icons.cabin_rounded,
    colors: [Color(0xFF315B48), Color(0xFF78A87B)],
    completedBookings: 38,
    description: 'مساحة هادئة للعائلات مع جلسة خارجية ومطبخ.',
    highlights: ['المكان', 'المرافق', 'آراء العملاء', 'التوفر'],
  ),
];

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({required this.provider, required this.onTap});

  final _ServiceProvider provider;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(18),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 156,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: provider.colors,
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: Opacity(
                        opacity: 0.2,
                        child:
                            Icon(provider.icon, size: 132, color: Colors.white),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: _CategoryTag(provider.category),
                    ),
                    Positioned(
                      bottom: 11,
                      left: 12,
                      child: _RatingChip(rating: provider.rating),
                    ),
                    Positioned(
                      bottom: 12,
                      right: 14,
                      child: Text(provider.city,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(provider.name,
                              style: const TextStyle(
                                  color: _white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 5),
                          Text(
                            '${provider.distance.toStringAsFixed(1)} كم · ${provider.reviews} تقييم',
                            style: const TextStyle(color: _muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${_money(provider.price)} ر.ي',
                            style: const TextStyle(
                                color: _accent, fontWeight: FontWeight.w700)),
                        const Text('يبدأ من',
                            style: TextStyle(color: _muted, fontSize: 10)),
                      ],
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_left, color: _muted),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _ProfileSummary extends StatelessWidget {
  const _ProfileSummary({required this.provider, this.isOwner = false});

  final _ServiceProvider provider;
  final bool isOwner;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 82,
              height: 82,
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [_accent, Color(0xFFFF9E59)]),
              ),
              child: CircleAvatar(
                backgroundColor: provider.colors.first,
                child: Icon(provider.icon, color: Colors.white, size: 34),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(provider.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: _white,
                                fontSize: 17,
                                fontWeight: FontWeight.w700)),
                      ),
                      if (provider.rating >= 4.8) ...[
                        const SizedBox(width: 5),
                        const Icon(Icons.verified,
                            color: Color(0xFF61A8FF), size: 17),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text('${provider.category} · ${provider.city}',
                      style: const TextStyle(color: _muted, fontSize: 12)),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          color: Color(0xFFFFC44D), size: 17),
                      const SizedBox(width: 3),
                      Text('${provider.rating} (${provider.reviews})',
                          style: const TextStyle(
                              color: _white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(provider.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Color(0xFFC7C7CC),
                          fontSize: 11,
                          height: 1.45)),
                  const SizedBox(height: 7),
                  Text('يبدأ السعر من ${_money(provider.price)} ر.ي',
                      style: const TextStyle(
                          color: _accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                  if (isOwner)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text('حساب مقدم خدمة · ظاهر للعملاء',
                          style: TextStyle(color: _muted, fontSize: 10)),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _ProfileMetric extends StatelessWidget {
  const _ProfileMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text(value,
              style: const TextStyle(
                  color: _white, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(color: _muted, fontSize: 11)),
        ],
      );
}

class _StoriesRow extends StatelessWidget {
  const _StoriesRow({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 98,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 5),
          scrollDirection: Axis.horizontal,
          itemCount: labels.length,
          separatorBuilder: (_, __) => const SizedBox(width: 13),
          itemBuilder: (context, index) => SizedBox(
            width: 65,
            child: Column(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient:
                        LinearGradient(colors: [_accent, Color(0xFFFF9E59)]),
                  ),
                  child: CircleAvatar(
                    backgroundColor: _surfaceRaised,
                    child: Icon(
                      const [
                        Icons.photo_library,
                        Icons.local_offer,
                        Icons.star,
                        Icons.place
                      ][index % 4],
                      size: 22,
                      color: _white,
                    ),
                  ),
                ),
                const SizedBox(height: 5),
                Text(labels[index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 10)),
              ],
            ),
          ),
        ),
      );
}

class _ProfileSectionTabs extends StatelessWidget {
  const _ProfileSectionTabs({this.active = 'المنشورات', this.onChanged});

  final String active;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          _ProfileTab(
            icon: Icons.grid_on_rounded,
            label: 'المنشورات',
            selected: active == 'المنشورات',
            onTap: () => onChanged?.call('المنشورات'),
          ),
          _ProfileTab(
            icon: Icons.calendar_month_outlined,
            label: 'التوفر',
            selected: active == 'التوفر',
            onTap: () => onChanged?.call('التوفر'),
          ),
          _ProfileTab(
            icon: Icons.video_library_outlined,
            label: 'الفيديوهات',
            selected: active == 'الفيديوهات',
            onTap: () => onChanged?.call('الفيديوهات'),
          ),
        ],
      );
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({
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
  Widget build(BuildContext context) => Expanded(
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected ? _accent : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Icon(icon, color: selected ? _white : _muted, size: 20),
          ),
        ),
      );
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final colors = _providers[index % _providers.length].colors;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: colors,
            begin: Alignment.topRight,
            end: Alignment.bottomLeft),
      ),
      child: Stack(
        children: [
          Center(
            child: Icon(_providers[index % _providers.length].icon,
                size: 44, color: Colors.white.withOpacity(0.82)),
          ),
          if (index % 3 == 2)
            const Positioned(
              top: 7,
              left: 7,
              child:
                  Icon(Icons.play_arrow_rounded, color: Colors.white, size: 20),
            ),
        ],
      ),
    );
  }
}

class _PriceCard extends StatelessWidget {
  const _PriceCard({required this.provider});

  final _ServiceProvider provider;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF303036)),
        ),
        child: Row(
          children: [
            const Icon(Icons.sell_outlined, color: _accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('السعر يبدأ من',
                      style: TextStyle(color: _muted, fontSize: 11)),
                  const SizedBox(height: 4),
                  Text('${_money(provider.price)} ر.ي',
                      style: const TextStyle(
                          color: _white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const Text('حسب تفاصيل المناسبة',
                style: TextStyle(color: _muted, fontSize: 10)),
          ],
        ),
      );
}

class _ProviderRequestTile extends StatelessWidget {
  const _ProviderRequestTile({
    required this.booking,
    required this.onConfirm,
    required this.onCancel,
  });

  final MarketplaceBooking booking;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
            color: _surface, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(booking.customerName,
                style: const TextStyle(
                    color: _white, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('${booking.serviceName} · ${_formatDate(booking.date)}',
                style: const TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 5),
            Text('${_money(booking.amount.round())} ر.ي',
                style: const TextStyle(
                    color: _accent, fontWeight: FontWeight.w700)),
            const SizedBox(height: 13),
            Row(
              children: [
                Expanded(
                  child: _FilledAction(label: 'تأكيد الحجز', onTap: onConfirm),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: _OutlineAction(
                    label: 'إلغاء',
                    onTap: onCancel,
                    color: _accent,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _BookingTile extends StatelessWidget {
  const _BookingTile({required this.booking});

  final MarketplaceBooking booking;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: _surface, borderRadius: BorderRadius.circular(15)),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  color: _accent.withOpacity(0.14), shape: BoxShape.circle),
              child: const Icon(Icons.event_available, color: _accent),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(booking.providerName,
                      style: const TextStyle(
                          color: _white, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('${booking.serviceName} · ${_formatDate(booking.date)}',
                      style: const TextStyle(color: _muted, fontSize: 11)),
                ],
              ),
            ),
            Text(_statusLabel(booking.status),
                style: TextStyle(
                    color: booking.status == 'confirmed'
                        ? const Color(0xFF7ED7A1)
                        : booking.status == 'cancelled'
                            ? _accent
                            : const Color(0xFFFFC44D),
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

class _InboxPage extends StatelessWidget {
  const _InboxPage();

  @override
  Widget build(BuildContext context) => _SimplePage(
        title: 'الرسائل',
        subtitle: 'تواصل مع مزودي الخدمات',
        child: Column(
          children: const [
            _ChatTile(
                name: 'قاعة ليالي صنعاء',
                preview: 'أهلاً بك، يسعدنا خدمتك',
                icon: Icons.apartment),
            _ChatTile(
                name: 'عدسة المصور',
                preview: 'هل حددت موعد المناسبة؟',
                icon: Icons.camera_alt),
            _ChatTile(
                name: 'لمسة ورد للكوش',
                preview: 'لدينا عروض جديدة لهذا الشهر',
                icon: Icons.local_florist),
          ],
        ),
      );
}

class _NotificationPage extends StatelessWidget {
  const _NotificationPage();

  @override
  Widget build(BuildContext context) => _SimplePage(
        title: 'الإشعارات',
        subtitle: 'آخر التنبيهات المتعلقة بحسابك',
        child: Column(
          children: const [
            _NotificationTile(
                title: 'طلب حجز جديد',
                detail: 'لديك طلب جديد بانتظار التأكيد',
                icon: Icons.event_available),
            _NotificationTile(
                title: 'تقييم جديد',
                detail: 'أضاف أحد العملاء تقييماً لخدمتك',
                icon: Icons.star_outline),
            _NotificationTile(
                title: 'تذكير',
                detail: 'تأكد من تحديث جدول التوفر',
                icon: Icons.calendar_month),
          ],
        ),
      );
}

class _CustomerProfilePage extends StatelessWidget {
  const _CustomerProfilePage();

  @override
  Widget build(BuildContext context) => _SimplePage(
        title: 'حسابي',
        subtitle: 'إدارة بياناتك وحجوزاتك',
        child: Column(
          children: const [
            _ProfileOption(
                icon: Icons.person_outline, title: 'البيانات الشخصية'),
            _ProfileOption(icon: Icons.favorite_border, title: 'المفضلة'),
            _ProfileOption(icon: Icons.notifications_none, title: 'الإشعارات'),
            _ProfileOption(icon: Icons.help_outline, title: 'المساعدة والدعم'),
          ],
        ),
      );
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.name,
    required this.preview,
    required this.icon,
  });

  final String name;
  final String preview;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: _surface, borderRadius: BorderRadius.circular(15)),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: _surfaceRaised,
              child: Icon(icon, color: _accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          color: _white, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(preview,
                      style: const TextStyle(color: _muted, fontSize: 11)),
                ],
              ),
            ),
            const Text('١٢:٣٠', style: TextStyle(color: _muted, fontSize: 10)),
          ],
        ),
      );
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.title,
    required this.detail,
    required this.icon,
  });

  final String title;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: _surface, borderRadius: BorderRadius.circular(15)),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: _accent.withOpacity(0.15),
              child: Icon(icon, color: _accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: _white, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(detail,
                      style: const TextStyle(color: _muted, fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.circle, color: _accent, size: 8),
          ],
        ),
      );
}

class _ProfileOption extends StatelessWidget {
  const _ProfileOption({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 9),
        decoration: BoxDecoration(
            color: _surface, borderRadius: BorderRadius.circular(13)),
        child: ListTile(
          leading: Icon(icon, color: _accent),
          title:
              Text(title, style: const TextStyle(color: _white, fontSize: 14)),
          trailing: const Icon(Icons.chevron_left, color: _muted),
          onTap: () => _showMessage(context, title),
        ),
      );
}

class _SimplePage extends StatelessWidget {
  const _SimplePage({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 19, 18, 19),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: _white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  Text(subtitle,
                      style: const TextStyle(color: _muted, fontSize: 12)),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            sliver: SliverToBoxAdapter(child: child),
          ),
        ],
      );
}

class _MarketplaceNavigation extends StatelessWidget {
  const _MarketplaceNavigation({
    required this.selectedIndex,
    required this.items,
    required this.onSelected,
  });

  final int selectedIndex;
  final List<_NavItem> items;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          color: _surface,
          border: Border(top: BorderSide(color: Color(0xFF303036))),
        ),
        child: NavigationBar(
          backgroundColor: _surface,
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelected,
          destinations: items
              .map((item) => NavigationDestination(
                    icon: Icon(item.icon),
                    selectedIcon: Icon(item.selectedIcon, color: Colors.white),
                    label: item.label,
                  ))
              .toList(),
        ),
      );
}

class _NavItem {
  const _NavItem(this.icon, this.selectedIcon, this.label);

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    this.onTap,
    this.badge = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool badge;

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          IconButton(
            onPressed: onTap,
            style: IconButton.styleFrom(
              backgroundColor: _surface,
              foregroundColor: _white,
              fixedSize: const Size(42, 42),
            ),
            icon: Icon(icon, size: 20),
          ),
          if (badge)
            const Positioned(
              top: 8,
              right: 8,
              child: CircleAvatar(radius: 4, backgroundColor: _accent),
            ),
        ],
      );
}

class _RoleMenu extends StatelessWidget {
  const _RoleMenu({required this.onChanged});

  final ValueChanged<MarketplaceRole> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<MarketplaceRole>(
        tooltip: 'تبديل الواجهة',
        color: _surfaceRaised,
        icon: const Icon(Icons.swap_horiz_rounded, color: _muted),
        onSelected: onChanged,
        itemBuilder: (context) => const [
          PopupMenuItem(
              value: MarketplaceRole.customer, child: Text('واجهة العميل')),
          PopupMenuItem(
              value: MarketplaceRole.provider,
              child: Text('واجهة مقدم الخدمة')),
          PopupMenuItem(
              value: MarketplaceRole.admin, child: Text('لوحة الإدارة')),
        ],
      );
}

class _DarkDropdown<T> extends StatelessWidget {
  const _DarkDropdown({
    required this.value,
    required this.items,
    required this.label,
    required this.onChanged,
  });

  final T value;
  final List<T> items;
  final String Function(T value) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            dropdownColor: _surfaceRaised,
            icon: const Icon(Icons.keyboard_arrow_down, color: _accent),
            style: const TextStyle(color: _white, fontSize: 12),
            items: items
                .map((item) =>
                    DropdownMenuItem<T>(value: item, child: Text(label(item))))
                .toList(),
            onChanged: (item) {
              if (item != null) onChanged(item);
            },
          ),
        ),
      );
}

class _FilledAction extends StatelessWidget {
  const _FilledAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 43,
        child: ElevatedButton(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          child: Text(label,
              maxLines: 1,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      );
}

class _OutlineAction extends StatelessWidget {
  const _OutlineAction({
    required this.label,
    required this.onTap,
    this.color = _white,
  });

  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 43,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: color,
            side: BorderSide(color: color.withOpacity(0.6)),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          child: Text(label,
              maxLines: 1,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Text(
        title,
        style: const TextStyle(
            color: _white, fontSize: 16, fontWeight: FontWeight.w700),
      );
}

class _CategoryTag extends StatelessWidget {
  const _CategoryTag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.42),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      );
}

class _RatingChip extends StatelessWidget {
  const _RatingChip({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.42),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            const Icon(Icons.star_rounded, color: Color(0xFFFFC44D), size: 16),
            const SizedBox(width: 3),
            Text('$rating',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

class _CalendarLegend extends StatelessWidget {
  const _CalendarLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: _muted, fontSize: 10)),
        ],
      );
}

class _EmptyMarketplace extends StatelessWidget {
  const _EmptyMarketplace({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 18),
        child: Column(
          children: [
            Icon(icon, color: _accent, size: 42),
            const SizedBox(height: 12),
            Text(title,
                style: const TextStyle(
                    color: _white, fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, fontSize: 12)),
          ],
        ),
      );
}

class _DarkField extends StatelessWidget {
  const _DarkField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        style: const TextStyle(color: _white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: _muted),
          filled: true,
          fillColor: _background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      );
}

Widget _darkField({
  required TextEditingController controller,
  required String label,
  TextInputType? keyboardType,
  String? Function(String?)? validator,
}) =>
    _DarkField(
      controller: controller,
      label: label,
      keyboardType: keyboardType,
      validator: validator,
    );

ThemeData get _darkTheme => ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _background,
      colorScheme: const ColorScheme.dark(
        primary: _accent,
        secondary: _accent,
        surface: _surface,
        onSurface: _white,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: _white),
        bodySmall: TextStyle(color: _muted),
        titleMedium: TextStyle(color: _white),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _surface,
        indicatorColor: const Color(0xFF701024),
        labelTextStyle: MaterialStateProperty.resolveWith<TextStyle?>(
          (states) => TextStyle(
            color: states.contains(MaterialState.selected) ? _white : _muted,
            fontSize: 10,
          ),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: _background,
        foregroundColor: _white,
      ),
    );

void _showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: _surfaceRaised,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

String _money(int amount) => amount.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );

String _formatDate(DateTime date) =>
    '${date.day} ${_arabicMonth(date.month)} ${date.year}';

String _arabicMonth(int month) => const [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ][month - 1];

String _statusLabel(String status) {
  switch (status) {
    case 'confirmed':
      return 'مؤكد';
    case 'cancelled':
      return 'ملغي';
    default:
      return 'بانتظار الرد';
  }
}

bool _sameDay(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

class _CategoryOption {
  const _CategoryOption(this.label, this.icon);

  final String label;
  final IconData icon;
}
