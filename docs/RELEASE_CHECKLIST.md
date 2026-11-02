# Checklist Rilis Desa AI

Gunakan project Firebase staging dan kredensial TriPay sandbox terlebih dahulu. Jangan menguji debit/kredit pada akun produksi.

## A. Konfigurasi wajib sebelum release build

- [ ] `lib/firebase_options.dart` Android mengarah ke project `desaai-dfe30` dan package ID `com.desaai.app`.
- [ ] Aktifkan Firebase Authentication > Google provider.
- [ ] Pastikan Android app `com.desaai.app` terdaftar di Firebase.
- [ ] Buat/ambil keystore permanen. Jika aplikasi pernah didistribusikan, gunakan upload key yang sesuai dengan konfigurasi Play Console; jangan membuat key baru sembarangan.
- [ ] Daftarkan SHA-1 dan SHA-256 dari keystore permanen ke Firebase Console > Project settings > Android app. Client OAuth Web untuk Google Sign-In sudah ditentukan eksplisit pada aplikasi; fingerprint Android tetap harus cocok.
- [ ] Tambahkan GitHub Actions secrets: `DESAAI_API_BASE_URL`, `DESAAI_KEYSTORE_BASE64`, `DESAAI_KEYSTORE_PASSWORD`, `DESAAI_KEY_ALIAS`, `DESAAI_KEY_PASSWORD`.
- [ ] `DESAAI_API_BASE_URL` harus URL HTTPS backend Express yang benar, tanpa `example.invalid`.
- [ ] Jangan commit file keystore, key.properties, service-account JSON, .env, atau rahasia provider.
- [ ] Simpan backup keystore dan password di dua tempat aman yang terpisah. Kehilangan signing key dapat menghambat pembaruan aplikasi.
- [ ] Backend VPS harus menggunakan `GOOGLE_CLOUD_PROJECT=desaai-dfe30`, service account dengan izin minimum, `OPENAI_API_KEY`, kredensial TriPay, `PUBLIC_API_BASE_URL`, dan `CRON_SECRET`.

Contoh membuat keystore baru untuk aplikasi yang belum pernah dirilis:

```bash
keytool -genkeypair -v -keystore desaai-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias desaai
keytool -list -v -keystore desaai-release.jks -alias desaai
```

Encode file keystore menjadi satu baris Base64 sebelum memasukkannya ke secret `DESAAI_KEYSTORE_BASE64`. Jangan mengirim keystore atau password melalui chat.

## B. Pemeriksaan source dan CI

- [ ] `flutter pub get`
- [ ] `flutter analyze`
- [ ] `cd functions && npm install && npm run check && npm run lint`
- [ ] Jalankan `npm run test:emulator` melalui Firestore Emulator.
- [ ] Dua reservasi saldo bersamaan tidak membuat saldo negatif atau ledger ganda.
- [ ] Review semua perubahan GitHub dan pastikan tidak ada API secret di source, history, APK, atau log.
- [ ] Pull request hanya menjalankan analyze; release APK hanya dibuat pada push/dispatch ketika URL backend dan signing secrets tersedia.
- [ ] Pastikan APK release memakai `com.desaai.app` dan sertifikat permanen yang sama pada setiap build.

## C. Autentikasi dan akun

- [ ] Login Google diuji pada Android dengan SHA-1/SHA-256 keystore permanen.
- [ ] Profil dibuat dengan saldo tepat Rp0 dan role `user`.
- [ ] Login/logout bekerja; token kadaluarsa dan kegagalan provisioning profil ditangani.
- [ ] Akun blocked/suspended gagal memanggil endpoint chat dan top-up.
- [ ] Akun dengan `billingHold=true` tidak dapat memakai AI, tetapi tetap dapat melakukan top-up untuk menyelesaikan kewajiban.
- [ ] Klien tidak bisa mengubah saldo, ledger, usage, ruang chat, pesan, atau payment records.
- [ ] Akun biasa tidak dapat memanggil fungsi admin rekonsiliasi dan penyelesaian kewajiban.

## D. Chat dan keamanan AI

