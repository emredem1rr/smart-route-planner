import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/settings_provider.dart';
import 'core/services/storage_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/sync_service.dart';
import 'features/auth/login_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/tasks/task_list_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Status bar şeffaf
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor:            Colors.transparent,
    statusBarIconBrightness:   Brightness.dark,
  ));
  await NotificationService().initialize();
  runApp(
    ChangeNotifierProvider(
      create: (_) => SettingsProvider(),
      child:  const SmartRouteApp(),
    ),
  );
}

class SmartRouteApp extends StatelessWidget {
  const SmartRouteApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return MaterialApp(
      title:                      'Smart Route Planner',
      debugShowCheckedModeBanner: false,
      navigatorKey:               navigatorKey,
      theme:                      AppTheme.lightTheme,
      darkTheme:                  AppTheme.darkTheme,
      themeMode:                  settings.themeMode,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('tr', 'TR'),
        Locale('en', 'US'),
      ],
      locale: const Locale('tr', 'TR'),
      home:   const SplashScreen(),
    );
  }
}

// ── Splash Screen ─────────────────────────────────────────────
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {

  // Logo animasyonu
  late final AnimationController _logoCtrl;
  late final Animation<double>    _logoScale;
  late final Animation<double>    _logoFade;

  // Yazı animasyonu
  late final AnimationController _textCtrl;
  late final Animation<double>    _textFade;
  late final Animation<Offset>    _textSlide;

  // Alt yükleme göstergesi
  late final AnimationController _dotCtrl;

  bool   _loggedIn       = false;
  bool   _showOnboarding = false;
  String _userKey        = 'guest';

  @override
  void initState() {
    super.initState();

    // Logo: scale 0.6 → 1.0 + fade
    _logoCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450));
    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(
        CurvedAnimation(parent: _logoCtrl, curve: Curves.elasticOut));
    _logoFade = CurvedAnimation(parent: _logoCtrl, curve: Curves.easeIn);

    // Yazı: aşağıdan yukarı kayar + fade (logo bittikten 200ms sonra)
    _textCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _textFade = CurvedAnimation(parent: _textCtrl, curve: Curves.easeIn);
    _textSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end:   Offset.zero,
    ).animate(CurvedAnimation(parent: _textCtrl, curve: Curves.easeOut));

    // Nokta yükleme animasyonu
    _dotCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat();

    // Sıralı animasyon
    _logoCtrl.forward().then((_) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _textCtrl.forward();
      });
    });

    // Init + minimum gösterim süresi — ikisi paralel, hangisi uzarsa bekle
    Future.wait([
      _init(),
      Future.delayed(const Duration(milliseconds: 1200)), // min görünüm süresi
    ]).then((_) {
      _navigate();
    });
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _textCtrl.dispose();
    _dotCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    SyncService().syncPending().catchError((_) {}); // arka planda

    // Paralel çalıştır — daha hızlı
    final results = await Future.wait([
      StorageService().isLoggedIn(),
      StorageService().getToken(),
      SharedPreferences.getInstance(),
    ]);

    _loggedIn = results[0] as bool;
    final token = (results[1] as String?) ?? 'guest';
    final prefs = results[2] as SharedPreferences;

    // Giriş yapmamış kullanıcı için her zaman onboarding göster
    if (!_loggedIn) {
      _showOnboarding = true;
    } else {
      _userKey = token.length > 8 ? token.substring(0, 16) : token;
      final key = 'onboarding_done_$_userKey';
      _showOnboarding = !(prefs.getBool(key) ?? false);
    }
  }

  void _navigate() {
    if (!mounted) return;
    if (_showOnboarding) {
      Navigator.pushReplacement(context,
          _fadeRoute(const OnboardingScreen()));
    } else {
      Navigator.pushReplacement(context,
          _fadeRoute(_loggedIn ? const TaskListScreen() : const LoginScreen()));
    }
  }

  PageRouteBuilder _fadeRoute(Widget screen) => PageRouteBuilder(
    pageBuilder:       (_, __, ___) => screen,
    transitionsBuilder: (_, anim, __, child) =>
        FadeTransition(opacity: anim, child: child),
    transitionDuration: const Duration(milliseconds: 350),
  );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F0F) : const Color(0xFFFAFAFA),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Logo ──────────────────────────────────────────
            ScaleTransition(
              scale: _logoScale,
              child: FadeTransition(
                opacity: _logoFade,
                child: Container(
                  width:  100,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end:   Alignment.bottomRight,
                      colors: [
                        AppColors.orange,
                        AppColors.orange.withOpacity(0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color:        AppColors.orange.withOpacity(0.35),
                        blurRadius:   32,
                        spreadRadius: 4,
                        offset:       const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.route_rounded,
                    color: Colors.white,
                    size:  50,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),

            // ── Yazı ──────────────────────────────────────────
            SlideTransition(
              position: _textSlide,
              child: FadeTransition(
                opacity: _textFade,
                child: Column(children: [
                  Text(
                    'Smart Route',
                    style: TextStyle(
                      color:         isDark ? Colors.white : const Color(0xFF1A1A1A),
                      fontSize:      30,
                      fontWeight:    FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Planner',
                    style: TextStyle(
                      color:         isDark
                          ? Colors.white.withOpacity(0.5)
                          : const Color(0xFF888888),
                      fontSize:      16,
                      fontWeight:    FontWeight.w400,
                      letterSpacing: 2.0,
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 60),

            // ── Nokta yükleme göstergesi ──────────────────────
            FadeTransition(
              opacity: _textFade,
              child: AnimatedBuilder(
                animation: _dotCtrl,
                builder: (_, __) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(3, (i) {
                      // Her nokta farklı fazda
                      final delay  = i / 3;
                      final value  = ((_dotCtrl.value - delay) % 1.0).abs();
                      final size   = 6.0 + (value < 0.5 ? value * 6 : (1 - value) * 6);
                      final opacity = 0.3 + (value < 0.5 ? value * 0.7 : (1 - value) * 0.7);
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Container(
                          width:  size,
                          height: size,
                          decoration: BoxDecoration(
                            color:  AppColors.orange.withOpacity(opacity),
                            shape:  BoxShape.circle,
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}