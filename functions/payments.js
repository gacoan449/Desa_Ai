"use strict";

const crypto = require("crypto");
const admin = require("firebase-admin");
const {onCall, onRequest, HttpsError, defineSecret, defineString, logger} = require("./runtime");

const db = admin.firestore();
const REGION = "asia-southeast2";
const TRIPAY_API_KEY = defineSecret("TRIPAY_API_KEY");
const TRIPAY_MERCHANT_CODE = defineSecret("TRIPAY_MERCHANT_CODE");
const TRIPAY_PRIVATE_KEY = defineSecret("TRIPAY_PRIVATE_KEY");
const TRIPAY_SANDBOX = defineString("TRIPAY_SANDBOX", {default: "true"});
const MIN_TOPUP_IDR = 10000;
const MAX_TOPUP_IDR = 10000000;

function clean(value, max = 200) {
  return typeof value === "string" ? value.trim().slice(0, max) : "";
}
function safeInt(value) {
  const n = Number(value);
  return Number.isSafeInteger(n) ? n : null;
}
function disabled(data = {}) {
  const status = String(data.status || data.accountStatus || "").trim().toLowerCase();
  return data.disabled === true || data.isDisabled === true || data.isBlocked === true ||
    data.isActive === false || ["disabled", "inactive", "blocked", "banned", "suspended", "nonaktif", "diblokir"].includes(status);
}
function requireUid(req) {
  if (!req.auth || !req.auth.uid) throw new HttpsError("unauthenticated", "Silakan login terlebih dahulu.");
  return req.auth.uid;
}
function sandbox() {
  return String(TRIPAY_SANDBOX.value()).toLowerCase() !== "false";
}
function apiBase() {
  return sandbox() ? "https://tripay.co.id/api-sandbox" : "https://tripay.co.id/api";
}
async function getUser(uid) {
  const ref = db.collection("users").doc(uid);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Profil pengguna tidak ditemukan.");
  const user = snap.data() || {};
  if (disabled(user)) throw new HttpsError("permission-denied", "Akun sedang dinonaktifkan.");
  return {ref, user};
}
async function getChannels() {
  const key = TRIPAY_API_KEY.value();
  if (!key) throw new HttpsError("failed-precondition", "TRIPAY_API_KEY belum dikonfigurasi.");
  const response = await fetch(apiBase() + "/merchant/payment-channel", {
    headers: {Authorization: "Bearer " + key, Accept: "application/json"}, signal: AbortSignal.timeout(15000)
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok || body.success !== true || !Array.isArray(body.data)) {
    throw new HttpsError("unavailable", "Daftar channel TriPay tidak tersedia.");
  }
  return body.data.filter((item) => item && item.active === true && typeof item.code === "string" &&
    (safeInt(item.minimum_amount) || 0) <= MAX_TOPUP_IDR && (safeInt(item.maximum_amount) || 0) >= MIN_TOPUP_IDR);
}

exports.aiGetPaymentChannels = onCall({region: REGION, secrets: [TRIPAY_API_KEY], maxInstances: 5}, async (request) => {
  const uid = requireUid(request);
  await getUser(uid);
  const channels = await getChannels();
  return {success: true, channels: channels.map((item) => ({
    code: item.code, name: item.name, group: item.group || "Pembayaran", iconUrl: item.icon_url || "",
    minimumAmount: safeInt(item.minimum_amount) || 10000, maximumAmount: safeInt(item.maximum_amount) || 100000000,
    feeCustomer: item.fee_customer || {flat: 0, percent: 0}
  }))};
});

exports.aiCreateTopupPayment = onCall({
  region: REGION, timeoutSeconds: 30, maxInstances: 5,
  secrets: [TRIPAY_API_KEY, TRIPAY_MERCHANT_CODE, TRIPAY_PRIVATE_KEY]
}, async (request) => {
  const uid = requireUid(request);
  const {user} = await getUser(uid);
  const amount = safeInt(request.data && request.data.amount);
  const method = clean(request.data && request.data.method, 50).toUpperCase();
  const email = clean((request.data && request.data.email) || user.email || (request.auth.token && request.auth.token.email), 200);
  if (amount === null || amount < MIN_TOPUP_IDR || amount > MAX_TOPUP_IDR) {
    throw new HttpsError("invalid-argument", "Nominal top-up harus antara Rp10.000 dan Rp10.000.000.");
  }
  if (!method) throw new HttpsError("invalid-argument", "Metode pembayaran wajib dipilih.");
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) throw new HttpsError("invalid-argument", "Email valid diperlukan untuk membuat invoice.");
  const apiKey = TRIPAY_API_KEY.value();
  const merchantCode = TRIPAY_MERCHANT_CODE.value();
  const privateKey = TRIPAY_PRIVATE_KEY.value();
  if (!apiKey || !merchantCode || !privateKey) throw new HttpsError("failed-precondition", "Kredensial TriPay belum lengkap.");
  const channels = await getChannels();
  const channel = channels.find((c) => c.code.toUpperCase() === method &&
    (safeInt(c.minimum_amount) || 0) <= amount && (safeInt(c.maximum_amount) || 0) >= amount);
  if (!channel) throw new HttpsError("failed-precondition", "Channel sedang tidak aktif atau tidak mendukung paket ini.");

  const merchantRef = "DAI-" + Date.now().toString(36).toUpperCase() + "-" + crypto.randomBytes(5).toString("hex").toUpperCase();
  const signature = crypto.createHmac("sha256", privateKey).update(merchantCode + merchantRef + amount).digest("hex");
  const form = new URLSearchParams();
  form.set("method", method);
  form.set("merchant_ref", merchantRef);
  form.set("amount", String(amount));
  form.set("customer_name", clean(user.name || user.displayName || user.nama || "Pengguna Desa AI", 100));
  form.set("customer_email", email);
  if (user.phone) form.set("customer_phone", clean(user.phone, 40));
  form.set("order_items[0][sku]", "DESA-AI-CREDIT");
  form.set("order_items[0][name]", "Kredit AI Desa AI");
  form.set("order_items[0][price]", String(amount));
  form.set("order_items[0][quantity]", "1");
  const publicApiUrl = String(process.env.PUBLIC_API_BASE_URL || "").replace(/\/+$/, "");
  if (!/^https:\/\//i.test(publicApiUrl)) {
    throw new HttpsError("failed-precondition", "PUBLIC_API_BASE_URL wajib berisi URL HTTPS server API publik.");
  }
  form.set("callback_url", publicApiUrl + "/aiTripayCallback");
  form.set("expired_time", String(Math.floor(Date.now() / 1000) + 86400));
  form.set("signature", signature);
  const createdResponse = await fetch(apiBase() + "/transaction/create", {
    method: "POST",
    headers: {Authorization: "Bearer " + apiKey, "Content-Type": "application/x-www-form-urlencoded", Accept: "application/json"},
    body: form, signal: AbortSignal.timeout(20000)
  });
  const created = await createdResponse.json().catch(() => ({}));
  if (!createdResponse.ok || created.success !== true || !created.data) {
    logger.error("TriPay invoice creation failed", {status: createdResponse.status, merchantRef});
    throw new HttpsError("unavailable", "TriPay gagal membuat tagihan. Saldo belum ditambahkan.");
  }
  const invoice = created.data;
  const totalAmount = safeInt(invoice.total_amount) || amount;
  const reference = clean(invoice.reference, 200);
  if (!reference || totalAmount < amount) throw new HttpsError("unavailable", "Data invoice TriPay tidak valid.");
  const now = admin.firestore.FieldValue.serverTimestamp();
  await db.collection("topup_transactions").doc(merchantRef).create({
    uid, merchantRef, reference, amount: totalAmount, totalAmount, packageAmount: amount, creditAmount: amount,
    status: "UNPAID", credited: false, source: "AI_TOPUP",
    paymentMethod: clean(invoice.payment_method || method, 60), paymentName: clean(invoice.payment_name || channel.name, 100),
    paymentCode: clean(invoice.pay_code || invoice.payment_code, 200), qrUrl: clean(invoice.qr_url, 1000),
    qrString: clean(invoice.qr_string, 2000), feeCustomer: safeInt(invoice.fee_customer) || 0,
    expiredTime: safeInt(invoice.expired_time) || (Math.floor(Date.now() / 1000) + 86400), createdAt: now, updatedAt: now
  });
  return {success: true, reference, merchant_ref: merchantRef, payment_method: invoice.payment_name || invoice.payment_method || method,
    payment_code: invoice.pay_code || invoice.payment_code || "", qr_url: invoice.qr_url || "", qr_string: invoice.qr_string || "",
    total_amount: totalAmount, fee_admin: safeInt(invoice.fee_customer) || 0, expired_time: safeInt(invoice.expired_time) || 0};
});

