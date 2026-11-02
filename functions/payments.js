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

async function enforceTopupRateLimit(uid) {
  const ref = db.collection("topup_rate_limits").doc(uid);
  const nowMs = Date.now();
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const previous = snap.exists && Array.isArray(snap.data().times) ? snap.data().times : [];
    const recent = previous.filter((time) => Number.isSafeInteger(time) && time > nowMs - 10 * 60 * 1000);
    if (recent.length >= 3) {
      throw new HttpsError("resource-exhausted", "Batas pembuatan top-up tercapai. Coba lagi setelah 10 menit.");
    }
    recent.push(nowMs);
    tx.set(ref, {times: recent, updatedAt: admin.firestore.FieldValue.serverTimestamp()});
  });
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

async function markInvoiceCreationState(topupRef, activeRef, merchantRef, status, details = {}) {
  await db.runTransaction(async (tx) => {
    const [topupSnap, lockSnap] = await Promise.all([tx.get(topupRef), tx.get(activeRef)]);
    if (!topupSnap.exists) return;
    const current = topupSnap.data() || {};
    const terminal = ["PAID", "FAILED", "EXPIRED", "REFUNDED", "REFUNDED_PARTIAL",
      "REFUNDED_UNCREDITED", "REFUND_NEEDS_REVIEW"].includes(current.status);
    if (terminal) {
      if (lockSnap.exists && lockSnap.data().merchantRef === merchantRef) tx.delete(activeRef);
      return;
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    tx.update(topupRef, {status, ...details, updatedAt: now});
    if (lockSnap.exists && lockSnap.data().merchantRef === merchantRef) {
      if (status === "CREATE_FAILED") tx.delete(activeRef);
      else tx.set(activeRef, {status, updatedAt: now}, {merge: true});
    }
  });
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
  await enforceTopupRateLimit(uid);
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
  const publicApiUrl = String(process.env.PUBLIC_API_BASE_URL || "").replace(/\/+$/, "");
  if (!/^https:\/\//i.test(publicApiUrl)) {
    throw new HttpsError("failed-precondition", "PUBLIC_API_BASE_URL wajib berisi URL HTTPS server API publik.");
  }

  const merchantRef = "DAI-" + Date.now().toString(36).toUpperCase() + "-" + crypto.randomBytes(5).toString("hex").toUpperCase();
  const topupRef = db.collection("topup_transactions").doc(merchantRef);
  const activeRef = db.collection("topup_active").doc(uid);
  const nowSeconds = Math.floor(Date.now() / 1000);
  // A per-user lock serializes invoice creation and prevents duplicate active invoices.
  await db.runTransaction(async (tx) => {
    const activeSnap = await tx.get(activeRef);
    if (activeSnap.exists) {
      const active = activeSnap.data() || {};
      const expiresAt = safeInt(active.expiresAt) || 0;
      const stillOpen = active.status === "CREATE_UNKNOWN" ||
        (["CREATING", "UNPAID"].includes(active.status) && expiresAt > nowSeconds);
      if (stillOpen) throw new HttpsError("already-exists", "Masih ada tagihan top-up aktif. Selesaikan atau tunggu kedaluwarsa sebelum membuat tagihan baru.");
    }
    const now = admin.firestore.FieldValue.serverTimestamp();
    tx.create(topupRef, {uid, merchantRef, reference: null, requestedAmount: amount, packageAmount: amount,
      creditAmount: amount, totalAmount: null, status: "CREATING", credited: false, source: "AI_TOPUP",
      paymentMethod: method, createdAt: now, updatedAt: now});
    tx.set(activeRef, {merchantRef, status: "CREATING", expiresAt: nowSeconds + 120, updatedAt: now});
  });
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
  form.set("callback_url", publicApiUrl + "/aiTripayCallback");
  form.set("expired_time", String(Math.floor(Date.now() / 1000) + 86400));
  form.set("signature", signature);
  let createdResponse;
  let created;
  try {
    createdResponse = await fetch(apiBase() + "/transaction/create", {
      method: "POST",
      headers: {Authorization: "Bearer " + apiKey, "Content-Type": "application/x-www-form-urlencoded", Accept: "application/json"},
      body: form, signal: AbortSignal.timeout(20000)
    });
    created = await createdResponse.json().catch(() => ({}));
  } catch (error) {
    // A timeout can happen after the provider created the invoice. Keep the lock for reconciliation.
    await markInvoiceCreationState(topupRef, activeRef, merchantRef, "CREATE_UNKNOWN",
      {reconciliationReason: "Provider request outcome unknown."});
    throw new HttpsError("unavailable", "Status pembuatan tagihan belum pasti. Jangan membuat pembayaran ulang; hubungi bantuan untuk pemeriksaan.");
  }
  if (!createdResponse.ok && createdResponse.status >= 500) {
    await markInvoiceCreationState(topupRef, activeRef, merchantRef, "CREATE_UNKNOWN",
      {providerHttpStatus: createdResponse.status, reconciliationReason: "Provider 5xx; invoice outcome is ambiguous."});
    throw new HttpsError("unavailable", "Status pembuatan tagihan belum pasti. Jangan membuat pembayaran ulang; hubungi bantuan untuk pemeriksaan.");
  }
  if (!createdResponse.ok || created.success !== true || !created.data) {
    await markInvoiceCreationState(topupRef, activeRef, merchantRef, "CREATE_FAILED",
      {providerHttpStatus: createdResponse.status});
    logger.error("TriPay invoice creation failed", {status: createdResponse.status, merchantRef});
    throw new HttpsError("unavailable", "TriPay gagal membuat tagihan. Saldo belum ditambahkan.");
  }
  const invoice = created.data;
  const totalAmount = safeInt(invoice.total_amount);
  const reference = clean(invoice.reference, 200);
  if (!reference || totalAmount === null || totalAmount < amount) {
    await markInvoiceCreationState(topupRef, activeRef, merchantRef, "CREATE_UNKNOWN",
      {reconciliationReason: "Provider returned incomplete invoice data."});
    throw new HttpsError("unavailable", "Data invoice belum lengkap. Tagihan ditahan untuk pemeriksaan agar tidak terbuat ganda.");
  }
  const expiresAt = safeInt(invoice.expired_time) || (nowSeconds + 86400);
  const now = admin.firestore.FieldValue.serverTimestamp();
  await db.runTransaction(async (tx) => {
    const [savedSnap, lockSnap] = await Promise.all([tx.get(topupRef), tx.get(activeRef)]);
    if (!savedSnap.exists) throw new Error("TOPUP_RECORD_MISSING");
    const current = savedSnap.data() || {};
    // A callback may arrive before the create response is persisted. Never downgrade a terminal state.
    if (!["PAID", "REFUNDED", "REFUNDED_UNCREDITED", "REFUND_NEEDS_REVIEW"].includes(current.status)) {
      tx.update(topupRef, {reference, amount: totalAmount, totalAmount, status: "UNPAID",
        paymentMethod: clean(invoice.payment_method || method, 60), paymentName: clean(invoice.payment_name || channel.name, 100),
        paymentCode: clean(invoice.pay_code || invoice.payment_code, 200), qrUrl: clean(invoice.qr_url, 1000),
        qrString: clean(invoice.qr_string, 2000), feeCustomer: safeInt(invoice.fee_customer) || 0,
        expiredTime: expiresAt, updatedAt: now});
    } else if (!current.reference) {
      tx.update(topupRef, {reference, amount: totalAmount, totalAmount, updatedAt: now});
    }
    if (lockSnap.exists && lockSnap.data().merchantRef === merchantRef) {
      if (["PAID", "REFUNDED", "REFUNDED_UNCREDITED", "REFUND_NEEDS_REVIEW"].includes(current.status)) tx.delete(activeRef);
      else tx.set(activeRef, {status: "UNPAID", expiresAt, updatedAt: now}, {merge: true});
    }
  });
  return {success: true, reference, merchant_ref: merchantRef, payment_method: invoice.payment_name || invoice.payment_method || method,
    payment_code: invoice.pay_code || invoice.payment_code || "", qr_url: invoice.qr_url || "", qr_string: invoice.qr_string || "",
    total_amount: totalAmount, fee_admin: safeInt(invoice.fee_customer) || 0, expired_time: expiresAt};
});

