# Peta Pengembangan Desa AI

Dokumen ini memisahkan implementasi saat ini dari roadmap dan kriteria sebelum fitur dianggap siap produksi.

## Prinsip produk

Desa AI adalah model gateway + dompet + plugin runtime. Pengalaman sebaiknya familier bagi pengguna AI chat modern tetapi punya identitas sendiri: sidebar riwayat, ruang chat lega, code block Markdown, pemilih model, kontrol plugin per chat, tarif terlihat, dan dompet rupiah.

## Lapisan kepercayaan

1. **Flutter client**: tampilan, input, streaming, dan membaca history/saldo. Tidak menentukan harga, model ID provider, usage final, saldo, atau status pembayaran.
2. **Firebase Auth**: setiap callable perlu user terautentikasi. Endpoint SSE memverifikasi ID token dan status akun di server.
3. **AI gateway**: validasi input, rate limit, moderasi, context guard, debit reserve atomik, panggilan Responses API, settlement berdasarkan usage provider, dan ledger.
4. **Plugin runtime**: allowlist server-side; client hanya mengirim ID yang diizinkan, server menentukan tool yang benar-benar dijalankan.
5. **Wallet/payment**: paket nominal tetap, channel dari merchant aktif, invoice server-side, callback HMAC, cek amount/reference, idempotency, dan kredit jumlah paket.
6. **Firestore Rules**: user membaca miliknya; pesan, saldo, ledger, dan payment record hanya ditulis backend.

## Status implementasi

| Area | Kondisi | Syarat selesai |
|---|---|---|
| Workspace responsif dan sidebar | Source tersedia | Build mobile/tablet/desktop dan pemeriksaan visual |
| Email/password | Source tersedia | Uji signup, login, logout dan akun nonaktif |
| Google Sign-In | Source tersedia | OAuth, SHA-1/SHA-256, tes perangkat |
| History/rename/delete | Source tersedia | Rules, timestamp, empty states |
| SSE streaming | Source tersedia | Tes timeout, disconnect, buffering dan model access |
| Pemilih model | Dua alias ditetapkan di backend | Verifikasi model ID dan harga sesuai project |
| Reservasi dan settlement saldo | Server code tersedia | Race test, saldo kurang, gagal/berhasil provider |
| Moderasi | Fail-closed | Uji konten ditolak dan moderasi error |
| Prompt caching | Prefix key disiapkan | Ukur cached tokens pada usage aktual |
| Web search | Responses API tool | Uji tool calls, sumber, dan biaya |
| Cek resi/e-commerce | Placeholder nonaktif | API legal, limit, akurasi, caching dan harga |
| Generator gambar | Placeholder nonaktif | Model/endpoint, biaya, moderation, storage |
| TriPay top-up | Backend/callback disiapkan | Sandbox sukses, gagal, expired, callback duplikat |
| Referral Rp1.000 | Belum dibuat | Proteksi referral palsu dan bonus hanya sekali |
| OTP WhatsApp | Belum dibuat | Provider resmi, consent, rate limit, abuse protection |
| Tokenizer presisi | Context guard UTF-8 aproksimasi | Tokenizer cocok model atau guard provider |
| Build/CI | Belum diverifikasi | Flutter analyze/test, lint, emulator, staging APK |

## Siklus pesan

~~~text
Firebase token → validasi akun dan rate limit → moderasi
→ estimasi context guard → reserve debit + ledger
→ OpenAI Responses API (stream=true) → SSE ke UI
→ usage final provider → hitung biaya server
→ refund sisa reserve / debit tambahan yang tersedia
→ simpan jawaban, token count, dan settlement status
~~~

Estimasi karakter hanya boleh menjadi batas awal. Penagihan final harus menggunakan usage provider.

## Status penggunaan

- RESERVED: saldo ditahan, request belum selesai.
- PENDING_RECONCILIATION: usage belum diketahui. Reserve tetap ditahan.
- SETTLED: usage tercatat dan sisa reserve dikembalikan.
- SETTLED_WITH_ERROR: provider melaporkan usage, tetapi output mengalami kegagalan.
- SETTLED_NEEDS_REVIEW: biaya melebihi reserve dan saldo tambahan tidak mencukupi.
- FAILED: provider menolak sebelum generasi dan reserve dikembalikan.

Transisi terminal tidak boleh mengkredit atau mendebit ulang. Request id unik per user mengurangi risiko duplikasi.

## Siklus top-up

~~~text
Pilih paket → channel merchant aktif → invoice server-side
→ catat merchantRef/reference/totalAmount/packageAmount
→ pelanggan membayar → callback TriPay
→ validasi HMAC raw body, event, reference, merchantRef, totalAmount
→ Firestore transaction: cek belum credited, kredit packageAmount,
  buat ledger/mutasi, tandai PAID
~~~

Callback berulang untuk satu merchantRef harus menghasilkan satu kredit. Jika jumlah, reference, signature, atau status bertentangan, jangan mengkredit otomatis.

## Kontrol biaya sebelum public launch

- Tetapkan budget dan alert di akun provider.
- Setel tarif input/output/cache, kurs FX, dan multiplier di konfigurasi server.
- Tetapkan max output dan konteks per model; byte guard bukan token count presisi.
- Buat dashboard admin untuk pending settlement, usage yang perlu review, callback mismatch, biaya per model, margin, dan saldo kurang.
- Uji concurrency pada dompet yang sama; saldo dan ledger harus diperbarui atomik.
- Sediakan kebijakan retensi/penghapusan, minimalkan data pribadi.
- Audit Firebase Rules, endpoint CORS, secret access, retry, timeout, dan logging sebelum promosi.

## Kriteria penerimaan minimum

1. Chat berhasil: jawaban stream sampai selesai, usage tercatat, saldo cocok dengan tarif.
2. Saldo tidak cukup: provider tidak dipanggil dan tidak ada debit.
3. Moderasi menolak input: model utama tidak dipanggil dan saldo tidak berubah.
4. Dua request bersamaan tidak membuat saldo negatif atau ledger ganda.
5. Provider menolak sebelum generasi: reserve dikembalikan satu kali.
6. Stream putus setelah provider mungkin menerima request: reserve tidak otomatis dikembalikan sampai status diketahui.
7. Callback palsu/mismatch/duplikat tidak menambah saldo.
8. Akun nonaktif tidak dapat menggunakan chat atau top-up.
9. Client tidak dapat menulis balance, ledger, usage, room, atau message.
10. Build release Android dan end-to-end pada project staging berhasil.
