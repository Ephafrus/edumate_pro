import 'package:go_router/go_router.dart';

import '../models/enums.dart';
import '../screens/admin/admin_applications_screen.dart';
import '../screens/admin/admin_application_detail_screen.dart';
import '../screens/admin/admin_chat_requests_screen.dart';
import '../screens/admin/admin_classes_screen.dart';
import '../screens/admin/admin_home_screen.dart';
import '../screens/admin/admin_learners_screen.dart';
import '../screens/admin/admin_payments_screen.dart';
import '../screens/admin/admin_staff_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/chat/chat_list_screen.dart';
import '../screens/chat/chat_thread_screen.dart';
import '../screens/chat/new_chat_screen.dart';
import '../screens/common/landing_screen.dart';
import '../screens/common/profile_screen.dart';
import '../screens/common/settings_screen.dart';
import '../screens/parent/application_detail_screen.dart';
import '../screens/parent/application_wizard_screen.dart';
import '../screens/parent/parent_home_screen.dart';
import '../screens/parent/parent_payments_screen.dart';
import '../screens/staff/scan_screen.dart';
import '../screens/teacher/teacher_class_screen.dart';
import '../screens/teacher/teacher_home_screen.dart';
import '../state/auth_controller.dart';

/// Route paths, referenced from navigation so there are no magic strings.
class Routes {
  static const landing = '/';
  static const login = '/login';
  static const profile = '/profile';
  static const settings = '/settings';

  static const parentHome = '/parent';
  static const apply = '/parent/apply';
  static const parentPayments = '/parent/payments';
  static String applicationDetail(String id) => '/parent/applications/$id';

  static const teacherHome = '/teacher';
  static String teacherClass(String id) => '/teacher/class/$id';

  static const adminHome = '/admin';
  static const adminStaff = '/admin/staff';
  static const adminClasses = '/admin/classes';
  static const adminLearners = '/admin/learners';
  static const adminApplications = '/admin/applications';
  static String adminApplicationDetail(String id) => '/admin/applications/$id';
  static const adminPayments = '/admin/payments';
  static const adminChatRequests = '/admin/chat-requests';

  static const chats = '/chats';
  static const newChat = '/chats/new';
  static String chatThread(String id) => '/chats/$id';

  /// QR attendance scanner — teachers and all school staff.
  static const scan = '/scan';
}

/// Home path for a given role + profile-completion state.
String homeFor(UserRole? role, bool needsProfile) {
  if (needsProfile) return Routes.profile;
  switch (role) {
    case UserRole.parent:
      return Routes.parentHome;
    case UserRole.teacher:
      return Routes.teacherHome;
    case UserRole.admin:
      return Routes.adminHome;
    case null:
      return Routes.login;
  }
}

GoRouter createRouter(AuthController auth) {
  return GoRouter(
    initialLocation: Routes.landing,
    refreshListenable: auth,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final authed = auth.isAuthenticated;
      final role = auth.role;

      // ---- Unauthenticated: only public pages ----------------------------
      if (!authed) {
        const public = {Routes.landing, Routes.login, Routes.settings};
        return public.contains(loc) ? null : Routes.login;
      }

      // ---- Authenticated --------------------------------------------------
      final home = homeFor(role, auth.needsProfile);

      // Bounce away from the login page once signed in.
      if (loc == Routes.login) return home;

      // Everyone completes a profile first (staff arrive pre-filled from
      // their invite; parents fill it in before applying for a child).
      if (auth.needsProfile &&
          loc != Routes.profile &&
          loc != Routes.settings) {
        return Routes.profile;
      }

      // Role guards — each role stays inside its own area (+ shared routes).
      switch (role) {
        case UserRole.parent:
          if (loc.startsWith('/admin') ||
              loc.startsWith('/teacher') ||
              loc == Routes.scan) {
            return home;
          }
          break;
        case UserRole.teacher:
          if (loc.startsWith('/admin') || loc.startsWith('/parent')) {
            return home;
          }
          break;
        case UserRole.admin:
          if (loc.startsWith('/parent') || loc.startsWith('/teacher')) {
            return home;
          }
          break;
        case null:
          break;
      }
      return null;
    },
    routes: [
      GoRoute(path: Routes.landing, builder: (_, __) => const LandingScreen()),
      GoRoute(path: Routes.login, builder: (_, __) => const LoginScreen()),
      GoRoute(path: Routes.profile, builder: (_, __) => const ProfileScreen()),
      GoRoute(
          path: Routes.settings, builder: (_, __) => const SettingsScreen()),

      // Parent
      GoRoute(
          path: Routes.parentHome,
          builder: (_, __) => const ParentHomeScreen()),
      GoRoute(
        path: Routes.apply,
        builder: (_, state) => ApplicationWizardScreen(
            applicationId: state.uri.queryParameters['id']),
      ),
      GoRoute(
          path: Routes.parentPayments,
          builder: (_, __) => const ParentPaymentsScreen()),
      GoRoute(
        path: '/parent/applications/:id',
        builder: (_, state) =>
            ApplicationDetailScreen(applicationId: state.pathParameters['id']!),
      ),

      // Teacher
      GoRoute(
          path: Routes.teacherHome,
          builder: (_, __) => const TeacherHomeScreen()),
      GoRoute(
        path: '/teacher/class/:id',
        builder: (_, state) =>
            TeacherClassScreen(classId: state.pathParameters['id']!),
      ),

      // Admin
      GoRoute(
          path: Routes.adminHome, builder: (_, __) => const AdminHomeScreen()),
      GoRoute(
          path: Routes.adminStaff,
          builder: (_, __) => const AdminStaffScreen()),
      GoRoute(
          path: Routes.adminClasses,
          builder: (_, __) => const AdminClassesScreen()),
      GoRoute(
          path: Routes.adminLearners,
          builder: (_, __) => const AdminLearnersScreen()),
      GoRoute(
          path: Routes.adminApplications,
          builder: (_, __) => const AdminApplicationsScreen()),
      GoRoute(
        path: '/admin/applications/:id',
        builder: (_, state) => AdminApplicationDetailScreen(
            applicationId: state.pathParameters['id']!),
      ),
      GoRoute(
          path: Routes.adminPayments,
          builder: (_, __) => const AdminPaymentsScreen()),
      GoRoute(
          path: Routes.adminChatRequests,
          builder: (_, __) => const AdminChatRequestsScreen()),

      // QR attendance scanner (staff only, guarded above)
      GoRoute(path: Routes.scan, builder: (_, __) => const ScanScreen()),

      // Chat (all roles). `/chats/new` is declared before `/chats/:id` so the
      // literal segment wins.
      GoRoute(path: Routes.chats, builder: (_, __) => const ChatListScreen()),
      GoRoute(path: Routes.newChat, builder: (_, __) => const NewChatScreen()),
      GoRoute(
        path: '/chats/:id',
        builder: (_, state) =>
            ChatThreadScreen(chatId: state.pathParameters['id']!),
      ),
    ],
  );
}
