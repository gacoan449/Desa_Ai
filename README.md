# Desa AI

AI workspace dengan saldo rupiah per pemakaian — aplikasi Flutter + Firebase Functions untuk pengguna Indonesia. Layout memiliki sidebar riwayat, tombol chat baru, pemilih model, respons streaming, katalog plugin, ringkasan saldo, dan top-up.

> Status: source aplikasi dan backend telah dimasukkan ke branch main. Belum siap produksi sebelum konfigurasi Firebase/provider, pengujian merchant sandbox, dan build Android dilakukan.

## Fitur dalam source

- Email/password dan Google Sign-In melalui Firebase Authentication.
- Workspace responsif dengan daftar ruang chat, ubah nama, hapus, dan chat baru.
- Pemilih model GPT-6.1 Sol (premium) dan GPT-6 Luna (hemat); model ID dan tarif dapat dioverride di backend.
- Streaming Responses API melalui Server-Sent Events.
- Reservasi saldo sebelum permintaan, settlement berdasarkan usage provider, ledger dan penanganan hasil tidak pasti.
- Rate limit 5 permintaan per 10 detik, moderasi sebelum generasi, context guard 30.000 token perkiraan dan warning 25.000.
- Plugin browsing web; plugin cek resi, pembanding e-commerce, dan gambar dinyatakan belum aktif sampai integrasi resminya siap.
- Top-up Rp10.000, Rp25.000, Rp50.000, Rp100.000 dengan channel aktif dari merchant TriPay.
- Callback TriPay memvalidasi HMAC raw body, invoice/nominal, dan mencegah kredit ganda.

## Peta arsitektur

~~~text
Flutter client
  ├─ Firebase Auth (email/password + Google)
  ├─ Chat workspace, history, plugin store, wallet
  └─ Firebase ID token
       ├─ aiChatStream (SSE)
       │    ├─ cek akun aktif dan rate limit
       │    ├─ moderasi
       │    ├─ reservasi saldo atomik
       │    ├─ OpenAI Responses API
       │    └─ settlement token, ledger, rekonsiliasi
       ├─ aiCreateRoom / aiRenameRoom / aiDeleteRoom
       └─ aiCreateTopupPayment
             └─ TriPay API → aiTripayCallback → kredit atomik
~~~

Region Cloud Functions: asia-southeast2 (Jakarta). Secret provider hanya disimpan di Firebase Functions secrets; jangan pernah membundelnya ke APK.

## 1. Prasyarat

- Flutter SDK kompatibel Dart 3.5+.
- Node.js 20 dan Firebase CLI.
- Project Firebase dengan Authentication, Cloud Firestore, dan Cloud Functions. Billing plan Firebase yang sesuai mungkin diperlukan untuk fungsi terjadwal.
- OpenAI API key yang memiliki akses ke model yang dikonfigurasi.
- Akun merchant TriPay dan kredensial sandbox.

## 2. Siapkan platform Android/Web

Repository berisi source inti, belum berisi direktori platform native hasil generator Flutter. Untuk membuatnya tanpa menimpa source aplikasi:

1. Di direktori sementara, jalankan: flutter create --platforms android,web --project-name desa_ai desa_ai_platforms
2. Salin folder android/ dan web/ dari scaffold tersebut ke root repo ini.
3. Jalankan flutter pub get.
4. Aktifkan provider Email/Password dan Google di Firebase Authentication.
5. Jalankan dart pub global activate flutterfire_cli, lalu flutterfire configure --project PROJECT_ID untuk mengikat project Firebase.

Google Sign-In memerlukan konfigurasi OAuth dan SHA-1/SHA-256 sesuai platform. OTP WhatsApp belum diaktifkan karena perlu provider OTP WhatsApp resmi; jangan menyatakan berhasil sebelum integrasi itu dibuat.

## 3. Rahasia backend

Pilih project Firebase lalu set secret lewat Firebase CLI:

~~~bash
firebase login
firebase use --add
firebase functions:secrets:set OPENAI_API_KEY
firebase functions:secrets:set TRIPAY_API_KEY
firebase functions:secrets:set TRIPAY_MERCHANT_CODE
firebase functions:secrets:set TRIPAY_PRIVATE_KEY
~~~

