import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/storage_service.dart';
import '../../core/theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../tasks/task_list_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final _ctrl = PageController();
  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;
  int _page = 0;

  static const _pages = [
    _OBPage(
      emoji:    '🗺️',
      title:    'Akıllı Rota Planlama',
      subtitle: 'Günlük görevlerini en verimli sırayla planla. Yapay zeka destekli algoritmalar en kısa rotayı senin için bulur.',
      color:    Color(0xFF6366F1),
    ),
    _OBPage(
      emoji:    '📍',
      title:    'Konum Bazlı Hatırlatma',
      subtitle: 'Bir göreve yaklaştığında otomatik bildirim al. "Markete 300m kaldı!" gibi akıllı uyarılarla hiçbir görevi kaçırma.',
      color:    Color(0xFF3D9CF5),
    ),
    _OBPage(
      emoji:    '🏙️',
      title:    'Şehir Keşfet',
      subtitle: 'Bulunduğun şehirde restoran, müze, park ve daha fazlasını keşfet. AI destekli önerilerle yeni yerler bul.',
      color:    Color(0xFF4CAF50),
    ),
    _OBPage(
      emoji:    '📊',
      title:    'İstatistik & Analiz',
      subtitle: 'Haftalık tamamlama oranın, streakın ve öncelik dağılımın. Verimlilik alışkanlığı kazan.',
      color:    Color(0xFF9C27B0),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  // Onboarding'i bitir ve bir sonraki ekrana git
  Future<void> _finish() async {
    final prefs    = await SharedPreferences.getInstance();
    final token    = await StorageService().getToken() ?? '';
    final loggedIn = token.isNotEmpty;

    // Sadece giriş yapmış kullanıcı için kaydet
    if (loggedIn && token.length > 8) {
      final key = 'onboarding_done_${token.substring(0, 16)}';
      await prefs.setBool(key, true);
    }
    // Giriş yapmamışsa login sonrası tekrar kontrol edilecek (main.dart'ta)

    if (!mounted) return;

    if (!mounted) return;

    // Stack'i tamamen temizle, yeni ekrana git
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder:        (_, __, ___) =>
        loggedIn ? const TaskListScreen() : const LoginScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 350),
      ),
          (route) => false, // tüm stack'i temizle
    );
  }

  void _next() {
    if (_page < _pages.length - 1) {
      _animCtrl.reset();
      _ctrl.nextPage(
          duration: const Duration(milliseconds: 350),
          curve:    Curves.easeInOut);
      _animCtrl.forward();
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _pages[_page];
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: page.color.withOpacity(0.06),
      body: SafeArea(
        child: Column(children: [
          // Atla
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 12, 16, 0),
              child: TextButton(
                onPressed: _finish,
                child: Text('Atla',
                    style: TextStyle(
                        color: AppColors.textSecond(context),
                        fontSize: 14)),
              ),
            ),
          ),

          // Sayfa içeriği
          Expanded(
            child: PageView.builder(
              controller:    _ctrl,
              onPageChanged: (i) {
                setState(() => _page = i);
                _animCtrl.reset();
                _animCtrl.forward();
              },
              itemCount:   _pages.length,
              itemBuilder: (_, i) => _buildPage(_pages[i], size),
            ),
          ),

          // Dots + buton
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 40),
            child: Column(children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pages.length, (i) {
                  final sel = i == _page;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin:   const EdgeInsets.symmetric(horizontal: 4),
                    width:    sel ? 24 : 8,
                    height:   8,
                    decoration: BoxDecoration(
                      color:        sel
                          ? page.color
                          : page.color.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: page.color,
                    foregroundColor: Colors.white,
                    padding:   const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(
                    _page == _pages.length - 1 ? 'Başlayalım! 🚀' : 'İleri',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildPage(_OBPage p, Size size) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 130, height: 130,
              decoration: BoxDecoration(
                color:  p.color.withOpacity(0.12),
                shape:  BoxShape.circle,
                border: Border.all(color: p.color.withOpacity(0.25), width: 2),
              ),
              child: Center(
                child: Text(p.emoji,
                    style: const TextStyle(fontSize: 56)),
              ),
            ),
            const SizedBox(height: 40),
            Text(p.title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize:   26,
                  fontWeight: FontWeight.w800,
                  color:      AppColors.textPrimary(context),
                  height:     1.2,
                )),
            const SizedBox(height: 16),
            Text(p.subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color:    AppColors.textSecond(context),
                  height:   1.6,
                )),
          ],
        ),
      ),
    );
  }
}

class _OBPage {
  final String emoji, title, subtitle;
  final Color  color;
  const _OBPage({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.color,
  });
}