exports.aiAdminListPendingTopups = onCall({region: REGION, maxInstances: 3}, async (request) => {
  const uid = requireUid(request);
  const {user} = await getUser(uid);
  if (user.role !== "admin") throw new HttpsError("permission-denied", "Akses hanya untuk admin.");
  const snap = await db.collection("topup_transactions").where("status", "in", ["CREATING", "CREATE_UNKNOWN"]).limit(100).get();
  return {pending: snap.docs.map((doc) => {
    const item = doc.data() || {};
    return {merchantRef: doc.id, uid: clean(item.uid, 128), status: clean(item.status, 40),
      packageAmount: safeInt(item.packageAmount) || 0, reference: clean(item.reference, 200),
      reconciliationReason: clean(item.reconciliationReason, 300),
      createdAtMillis: item.createdAt && typeof item.createdAt.toMillis === "function" ? item.createdAt.toMillis() : null};
  })};
});

exports.aiAdminResolveUnknownTopup = onCall({region: REGION, maxInstances: 3}, async (request) => {
  const adminUid = requireUid(request);
  const {user} = await getUser(adminUid);
  if (user.role !== "admin") throw new HttpsError("permission-denied", "Akses hanya untuk admin.");
  const merchantRef = clean(request.data && request.data.merchantRef, 200);
  const reason = clean(request.data && request.data.reason, 500);
  const verified = request.data && request.data.providerVerifiedNoInvoice === true;
  if (!merchantRef || reason.length < 20 || !verified) {
    throw new HttpsError("invalid-argument", "Merchant reference, alasan audit minimal 20 karakter, dan verifikasi provider bahwa invoice tidak ada wajib diisi.");
  }
  const topupRef = db.collection("topup_transactions").doc(merchantRef);
  return db.runTransaction(async (tx) => {
    const topupSnap = await tx.get(topupRef);
    if (!topupSnap.exists) throw new HttpsError("not-found", "Catatan top-up tidak ditemukan.");
    const item = topupSnap.data() || {};
    if (!["CREATING", "CREATE_UNKNOWN"].includes(item.status) || item.reference || item.credited === true) {
      throw new HttpsError("failed-precondition", "Hanya invoice yang belum memiliki reference dan masih berstatus tidak pasti yang dapat diselesaikan dengan prosedur ini.");
    }
    const userLockRef = db.collection("topup_active").doc(String(item.uid || ""));
    const lockSnap = await tx.get(userLockRef);
    const now = admin.firestore.FieldValue.serverTimestamp();
    tx.update(topupRef, {status: "CREATE_FAILED", resolvedBy: adminUid, resolutionReason: reason,
      providerVerifiedNoInvoice: true, resolvedAt: now, updatedAt: now});
    if (lockSnap.exists && lockSnap.data().merchantRef === merchantRef) tx.delete(userLockRef);
    return {success: true, status: "CREATE_FAILED"};
  });
});

