import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/auth_service.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/theme/app_theme.dart';
import '../tasks/task_list_screen.dart';

class VerifyEmailScreen extends StatefulWidget {
  final String email;
  const VerifyEmailScreen({super.key, required this.email});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final _codeCtrl    = TextEditingController();
  final _authService = AuthService();
  bool  _loading     = false;
  bool  _resending   = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_codeCtrl.text.trim().isEmpty) return;
    setState(() => _loading = true);

    final result = await _authService.verifyEmail(
      email: widget.email,
      code:  _codeCtrl.text.trim(),
    );

    setState(() => _loading = false);
    if (!mounted) return;

    if (result['success'] == true) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const TaskListScreen()),
            (_) => false,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:         Text(result['error'] ?? 'Doğrulama başarısız.'),
          backgroundColor: AppColors.danger,
          behavior:        SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    await _authService.resendVerification(widget.email);
    setState(() => _resending = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:         const Text('Kod tekrar gönderildi.'),
        backgroundColor: AppColors.success,
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
        title: Row(children: [
          Container(width: 30, height: 30,
              decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.mark_email_read_rounded, color: Colors.white, size: 15)),
          const SizedBox(width: 10),
          Expanded(child: Text(t('verify'), style: TextStyle(color: tp, fontSize: 16,
              fontWeight: FontWeight.w700, letterSpacing: -0.3))),
        ]),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: border),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 48),

            // ── İkon + Açıklama ──────────────────────────
            Center(
              child: Column(
                children: [
                  Container(
                    width:  72,
                    height: 72,
                    decoration: BoxDecoration(
                      color:        AppColors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.mark_email_read_outlined,
                      color: AppColors.orange,
                      size:  36,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'E-postanı doğrula',
                    style: TextStyle(
                      fontSize:      22,
                      fontWeight:    FontWeight.w700,
                      color:         tp,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Gönderilen kodu gir',
                    style: TextStyle(fontSize: 14, color: ts),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color:        AppColors.orange.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      widget.email,
                      style: const TextStyle(
                        color:      AppColors.orange,
                        fontSize:   13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),

            // ── Kod alanı ────────────────────────────────
            TextField(
              controller:   _codeCtrl,
              keyboardType: TextInputType.number,
              textAlign:    TextAlign.center,
              style: TextStyle(
                fontSize:      28,
                letterSpacing: 12,
                fontWeight:    FontWeight.w700,
                color:         tp,
              ),
              decoration: InputDecoration(
                hintText:  '------',
                hintStyle: TextStyle(
                  fontSize:      28,
                  letterSpacing: 12,
                  color:         border,
                  fontWeight:    FontWeight.w700,
                ),
                filled:         true,
                fillColor:      surf,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 18,
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
                  borderSide: const BorderSide(
                    color: AppColors.orange, width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),

            // ── Doğrula butonu ───────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _verify,
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
                  t('verify'),
                  style: const TextStyle(
                    fontSize:   15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Tekrar Gönder ────────────────────────────
            Center(
              child: TextButton(
                onPressed: _resending ? null : _resend,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.orange,
                ),
                child: _resending
                    ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color:       AppColors.orange,
                  ),
                )
                    : Text(
                  'Kodu tekrar gönder',
                  style: TextStyle(fontSize: 14, color: ts),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}