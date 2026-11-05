import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:booking_manager/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef AuthFlowComplete = void Function(
  String userId,
  String role,
  String? verificationStatus,
);

class AuthFlow extends StatefulWidget {
  const AuthFlow({
    super.key,
    required this.onComplete,
    required this.onGuest,
  });

  final AuthFlowComplete onComplete;
  final VoidCallback onGuest;

  @override
  State<AuthFlow> createState() => _AuthFlowState();
}

class _AuthFlowState extends State<AuthFlow> {
  static const _googleRedirectUrl =
      'com.munasbh.booking_manager://login-callback/';

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _business = TextEditingController();
  final _city = TextEditingController();
  final _description = TextEditingController();
  final _startingPrice = TextEditingController();
  final _maxGuests = TextEditingController();
  final _depositPercent = TextEditingController(text: '20');
  bool _isProvider = false;
  bool _isRegistering = true;
  bool _isBusy = false;
  bool _providerRegistrationPending = false;
  bool _googleSignInPending = false;
  String? _notice;
  String _category = 'wedding_hall';
  String? _error;
  PlatformFile? _identityDocument;
  PlatformFile? _ownershipDocument;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((state) async {
      final user = state.session?.user;
      if (!_googleSignInPending ||
          state.event != AuthChangeEvent.signedIn ||
          user == null) {
        return;
      }
      _googleSignInPending = false;
      try {
        await _completeAuthenticatedUser(user.id);
      } catch (error) {
        _showError('تم تسجيل الدخول، لكن تعذر تحميل بيانات الحساب: $error');
      }
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _business.dispose();
    _city.dispose();
    _description.dispose();
    _startingPrice.dispose();
    _maxGuests.dispose();
    _depositPercent.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _isBusy = true;
      _error = null;
    });
    _googleSignInPending = true;
    try {
      final launched = await Supabase.instance.client.auth.signInWithOAuth(
        Provider.google,
        context: context,
        redirectTo: kIsWeb ? Uri.base.origin : _googleRedirectUrl,
      );
      if (!launched) {
        _googleSignInPending = false;
        throw StateError('تعذر فتح صفحة تسجيل الدخول باستخدام Google.');
      }
    } on AuthException catch (error) {
      _googleSignInPending = false;
      _showError(error.message);
    } catch (error) {
      _googleSignInPending = false;
      _showError('تعذر بدء تسجيل الدخول باستخدام Google: $error');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  String? _normalizePhone(String input) {
    var phone = input.replaceAll(RegExp(r'[\s()-]'), '');
    if (phone.startsWith('00')) phone = '+${phone.substring(2)}';
    if (RegExp(r'^0?7\d{8}$').hasMatch(phone)) {
      phone = '+967${phone.startsWith('0') ? phone.substring(1) : phone}';
    } else if (RegExp(r'^[1-9]\d{7,14}$').hasMatch(phone)) {
      phone = '+$phone';
    }
    return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone) ? phone : null;
  }