Masukkan secret secara interaktif di CLI. Jangan letakkan nilainya di repository, log, atau APK. TRIPAY_SANDBOX default-nya true. Uji sandbox sebelum beralih ke production.

~~~bash
cd functions
npm install
npm run lint
cd ..
firebase deploy --only functions,firestore:rules
~~~

Endpoint callback yang didaftarkan pada merchant (bila diperlukan):
https://asia-southeast2-PROJECT_ID.cloudfunctions.net/aiTripayCallback

Create invoice juga mengirim callback URL. Pastikan project ID dan URL produksi sesuai dengan project Firebase Anda.

## 4. Harga model dan saldo

Backend membaca konfigurasi override dari dokumen Firestore settings/ai_pricing:

- fxIdrPerUsd: kurs konversi USD ke rupiah yang ditetapkan bisnis.
- retailMultiplier: margin di atas biaya provider.
- models.premium.id, inputUsdPerMillion, outputUsdPerMillion, cachedInputUsdPerMillion, active.
- models.economy.* dengan properti serupa.
- maxOutputTokens, minBalanceIdr, dan webSearchUsdPerCall.

Default yang disetel sekarang memakai harga Standard per 1 juta token dari halaman harga OpenAI yang diperiksa 25 Oktober 2026: GPT-6.1 Sol input $2, output $10, cached input $0.10; GPT-6 Luna input $0.10, output $0.50, cached input $0.01. Tarif aplikasi kemudian dikalikan kurs dan retailMultiplier. Ini adalah nilai awal, bukan kontrak harga tetap. Harga bisa berbeda menurut tier pemrosesan, ukuran konteks, cache write, tools, dan program harga. Verifikasi bahwa model ID tersedia di project API Anda dan sesuaikan konfigurasi server sebelum membuka transaksi nyata. Referensi resmi: https://developers.openai.com/api/docs/models dan https://developers.openai.com/api/docs/pricing.

Estimasi konteks saat ini adalah guardrail ukuran UTF-8, bukan tokenizer tiktoken yang presisi. Settlement membaca usage.input_tokens, usage.output_tokens, dan cached-token count dari provider. Biaya cache-write/tool belum dipisah sempurna dari usage token pada versi awal; retailMultiplier memberikan bantalan biaya, tetapi angka stored sebagai estimated provider cost tetap estimasi. Jangan menampilkan angka tersebut sebagai bukti invoice provider. Frontend tidak menentukan tagihan final.

## 5. Prinsip transaksi

1. Backend memeriksa akun aktif dan rate limit.
2. Moderasi berjalan sebelum model; jika layanan moderasi gagal, request ditolak.
3. Reservasi saldo dan ledger dibuat dalam transaksi Firestore sebelum panggilan provider.
4. Setelah usage provider diterima, backend menghitung biaya dan mengembalikan sisa reservasi.
5. Jika status pemrosesan belum pasti, reservasi ditahan dan ditandai untuk rekonsiliasi. Jangan refund otomatis untuk request yang mungkin sudah diproses provider.
6. Callback TriPay harus memiliki signature yang valid, reference cocok, total sesuai invoice, dan status yang diizinkan. Kredit memakai jumlah paket (creditAmount), bukan fee.
7. Client tidak boleh menulis balance, ledger, pesan, penggunaan, atau catatan pembayaran.

## 6. Jalankan UI

Setelah platform dan Firebase disiapkan:

~~~bash
flutter pub get
flutter run
flutter build apk --release
~~~

## Batasan sebelum public launch

- Flutter analyze, build APK dan tes end-to-end belum dijalankan di lingkungan pengerjaan ini.
- Backend belum diuji dengan secret/OpenAI API key dan merchant sandbox nyata.
- Cek resi, pencarian e-commerce, dan generator gambar masih nonaktif.
- Google Sign-In perlu konfigurasi OAuth platform yang sesuai.
- Prompt caching tidak menjamin hit rate atau persentase diskon tertentu; tagihan provider mengikuti usage aktual.
- Rekonsiliasi otomatis dapat menangani respons yang memiliki response ID. Status tidak pasti tanpa response ID perlu peninjauan operasional.
- Tinjau harga provider, kurs FX, multiplier, model access, rules, CORS, privacy retention, budget/alerts dan proses refund sebelum rilis.

Lihat docs/BLUEPRINT.md untuk roadmap dan kriteria penerimaan.
