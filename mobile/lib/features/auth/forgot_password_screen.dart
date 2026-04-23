import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/auth_service.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/theme/app_theme.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl   = TextEditingController();
  final _codeCtrl    = TextEditingController();
  final _passCtrl    = TextEditingController();
  final _authService = AuthService();

  bool _loading  = false;
  bool _codeSent = false;
  bool _obscure  = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_emailCtrl.text.trim().isEmpty) return;
    setState(() => _loading = true);

    final result = await _authService.forgotPassword(_emailCtrl.text.trim());

    setState(() => _loading = false);
    if (!mounted) return;

    if (result['success'] == true) {
      setState(() => _codeSent = true);
    } else {
      _showError(result['error'] ?? 'Hata oluştu.');
    }
  }

  Future<void> _resetPassword() async {
    if (_codeCtrl.text.isEmpty || _passCtrl.text.isEmpty) return;
    setState(() => _loading = true);

    final result = await _authService.resetPassword(
      email:       _emailCtrl.text.trim(),
      resetCode:   _codeCtrl.text.trim(),
      newPassword: _passCtrl.text,
    );

    setState(() => _loading = false);
    if (!mounted) return;

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:         const Text('Şifre başarıyla güncellendi.'),
          backgroundColor: AppColors.success,
          behavior:        SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      Navigator.pop(context);
    } else {
      _showError(result['error'] ?? 'Hata oluştu.');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:         Text(msg),
        backgroundColor: AppColors.danger,
        behavior:        SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
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
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: AppColors.surfaceHigh(context),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: border)),
            child: Icon(Icons.arrow_back_rounded, color: tp, size: 18),
          ),
        ),
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.lock_reset_rounded, color: Colors.white, size: 15),
          ),
          const SizedBox(width: 10),
          Text(t('forgot_password'), style: TextStyle(color: tp, fontSize: 16,
              fontWeight: FontWeight.w700, letterSpacing: -0.3)),
        ]),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              Text(t('forgot_password_desc'),
                  style: TextStyle(color: ts, fontSize: 14, height: 1.5)),
              const SizedBox(height: 28),
              Text(t('email'), style: TextStyle(color: ts, fontSize: 12,
                  fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              _buildField(
                controller: _emailCtrl,
                hintText: t('email_hint'),
                prefixIcon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
                surf: surf, border: border, tp: tp, ts: ts,
              ),
              const SizedBox(height: 24),
              SizedBox(width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _sendCode,
                  style: _btnStyle(),
                  child: _loading
                      ? _loader()
                      : Text(t('send_reset_link'),
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
              const SizedBox(height: 20),
              _StepIndicator(step: _codeSent ? 2 : 1, border: border),
            ],
          ),
        ),
      ),
    );
  }

  ButtonStyle _btnStyle() => ElevatedButton.styleFrom(
    backgroundColor:         AppColors.orange,
    foregroundColor:         Colors.white,
    disabledBackgroundColor: AppColors.orange.withOpacity(0.5),
    padding:   const EdgeInsets.symmetric(vertical: 15),
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
  );

  Widget _loader() => const SizedBox(
    width: 20, height: 20,
    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
  );

  Widget _buildField({
    required TextEditingController controller,
    required String                hintText,
    required IconData              prefixIcon,
    required Color                 surf,
    required Color                 border,
    required Color                 tp,
    required Color                 ts,
    bool                           obscureText  = false,
    bool                           enabled      = true,
    TextInputType?                 keyboardType,
    Widget?                        suffixIcon,
  }) {
    return TextField(
      controller:   controller,
      obscureText:  obscureText,
      keyboardType: keyboardType,
      enabled:      enabled,
      style: TextStyle(color: tp, fontSize: 15),
      decoration: InputDecoration(
        hintText:       hintText,
        hintStyle:      TextStyle(color: ts, fontSize: 14),
        prefixIcon:     Icon(
          prefixIcon,
          color: enabled ? ts : ts.withOpacity(0.4),
          size:  20,
        ),
        suffixIcon:     suffixIcon,
        filled:         true,
        fillColor:      enabled ? surf : surf.withOpacity(0.5),
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
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:   BorderSide(color: border.withOpacity(0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.orange, width: 1.5),
        ),
      ),
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

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

class _StepIndicator extends StatelessWidget {
  final int   step;
  final Color border;
  const _StepIndicator({required this.step, required this.border});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _dot(1),
      Expanded(
        child: Divider(
          color:     step >= 2 ? AppColors.orange : border,
          thickness: 1.5,
        ),
      ),
      _dot(2),
    ],
  );

  Widget _dot(int n) {
    final active = step >= n;
    return Container(
      width:  28, height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? AppColors.orange : Colors.transparent,
        border: Border.all(
          color: active ? AppColors.orange : border,
          width: 1.5,
        ),
      ),
      child: Center(
        child: Text(
          '$n',
          style: TextStyle(
            fontSize:   12,
            fontWeight: FontWeight.w600,
            color:      active ? Colors.white : border,
          ),
        ),
      ),
    );
  }
}