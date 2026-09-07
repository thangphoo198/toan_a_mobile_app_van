import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/api_service.dart';
import 'services/prefs_service.dart';
import 'state/auth_provider.dart';
import 'state/theme_provider.dart';
import 'state/van_list_provider.dart';
import 'screens/login_screen.dart';
import 'screens/main_shell.dart';
import 'theme.dart';

void main() {
  runApp(const VanApp());
}

class VanApp extends StatelessWidget {
  const VanApp({super.key});

  @override
  Widget build(BuildContext context) {
    final api = ApiService();
    final prefs = PrefsService();

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider(api: api, prefs: prefs)),
        ChangeNotifierProvider(create: (_) => VanListProvider(api: api)),
        ChangeNotifierProvider(create: (_) => ThemeProvider(prefs: prefs)),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) => MaterialApp(
          title: 'AQUATECHVINA',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeProvider.mode,
          home: const _StartupGate(),
        ),
      ),
    );
  }
}

/// Kiem tra phien dang nhap luc mo app - giong checkExistingSession() trong
/// login.html: neu con token hop le thi vao thang MainShell.
class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<AuthProvider>().tryRestoreSession();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    switch (auth.status) {
      case AuthStatus.unknown:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case AuthStatus.loggedIn:
        return const MainShell();
      case AuthStatus.loggedOut:
        return const LoginScreen();
    }
  }
}
