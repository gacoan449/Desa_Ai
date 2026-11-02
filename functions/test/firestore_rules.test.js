"use strict";

const {readFileSync} = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const assert = require("node:assert/strict");
const {initializeTestEnvironment, assertFails, assertSucceeds} = require("@firebase/rules-unit-testing");
const {doc, getDoc, setDoc, updateDoc} = require("firebase/firestore");

let env;
test.before(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("Firestore Emulator required.");
  env = await initializeTestEnvironment({
    projectId: "demo-desa-ai-p0",
    firestore: {rules: readFileSync(path.join(__dirname, "../../firestore.rules"), "utf8")}
  });
});
test.after(async () => { if (env) await env.cleanup(); });

test("unauthenticated clients cannot read user profiles", async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users/user-a"), {uid:"user-a", balance:0, role:"user"});
  });
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "users/user-a")));
});

test("user can read own profile but cannot read another profile", async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users/user-a"), {uid:"user-a", balance:100, role:"user"});
    await setDoc(doc(context.firestore(), "users/user-b"), {uid:"user-b", balance:200, role:"user"});
  });
  const db = env.authenticatedContext("user-a").firestore();
  await assertSucceeds(getDoc(doc(db, "users/user-a")));
  await assertFails(getDoc(doc(db, "users/user-b")));
});

test("client cannot modify balance or role, but can update display name", async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "users/user-a"), {uid:"user-a", balance:100, role:"user", name:"A"});
  });
  const db = env.authenticatedContext("user-a").firestore();
  await assertSucceeds(updateDoc(doc(db, "users/user-a"), {name:"Nama Baru"}));
  await assertFails(updateDoc(doc(db, "users/user-a"), {balance:999999}));
  await assertFails(updateDoc(doc(db, "users/user-a"), {role:"admin"}));
});

test("AI messages, ledgers, and top-ups are server-write-only", async () => {
  const db = env.authenticatedContext("user-a").firestore();
  await assertFails(setDoc(doc(db, "ai_users/user-a/rooms/r1/messages/m1"), {text:"forged"}));
  await assertFails(setDoc(doc(db, "balance_ledger/fake"), {uid:"user-a", amount:1000000}));
  await assertFails(setDoc(doc(db, "topup_transactions/fake"), {uid:"user-a", status:"PAID"}));
});
