import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/providers/settings_provider.dart';
import '../../core/services/offline_map_service.dart';
import '../auth/login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();

  Map<String, dynamic>? _profile;
  bool   _loading   = true;
  String _photoPath = ''; // Yerel fotoğraf yolu

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadPhoto();
  }

  Future<void> _loadPhoto() async {
    final prefs = await SharedPreferences.getInstance();
    final path  = prefs.getString('profile_photo') ?? '';
    if (path.isNotEmpty && File(path).existsSync()) {
      setState(() => _photoPath = path);
    }
  }

  Future<void> _pickPhoto() async {
    // Galeri mi kamera mı sor
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface(context),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) {
        final tp = AppColors.textPrimary(context);
        final ts = AppColors.textSecond(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.border(context),
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Text('Fotoğraf Seç', style: TextStyle(
                  color: tp, fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.photo_library_rounded,
                        color: Color(0xFF6366F1), size: 20)),
                title: Text('Galeriden Seç',
                    style: TextStyle(color: tp, fontWeight: FontWeight.w600)),
                subtitle: Text('Telefonundaki fotoğraflardan seç',
                    style: TextStyle(color: ts, fontSize: 12)),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              ListTile(
                leading: Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.camera_alt_rounded,
                        color: Color(0xFF6366F1), size: 20)),
                title: Text('Kamera ile Çek',
                    style: TextStyle(color: tp, fontWeight: FontWeight.w600)),
                subtitle: Text('Şu an fotoğraf çek',
                    style: TextStyle(color: ts, fontSize: 12)),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              const SizedBox(height: 8),
            ]),
          ),
        );
      },
    );

    if (source == null) return;

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source:       source,
        maxWidth:     512,
        maxHeight:    512,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profile_photo', picked.path);
      setState(() => _photoPath = picked.path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Profil fotoğrafı güncellendi'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Fotoğraf seçilemedi: $e'),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    final result = await _authService.getProfile();
    setState(() {
      _profile = result['success'] == true ? result['user'] : null;
      _loading = false;
    });
  }

  Future<void> _editProfile() async {
    if (_profile == null) return;
    final updated = await Navigator.push<bool>(context,
        MaterialPageRoute(builder: (_) => EditProfileScreen(profile: _profile!)));
    if (updated == true) await _loadProfile();
  }

  Future<void> _changePassword() async => Navigator.push(context,
      MaterialPageRoute(builder: (_) => const ChangePasswordScreen()));

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(context: context,
        builder: (_) => _DeleteAccountDialog(authService: _authService));
    if (confirmed == true && mounted) {
      Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
    }
  }

  Future<void> _downloadOfflineMap() async {
    // Kullanıcının şu anki konumu veya Türkiye merkezi
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setD) {
          int done = 0, total = 1;

          OfflineMapService.cacheTilesForArea(
            centerLat: 39.9208, centerLng: 32.8541,
            minZoom:  10,
            maxZoom:  14,
            radiusKm: 50,
            onProgress: (d, t) => setD(() { done = d; total = t; }),
          ).then((_) => Navigator.pop(ctx));

          return AlertDialog(
            backgroundColor: AppColors.surface(context),
            title: Text('Harita İndiriliyor',
                style: TextStyle(color: AppColors.textPrimary(context),
                    fontWeight: FontWeight.w700)),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Çevrimdışı kullanım için harita tile kareleri indiriliyor...',
                  style: TextStyle(color: AppColors.textSecond(context),
                      fontSize: 13)),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value:            total > 0 ? done / total : 0,
                color:            AppColors.orange,
                backgroundColor:  AppColors.border(context),
              ),
              const SizedBox(height: 8),
              Text('$done / $total',
                  style: TextStyle(color: AppColors.textSecond(context),
                      fontSize: 12)),
            ]),
          );
        },
      ),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:         const Text('Harita önbelleğe alındı'),
        backgroundColor: AppColors.success,
        behavior:        SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _clearMapCache() async {
    await OfflineMapService.clearCache();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:         const Text('Harita önbelleği temizlendi'),
        backgroundColor: AppColors.warn,
        behavior:        SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final bg     = AppColors.bg(context);
    final surf   = AppColors.surface(context);
    final border = AppColors.border(context);
    final tp     = AppColors.textPrimary(context);
    final ts     = AppColors.textSecond(context);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surf, elevation: 0, surfaceTintColor: Colors.transparent,
        toolbarHeight: 64,
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
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.person_rounded, color: Colors.white, size: 15),
          ),
          const SizedBox(width: 10),
          Text('Profil', style: TextStyle(color: tp, fontSize: 16,
              fontWeight: FontWeight.w700, letterSpacing: -0.3)),
        ]),
        actions: [
          if (_profile != null)
            IconButton(icon: Icon(Icons.edit_outlined, color: tp),
                tooltip: 'Düzenle', onPressed: _editProfile),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: border)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.orange))
          : _profile == null
          ? Center(child: Text('Profil yüklenemedi.', style: TextStyle(color: ts)))
          : _buildBody(context, surf, border, tp, ts),
    );
  }

  Widget _buildBody(BuildContext context, Color surf, Color border, Color tp, Color ts) {
    final name    = _profile!['name']  as String? ?? '';
    final email   = _profile!['email'] as String? ?? '';
    final phone   = _profile!['phone'] as String? ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [

        // ── Avatar ────────────────────────────────────
        Center(child: Column(children: [
          GestureDetector(
            onTap: _pickPhoto,
            child: Stack(children: [
              Container(
                width: 90, height: 90,
                decoration: BoxDecoration(
                  color:  AppColors.orange,
                  shape:  BoxShape.circle,
                  border: Border.all(color: AppColors.orange.withOpacity(0.3), width: 3),
                  image:  _photoPath.isNotEmpty
                      ? DecorationImage(
                    image: FileImage(File(_photoPath)),
                    fit:   BoxFit.cover,
                  )
                      : null,
                ),
                child: _photoPath.isEmpty
                    ? Center(child: Text(initial,
                    style: const TextStyle(fontSize: 34, color: Colors.white,
                        fontWeight: FontWeight.w700)))
                    : null,
              ),
              // Kamera ikonu overlay
              Positioned(
                right: 0, bottom: 0,
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color:  AppColors.orange,
                    shape:  BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: const Icon(Icons.camera_alt_rounded,
                      color: Colors.white, size: 14),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _pickPhoto,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.orange,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            ),
            child: const Text('Fotoğrafı Değiştir',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 4),
          Text(name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
              color: tp, letterSpacing: -0.3)),
          const SizedBox(height: 4),
          Text(email, style: TextStyle(color: ts, fontSize: 14)),
        ])),
        const SizedBox(height: 28),

        // ── Bilgiler ──────────────────────────────────
        _Section(surf: surf, border: border, children: [
          _InfoTile(icon: Icons.person_outline_rounded, label: 'Ad Soyad', value: name,
              surf: surf, border: border, tp: tp, ts: ts),
          _Divider(border: border),
          _InfoTile(icon: Icons.email_outlined, label: 'E-posta', value: email,
              surf: surf, border: border, tp: tp, ts: ts),
          _Divider(border: border),
          _InfoTile(icon: Icons.phone_outlined, label: 'Telefon',
              value: phone.isNotEmpty ? phone : 'Eklenmemiş',
              surf: surf, border: border, tp: tp, ts: ts),
        ]),
        const SizedBox(height: 16),

        // ── Ayarlar (sadece karanlık mod) ─────────────
        _Section(surf: surf, border: border, children: [
          Consumer<SettingsProvider>(
            builder: (context, settings, _) => _SettingsTile(
              icon: settings.isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
              label: 'Karanlık Mod',
              surf: surf, border: border, tp: tp, ts: ts,
              trailing: Switch(
                value:              settings.isDark,
                onChanged:          settings.toggleDark,
                activeColor:        AppColors.orange,
                inactiveThumbColor: ts,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 16),

        // ── Çevrimdışı Harita ────────────────────────
        _Section(surf: surf, border: border, children: [
          _ActionTile(
            icon:   Icons.download_for_offline_rounded,
            label:  'Harita Önbelleği İndir',
            color:  AppColors.info,
            surf:   surf, border: border, ts: ts,
            onTap:  _downloadOfflineMap,
          ),
          _Divider(border: border),
          _ActionTile(
            icon:   Icons.delete_sweep_outlined,
            label:  'Harita Önbelleğini Temizle',
            color:  AppColors.warn,
            surf:   surf, border: border, ts: ts,
            onTap:  _clearMapCache,
          ),
        ]),
        const SizedBox(height: 16),

        // ── Aksiyonlar ────────────────────────────────
        _Section(surf: surf, border: border, children: [
          _ActionTile(icon: Icons.lock_outline_rounded, label: 'Şifre Değiştir',
              color: AppColors.info, onTap: _changePassword,
              surf: surf, border: border, ts: ts),
          _Divider(border: border),
          _ActionTile(icon: Icons.logout_rounded, label: 'Çıkış Yap',
              color: AppColors.warn, onTap: _logout,
              surf: surf, border: border, ts: ts),
          _Divider(border: border),
          _ActionTile(icon: Icons.delete_forever_outlined, label: 'Hesabı Sil',
              color: AppColors.danger, onTap: _deleteAccount,
              surf: surf, border: border, ts: ts),
        ]),
        const SizedBox(height: 32),
      ]),
    );
  }
}

// ── Edit Profile Screen ───────────────────────────────────────────────────────

class EditProfileScreen extends StatefulWidget {
  final Map<String, dynamic> profile;
  const EditProfileScreen({super.key, required this.profile});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  final AuthService _authService = AuthService();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl  = TextEditingController(text: widget.profile['name']  ?? '');
    _phoneCtrl = TextEditingController(text: widget.profile['phone'] ?? '');
  }

  @override
  void dispose() { _nameCtrl.dispose(); _phoneCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) return;
    setState(() => _loading = true);
    final result = await _authService.updateProfile(
        name: _nameCtrl.text.trim(), phone: _phoneCtrl.text.trim());
    setState(() => _loading = false);
    if (!mounted) return;
    if (result['success'] == true) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['error'] ?? 'Güncelleme başarısız.'),
        backgroundColor: AppColors.danger, behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg     = AppColors.bg(context);
    final surf   = AppColors.surface(context);
    final border = AppColors.border(context);
    final tp     = AppColors.textPrimary(context);
    final ts     = AppColors.textSecond(context);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surf, elevation: 0, surfaceTintColor: Colors.transparent,
        toolbarHeight: 64,
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
              child: Icon(Icons.close_rounded, color: tp, size: 18),
            ),
          ),
        ),
        title: Text('Profili Düzenle',
            style: TextStyle(color: tp, fontSize: 17, fontWeight: FontWeight.w600)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton(
              onPressed: _loading ? null : _save,
              style: TextButton.styleFrom(
                backgroundColor: AppColors.orange, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Kaydet',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            ),
          ),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: border)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 8),
          _SectionLabel(text: 'Ad Soyad', color: ts),
          const SizedBox(height: 8),
          _buildField(controller: _nameCtrl, hintText: 'Ad Soyad',
              prefixIcon: Icons.person_outline_rounded,
              surf: surf, border: border, tp: tp, ts: ts),
          const SizedBox(height: 16),
          _SectionLabel(text: 'Telefon', color: ts),
          const SizedBox(height: 8),
          _buildField(controller: _phoneCtrl, hintText: '05xx xxx xx xx',
              prefixIcon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              surf: surf, border: border, tp: tp, ts: ts),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.orange, foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.orange.withOpacity(0.5),
                padding: const EdgeInsets.symmetric(vertical: 15),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _loading
                  ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Kaydet',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String   hintText,
    required IconData prefixIcon,
    required Color    surf, border, tp, ts,
    TextInputType?    keyboardType,
  }) => TextField(
    controller: controller, keyboardType: keyboardType,
    style: TextStyle(color: tp, fontSize: 15),
    decoration: InputDecoration(
      hintText: hintText, hintStyle: TextStyle(color: ts, fontSize: 14),
      prefixIcon: Icon(prefixIcon, color: ts, size: 20),
      filled: true, fillColor: surf,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border:        OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.orange, width: 1.5)),
    ),
  );
}

