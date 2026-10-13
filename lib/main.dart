import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/database/glance_db.dart';
import 'screens/splash/splash.dart';
import 'screens/onboarding/onboarding.dart';
import 'screens/permission/permission.dart';
import 'screens/home/home.dart';
import 'screens/timeline/timeline.dart';
import 'screens/collection/collection.dart';
import 'screens/capture/capture.dart';
import 'screens/settings/settings.dart';
import 'screens/search/search_screen.dart';
import 'screens/model_download/model_download_screen.dart';
import 'main_layout.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize shared preferences & offline SQLite database
  await SharedPreferences.getInstance();
  await GlanceDatabase.instance.initialize();
  
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

// GlobalKey for root navigator
final GlobalKey<NavigatorState> _rootNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter _router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/splash',
  routes: <RouteBase>[
    GoRoute(
      path: '/splash',
      builder: (BuildContext context, GoRouterState state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (BuildContext context, GoRouterState state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: '/permission',
      builder: (BuildContext context, GoRouterState state) => const PermissionScreen(),
    ),
    GoRoute(
      path: '/search',
      builder: (BuildContext context, GoRouterState state) => const SearchScreen(),
    ),
    GoRoute(
      path: '/model-download',
      builder: (BuildContext context, GoRouterState state) => const ModelDownloadScreen(),
    ),
    StatefulShellRoute.indexedStack(
      builder: (BuildContext context, GoRouterState state, StatefulNavigationShell navigationShell) {
        return MainLayout(navigationShell: navigationShell);
      },
      branches: <StatefulShellBranch>[
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/home',
              builder: (BuildContext context, GoRouterState state) => const HomeScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/timeline',
              builder: (BuildContext context, GoRouterState state) => const TimelineScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/capture',
              builder: (BuildContext context, GoRouterState state) => const CaptureScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/collection',
              builder: (BuildContext context, GoRouterState state) => const CollectionScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: <RouteBase>[
            GoRoute(
              path: '/settings',
              builder: (BuildContext context, GoRouterState state) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: _router,
      title: 'Glance App',
      theme: ThemeData(
        fontFamily: 'DMSans',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3478F6),
          surfaceTint: Colors.transparent,
        ),
        appBarTheme: const AppBarTheme(
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
          ),
          titleTextStyle: TextStyle(
            fontFamily: 'PlaywriteAR',
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(0xFF111418),
          ),
        ),
        useMaterial3: true,
      ),
    );
  }
}
