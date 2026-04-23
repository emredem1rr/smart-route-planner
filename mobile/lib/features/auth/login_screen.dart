import 'package:flutter/material.dart';
import '../../core/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../../core/services/auth_service.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/theme/app_theme.dart';
import '../tasks/task_list_screen.dart';
import 'register_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey     = GlobalKey<FormState>();
  final _identCtrl   = TextEditingController();
  final _passCtrl    = TextEditingController();
  final _authService = AuthService();

  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _identCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    final result = await _authService.login(
      identifier: _identCtrl.text.trim(),
      password:   _passCtrl.text,
    );

    setState(() => _loading = false);
    if (!mounted) return;

    if (result['success'] == true) {
      // Onboarding'i bu kullanıcı için tamamlandı olarak işaretle
      final token = await StorageService().getToken() ?? '';
      if (token.length > 8) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('onboarding_done_${token.substring(0, 16)}', true);
      }
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const TaskListScreen()),
            (_) => false,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:         Text(result['error'] ?? 'Giriş başarısız.'),
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 56),

                // ── Logo ────────────────────────────────────
                Center(
                  child: Column(
                    children: [
                      Container(
                        width:  72,
                        height: 72,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                              begin: Alignment.topLeft, end: Alignment.bottomRight),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(
                              color: const Color(0xFF6366F1).withOpacity(0.35),
                              blurRadius: 20, offset: const Offset(0, 8))],
                        ),
                        child: const Icon(
                          Icons.route_rounded,
                          color: Colors.white,
                          size:  36,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        t('app_name'),
                        style: TextStyle(
                          fontSize:      22,
                          fontWeight:    FontWeight.w700,
                          color:         tp,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Rotanı akıllıca planla',
                        style: TextStyle(fontSize: 13, color: ts),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),

                // ── Başlık ──────────────────────────────────
                Text(
                  t('login'),
                  style: TextStyle(
                    fontSize:      24,
                    fontWeight:    FontWeight.w700,
                    color:         tp,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Hesabına giriş yap',
                  style: TextStyle(fontSize: 14, color: ts),
                ),
                const SizedBox(height: 28),

                // ── E-posta / Telefon ───────────────────────
                _buildField(
                  controller: _identCtrl,
                  hintText:   t('email'),
                  prefixIcon: Icons.person_outline_rounded,
                  surf: surf, border: border, tp: tp, ts: ts,
                  validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Zorunlu alan' : null,
                ),
                const SizedBox(height: 14),

                // ── Şifre ───────────────────────────────────
                _buildField(
                  controller:  _passCtrl,
                  hintText:    t('password'),
                  prefixIcon:  Icons.lock_outline_rounded,
                  obscureText: _obscure,
                  surf: surf, border: border, tp: tp, ts: ts,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: ts,
                      size:  20,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  validator: (v) =>
                  (v == null || v.isEmpty) ? 'Zorunlu alan' : null,
                ),
                const SizedBox(height: 8),

                // ── Şifremi Unuttum ─────────────────────────
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ForgotPasswordScreen(),
                      ),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.orange,
                      padding:        EdgeInsets.zero,
                    ),
                    child: Text(
                      t('forgot_password'),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // ── Giriş Butonu ────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _login,
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
                      t('login'),
                      style: const TextStyle(
                        fontSize:   15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // ── Kayıt Ol ────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Hesabın yok mu?  ',
                      style: TextStyle(color: ts, fontSize: 14),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RegisterScreen(),
                        ),
                      ),
                      child: Text(
                        t('register'),
                        style: const TextStyle(
                          color:      AppColors.orange,
                          fontSize:   14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
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
    bool                               obscureText = false,
    Widget?                            suffixIcon,
    String? Function(String?)?         validator,
  }) {
    return TextFormField(
      controller:  controller,
      obscureText: obscureText,
      validator:   validator,
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