// ── Change Password Screen ────────────────────────────────────────────────────

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentCtrl = TextEditingController();
  final _newCtrl     = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _authService = AuthService();
  bool  _loading     = false;
  bool  _ob1 = true, _ob2 = true, _ob3 = true;

  @override
  void dispose() {
    _currentCtrl.dispose(); _newCtrl.dispose(); _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_newCtrl.text != _confirmCtrl.text) { _snackErr('Yeni şifreler eşleşmiyor.'); return; }
    if (_newCtrl.text.length < 6) { _snackErr('Şifre en az 6 karakter olmalı.'); return; }
    setState(() => _loading = true);
    final result = await _authService.changePassword(
        currentPassword: _currentCtrl.text, newPassword: _newCtrl.text);
    setState(() => _loading = false);
    if (!mounted) return;
    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Şifre başarıyla güncellendi.'),
        backgroundColor: AppColors.success, behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
      Navigator.pop(context);
    } else {
      _snackErr(result['error'] ?? 'Hata oluştu.');
    }
  }

  void _snackErr(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg), backgroundColor: AppColors.danger,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  ));

  @override
  Widget build(BuildContext context) {
    final bg     = AppColors.bg(context);
    final surf   = AppColors.surface(context);
    final border = AppColors.border(context);
    final tp     = AppColors.textPrimary(context);
    final ts     = AppColors.textSecond(context);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surf, elevation: 0, surfaceTintColor: Colors.transparent,
        toolbarHeight: 64,
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
        title: Text('Şifre Değiştir',
            style: TextStyle(color: tp, fontSize: 17, fontWeight: FontWeight.w600)),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: border)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 8),
          _SectionLabel(text: 'Mevcut Şifre', color: ts),
          const SizedBox(height: 8),
          _pwField(_currentCtrl, 'Mevcut şifre', _ob1,
                  () => setState(() => _ob1 = !_ob1), surf, border, tp, ts),
          const SizedBox(height: 16),
          _SectionLabel(text: 'Yeni Şifre', color: ts),
          const SizedBox(height: 8),
          _pwField(_newCtrl, 'Yeni şifre', _ob2,
                  () => setState(() => _ob2 = !_ob2), surf, border, tp, ts),
          const SizedBox(height: 16),
          _SectionLabel(text: 'Yeni Şifre (tekrar)', color: ts),
          const SizedBox(height: 8),
          _pwField(_confirmCtrl, 'Yeni şifre tekrar', _ob3,
                  () => setState(() => _ob3 = !_ob3), surf, border, tp, ts),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.orange, foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.orange.withOpacity(0.5),
                padding: const EdgeInsets.symmetric(vertical: 15), elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _loading
                  ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Şifreyi Güncelle',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _pwField(TextEditingController ctrl, String hint, bool obscure,
      VoidCallback toggle, Color surf, Color border, Color tp, Color ts) =>
      TextField(
        controller: ctrl, obscureText: obscure,
        style: TextStyle(color: tp, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint, hintStyle: TextStyle(color: ts, fontSize: 14),
          prefixIcon: Icon(Icons.lock_outline_rounded, color: ts, size: 20),
          suffixIcon: IconButton(
            icon: Icon(obscure ? Icons.visibility : Icons.visibility_off, color: ts, size: 20),
            onPressed: toggle,
          ),
          filled: true, fillColor: surf,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          border:        OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.orange, width: 1.5)),
        ),
      );
}

