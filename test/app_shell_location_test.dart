// The app shell reads the current location to highlight the sidebar. It used
// to call `GoRouterState.of`, which only resolves inside a
// `RouteBase.builder` subtree — a page rebuilding after go_router had
// deregistered its state (routine during the redirects that follow sign-in)
// threw, and the error box that replaced the shell blew the surrounding Row
// out by tens of thousands of pixels.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:edumate_pro/widgets/app_shell.dart';

/// Renders the location the same way the sidebar does.
class _Probe extends StatelessWidget {
  const _Probe();

  @override
  Widget build(BuildContext context) =>
      Text(currentLocation(context), textDirection: TextDirection.ltr);
}

void main() {
  GoRouter buildRouter() => GoRouter(
        initialLocation: '/admin',
        routes: [
          GoRoute(path: '/admin', builder: (_, __) => const _Probe()),
          GoRoute(
              path: '/admin/classes/:id', builder: (_, __) => const _Probe()),
        ],
      );

  testWidgets('reports the current location', (tester) async {
    await tester.pumpWidget(MaterialApp.router(routerConfig: buildRouter()));
    expect(find.text('/admin'), findsOneWidget);
  });

  testWidgets('follows navigation, including a detail route',
      (tester) async {
    final router = buildRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    router.go('/admin/classes/abc123');
    await tester.pumpAndSettle();

    // The sidebar highlights by longest prefix, so it needs the real path
    // rather than the route pattern.
    expect(find.text('/admin/classes/abc123'), findsOneWidget);
  });

  testWidgets('degrades quietly when the router cannot be reached',
      (tester) async {
    // `MaterialApp.builder` wraps every page but sits above the router's own
    // inherited widget — the same shape as a rebuild during a redirect,
    // which is what used to throw and take the shell down with it. No
    // highlight is fine here; an exception is not.
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: buildRouter(),
      builder: (context, child) => Column(
        children: [const _Probe(), Expanded(child: child!)],
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text(''), findsOneWidget);
  });

  testWidgets('survives a rebuild during a route swap', (tester) async {
    final router = buildRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    // Drive a redirect-like swap and pump mid-transition: the outgoing page
    // rebuilds here, which is exactly when the old lookup threw.
    router.go('/admin/classes/abc123');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