  Future<void> _authenticate() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isProvider &&
        _isRegistering &&
        (_identityDocument == null || _ownershipDocument == null)) {
      setState(() => _error = 'أرفق صورة الهوية وإثبات ملكية النشاط أولاً.');
      return;
    }
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      final auth = Supabase.instance.client.auth;
      final email = _email.text.trim().toLowerCase();
      if (_isRegistering) {
        _providerRegistrationPending = _isProvider;
        final response = await auth.signUp(
          email: email,
          password: _password.text,
          data: {
            'full_name': _name.text.trim(),
            if (_phone.text.trim().isNotEmpty)
              'phone': _normalizePhone(_phone.text.trim()),
          },
        );
        final user = response.user;
        if (user == null) {
          throw StateError('لم يتم إنشاء الحساب. حاول مرة أخرى.');
        }
        if (response.session == null) {
          if (!mounted) return;
          setState(() {
            _isRegistering = false;
            _notice =
                'تم إنشاء الحساب. افتح رسالة تأكيد البريد، ثم سجّل الدخول هنا.';
          });
          return;
        }
        await _completeAuthenticatedUser(user.id, isNewUser: true);
      } else {
        final response = await auth.signInWithPassword(
          email: email,
          password: _password.text,
        );
        final user = response.user;
        if (user == null) {
          throw StateError('تعذر تسجيل الدخول بهذا البريد.');
        }
        await _completeAuthenticatedUser(user.id);
      }
    } on AuthException catch (error) {
      _showError(error.message);
    } catch (error) {
      _showError('تعذر إكمال العملية: $error');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _completeAuthenticatedUser(
    String userId, {
    bool isNewUser = false,
  }) async {
    final client = Supabase.instance.client;
    if (_isProvider) {
      var status = await client.rpc('get_current_provider_status') as String?;
      if (status == null &&
          (isNewUser || _providerRegistrationPending) &&
          _identityDocument != null &&
          _ownershipDocument != null) {
        await _registerProvider(userId);
        status = 'pending';
        _providerRegistrationPending = false;
      }
      if (status == null) {
        throw StateError('لا يوجد طلب مقدم خدمة مرتبط بهذا الحساب.');
      }
      widget.onComplete(userId, 'provider', status);
      return;
    }

    if (isNewUser) await _saveCustomerProfile(userId);
    final profile = await client
        .from('profiles')
        .select('role')
        .eq('id', userId)
        .maybeSingle();
    final role = profile?['role'] as String? ?? 'customer';
    if (role == 'provider') {
      final status = await client.rpc('get_current_provider_status') as String?;
      widget.onComplete(userId, role, status);
    } else {
      widget.onComplete(userId, role, null);
    }
  }

  Future<void> _saveCustomerProfile(String userId) async {
    final profile = <String, dynamic>{};
    if (_name.text.trim().isNotEmpty) profile['full_name'] = _name.text.trim();
    final phoneInput = _phone.text.trim();
    if (phoneInput.isNotEmpty) {
      final phone = _normalizePhone(phoneInput);
      if (phone == null) throw StateError('أدخل رقم هاتف بصيغة صحيحة.');
      profile['phone'] = phone;
    }
    if (profile.isNotEmpty) {
      await Supabase.instance.client
          .from('profiles')
          .update(profile)
          .eq('id', userId);
    }
  }

  Future<void> _registerProvider(String userId) async {
    final idPath = await _uploadDocument(
      userId,
      _identityDocument!,
      'identity',
    );
    final ownershipPath = await _uploadDocument(
      userId,
      _ownershipDocument!,
      'ownership',
    );
    await Supabase.instance.client.rpc('register_provider', params: {
      'p_full_name': _name.text.trim(),
      'p_phone': _normalizePhone(_phone.text)!,
      'p_category': _category,
      'p_business_name': _business.text.trim(),
      'p_city': _city.text.trim(),
      'p_description': _description.text.trim(),
      'p_starting_price': double.parse(_startingPrice.text.trim()),
      'p_max_guests': _category == 'wedding_hall'
          ? int.parse(_maxGuests.text.trim())
          : null,
      'p_deposit_percent': double.parse(_depositPercent.text.trim()),
      'p_id_card_path': idPath,
      'p_ownership_doc_path': ownershipPath,
    });
  }

  Future<String> _uploadDocument(
    String userId,
    PlatformFile file,
    String label,
  ) async {
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw StateError('تعذر قراءة ملف ${file.name}. اختره مرة أخرى.');
    }
    final extension = file.extension?.toLowerCase();
    const mimeTypes = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'webp': 'image/webp',
    };
    final mimeType = mimeTypes[extension];
    if (mimeType == null || bytes.length > 5 * 1024 * 1024) {
      throw StateError(
          'يجب أن تكون الوثيقة صورة JPG أو PNG أو WebP وأقل من 5 ميغابايت.');
    }
    final path =
        '$userId/$label-${DateTime.now().microsecondsSinceEpoch}.$extension';
    await Supabase.instance.client.storage
        .from('provider-documents')
        .uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: FileOptions(contentType: mimeType),
        );
    return path;
  }

  Future<void> _pickDocument(bool identity) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final extension = file.extension?.toLowerCase();
      if (file.bytes == null ||
          file.bytes!.length > 5 * 1024 * 1024 ||
          !const {'jpg', 'jpeg', 'png', 'webp'}.contains(extension)) {
        _showError('اختر صورة JPG أو PNG أو WebP وحجمها لا يتجاوز 5 ميغابايت.');
        return;
      }
      setState(() {
        if (identity) {
          _identityDocument = file;
        } else {
          _ownershipDocument = file;
        }
      });
    } catch (error) {
      _showError('تعذر اختيار الملف: $error');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('الحساب والتحقق'),
          leading: IconButton(
            onPressed: widget.onGuest,
            icon: const Icon(Icons.arrow_back),
            tooltip: 'التصفح كزائر',
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  const Text(
                    'دخول آمن إلى حسابك',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'سجّل الدخول بالبريد الإلكتروني وكلمة المرور. يمكنك التصفح كزائر.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 22),
                  ToggleButtons(
                    isSelected: [_isProvider == false, _isProvider == true],
                    onPressed: (index) => setState(() {
                      _isProvider = index == 1;
                      _error = null;
                      _notice = null;
                    }),
                    children: const [
                      Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20),
                          child: Text('عميل')),
                      Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20),
                          child: Text('مقدم خدمة')),
                    ],
                  ),
                  if (!SupabaseConfig.isSupabaseConfigured) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'تسجيل الدخول والتحقق غير متاحين حتى إعداد SUPABASE_URL وSUPABASE_ANON_KEY. لا تُخزّن الوثائق الحساسة محلياً.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(_isRegistering ? 'إنشاء حساب' : 'تسجيل الدخول',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(() {
                          _isRegistering = !_isRegistering;
                          _notice = null;
                          _error = null;
                        }),
                        child: Text(
                            _isRegistering ? 'لدي حساب' : 'إنشاء حساب جديد'),
                      ),
                    ],
                  ),
                  if (_notice != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _notice!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.green),
                    ),
                  ],
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        if (_isRegistering) _field(_name, 'الاسم الكامل'),
                        _field(
                          _email,
                          'البريد الإلكتروني',
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) {
                            final email = (value ?? '').trim();
                            return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                    .hasMatch(email)
                                ? null
                                : 'أدخل بريداً إلكترونياً صحيحاً.';
                          },
                        ),
                        _field(
                          _password,
                          'كلمة المرور',
                          obscureText: true,
                          validator: (value) => (value ?? '').length < 8
                              ? 'يجب أن تتكون كلمة المرور من 8 أحرف على الأقل.'
                              : null,
                        ),
                        if (_isRegistering) ...[
                          _field(
                            _phone,
                            _isProvider
                                ? 'رقم الهاتف للتواصل مع رمز الدولة'
                                : 'رقم الهاتف (اختياري)',
                            keyboardType: TextInputType.phone,
                            required: _isProvider,
                            validator: (value) {
                              if ((value ?? '').trim().isEmpty &&
                                  !_isProvider) {
                                return null;
                              }
                              return _normalizePhone(value ?? '') == null
                                  ? 'أدخل رقم هاتف بصيغة دولية صحيحة.'
                                  : null;
                            },
                          ),
                          if (_isProvider) ...[
                            _field(_business, 'اسم النشاط'),
                            _field(_city, 'المدينة'),
                            _field(
                              _startingPrice,
                              'السعر الأساسي (ر.ي)',
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                final amount = double.tryParse(value ?? '');
                                return amount == null ||
                                        !amount.isFinite ||
                                        amount <= 0
                                    ? 'أدخل سعراً أساسياً صالحاً.'
                                    : null;
                              },
                            ),
                            if (_category == 'wedding_hall')
                              _field(
                                _maxGuests,
                                'سعة القاعة بالضيوف',
                                keyboardType: TextInputType.number,
                                validator: (value) {
                                  final count = int.tryParse(value ?? '');
                                  return count == null || count < 1
                                      ? 'أدخل سعة صحيحة.'
                                      : null;
                                },
                              ),
                            _field(
                              _depositPercent,
                              'نسبة العربون (%)',
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                final percent = double.tryParse(value ?? '');
                                return percent == null ||
                                        !percent.isFinite ||
                                        percent < 0 ||
                                        percent > 100
                                    ? 'النسبة يجب أن تكون من 0 إلى 100.'
                                    : null;
                              },
                            ),
                            DropdownButtonFormField<String>(
                              value: _category,
                              decoration: const InputDecoration(
                                labelText: 'التخصص',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                    value: 'wedding_hall',
                                    child: Text('قاعة مناسبات')),
                                DropdownMenuItem(
                                    value: 'artist', child: Text('فنان')),
                                DropdownMenuItem(
                                    value: 'photographer', child: Text('مصور')),
                                DropdownMenuItem(
                                    value: 'wedding_service',
                                    child: Text('خدمات أفراح')),
                              ],
                              onChanged: (value) =>
                                  setState(() => _category = value!),
                            ),
                            const SizedBox(height: 12),
                            _field(_description, 'نبذة عن النشاط',
                                required: false),
                            _documentButton(
                              label: 'صورة الهوية',
                              file: _identityDocument,
                              onPressed: () => _pickDocument(true),
                            ),
                            _documentButton(
                              label: 'إثبات ملكية النشاط',
                              file: _ownershipDocument,
                              onPressed: () => _pickDocument(false),
                            ),
                          ],
                        ],
                        const SizedBox(height: 14),
                        _submitButton(
                          label:
                              _isRegistering ? 'إنشاء الحساب' : 'تسجيل الدخول',
                          onPressed: _authenticate,
                        ),
                      ],
                    ),
                  ),
                  if (!_isProvider) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _isBusy || !SupabaseConfig.isSupabaseConfigured
                          ? null
                          : _signInWithGoogle,
                      icon: const Icon(Icons.g_mobiledata, size: 28),
                      label: const Text('المتابعة باستخدام Google'),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                        textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: widget.onGuest,
                    child: const Text('متابعة التصفح كزائر'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
    bool required = true,
    bool obscureText = false,
    String? Function(String?)? validator,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          validator: validator ??
              (value) => required && (value == null || value.trim().isEmpty)
                  ? 'هذا الحقل مطلوب.'
                  : null,
        ),
      );

  Widget _documentButton({
    required String label,
    required PlatformFile? file,
    required VoidCallback onPressed,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(file == null ? Icons.upload_file : Icons.check_circle),
          label: Text(file?.name ?? 'إرفاق $label'),
        ),
      );

  Widget _submitButton({
    required String label,
    required Future<void> Function() onPressed,
  }) =>
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _isBusy || !SupabaseConfig.isSupabaseConfigured
              ? null
              : onPressed,
          child: _isBusy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(label),
        ),
      );
}
