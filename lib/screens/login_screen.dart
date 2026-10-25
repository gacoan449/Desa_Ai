import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

const _green = Color(0xFF157A52);
const _ink = Color(0xFF18251F);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _ensureProfile(User user) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      if (snapshot.exists) return;
      transaction.set(ref, {
        'uid': user.uid,
        'name': user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : 'Pengguna Desa AI',
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

  Future<void> _googleSignIn() async {
    if (_busy) return;
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
    } on FirebaseAuthException catch (error) {
      if (mounted) setState(() {
        _error = switch (error.code) {
          'account-exists-with-different-credential' => 'Akun sudah terhubung dengan metode masuk lain.',
          'network-request-failed' => 'Periksa koneksi internet Anda.',
          'user-disabled' => 'Akun ini dinonaktifkan.',
          _ => error.message ?? 'Login Google gagal.',
        };
      });
    } catch (error) {
      if (mounted) setState(() {
        _error = 'Login Google gagal. Periksa provider Google dan OAuth Firebase. $error';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
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
      const Text('Masuk ke Desa AI', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: _ink)),
      const SizedBox(height: 8),
      const Text('Gunakan akun Google untuk melanjutkan ke ruang kerja AI Anda.', style: TextStyle(color: Color(0xFF758078), height: 1.45)),
      const SizedBox(height: 24),
      if (_error != null) ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFFF0EF), borderRadius: BorderRadius.circular(12)),
          child: Text(_error!, style: const TextStyle(color: Color(0xFFB42318), fontSize: 12, height: 1.4)),
        ),
        const SizedBox(height: 14),
      ],
      OutlinedButton.icon(
        onPressed: _busy ? null : _googleSignIn,
        icon: const Icon(Icons.g_mobiledata_rounded, size: 30),
        label: const Text('Lanjutkan dengan Google'),
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
      ),
      if (_busy) ...[
        const SizedBox(height: 18),
        const Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))),
      ],
      const SizedBox(height: 18),
      const Text('Nama dan foto profil diambil dari akun Google. Desa AI tidak meminta kata sandi Google Anda.',
        textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF9AA29C), fontSize: 11, height: 1.5)),
    ]),
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
