"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const {validSignature, clean, safeInt} = require("../payments").__test;
const {billingSnapshot, calculateChargeIdr} = require("../ai").__test;

test("TriPay callback HMAC accepts only the exact raw body", () => {
  const secret = "test-callback-secret";
  const raw = Buffer.from('{"reference":"T123","status":"PAID"}');
  const signature = crypto.createHmac("sha256", secret).update(raw).digest("hex");
  assert.equal(validSignature(raw, signature, secret), true);
  assert.equal(validSignature(Buffer.from(raw.toString() + " "), signature, secret), false);
  assert.equal(validSignature(raw, signature, "wrong-secret"), false);
  assert.equal(validSignature(raw, "00", secret), false);
});

test("TriPay input validation helpers reject unsafe values", () => {
  assert.equal(safeInt(10000), 10000);
  assert.equal(safeInt(10000.5), null);
  assert.equal(safeInt(Number.MAX_SAFE_INTEGER + 1), null);
  assert.equal(clean("  INV-123  ", 20), "INV-123");
  assert.equal(clean(123, 20), "");
});

test("AI charge uses provider usage and immutable billing snapshot", () => {
  const model = {key:"economy", id:"model-test", inputUsdPerMillion:1, outputUsdPerMillion:2, cachedInputUsdPerMillion:0.25};
  const config = {fxIdrPerUsd:18000, retailMultiplier:2.5, webSearchUsdPerCall:0.01};
  const snapshot = billingSnapshot(model, ["web_search"], config);
  model.inputUsdPerMillion = 100;
  config.fxIdrPerUsd = 99000;
  const response = {usage:{input_tokens:1000, output_tokens:500, input_tokens_details:{cached_tokens:200}}, output:[{type:"web_search_call"}]};
  const result = calculateChargeIdr(response, snapshot, false);
  const expectedUsd = (800*1 + 200*0.25 + 500*2)/1e6 + 0.01;
  assert.equal(result.amountIdr, Math.ceil(expectedUsd*18000*2.5));
  assert.equal(result.searchCalls, 1);
});
