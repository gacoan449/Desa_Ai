"use strict";
const admin = require("firebase-admin");
class HttpsError extends Error {
  constructor(code, message) { super(message); this.name = "HttpsError"; this.code = code; }
}
const statusForCode = {"unauthenticated":401,"permission-denied":403,"not-found":404,"invalid-argument":400,"resource-exhausted":429,"failed-precondition":409,"already-exists":409,"unavailable":503,"deadline-exceeded":504};
function onCall(_options, handler) {
  return async (req, res) => {
    try {
      const match = String(req.get("Authorization") || "").match(/^Bearer\s+(.+)$/i);
      if (!match) throw new HttpsError("unauthenticated", "Silakan login terlebih dahulu.");
      let decoded;
      try { decoded = await admin.auth().verifyIdToken(match[1], true); }
      catch (_) { throw new HttpsError("unauthenticated", "Sesi login tidak valid."); }
      const data = req.body && req.body.data && typeof req.body.data === "object" ? req.body.data : (req.body || {});
      const result = await handler({auth: {uid: decoded.uid, token: decoded}, data});
      return res.status(200).json({result});
    } catch (error) {
      return res.status(statusForCode[error.code] || 500).json({error:{status:error.code||"internal",message:error.message||"Permintaan gagal."},message:error.message||"Permintaan gagal."});
    }
  };
}
function onRequest(_options, handler) { return handler; }
function onSchedule(_options, handler) {
  return async (req, res) => {
    try {
      const expected = process.env.CRON_SECRET;
      const supplied = String(req.get("Authorization") || "").replace(/^Bearer\s+/i, "");
      if (!expected || supplied !== expected) return res.status(401).json({message:"Unauthorized"});
      await handler();
      return res.status(200).json({success:true});
    } catch (error) {
      console.error("Scheduled task failed", error);
      return res.status(500).json({message:"Scheduled task failed"});
    }
  };
}
function defineSecret(name) { return {value: () => process.env[name] || ""}; }
function defineString(name, options = {}) { return {value: () => process.env[name] ?? options.default ?? ""}; }
const logger = {info:(m,d)=>console.info(m,d||""),warn:(m,d)=>console.warn(m,d||""),error:(m,d)=>console.error(m,d||"")};
module.exports = {onCall,onRequest,onSchedule,HttpsError,defineSecret,defineString,logger};