// ── Delete Account Dialog ─────────────────────────────────────────────────────

class _DeleteAccountDialog extends StatefulWidget {
  final AuthService authService;
  const _DeleteAccountDialog({required this.authService});
  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _passCtrl = TextEditingController();
  bool  _loading  = false;

  @override
  void dispose() { _passCtrl.dispose(); super.dispose(); }

  Future<void> _confirm() async {
    if (_passCtrl.text.isEmpty) return;
    setState(() => _loading = true);
    final result = await widget.authService.deleteAccount(_passCtrl.text);
    setState(() => _loading = false);
    if (!mounted) return;
    if (result['success'] == true) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['error'] ?? 'Hata oluştu.'),
        backgroundColor: AppColors.danger, behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final surf   = AppColors.surface(context);
    final tp     = AppColors.textPrimary(context);
    final ts     = AppColors.textSecond(context);
    final border = AppColors.border(context);

    return AlertDialog(
      backgroundColor: surf,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Hesabı Sil',
          style: TextStyle(color: tp, fontWeight: FontWeight.w700)),
      content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.danger.withOpacity(0.2)),
              ),
              child: const Row(children: [
                Icon(Icons.warning_amber_rounded, color: AppColors.danger, size: 18),
                SizedBox(width: 8),
                Expanded(child: Text('Bu işlem geri alınamaz.',
                    style: TextStyle(color: AppColors.danger, fontSize: 13))),
              ]),
            ),
            const SizedBox(height: 16),
            Text('Onaylamak için şifrenizi girin:', style: TextStyle(color: ts, fontSize: 13)),
            const SizedBox(height: 10),
            TextField(
              controller: _passCtrl, obscureText: true,
              style: TextStyle(color: tp, fontSize: 15),
              decoration: InputDecoration(
                hintText: 'Şifre', hintStyle: TextStyle(color: ts, fontSize: 14),
                prefixIcon: Icon(Icons.lock_outline_rounded, color: ts, size: 20),
                filled: true, fillColor: AppColors.bg(context),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                border:        OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.orange, width: 1.5)),
              ),
            ),
          ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          style: TextButton.styleFrom(foregroundColor: ts),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.danger, foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onPressed: _loading ? null : _confirm,
          child: _loading
              ? const SizedBox(width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Sil'),
        ),
      ],
    );
  }
}

