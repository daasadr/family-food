import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/auth/auth_screen.dart';
import 'features/calendar/calendar_screen.dart';
import 'features/day/day_screen.dart';
import 'features/home/week_screen.dart';
import 'features/onboarding/family_setup_screen.dart';
import 'features/proposal/proposal_screen.dart';
import 'features/proposal/propose_meal_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/shopping/shopping_list_screen.dart';
import 'features/shopping/shopping_lists_screen.dart';
import 'providers/providers.dart';

/// Přesměrování řídí stav autentizace:
/// nepřihlášen → /auth, přihlášen bez rodiny → /setup, jinak plánovač.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final location = state.matchedLocation;

      if (auth is AuthLoading) return location == '/splash' ? null : '/splash';
      if (auth is Unauthenticated) return location == '/auth' ? null : '/auth';

      final user = (auth as Authenticated).user;
      if (!user.hasFamily) return location == '/setup' ? null : '/setup';

      // Přihlášený člen rodiny nemá co dělat na uvítacích obrazovkách.
      if (location == '/auth' || location == '/setup' || location == '/splash') {
        return '/';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, __) =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(path: '/auth', builder: (_, __) => const AuthScreen()),
      GoRoute(path: '/setup', builder: (_, __) => const FamilySetupScreen()),
      GoRoute(path: '/', builder: (_, __) => const WeekScreen()),
      GoRoute(path: '/calendar', builder: (_, __) => const CalendarScreen()),
      GoRoute(
        path: '/shopping',
        builder: (_, __) => const ShoppingListsScreen(),
        routes: [
          GoRoute(
            path: ':listId',
            builder: (_, state) =>
                ShoppingListScreen(listId: state.pathParameters['listId']!),
          ),
        ],
      ),
      GoRoute(
        path: '/day/:date',
        builder: (_, state) =>
            DayScreen(date: state.pathParameters['date']!),
        routes: [
          GoRoute(
            path: 'slot/:slotId/propose',
            builder: (_, state) => ProposeMealScreen(
              date: state.pathParameters['date']!,
              slotId: state.pathParameters['slotId']!,
            ),
          ),
          GoRoute(
            path: 'proposal/:proposalId',
            builder: (_, state) => ProposalScreen(
              date: state.pathParameters['date']!,
              proposalId: state.pathParameters['proposalId']!,
            ),
          ),
        ],
      ),
      GoRoute(
        path: '/settings',
        builder: (_, __) => const SettingsScreen(),
        routes: [
          GoRoute(
            path: 'family',
            builder: (_, __) => const FamilySettingsScreen(),
          ),
          GoRoute(
            path: 'template',
            builder: (_, __) => const TemplateSettingsScreen(),
          ),
        ],
      ),
    ],
  );
});
