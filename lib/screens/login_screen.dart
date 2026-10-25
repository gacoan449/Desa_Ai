import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../main.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  bool _isRegister = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _ensureProfile(User user, {String? name}) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (snapshot.exists) return;
      transaction.set(ref, {
        'uid': user.uid,
        'name': (name?.trim().isNotEmpty == true ? name!.trim() : user.displayName ?? 'Pengguna Desa AI'),
        'displayName': user.displayName ?? name ?? '',
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      final auth = FirebaseAuth.instance;
      UserCredential result;
      if (_isRegister) {
        result = await auth.createUserWithEmailAndPassword(email: _email.text.trim(), password: _password.text);
        await result.user?.updateDisplayName(_name.text.trim());
        if (result.user != null) await _ensureProfile(result.user!, name: _name.text);
      } else {
        result = await auth.signInWithEmailAndPassword(email: _email.text.trim(), password: _password.text);
        if (result.user != null) await _ensureProfile(result.user!);
      }
    } on FirebaseAuthException catch (error) {
      _showError(switch (error.code) {
        'invalid-email' => 'Format email tidak valid.',
        'user-not-found' || 'wrong-password' || 'invalid-credential' => 'Email atau kata sandi salah.',
        'email-already-in-use' => 'Email sudah terdaftar. Silakan masuk.',
        'weak-password' => 'Gunakan kata sandi minimal 6 karakter.',
        'network-request-failed' => 'Periksa koneksi internet Anda.',
        _ => error.message ?? 'Autentikasi gagal.',
      });
    } catch (error) {
      _showError('Tidak dapat menyiapkan profil: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _googleSignIn() async {
    setState(() { _busy = true; _error = null; });
    try {
      final googleUser = await GoogleSignIn(scopes: const ['email']).signIn();
      if (googleUser == null) return;
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final result = await FirebaseAuth.instance.signInWithCredential(credential);
      if (result.user != null) await _ensureProfile(result.user!);
    } catch (error) {
      _showError('Google Sign-In gagal. Periksa konfigurasi OAuth Firebase. $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String value) {
    if (mounted) setState(() => _error = value);
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
                  ? Row(
                      children: [
                        Expanded(child: _welcomePanel()),
                        const SizedBox(width: 42),
                        Expanded(child: _formPanel()),
                      ],
                    )
                  : _formPanel(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _welcomePanel() => Container(
    height: 570,
    padding: const EdgeInsets.all(34),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(30),
      gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [Color(0xFF133D2D), Color(0xFF157A52), Color(0xFF3E9B73)]),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 42, height: 42, decoration: BoxDecoration(color: Colors.white.withOpacity(.14), borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.auto_awesome_rounded, color: Colors.white)),
        const SizedBox(width: 12),
        const Text('Desa AI', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
      ]),
      const Spacer(),
      const Text('Satu ruang.\nBanyak kemungkinan.', style: TextStyle(color: Colors.white, fontSize: 34, height: 1.15, fontWeight: FontWeight.w800)),
      const SizedBox(height: 16),
      Text('Teman berpikir untuk belajar, bekerja, mencari ide, dan menyelesaikan hal sehari-hari.',
        style: TextStyle(color: Colors.white.withOpacity(.82), fontSize: 15, height: 1.55)),
      const SizedBox(height: 28),
      const _FeatureLine(icon: Icons.bolt_rounded, text: 'Jawaban streaming dan penggunaan transparan'),
      const SizedBox(height: 14),
      const _FeatureLine(icon: Icons.account_balance_wallet_outlined, text: 'Saldo rupiah dan biaya per token'),
      const SizedBox(height: 14),
      const _FeatureLine(icon: Icons.extension_outlined, text: 'Plugin yang diaktifkan sesuai kebutuhan'),
      const Spacer(),
      Text('Dirancang untuk pengguna Indonesia.', style: TextStyle(color: Colors.white.withOpacity(.72), fontSize: 12)),
    ]),
  );

  Widget _formPanel() => Container(
    padding: const EdgeInsets.all(26),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(26), border: Border.all(color: const Color(0xFFE8ECE8))),
    child: Form(
      key: _formKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (MediaQuery.sizeOf(context).width <= 760) ...[
          Center(child: Container(width: 60, height: 60,
            decoration: BoxDecoration(color: const Color(0xFFE5F3EB), borderRadius: BorderRadius.circular(19)),
            child: const Icon(Icons.auto_awesome_rounded, color: DesaAiApp.green, size: 30))),
          const SizedBox(height: 12),
          const Center(child: Text('Desa AI', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: DesaAiApp.ink))),
        ],
        Text(_isRegister ? 'Buat akun Anda' : 'Selamat datang kembali',
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: DesaAiApp.ink)),
        const SizedBox(height: 7),
        Text(_isRegister ? 'Mulai obrolan AI dengan biaya yang transparan.' : 'Masuk untuk melanjutkan ruang obrolan Anda.',
          style: const TextStyle(color: Color(0xFF758078), height: 1.45)),
        const SizedBox(height: 24),
        if (_isRegister) ...[
          TextFormField(controller: _name, textInputAction: TextInputAction.next, decoration: const InputDecoration(labelText: 'Nama lengkap', prefixIcon: Icon(Icons.person_outline_rounded)),
            validator: (value) => (value == null || value.trim().length < 2) ? 'Masukkan nama Anda.' : null),
          const SizedBox(height: 13),
        ],
        TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded)),
          validator: (value) => (value == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim())) ? 'Masukkan email yang valid.' : null),
        const SizedBox(height: 13),
        TextFormField(controller: _password, obscureText: _obscure, textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _busy ? null : _submit(),
          decoration: InputDecoration(labelText: 'Kata sandi', prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(onPressed: () => setState(() => _obscure = !_obscure), icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined))),
          validator: (value) => (value == null || value.length < 6) ? 'Minimal 6 karakter.' : null),
        if (_error != null) ...[
          const SizedBox(height: 13),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFFFF0EF), borderRadius: BorderRadius.circular(12)),
            child: Text(_error!, style: const TextStyle(color: Color(0xFFB42318), fontSize: 12, height: 1.4))),
        ],
        const SizedBox(height: 18),
        FilledButton(onPressed: _busy ? null : _submit,
          child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(_isRegister ? 'Buat akun' : 'Masuk')),
        const SizedBox(height: 12),
        OutlinedButton.icon(onPressed: _busy ? null : _googleSignIn,
          icon: const Icon(Icons.g_mobiledata_rounded, size: 28), label: const Text('Lanjutkan dengan Google')),
        const SizedBox(height: 18),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(_isRegister ? 'Sudah punya akun? ' : 'Belum punya akun? ', style: const TextStyle(color: Color(0xFF758078), fontSize: 13)),
          TextButton(onPressed: _busy ? null : () => setState(() { _isRegister = !_isRegister; _error = null; }),
            child: Text(_isRegister ? 'Masuk' : 'Daftar', style: const TextStyle(fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 4),
        const Text('Dengan masuk, saldo dan riwayat chat Anda dikelola secara aman oleh server.',
          textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF9AA29C), fontSize: 10, height: 1.4)),
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
