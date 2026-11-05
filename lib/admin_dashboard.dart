import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key, required this.onExit});

  final VoidCallback onExit;

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _tab = 0;
  bool _loading = true;
  Object? _error;
  List<Map<String, dynamic>> _providers = [];
  List<Map<String, dynamic>> _bookings = [];
  List<Map<String, dynamic>> _ledger = [];
  List<Map<String, dynamic>> _reports = [];

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _asRows(dynamic value) => (value as List)
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = _client.auth.currentUser;
      if (user == null) throw StateError('يلزم تسجيل الدخول بحساب إداري.');
      final profile = await _client
          .from('profiles')
          .select('role')
          .eq('id', user.id)
          .maybeSingle();
      if (profile?['role'] != 'admin') {
        throw StateError('هذا الحساب لا يملك صلاحية الإدارة.');
      }

      final providers = await _client.rpc('admin_list_providers');
      final bookings = await _client
          .from('bookings')
          .select(
              'id,customer_id,customer_name,customer_phone,provider_id,service_name,event_date,shift_type,package_name,guest_count,total_amount,deposit_amount,deposit_paid,status,created_at')
          .order('event_date', ascending: false);
      final ledger = await _client
          .from('ledger_entries')
          .select('id,user_id,title,amount,entry_date,kind,note')
          .order('entry_date', ascending: false);
      final reports = await _client
          .from('reports')
          .select(
              'id,reporter_id,provider_id,booking_id,reason,details,status,admin_note,created_at')
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _providers = _asRows(providers);
        _bookings = _asRows(bookings);
        _ledger = _asRows(ledger);
        _reports = _asRows(reports);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runAction(
    Future<void> Function() action, {
    String? successMessage,
  }) async {
    try {
      await action();
      if (successMessage != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(successMessage)));
      }
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تنفيذ الإجراء: $error')),
        );
      }
    }
  }

  Future<void> _reviewProvider(
    Map<String, dynamic> provider,
    String status,
  ) async {
    String? reason;
    if (status == 'rejected') {
      final controller = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('سبب رفض الطلب'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration:
                const InputDecoration(hintText: 'أدخل ملاحظة توضح سبب الرفض'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('رجوع'),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text.trim().isNotEmpty) {
                  Navigator.pop(context, controller.text.trim());
                }
              },
              child: const Text('رفض الطلب'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (reason == null) return;
    }
    await _runAction(
      () async {
        await _client.rpc('admin_set_provider_status', params: {
          'target_provider_id': provider['id'],
          'new_status': status,
          'reason': reason,
        });
      },
      successMessage: status == 'approved'
          ? 'تم اعتماد مقدم الخدمة.'
          : 'تم رفض طلب مقدم الخدمة.',
    );
  }

  Future<void> _showProviderDocuments(Map<String, dynamic> provider) async {
    try {
      final documents = await _client
          .from('provider_verification_documents')
          .select('id_card_path,ownership_doc_path')
          .eq('provider_id', provider['id'])
          .maybeSingle();
      if (documents == null) throw StateError('لم تُرفع وثائق لهذا الطلب.');
      final storage = _client.storage.from('provider-documents');
      final identityUrl = await storage.createSignedUrl(
          documents['id_card_path'] as String, 60);
      final ownershipUrl = await storage.createSignedUrl(
          documents['ownership_doc_path'] as String, 60);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('وثائق ${provider['full_name']}'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _DocumentPreview(label: 'الهوية', imageUrl: identityUrl),
                  const SizedBox(height: 16),
                  _DocumentPreview(
                      label: 'إثبات ملكية النشاط', imageUrl: ownershipUrl),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر فتح الوثائق: $error')),
        );
      }
    }
  }

  Future<void> _setBookingStatus(
      Map<String, dynamic> booking, String status) async {
    await _runAction(
      () async {
        await _client
            .from('bookings')
            .update({'status': status}).eq('id', booking['id']);
      },
      successMessage: 'تم تحديث حالة الحجز.',
    );
  }

  Future<void> _resolveReport(Map<String, dynamic> report) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('معالجة البلاغ'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'ملاحظة إدارية'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('إغلاق البلاغ'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (note == null) return;
    await _runAction(
      () async {
        await _client.from('reports').update({
          'status': 'resolved',
          'admin_note': note,
          'resolved_at': DateTime.now().toUtc().toIso8601String(),
        }).eq('id', report['id']);
      },
      successMessage: 'تم تحديث البلاغ.',
    );
  }

  Future<void> _addLedgerEntry() async {
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    final noteController = TextEditingController();
    var kind = 'income';
    String? formError;
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('إضافة حركة مالية'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'العنوان'),
              ),
              TextField(
                controller: amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'المبلغ'),
              ),
              DropdownButtonFormField<String>(
                value: kind,
                decoration: const InputDecoration(labelText: 'النوع'),
                items: const [
                  DropdownMenuItem(value: 'income', child: Text('إيراد')),
                  DropdownMenuItem(value: 'expense', child: Text('مصروف')),
                ],
                onChanged: (value) => setDialogState(() => kind = value!),
              ),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'ملاحظة'),
              ),
              if (formError != null)
                Text(formError!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                final amount = double.tryParse(amountController.text.trim());
                if (titleController.text.trim().isEmpty ||
                    amount == null ||
                    !amount.isFinite ||
                    amount <= 0) {
                  setDialogState(
                      () => formError = 'أدخل عنواناً ومبلغاً صالحاً.');
                  return;
                }
                Navigator.pop(context, {
                  'title': titleController.text.trim(),
                  'amount': amount.toString(),
                  'kind': kind,
                  'note': noteController.text.trim(),
                });
              },
              child: const Text('حفظ الحركة'),
            ),
          ],
        ),
      ),
    );
    titleController.dispose();
    amountController.dispose();
    noteController.dispose();
    if (result == null) return;
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) _showAdminMessage('انتهت الجلسة؛ سجّل الدخول مجدداً.');
      return;
    }
    await _runAction(
      () async {
        await _client.from('ledger_entries').insert({
          'user_id': userId,
          'title': result['title'],
          'amount': double.parse(result['amount']!),
          'entry_date': DateTime.now().toUtc().toIso8601String(),
          'kind': result['kind'],
          'note': result['note'],
        });
      },
      successMessage: 'تمت إضافة الحركة المالية.',
    );
  }

  void _showAdminMessage(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('لوحة الإدارة'),
          leading: IconButton(
            tooltip: 'العودة',
            onPressed: widget.onExit,
            icon: const Icon(Icons.arrow_back),
          ),
          actions: [
            IconButton(
              tooltip: 'تحديث البيانات',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorPanel(error: _error!, onRetry: _load)
                : IndexedStack(
                    index: _tab,
                    children: [
                      _providersPage(),
                      _bookingsPage(),
                      _financePage(),
                      _reportsPage(),
                    ],
                  ),
        floatingActionButton: _tab == 2 && !_loading && _error == null
            ? FloatingActionButton.extended(
                onPressed: _addLedgerEntry,
                icon: const Icon(Icons.add),
                label: const Text('إضافة حركة'),
              )
            : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (index) => setState(() => _tab = index),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.verified_user_outlined), label: 'التحقق'),
            NavigationDestination(
                icon: Icon(Icons.event_note_outlined), label: 'الحجوزات'),
            NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined),
                label: 'المالية'),
            NavigationDestination(
                icon: Icon(Icons.flag_outlined), label: 'البلاغات'),
          ],
        ),
      );

  Widget _providersPage() {
    final pending =
        _providers.where((item) => item['verification_status'] == 'pending');
    final other =
        _providers.where((item) => item['verification_status'] != 'pending');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionTitle(
            title: 'طلبات التحقق',
            subtitle: '${pending.length} طلب بانتظار المراجعة'),
        for (final provider in pending) _providerCard(provider, review: true),
        if (pending.isEmpty) const _EmptyMessage('لا توجد طلبات تحقق معلقة.'),
        const SizedBox(height: 20),
        const _SectionTitle(
            title: 'مزودون آخرون', subtitle: 'الطلبات السابقة والحالة الحالية'),
        for (final provider in other) _providerCard(provider),
      ],
    );
  }

  Widget _providerCard(
    Map<String, dynamic> provider, {
    bool review = false,
  }) =>
      Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(provider['business_name'] as String? ?? 'نشاط غير مسمى',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                '${provider['full_name']} · ${provider['category']} · ${provider['city']}',
              ),
              Text('الهاتف: ${provider['phone']}'),
              Text(
                  'الحالة: ${_providerStatus(provider['verification_status'] as String?)}'),
              if (provider['rejection_reason'] != null)
                Text('سبب الرفض: ${provider['rejection_reason']}'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  OutlinedButton.icon(
                    onPressed: _loading
                        ? null
                        : () => _showProviderDocuments(provider),
                    icon: const Icon(Icons.description_outlined),
                    label: const Text('عرض الوثائق'),
                  ),
                  if (review) ...[
                    ElevatedButton.icon(
                      onPressed: _loading
                          ? null
                          : () => _reviewProvider(provider, 'approved'),
                      icon: const Icon(Icons.check),
                      label: const Text('اعتماد'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _loading
                          ? null
                          : () => _reviewProvider(provider, 'rejected'),
                      icon: const Icon(Icons.close),
                      label: const Text('رفض'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      );

  Widget _bookingsPage() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionTitle(
              title: 'الحجوزات',
              subtitle: '${_bookings.length} حجزاً في النظام'),
          for (final booking in _bookings)
            Card(
              child: ListTile(
                title: Text(booking['service_name'] as String? ?? 'خدمة'),
                subtitle: Text(
                  '${booking['event_date']} · ${booking['shift_type']} · ${booking['status']}\n'
                  'الإجمالي ${booking['total_amount']} · '
                  'العربون المطلوب ${booking['deposit_amount']} · '
                  'المسدّد ${booking['deposit_paid']}',
                ),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  onSelected: (status) => _setBookingStatus(booking, status),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                        value: 'confirmed', child: Text('تأكيد الحجز')),
                    PopupMenuItem(
                        value: 'completed', child: Text('إتمام الحجز')),
                    PopupMenuItem(
                        value: 'cancelled', child: Text('إلغاء الحجز')),
                  ],
                ),
              ),
            ),
        ],
      );

  Widget _financePage() {
    final income = _ledger
        .where((entry) => entry['kind'] == 'income')
        .fold<double>(
            0, (total, entry) => total + (entry['amount'] as num).toDouble());
    final expenses = _ledger
        .where((entry) => entry['kind'] == 'expense')
        .fold<double>(
            0, (total, entry) => total + (entry['amount'] as num).toDouble());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _SectionTitle(
            title: 'المالية', subtitle: 'الحركات المسجلة في النظام'),
        Card(
          child: ListTile(
            title: const Text('صافي الحركات'),
            subtitle: Text('إيرادات $income · مصروفات $expenses'),
            trailing: Text('${income - expenses}'),
          ),
        ),
        for (final entry in _ledger)
          Card(
            child: ListTile(
              title: Text(entry['title'] as String? ?? 'حركة مالية'),
              subtitle: Text(
                  '${entry['entry_date']} · ${entry['kind']} · ${entry['note'] ?? ''}'),
              trailing: Text('${entry['amount']}'),
            ),
          ),
        if (_ledger.isEmpty) const _EmptyMessage('لا توجد حركات مالية.'),
      ],
    );
  }

  Widget _reportsPage() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionTitle(
              title: 'البلاغات', subtitle: 'المتابعة والمعالجة'),
          for (final report in _reports)
            Card(
              child: ListTile(
                title: Text(report['reason'] as String? ?? 'بلاغ'),
                subtitle: Text(
                    '${report['details'] ?? ''}\nالحالة: ${report['status']}'),
                isThreeLine: true,
                trailing: report['status'] == 'resolved'
                    ? null
                    : IconButton(
                        tooltip: 'معالجة البلاغ',
                        onPressed: () => _resolveReport(report),
                        icon: const Icon(Icons.done),
                      ),
              ),
            ),
          if (_reports.isEmpty) const _EmptyMessage('لا توجد بلاغات.'),
        ],
      );

  String _providerStatus(String? status) {
    switch (status) {
      case 'approved':
        return 'معتمد';
      case 'rejected':
        return 'مرفوض';
      case 'suspended':
        return 'موقوف';
      default:
        return 'قيد المراجعة';
    }
  }
}

class _DocumentPreview extends StatelessWidget {
  const _DocumentPreview({required this.label, required this.imageUrl});

  final String label;
  final String imageUrl;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Image.network(
            imageUrl,
            height: 260,
            width: double.infinity,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) =>
                const Text('تعذر عرض الصورة.'),
          ),
        ],
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(subtitle),
          ],
        ),
      );
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Center(child: Text(message)),
      );
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 42),
              const SizedBox(height: 12),
              Text('$error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: onRetry,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
}
