"use strict";

const admin = require("firebase-admin");
if (!admin.apps.length) admin.initializeApp();

Object.assign(exports, require("./ai"));
Object.assign(exports, require("./payments"));
