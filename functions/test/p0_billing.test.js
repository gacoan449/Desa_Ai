"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const admin = require("firebase-admin");

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error("FIRESTORE_EMULATOR_HOST is required; never run this test against production.");
}
if (!admin.apps.length) admin.initializeApp({projectId: "demo-desa-ai-p0"});

const db = admin.firestore();
const {reserveMessage} = require("../ai");

test("two concurrent AI reservations cannot overspend one account", async () => {
  const uid = "p0-" + crypto.randomUUID();
  const roomId = "room-" + crypto.randomUUID();
  const room = db.collection("ai_users").doc(uid).collection("rooms").doc(roomId);
  const user = db.collection("users").doc(uid);
  await user.set({uid, role: "user", balance: 1000});
  await room.set({uid, title: "Concurrency test", deleted: false, messageCount: 0});

  const model = {
    key: "economy", id: "emulator-test-model",
    inputUsdPerMillion: 1, outputUsdPerMillion: 1, cachedInputUsdPerMillion: 0
  };
  const config = {
    fxIdrPerUsd: 18000, retailMultiplier: 2.5,
    minBalanceIdr: 500, maxOutputTokens: 1000, webSearchUsdPerCall: 0
  };
  const reserve = (requestId) => reserveMessage({
    uid, requestId, roomId, message: "Concurrency test",
    modelKey: "economy", model, config, plugins: [], estimatedContext: 100
  });

  const outcomes = await Promise.allSettled([
    reserve("request-" + crypto.randomUUID()),
    reserve("request-" + crypto.randomUUID())
  ]);
  assert.equal(outcomes.filter((item) => item.status === "fulfilled").length, 1);
  assert.equal(outcomes.filter((item) => item.status === "rejected").length, 1);

  const finalUser = await user.get();
  assert.equal(finalUser.data().balance, 235);

  const ledger = await db.collection("balance_ledger").where("uid", "==", uid).get();
  assert.equal(ledger.size, 1);
  assert.equal(ledger.docs[0].data().amount, 765);

  const usage = await db.collection("ai_usage_ledger").where("uid", "==", uid).get();
  assert.equal(usage.size, 1);
  assert.equal(usage.docs[0].data().status, "RESERVED");

  await Promise.all(usage.docs.map((doc) => doc.ref.delete()));
  await Promise.all(ledger.docs.map((doc) => doc.ref.delete()));
  await room.delete();
  await user.delete();
});

test("billing snapshot keeps the original price when live config changes", () => {
  const model = {
    key: "economy", id: "test-model",
    inputUsdPerMillion: 1, outputUsdPerMillion: 2, cachedInputUsdPerMillion: 0.25
  };
  const snapshot = {
    modelKey: model.key, modelId: model.id,
    inputUsdPerMillion: model.inputUsdPerMillion,
    outputUsdPerMillion: model.outputUsdPerMillion,
    cachedInputUsdPerMillion: model.cachedInputUsdPerMillion,
    fxIdrPerUsd: 18000, retailMultiplier: 2.5, webSearchUsdPerCall: 0
  };
  const response = {
    usage: {input_tokens: 1000, output_tokens: 500, input_tokens_details: {cached_tokens: 200}},
    output: []
  };
  const uncached = 800;
  const expectedUsd = (uncached * 1 + 200 * 0.25 + 500 * 2) / 1000000;
  const expectedIdr = Math.ceil(expectedUsd * 18000 * 2.5);
  const {calculateChargeIdr} = require("../ai").__test;
  const result = calculateChargeIdr(response, snapshot, false);
  assert.equal(result.amountIdr, expectedIdr);
  assert.equal(result.inputTokens, 1000);
  assert.equal(result.outputTokens, 500);
  assert.equal(result.cachedTokens, 200);
});