exports.aiReconcileTopups = onRequest({region: REGION, timeoutSeconds: 120, maxInstances: 2, secrets: [TRIPAY_API_KEY]}, async (req, res) => {
  if (req.method !== "POST") return res.status(405).json({success: false});
  const expectedCron = String(process.env.CRON_SECRET || "");
  const suppliedCron = String(req.get("Authorization") || "").replace(/^Bearer\\s+/i, "");
  const expectedBytes = Buffer.from(expectedCron);
  const suppliedBytes = Buffer.from(suppliedCron);
  if (!expectedCron || !suppliedCron || expectedBytes.length !== suppliedBytes.length ||
      !crypto.timingSafeEqual(expectedBytes, suppliedBytes)) {
    return res.status(401).json({success: false, message: "Unauthorized"});
  }
  const apiKey = TRIPAY_API_KEY.value();
  if (!apiKey) return res.status(503).json({success: false, message: "TriPay API key belum tersedia."});
  const snap = await db.collection("topup_transactions").where("status", "==", "UNPAID").limit(25).get();
  const results = [];
  for (const doc of snap.docs) {
    const item = doc.data() || {};
    const reference = clean(item.reference, 200);
    const merchantRef = clean(item.merchantRef || doc.id, 200);
    if (!reference || !merchantRef) continue;
    try {
      const url = apiBase() + "/transaction/detail?reference=" + encodeURIComponent(reference);
      const response = await fetch(url, {headers: {Authorization: "Bearer " + apiKey, "Accept": "application/json"},
        signal: AbortSignal.timeout(12000)});
      const body = await response.json().catch(() => ({}));
      const provider = body.data || {};
      const providerAmount = safeInt(provider.amount);
      const providerFee = safeInt(provider.fee_customer) || 0;
      const detailTotal = safeInt(provider.total_amount) || (providerAmount === null ? null : providerAmount + providerFee);
      if (!response.ok || body.success !== true || provider.reference !== reference ||
          provider.merchant_ref !== merchantRef || detailTotal !== safeInt(item.totalAmount)) {
        results.push({merchantRef, outcome: "MISMATCH_OR_UNAVAILABLE"});
        continue;
      }
      const status = clean(provider.status, 30).toUpperCase();
      if (status === "PAID") {
        const userRef = db.collection("users").doc(String(item.uid || ""));
        const ledgerId = "tripay_" + crypto.createHash("sha256").update(merchantRef).digest("hex");
        const ledgerRef = db.collection("balance_ledger").doc(ledgerId);
        const mutationRef = db.collection("mutasi_saldo").doc(ledgerId);
        const outcome = await db.runTransaction(async (tx) => {
          const lockRef = db.collection("topup_active").doc(String(item.uid || ""));
          const [currentSnap, userSnap, ledgerSnap, lockSnap] = await Promise.all([
            tx.get(doc.ref), tx.get(userRef), tx.get(ledgerRef), tx.get(lockRef)
          ]);
          if (!currentSnap.exists) return "MISSING";
          const current = currentSnap.data() || {};
          if (current.status === "PAID" && current.credited === true) return "ALREADY_CREDITED";
          if (["REFUNDED", "REFUNDED_PARTIAL", "REFUNDED_UNCREDITED", "REFUND_NEEDS_REVIEW", "FAILED", "EXPIRED"].includes(current.status)) return "TERMINAL_CONFLICT";
          if (!userSnap.exists || ledgerSnap.exists) return "REVIEW_REQUIRED";
          const amount = safeInt(current.creditAmount || current.packageAmount);
          const before = safeInt((userSnap.data() || {}).balance);
          if (!amount || amount < 1 || before === null || before < 0 || !Number.isSafeInteger(before + amount)) return "REVIEW_REQUIRED";
          const after = before + amount;
          const now = admin.firestore.FieldValue.serverTimestamp();
          tx.update(userRef, {balance: after, updatedAt: now});
          tx.create(ledgerRef, {uid: current.uid, type: "CREDIT", amount, before, after,
            reason: "Rekonsiliasi top-up TriPay PAID", source: "AI_TOPUP_TRIPAY_RECONCILIATION",
            merchantRef, reference, createdAt: now});
          tx.create(mutationRef, {uid: current.uid, tipe: "MASUK", nominal: amount, saldoAwal: before, saldoAkhir: after,
            keterangan: "Rekonsiliasi top-up Desa AI via TriPay", sumber: "AI_TOPUP_TRIPAY_RECONCILIATION",
            merchantRef, reference, waktu: now});
          tx.update(doc.ref, {status: "PAID", credited: true, creditedAmount: amount, totalAmount: detailTotal,
            amount: detailTotal, paidAt: now, reconciledAt: now, updatedAt: now});
          if (lockSnap.exists && lockSnap.data().merchantRef === merchantRef) tx.delete(lockRef);
          return "CREDITED";
        });
        results.push({merchantRef, outcome});
      } else if (["FAILED", "EXPIRED"].includes(status)) {
        await db.runTransaction(async (tx) => {
          const [currentSnap, lockSnap] = await Promise.all([
            tx.get(doc.ref), tx.get(db.collection("topup_active").doc(String(item.uid || "")))
          ]);
          if (!currentSnap.exists || currentSnap.data().status !== "UNPAID") return;
          const now = admin.firestore.FieldValue.serverTimestamp();
          tx.update(doc.ref, {status, reconciledAt: now, updatedAt: now});
          if (lockSnap.exists && lockSnap.data().merchantRef === merchantRef) tx.delete(db.collection("topup_active").doc(String(item.uid || "")));
        });
        results.push({merchantRef, outcome: status});
      } else {
        results.push({merchantRef, outcome: "STILL_" + (status || "UNKNOWN")});
      }
    } catch (error) {
      logger.warn("TriPay reconciliation failed", {merchantRef, message: error.message});
      results.push({merchantRef, outcome: "RETRY"});
    }
  }
  return res.status(200).json({success: true, checked: results.length, results});
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
  const ledgerId = "tripay_" + crypto.createHash("sha256").update(merchantRef).digest("hex");
  const ledgerRef = db.collection("balance_ledger").doc(ledgerId);
  const mutationRef = db.collection("mutasi_saldo").doc(ledgerId);
  const refundId = "tripay_refund_" + crypto.createHash("sha256").update(merchantRef).digest("hex");
  const refundLedgerRef = db.collection("balance_ledger").doc(refundId);
  const refundMutationRef = db.collection("mutasi_saldo").doc(refundId);
  const obligationRef = db.collection("ai_billing_obligations").doc(refundId);
  try {
    const result = await db.runTransaction(async (tx) => {
      const topupSnap = await tx.get(topupRef);
      if (!topupSnap.exists) throw new Error("TOPUP_NOT_FOUND");
      const topup = topupSnap.data() || {};
      if (topup.merchantRef !== merchantRef) throw new Error("REFERENCE_MISMATCH");
      const pendingInvoice = !topup.reference && ["CREATING", "CREATE_UNKNOWN"].includes(topup.status);
      if (!pendingInvoice && topup.reference !== reference) throw new Error("REFERENCE_MISMATCH");
      if (pendingInvoice && totalAmount < (safeInt(topup.packageAmount) || 0)) throw new Error("AMOUNT_MISMATCH");
      if (!pendingInvoice && safeInt(topup.totalAmount) !== totalAmount) throw new Error("AMOUNT_MISMATCH");
      const uid = String(topup.uid || "");
      const userRef = db.collection("users").doc(uid);
      const lockRef = db.collection("topup_active").doc(uid);
      const [userSnap, lockSnap] = await Promise.all([tx.get(userRef), tx.get(lockRef)]);
      const now = admin.firestore.FieldValue.serverTimestamp();

      if (status === "PAID") {
        if (topup.status === "PAID" && topup.credited === true) return {alreadyPaid: true};
        if (["REFUNDED", "REFUNDED_UNCREDITED", "REFUND_NEEDS_REVIEW", "FAILED", "EXPIRED"].includes(topup.status)) throw new Error("TERMINAL_STATE_CONFLICT");
        if (!userSnap.exists) throw new Error("USER_NOT_FOUND");
        const creditAmount = safeInt(topup.creditAmount || topup.packageAmount);
        const before = safeInt((userSnap.data() || {}).balance);
        if (!creditAmount || creditAmount < 1 || before === null || before < 0 || !Number.isSafeInteger(before + creditAmount)) throw new Error("BALANCE_INVALID");
        const after = before + creditAmount;
        tx.update(userRef, {balance: after, updatedAt: now});
        tx.create(ledgerRef, {uid, type: "CREDIT", amount: creditAmount, before, after,
          reason: "Top-up saldo AI melalui TriPay", source: "AI_TOPUP_TRIPAY", merchantRef, reference, createdAt: now});
        tx.create(mutationRef, {uid, tipe: "MASUK", nominal: creditAmount, saldoAwal: before, saldoAkhir: after,
          keterangan: "Top-up Desa AI via TriPay", sumber: "AI_TOPUP_TRIPAY", merchantRef, reference, waktu: now});
        tx.update(topupRef, {reference, amount: totalAmount, totalAmount, status: "PAID", credited: true,
          creditedAmount: creditAmount, saldoAwal: before, saldoAkhir: after, amountReceived: safeInt(data.amount_received) || 0,
          paidAt: now, updatedAt: now});
        if (lockSnap.exists && lockSnap.data().merchantRef === merchantRef) tx.delete(lockRef);
        return {credited: true, amount: creditAmount};
      }

      if (status === "REFUND") {
        if (["REFUNDED", "REFUNDED_PARTIAL", "REFUNDED_UNCREDITED"].includes(topup.status)) return {alreadyRefunded: true};
        if (topup.status === "REFUND_NEEDS_REVIEW") return {alreadyPendingReview: true};
        if (topup.status !== "PAID" || topup.credited !== true) {
          tx.update(topupRef, {reference, amount: totalAmount, totalAmount, status: "REFUNDED_UNCREDITED",
            refunded: true, refundedAt: now, updatedAt: now});
          if (lockSnap.exists && lockSnap.data().merchantRef === merchantRef) tx.delete(lockRef);
          return {credited: false, refunded: false, status: "REFUNDED_UNCREDITED"};
        }
        const creditAmount = safeInt(topup.creditedAmount || topup.creditAmount || topup.packageAmount);
        if (!userSnap.exists || !creditAmount || creditAmount < 1) throw new Error("REFUND_AMOUNT_INVALID");
        // TriPay's callback supplies the original total_amount but no dedicated refund_amount.
        // Never debit a guessed amount: require an admin to verify the actual refund with the provider.
        tx.create(obligationRef, {uid, type: "TRIPAY_REFUND", sourceId: merchantRef,
          amountIdr: creditAmount, maxRefundAmountIdr: creditAmount, amountVerified: false,
          status: "OPEN", reason: "TriPay mengirim status REFUND; nominal refund harus diverifikasi di dashboard provider.",
          createdAt: now, updatedAt: now});
        tx.update(userRef, {billingHold: true, billingHoldReason: "TRIPAY_REFUND_REVIEW", updatedAt: now});
        tx.update(topupRef, {status: "REFUND_NEEDS_REVIEW", refundAmount: null,
          refundMaximumAmount: creditAmount, refunded: false, refundPending: true, updatedAt: now});
        if (lockSnap.exists && lockSnap.data().merchantRef === merchantRef) tx.delete(lockRef);
        return {credited: true, refunded: false, needsReview: true, maxAmountIdr: creditAmount};
      }

      if (["FAILED", "EXPIRED"].includes(status)) {
        if (topup.status === "PAID" || topup.credited === true || ["REFUNDED", "REFUNDED_PARTIAL", "REFUND_NEEDS_REVIEW"].includes(topup.status)) throw new Error("TERMINAL_STATE_CONFLICT");
        tx.update(topupRef, {reference: reference || null, amount: totalAmount, totalAmount, status, updatedAt: now});
        if (lockSnap.exists && lockSnap.data().merchantRef === merchantRef) tx.delete(lockRef);
        return {credited: false, status};
      }
      throw new Error("UNSUPPORTED_STATUS");
    });
    return reply(200, {success: true, ...result});
  } catch (err) {
    logger.error("TriPay callback failed", {merchantRef, code: err.message});
    return reply(err.message === "TOPUP_NOT_FOUND" ? 404 : 409, {success: false, message: "Callback belum dapat diproses; akan dicoba ulang."});
  }
});


exports.__test = {validSignature, clean, safeInt};
