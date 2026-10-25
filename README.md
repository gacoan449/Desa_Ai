# Desa AI

Aplikasi Flutter ruang obrolan AI dengan login Google saja, riwayat chat, pilihan model, plugin, saldo rupiah, dan top-up TriPay. Backend berjalan sebagai **Node.js + Express API di server/VPS**, bukan Firebase Cloud Functions. Firebase tetap dipakai untuk Authentication dan Cloud Firestore; API memakai Firebase Admin SDK untuk memverifikasi token dan mengakses data.

> **Status:** source dan CI sedang diperbaiki. Sebelum dipakai pengguna nyata, wajib memasukkan konfigurasi Firebase yang valid, men-deploy backend Express ke server HTTPS, mengatur secret, dan menguji OpenAI serta TriPay sandbox. Jangan anggap layanan sudah aktif hanya karena APK berhasil dibangun.

## Komponen

- Flutter Android client.
- Firebase Authentication dengan **Google Sign-In sebagai satu-satunya metode login**.
- Cloud Firestore untuk profil, riwayat, ledger dan transaksi.
- Node.js/Express backend di folder `functions/` (folder dipertahankan untuk migrasi historis; proses ini **tidak** menggunakan Firebase Functions).
- OpenAI Responses API melalui backend; API key tidak pernah dimasukkan ke APK.
- TriPay untuk invoice top-up dan callback bertanda tangan.

## Menjalankan backend di VPS

Persyaratan: Node.js 20+, Firebase project dengan Authentication dan Firestore aktif, akun service untuk Firebase Admin SDK, OpenAI API key, dan kredensial TriPay sandbox.

1. Buat service account dengan izin minimum yang diperlukan untuk Authentication/Firestore. Simpan JSON di luar repository; jangan pernah commit file tersebut.
2. Salin `functions/.env.example` menjadi `functions/.env`, lalu isi nilai di environment server/secret manager. Jangan commit `.env`.
3. Atur `GOOGLE_APPLICATION_CREDENTIALS` ke lokasi service-account JSON dan `GOOGLE_CLOUD_PROJECT` ke project Firebase yang benar.
4. Dari folder `functions`, jalankan:

   ```bash
   npm install
   npm run check
   npm start
   ```

5. Pasang reverse proxy HTTPS (misalnya Nginx/Caddy) di depan port 8080. Set `PUBLIC_API_BASE_URL` ke URL HTTPS publik tersebut.
6. Batasi `ALLOWED_ORIGINS` ke origin web yang benar jika web client digunakan. Untuk Android native, request tidak membutuhkan browser origin.
7. Jalankan `POST /_internal/reconcile` melalui cron setiap 10 menit dengan header `Authorization: Bearer <CRON_SECRET>`. Jangan buka secret cron ke aplikasi.
8. Daftarkan URL `https://API-ANDA/aiTripayCallback` pada pengaturan callback merchant jika dashboard TriPay memerlukannya. Backend juga mengirim URL callback itu saat membuat invoice.

Variabel server wajib: `OPENAI_API_KEY`, `TRIPAY_API_KEY`, `TRIPAY_MERCHANT_CODE`, `TRIPAY_PRIVATE_KEY`, `PUBLIC_API_BASE_URL`, `GOOGLE_CLOUD_PROJECT`, `GOOGLE_APPLICATION_CREDENTIALS`, dan `CRON_SECRET`. `TRIPAY_SANDBOX` default-nya `true`. Jangan beralih ke transaksi nyata sebelum tes sandbox lulus.

## Konfigurasi Firebase dan Google login

1. Aktifkan Google provider di Firebase Authentication.
2. Daftarkan aplikasi Android dengan package name yang sesuai dan konfigurasi SHA-1/SHA-256 yang benar.
3. Jalankan FlutterFire CLI hanya untuk membuat konfigurasi client Firebase (bukan untuk deploy Functions): `flutterfire configure --project PROJECT_ID`.
4. Untuk menjalankan aplikasi, berikan URL server API:

   ```bash
   flutter pub get
   flutter run --dart-define=DESA_AI_API_URL=https://api.domain-anda
   flutter build apk --release --dart-define=DESA_AI_API_URL=https://api.domain-anda
   ```

   Jangan masukkan secret OpenAI, TriPay, service-account JSON, atau CRON_SECRET ke `--dart-define`.

Login menampilkan satu tombol Google. Nama dan foto profil berasal dari profil Google; tidak ada form nama, email, atau kata sandi manual.

## Endpoint API

- `POST /aiGetConfig`
- `POST /aiCreateRoom`, `/aiRenameRoom`, `/aiDeleteRoom`
- `POST /aiChatStream` (Server-Sent Events)
- `POST /aiGetPaymentChannels`, `/aiCreateTopupPayment`
- `POST /aiTripayCallback` (callback provider; validasi signature)
- `POST /_internal/reconcile` (hanya cron dengan secret)
- `GET /healthz`

Endpoint pengguna selain callback memerlukan header `Authorization: Bearer <Firebase ID token>`. Jangan membuka port backend langsung tanpa TLS/reverse proxy dan aturan firewall. Gunakan akun admin terpisah untuk endpoint admin; backend tetap memvalidasi role.

## Pengamanan transaksi

- Backend memeriksa status akun, saldo dan rate limit.
- Reservasi saldo dibuat sebelum pemanggilan provider; settlement mengikuti usage yang diterima dari provider.
- Hasil provider yang tidak pasti tetap pending sampai rekonsiliasi atau tinjauan admin; jangan refund otomatis jika provider mungkin sudah memproses permintaan.
- Callback TriPay memvalidasi HMAC raw body, referensi dan nominal; kredit top-up harus idempoten.
- Client tidak boleh menulis balance, ledger, pesan, usage, atau transaksi secara langsung.
- Estimasi konteks merupakan guardrail ukuran teks, bukan tokenizer presisi. Tarif dan akses model harus diverifikasi terhadap akun API aktual sebelum peluncuran.

## CI

GitHub Actions menjalankan Flutter analyze, membuat scaffold Android saat job berlangsung lalu membangun APK debug, serta menjalankan pemeriksaan sintaks dan lint backend. Scaffold Android yang dibuat oleh CI tidak otomatis menjadi file native yang tersimpan di repository. Untuk build lokal/release yang dapat direproduksi, buat dan commit folder platform Android setelah memeriksa package ID dan konfigurasi signing.

Lihat `docs/RELEASE_CHECKLIST.md` sebelum rilis.
