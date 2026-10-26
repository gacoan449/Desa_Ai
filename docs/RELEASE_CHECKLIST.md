# Checklist Rilis Desa AI

Gunakan project Firebase staging dan kredensial TriPay sandbox terlebih dahulu. Jangan menguji debit/kredit pada akun produksi.

## A. Pemeriksaan source

- [ ] `flutter pub get`
- [ ] `flutter analyze`
- [ ] `cd functions && npm install && node --check index.js && node --check ai.js && node --check payments.js && npm run lint`
- [ ] Jalankan pemeriksaan Firestore Rules pada emulator/test suite sebelum deploy.
- [ ] Review semua perubahan GitHub dan pastikan tidak ada API secret di source, history, APK, atau log.
- [ ] Pastikan `lib/firebase_options.dart` diganti dengan output `flutterfire configure`.
- [ ] Generate Android/Web platform scaffold sebelum menjalankan build platform.

## B. Autentikasi dan akun

- [ ] Registrasi email/password membuat profil dengan saldo tepat Rp0 dan role `user`.
- [ ] Login/logout bekerja; sesi token kadaluarsa ditangani.
- [ ] Google Sign-In diuji pada Android dan Web dengan OAuth IDs / SHA yang tepat.
- [ ] Akun blocked/suspended gagal memanggil endpoint chat dan top-up.
- [ ] Klien tidak bisa mengubah `users.balance`, ledger, usage, ruang chat, pesan, atau payment records.
- [ ] Akun biasa tidak dapat memanggil fungsi admin rekonsiliasi.

## C. Chat dan keamanan AI

- [ ] Model ID aktif diverifikasi lewat API project; tarif input/output/cache diperiksa dengan halaman harga provider.
- [ ] Chat sukses: token stream sampai selesai, pesan assistant disimpan satu kali, usage final tercatat.
- [ ] Saldo di bawah reservasi: request tidak masuk ke moderation/model dan saldo tidak berubah.
- [ ] Moderasi memblokir input yang melanggar kebijakan dan kegagalan moderation menolak request.
- [ ] Rate limit maksimal 5 request per 10 detik diuji.
- [ ] Dua request serentak tidak membuat saldo negatif atau ledger ganda.
- [ ] Provider menolak request sebelum generasi: reservasi dikembalikan tepat satu kali.
- [ ] Putus koneksi setelah provider menerima request: reservasi tidak langsung di-refund.
- [ ] Request pending dengan response ID direkonsiliasi oleh job scheduler.
- [ ] Pending tanpa response ID muncul di antrean admin; jangan refund sebelum verifikasi provider.
- [ ] Refund manual admin memerlukan alasan audit, membuat satu kredit ledger/mutasi, dan membuka ruang yang tertahan.
- [ ] Uji konteks 12.000 token (warning) dan 16.000 token (hard guard). Pastikan riwayat tertua dipangkas otomatis dan batas estimasi konservatif tidak mengirim konteks melewati reservasi.

## D. TriPay / keuangan

- [ ] Daftar channel diambil dari akun merchant dan hanya channel aktif ditampilkan.
- [ ] Invoice sukses menampilkan QR/payment code dan reference.
- [ ] Callback sandbox sukses mengkredit nilai paket, bukan total fee yang dibayar pelanggan.
- [ ] Signature tidak valid: callback ditolak tanpa kredit.
- [ ] Amount/reference mismatch: callback ditolak tanpa kredit.
- [ ] Callback PAID yang sama dikirim dua kali: hanya satu kredit.
- [ ] Callback FAILED/EXPIRED tidak mengkredit.
- [ ] Callback setelah terminal state yang bertentangan ditinjau, bukan dikredit otomatis.
- [ ] `TRIPAY_SANDBOX` tetap true sampai sandbox selesai.
- [ ] Kurs FX, retail multiplier, model rates, fee tool, batas top-up Rp10.000–Rp10.000.000, limit konteks/output dan alert provider diset sebelum transaksi real.

## E. Release platform

- [ ] Generate platform native dan konfigurasi Firebase untuk target Android.
- [ ] `flutter build apk --release` berhasil pada environment release.
- [ ] Install dan uji APK pada perangkat fisik.
- [ ] Uji jaringan lambat, lifecycle app, orientation, streaming, keyboard/composer, navigation drawer dan history.
- [ ] Verifikasi log tidak berisi token ID, prompt sensitif, secret, PIN, atau data pembayaran berlebih.
- [ ] Lakukan review legal/privacy dan backup data sebelum public launch.