function validSignature(raw, received, secret) {
  if (!raw || !received || !secret) return false;
  const expected = crypto.createHmac("sha256", secret).update(raw).digest();
  let actual;
  try { actual = Buffer.from(String(received).trim(), "hex"); } catch (_) { return false; }
  return actual.length === expected.length && crypto.timingSafeEqual(expected, actual);
}
exports.aiTripayCallback = onRequest({
  region: REGION, timeoutSeconds: 30, maxInstances: 5, secrets: [TRIPAY_PRIVATE_KEY]
}, async (req, res) => {
  const reply = (status, data) => res.status(status).json(data);
  if (req.method !== "POST") return reply(405, {success: false, message: "Method not allowed."});
  if (!Buffer.isBuffer(req.rawBody)) return reply(500, {success: false, message: "Raw body unavailable."});
  const signature = req.get("X-Callback-Signature") || "";
  if (!validSignature(req.rawBody, signature, TRIPAY_PRIVATE_KEY.value())) return reply(401, {success: false, message: "Invalid signature."});
  if (String(req.get("X-Callback-Event") || "").toLowerCase() !== "payment_status") return reply(400, {success: false, message: "Unknown callback event."});
  let data;
  try { data = JSON.parse(req.rawBody.toString("utf8")); } catch (_) { return reply(400, {success: false, message: "Invalid JSON."}); }
  const reference = clean(data.reference, 200);
  const merchantRef = clean(data.merchant_ref, 200);
  const status = clean(data.status, 30).toUpperCase();
  const totalAmount = safeInt(data.total_amount);
  if (!reference || !merchantRef || totalAmount === null || !["PAID", "FAILED", "EXPIRED", "REFUND"].includes(status)) {
    return reply(400, {success: false, message: "Invalid callback fields."});
  }
  const topupRef = db.collection("topup_transactions").doc(merchantRef);
  const ledgerRef = db.collection("balance_ledger").doc("tripay_" + crypto.createHash("sha256").update(merchantRef).digest("hex"));
  const mutationRef = db.collection("mutasi_saldo").doc("tripay_" + crypto.createHash("sha256").update(merchantRef).digest("hex"));
  try {
    const result = await db.runTransaction(async (tx) => {
      const topupSnap = await tx.get(topupRef);
      if (!topupSnap.exists) throw new Error("TOPUP_NOT_FOUND");
      const topup = topupSnap.data() || {};
      if (topup.reference !== reference || topup.merchantRef !== merchantRef) throw new Error("REFERENCE_MISMATCH");
      if (safeInt(topup.totalAmount) !== totalAmount) throw new Error("AMOUNT_MISMATCH");
      if (topup.status === "PAID" && topup.credited === true) return {alreadyPaid: true};
      if (["FAILED", "EXPIRED", "REFUND"].includes(topup.status) && topup.status !== status) throw new Error("TERMINAL_STATE_CONFLICT");
      if (status !== "PAID") {
        tx.update(topupRef, {status, updatedAt: admin.firestore.FieldValue.serverTimestamp()});
        return {credited: false, status};
      }
      const creditAmount = safeInt(topup.creditAmount || topup.packageAmount);
      if (!creditAmount || creditAmount < 1) throw new Error("CREDIT_AMOUNT_INVALID");
      const userRef = db.collection("users").doc(String(topup.uid || ""));
      const userSnap = await tx.get(userRef);
      if (!userSnap.exists) throw new Error("USER_NOT_FOUND");
      const user = userSnap.data() || {};
      const before = safeInt(user.balance);
      if (before === null || before < 0 || !Number.isSafeInteger(before + creditAmount)) throw new Error("BALANCE_INVALID");
      const after = before + creditAmount;
      const now = admin.firestore.FieldValue.serverTimestamp();
      tx.update(userRef, {balance: after, updatedAt: now});
      tx.create(ledgerRef, {uid: topup.uid, type: "CREDIT", amount: creditAmount, before, after,
        reason: "Top-up saldo AI melalui TriPay", source: "AI_TOPUP_TRIPAY", merchantRef, reference, createdAt: now});
      tx.create(mutationRef, {uid: topup.uid, tipe: "MASUK", nominal: creditAmount, saldoAwal: before, saldoAkhir: after,
        keterangan: "Top-up Desa AI via TriPay", sumber: "AI_TOPUP_TRIPAY", merchantRef, reference, waktu: now});
      tx.update(topupRef, {status: "PAID", credited: true, creditedAmount: creditAmount, saldoAwal: before, saldoAkhir: after,
        amountReceived: safeInt(data.amount_received) || 0, paidAt: now, updatedAt: now});
      return {credited: true, amount: creditAmount};
    });
    return reply(200, {success: true, ...result});
  } catch (err) {
    logger.error("TriPay callback failed", {merchantRef, code: err.message});
    return reply(err.message === "TOPUP_NOT_FOUND" ? 404 : 409, {success: false, message: "Callback belum dapat diproses; akan dicoba ulang."});
  }
});
