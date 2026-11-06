import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const _green = Color(0xFF157A52);
const _ink = Color(0xFF18251F);
const _adminWhatsApp = 'https://wa.me/6285642131263';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _busy = false;
  bool _registerMode = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _ensureProfile(User user) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (snapshot.exists) return;
      transaction.set(ref, {
        'uid': user.uid,
        'name': user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : (user.email?.split('@').first ?? 'Pengguna Desa AI'),
        'displayName': user.displayName ?? '',
        'email': user.email ?? '',
        'phone': user.phoneNumber ?? '',
        'balance': 0,
        'role': 'user',
        'status': 'Aktif',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'photoUrl': user.photoURL ?? '',
      });
    });
  }

  String _authError(FirebaseAuthException error) {
    return switch (error.code) {
      'invalid-email' => 'Format email tidak valid.',
      'user-disabled' => 'Akun ini dinonaktifkan. Hubungi admin.',
      'user-not-found' => 'Email belum terdaftar.',
      'wrong-password' || 'invalid-credential' => 'Email atau password salah.',
      'email-already-in-use' => 'Email sudah terdaftar. Silakan masuk.',
      'weak-password' => 'Password terlalu lemah. Gunakan minimal 6 karakter.',
      'too-many-requests' => 'Terlalu banyak percobaan. Coba beberapa saat lagi.',
      'network-request-failed' => 'Koneksi internet bermasalah. Periksa jaringan Anda.',
      'operation-not-allowed' => 'Login Email/Password belum diaktifkan di Firebase Console.',
      _ => error.message ?? 'Autentikasi gagal. Silakan coba lagi.',
    };
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (_busy || !_formKey.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    User? user;
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      final credential = _registerMode
          ? await FirebaseAuth.instance.createUserWithEmailAndPassword(
              email: email, password: password)
          : await FirebaseAuth.instance.signInWithEmailAndPassword(
              email: email, password: password);
      user = credential.user;
      if (user != null) {
        try {
          await _ensureProfile(user);
        } catch (_) {
          await FirebaseAuth.instance.signOut();
          rethrow;
        }
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) setState(() => _error = _authError(error));
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Akun berhasil diautentikasi, tetapi profil belum dapat disiapkan. Periksa koneksi lalu hubungi admin jika berulang.');
      }
      if (user != null) {
        try { await FirebaseAuth.instance.signOut(); } catch (_) {}
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _contactAdmin() async {
    final uri = Uri.parse(_adminWhatsApp);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        setState(() => _error = 'WhatsApp tidak dapat dibuka. Simpan nomor admin: 085642131263.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'WhatsApp tidak dapat dibuka. Simpan nomor admin: 085642131263.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width > 760;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? 900 : 460),
              child: wide
                  ? Row(children: [
                      Expanded(child: _welcomePanel()),
                      const SizedBox(width: 42),
                      Expanded(child: _loginPanel()),
                    ])
                  : _loginPanel(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _welcomePanel() => Container(
    height: 500,
    padding: const EdgeInsets.all(34),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(30),
      gradient: const LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFF133D2D), Color(0xFF157A52), Color(0xFF3E9B73)],
      ),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: .14), borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.auto_awesome_rounded, color: Colors.white),
        ),
        const SizedBox(width: 12),
        const Text('Desa AI', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
      ]),
      const Spacer(),
      const Text('Satu ruang.\nBanyak kemungkinan.', style: TextStyle(color: Colors.white, fontSize: 34, height: 1.15, fontWeight: FontWeight.w800)),
      const SizedBox(height: 16),
      Text('Teman berpikir untuk belajar, bekerja, mencari ide, dan menyelesaikan hal sehari-hari.',
        style: TextStyle(color: Colors.white.withValues(alpha: .82), fontSize: 15, height: 1.55)),
      const SizedBox(height: 28),
      const _FeatureLine(icon: Icons.bolt_rounded, text: 'Jawaban streaming dan penggunaan transparan'),
      const SizedBox(height: 14),
      const _FeatureLine(icon: Icons.account_balance_wallet_outlined, text: 'Saldo rupiah dan biaya per token'),
      const SizedBox(height: 14),
      const _FeatureLine(icon: Icons.extension_outlined, text: 'Plugin sesuai kebutuhan'),
      const Spacer(),
      Text('Dirancang untuk pengguna Indonesia.', style: TextStyle(color: Colors.white.withValues(alpha: .72), fontSize: 12)),
    ]),
  );

  Widget _loginPanel() => Container(
    padding: const EdgeInsets.all(26),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26), border: Border.all(color: const Color(0xFFE8ECE8))),
    child: Form(
      key: _formKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (MediaQuery.sizeOf(context).width <= 760) ...[
          Center(child: Container(
            width: 64, height: 64,
            decoration: BoxDecoration(color: const Color(0xFFE5F3EB), borderRadius: BorderRadius.circular(19)),
            child: const Icon(Icons.auto_awesome_rounded, color: _green, size: 32),
          )),
          const SizedBox(height: 12),
          const Center(child: Text('Desa AI', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: _ink))),
        ],
        Text(_registerMode ? 'Buat akun Desa AI' : 'Masuk ke Desa AI',
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: _ink)),
        const SizedBox(height: 8),
        Text(_registerMode
            ? 'Daftar menggunakan alamat email dan buat password.'
            : 'Masukkan email dan password akun Desa AI Anda.',
          style: const TextStyle(color: Color(0xFF758078), height: 1.45)),
        const SizedBox(height: 22),
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(
            labelText: 'Email',
            hintText: 'nama@email.com',
            prefixIcon: Icon(Icons.email_outlined),
          ),
          validator: (value) {
            final email = (value ?? '').trim();
            if (email.isEmpty) return 'Email wajib diisi.';
            if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) return 'Masukkan alamat email yang valid.';
            return null;
          },
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.done,
          autofillHints: _registerMode
              ? const [AutofillHints.newPassword]
              : const [AutofillHints.password],
          onFieldSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              tooltip: _obscurePassword ? 'Tampilkan password' : 'Sembunyikan password',
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            ),
          ),
          validator: (value) {
            if ((value ?? '').isEmpty) return 'Password wajib diisi.';
            if (_registerMode && value!.length < 6) return 'Password minimal 6 karakter.';
            return null;
          },
        ),
        if (!_registerMode) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _busy ? null : _contactAdmin,
              child: const Text('Lupa password? Hubungi Admin'),
            ),
          ),
        ] else
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Text('Gunakan password minimal 6 karakter dan simpan dengan aman.',
              style: TextStyle(color: Color(0xFF758078), fontSize: 12)),
          ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFFF0EF), borderRadius: BorderRadius.circular(12)),
            child: Text(_error!, style: const TextStyle(color: Color(0xFFB42318), fontSize: 12, height: 1.4)),
          ),
        ],
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: _busy
                ? const SizedBox(width: 21, height: 21, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(_registerMode ? 'Daftar akun' : 'Masuk'),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _busy ? null : () => setState(() {
            _registerMode = !_registerMode;
            _error = null;
          }),
          child: Text(_registerMode
              ? 'Sudah punya akun? Masuk'
              : 'Belum punya akun? Daftar sekarang'),
        ),
        const SizedBox(height: 8),
        const Text('Login aman menggunakan Firebase Email/Password.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF9AA29C), fontSize: 11, height: 1.5)),
      ]),
    ),
  );
}

class _FeatureLine extends StatelessWidget {
  const _FeatureLine({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, color: Colors.white, size: 19),
    const SizedBox(width: 12),
    Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500))),
  ]);
}