// ── Shared Widgets ────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final List<Widget> children;
  final Color surf, border;
  const _Section({required this.children, required this.surf, required this.border});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: surf, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border)),
    child: Column(children: children),
  );
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String   label, value;
  final Color    surf, border, tp, ts;
  const _InfoTile({required this.icon, required this.label, required this.value,
    required this.surf, required this.border, required this.tp, required this.ts});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(children: [
      Icon(icon, color: AppColors.orange, size: 20),
      const SizedBox(width: 14),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 11, color: ts)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: tp)),
      ]),
    ]),
  );
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Widget   trailing;
  final Color    surf, border, tp, ts;
  const _SettingsTile({required this.icon, required this.label, required this.trailing,
    required this.surf, required this.border, required this.tp, required this.ts});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Row(children: [
      Icon(icon, color: AppColors.orange, size: 20),
      const SizedBox(width: 14),
      Expanded(child: Text(label, style: TextStyle(fontSize: 15, color: tp))),
      trailing,
    ]),
  );
}

class _ActionTile extends StatelessWidget {
  final IconData icon; final String label; final Color color, surf, border, ts;
  final VoidCallback onTap;
  const _ActionTile({required this.icon, required this.label, required this.color,
    required this.onTap, required this.surf, required this.border, required this.ts});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(14),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 14),
        Expanded(child: Text(label,
            style: TextStyle(fontSize: 15, color: color, fontWeight: FontWeight.w500))),
        Icon(Icons.chevron_right, color: ts, size: 18),
      ]),
    ),
  );
}

class _Divider extends StatelessWidget {
  final Color border;
  const _Divider({required this.border});
  @override
  Widget build(BuildContext context) => Divider(height: 1, indent: 50, color: border);
}

class _SectionLabel extends StatelessWidget {
  final String text; final Color color;
  const _SectionLabel({required this.text, required this.color});
  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
          color: color, letterSpacing: 0.2));
}