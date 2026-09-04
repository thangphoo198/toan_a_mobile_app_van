import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state/auth_provider.dart';
import 'van_list_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isRegisterPane = false;

  final _loginUser = TextEditingController();
  final _loginPass = TextEditingController();

  final _regUser = TextEditingController();
  final _regEmail = TextEditingController();
  final _regPass = TextEditingController();
  final _regPass2 = TextEditingController();

  @override
  void dispose() {
    _loginUser.dispose();
    _loginPass.dispose();
    _regUser.dispose();
    _regEmail.dispose();
    _regPass.dispose();
    _regPass2.dispose();
    super.dispose();
  }

  Future<void> _doLogin(AuthProvider auth) async {
    final username = _loginUser.text.trim();
    final password = _loginPass.text;
    if (username.isEmpty || password.isEmpty) {
      _showMsg('Vui lòng nhập đầy đủ tên đăng nhập và mật khẩu.');
      return;
    }
    final ok = await auth.login(username, password);
    if (ok && mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const VanListScreen()));
    } else if (mounted) {
      _showMsg(auth.error ?? 'Đăng nhập thất bại.');
    }
  }

  Future<void> _doRegister(AuthProvider auth) async {
    final username = _regUser.text.trim();
    final email = _regEmail.text.trim();
    final password = _regPass.text;
    final password2 = _regPass2.text;

    if (username.length < 3) {
      _showMsg('Tên đăng nhập phải từ 3 ký tự trở lên.');
      return;
    }
    if (!RegExp(r'^[a-zA-Z0-9_.-]+$').hasMatch(username)) {
      _showMsg('Tên đăng nhập chỉ được chứa chữ, số, dấu . _ -');
      return;
    }
    if (password.length < 6) {
      _showMsg('Mật khẩu phải từ 6 ký tự trở lên.');
      return;
    }
    if (password != password2) {
      _showMsg('Mật khẩu nhập lại không khớp.');
      return;
    }

    final ok = await auth.register(username, password, email.isEmpty ? null : email);
    if (ok && mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const VanListScreen()));
    } else if (mounted) {
      _showMsg(auth.error ?? 'Tạo tài khoản thất bại.');
    }
  }

  void _showMsg(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 10)),
                      ],
                    ),
                    child: Image.asset('assets/images/logo.png', width: 220, fit: BoxFit.contain),
                  ),
                  const SizedBox(height: 18),
                  Text('Van Toàn Á', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text('Smart Control Center', style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 32),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Đăng Nhập')),
                      ButtonSegment(value: true, label: Text('Tạo Tài Khoản')),
                    ],
                    selected: {_isRegisterPane},
                    onSelectionChanged: (s) => setState(() => _isRegisterPane = s.first),
                    style: SegmentedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                  ),
                  const SizedBox(height: 24),
                  if (!_isRegisterPane) ...[
                    TextField(
                      controller: _loginUser,
                      decoration: const InputDecoration(labelText: 'Tên đăng nhập', prefixIcon: Icon(Icons.person_outline)),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _loginPass,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Mật khẩu', prefixIcon: Icon(Icons.lock_outline)),
                      onSubmitted: (_) => _doLogin(auth),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: auth.busy ? null : () => _doLogin(auth),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                      child: auth.busy
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Đăng Nhập'),
                    ),
                  ] else ...[
                    TextField(
                      controller: _regUser,
                      decoration: const InputDecoration(labelText: 'Tên đăng nhập (≥3 ký tự)', prefixIcon: Icon(Icons.person_outline)),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _regEmail,
                      decoration: const InputDecoration(labelText: 'Email (tuỳ chọn)', prefixIcon: Icon(Icons.email_outlined)),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _regPass,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Mật khẩu (≥6 ký tự)', prefixIcon: Icon(Icons.lock_outline)),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _regPass2,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Nhập lại mật khẩu', prefixIcon: Icon(Icons.lock_outline)),
                      onSubmitted: (_) => _doRegister(auth),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: auth.busy ? null : () => _doRegister(auth),
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                      child: auth.busy
                          ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Tạo Tài Khoản'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