- [ ] Model ID aktif dan tarif provider diverifikasi terhadap akun API aktual.
- [ ] Snapshot harga input/output/cache, kurs, multiplier, dan biaya pencarian disimpan pada saat reservasi.
- [ ] Perubahan tarif admin saat request berjalan tidak mengubah tarif transaksi yang sedang diproses.
- [ ] Chat sukses: token stream sampai selesai, pesan assistant disimpan satu kali, usage final tercatat.
- [ ] Saldo di bawah reservasi: request tidak masuk ke moderation/model dan saldo tidak berubah.
- [ ] Moderasi gagal: request ditolak sebelum dikirim ke model.
- [ ] Rate limit maksimal 5 request per 10 detik diuji.
- [ ] Provider menolak request sebelum generasi: reservasi dikembalikan tepat satu kali.
- [ ] Putus koneksi setelah provider menerima request: reservasi tidak langsung di-refund.
- [ ] Pending dengan response ID direkonsiliasi oleh job scheduler.
- [ ] Pending tanpa response ID masuk antrean admin; jangan refund sebelum verifikasi provider.
- [ ] Kekurangan biaya provider dicatat sebagai `ai_billing_obligations`, akun ditahan dari penggunaan AI, dan penyelesaian admin membuat debit ledger idempoten.
- [ ] Refund manual admin memerlukan alasan audit dan bukti provider tidak menagih.

## E. TriPay / keuangan

- [ ] Setiap invoice memiliki record `CREATING` dan lock per pengguna sebelum request dikirim ke provider.
- [ ] Timeout atau HTTP 5xx saat pembuatan invoice menghasilkan `CREATE_UNKNOWN` dan tidak membuka invoice duplikat.
- [ ] Invoice sukses disimpan sebagai `UNPAID` dengan reference, total amount, dan expiry.
- [ ] Channel aktif dan batas minimum/maksimum divalidasi server.
- [ ] Callback HMAC, reference, dan nominal diverifikasi.
- [ ] Callback PAID berulang hanya mengkredit satu kali.
- [ ] Callback REFUND setelah PAID membuat kewajiban pemeriksaan; callback TriPay tidak menyediakan field nominal refund terpisah, jadi nominal tidak boleh ditebak.
- [ ] Admin memverifikasi nominal refund di dashboard TriPay, lalu mengirim verifiedRefundAmountIdr dan providerVerifiedRefundAmount=true untuk pembalikan idempoten.
- [ ] Jika saldo tidak cukup untuk pembalikan refund, kewajiban tetap terbuka dan penggunaan AI ditahan.
- [ ] Callback FAILED/EXPIRED tidak mengkredit.
- [ ] Callback status terminal yang bertentangan ditolak untuk pemeriksaan.
- [ ] `TRIPAY_SANDBOX=true` sampai seluruh tes sandbox selesai.
- [ ] Rekonsiliasi transaksi provider dan ledger dilakukan sebelum transaksi real.

## F. Release platform

- [ ] Flutter analyze dan backend checks lulus.
- [ ] Release APK dibangun dengan URL backend HTTPS dan signing permanen.
- [ ] `apksigner verify` berhasil dan fingerprint sesuai Firebase OAuth.
- [ ] Install dan uji APK pada perangkat fisik.
- [ ] Uji jaringan lambat, lifecycle app, streaming, keyboard/composer, navigasi, dan riwayat.
- [ ] Verifikasi log tidak berisi token ID, prompt sensitif, secret, PIN, atau data pembayaran berlebih.
- [ ] Review legal/privacy, penghapusan data, dan backup sebelum public launch.

## G. Endpoint admin baru

- `POST /aiAdminListBillingObligations` — daftar kewajiban terbuka.
- `POST /aiAdminSettleBillingObligation` — selesaikan kewajiban setelah saldo cukup; wajib menyertakan alasan audit minimal 20 karakter.
- `POST /aiAdminListPendingTopups` — daftar invoice dengan status pembuatan tidak pasti.
- `POST /aiAdminResolveUnknownTopup` — tutup invoice tidak pasti hanya setelah admin memverifikasi ke TriPay bahwa invoice memang tidak pernah dibuat.
