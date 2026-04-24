import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/auth_service.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/theme/app_theme.dart';
import 'verify_email_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey     = GlobalKey<FormState>();
  final _nameCtrl    = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _phoneCtrl   = TextEditingController();
  final _passCtrl    = TextEditingController();
  final _authService = AuthService();

  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final result = await _authService.register(
      name:     _nameCtrl.text.trim(),
      email:    _emailCtrl.text.trim(),
      phone:    _phoneCtrl.text.trim(),
      password: _passCtrl.text,
    );

    setState(() => _loading = false);
    if (!mounted) return;

    if (result['success'] == true) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => VerifyEmailScreen(email: _emailCtrl.text.trim()),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:         Text(result['error'] ?? 'Kayıt başarısız.'),
          backgroundColor: AppColors.danger,
          behavior:        SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t      = context.watch<SettingsProvider>().t;
    final bg     = AppColors.bg(context);
    final surf   = AppColors.surface(context);
    final border = AppColors.border(context);
    final tp     = AppColors.textPrimary(context);
    final ts     = AppColors.textSecond(context);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor:  surf,
        elevation:        0,
        surfaceTintColor: Colors.transparent,
        toolbarHeight:    64,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                  color: AppColors.surfaceHigh(context),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: border)),
              child: Icon(Icons.arrow_back_rounded, color: tp, size: 18),
            ),
          ),
        ),
        title: Text(
          t('register'),
          style: TextStyle(
            color:      tp,
            fontSize:   17,
            fontWeight: FontWeight.w600,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: border),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),

              // ── Logo ────────────────────────────────────
              Center(
                child: Column(
                  children: [
                    Container(
                      width:  64,
                      height: 64,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                            begin: Alignment.topLeft, end: Alignment.bottomRight),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [BoxShadow(
                            color: const Color(0xFF6366F1).withOpacity(0.35),
                            blurRadius: 20, offset: const Offset(0, 8))],
                      ),
                      child: const Icon(
                        Icons.route_rounded,
                        color: Colors.white,
                        size:  32,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Hesap Oluştur',
                      style: TextStyle(
                        fontSize:      20,
                        fontWeight:    FontWeight.w700,
                        color:         tp,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Bilgilerini girerek başla',
                      style: TextStyle(fontSize: 13, color: ts),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // ── Ad Soyad ────────────────────────────────
              _SectionLabel(text: t('full_name'), color: ts),
              const SizedBox(height: 8),
              _buildField(
                controller: _nameCtrl,
                hintText:   'Adın ve soyadın',
                prefixIcon: Icons.person_outline_rounded,
                surf: surf, border: border, tp: tp, ts: ts,
                validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Zorunlu alan' : null,
              ),
              const SizedBox(height: 16),

              // ── E-posta ─────────────────────────────────
              _SectionLabel(text: t('email'), color: ts),
              const SizedBox(height: 8),
              _buildField(
                controller:   _emailCtrl,
                hintText:     'ornek@email.com',
                prefixIcon:   Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                surf: surf, border: border, tp: tp, ts: ts,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Zorunlu alan';
                  if (!v.contains('@')) return 'Geçersiz e-posta';
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // ── Telefon ─────────────────────────────────
              _SectionLabel(text: t('phone'), color: ts),
              const SizedBox(height: 8),
              _buildField(
                controller:   _phoneCtrl,
                hintText:     '05xx xxx xx xx',
                prefixIcon:   Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                surf: surf, border: border, tp: tp, ts: ts,
                validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Zorunlu alan' : null,
              ),
              const SizedBox(height: 16),

              // ── Şifre ───────────────────────────────────
              _SectionLabel(text: t('password'), color: ts),
              const SizedBox(height: 8),
              _buildField(
                controller:  _passCtrl,
                hintText:    'En az 6 karakter',
                prefixIcon:  Icons.lock_outline_rounded,
                obscureText: _obscure,
                surf: surf, border: border, tp: tp, ts: ts,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility
                        : Icons.visibility_off,
                    color: ts,
                    size:  20,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Zorunlu alan';
                  if (v.length < 6) return 'En az 6 karakter';
                  return null;
                },
              ),
              const SizedBox(height: 32),

              // ── Kayıt Ol butonu ─────────────────────────
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _register,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:         AppColors.orange,
                    foregroundColor:         Colors.white,
                    disabledBackgroundColor: AppColors.orange.withOpacity(0.5),
                    padding:   const EdgeInsets.symmetric(vertical: 15),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color:       Colors.white,
                    ),
                  )
                      : Text(
                    t('register'),
                    style: const TextStyle(
                      fontSize:   15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController     controller,
    required String                    hintText,
    required IconData                  prefixIcon,
    required Color                     surf,
    required Color                     border,
    required Color                     tp,
    required Color                     ts,
    bool                               obscureText  = false,
    TextInputType?                     keyboardType,
    Widget?                            suffixIcon,
    String? Function(String?)?         validator,
  }) {
    return TextFormField(
      controller:   controller,
      obscureText:  obscureText,
      keyboardType: keyboardType,
      validator:    validator,
      style: TextStyle(color: tp, fontSize: 15),
      decoration: InputDecoration(
        hintText:       hintText,
        hintStyle:      TextStyle(color: ts, fontSize: 14),
        prefixIcon:     Icon(prefixIcon, color: ts, size: 20),
        suffixIcon:     suffixIcon,
        filled:         true,
        fillColor:      surf,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:   BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:   BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.orange, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final Color  color;
  const _SectionLabel({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize:      13,
      fontWeight:    FontWeight.w600,
      color:         color,
      letterSpacing: 0.2,
    ),
  );
}