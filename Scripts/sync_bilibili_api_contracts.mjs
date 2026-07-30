#!/usr/bin/env node

import { readFileSync, copyFileSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(scriptDirectory, "..");
const canonicalPath = resolve(
  projectRoot,
  "Sources/FocusCore/Resources/bilibili-api-contracts.json",
);
const kotlinMirrorPath = resolve(
  projectRoot,
  "focus-core/src/commonMain/resources/bilibili-api-contracts.json",
);

function usage() {
  process.stderr.write(
    "Usage: sync_bilibili_api_contracts.mjs --check | --sync | --validate-source [bilibili-api-path]\n",
  );
}

function readJSON(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

function validateLocalSnapshot(snapshot) {
  if (snapshot.schemaVersion !== 1) {
    throw new Error("Unsupported local API contract schemaVersion");
  }
  if (!snapshot.source?.repository || !snapshot.source?.validatedCommit) {
    throw new Error("Missing API contract validation provenance");
  }

  const endpoints = Object.entries(snapshot.endpoints ?? {});
  if (endpoints.length < 40) {
    throw new Error(`Local API contract subset is unexpectedly small (${endpoints.length})`);
  }
  for (const [key, endpoint] of endpoints) {
    if (!/^https:\/\//.test(endpoint.url)) {
      throw new Error(`Endpoint ${key} is not HTTPS: ${endpoint.url}`);
    }
    if (!["GET", "POST", "DELETE", "PATCH", "PUT"].includes(endpoint.method)) {
      throw new Error(`Endpoint ${key} has unsupported method ${endpoint.method}`);
    }
  }
}

function flattenSource(category, value, path = [], output = {}) {
  for (const [name, child] of Object.entries(value)) {
    if (!child || typeof child !== "object") {
      continue;
    }
    const nextPath = [...path, name];
    if (typeof child.url === "string" && typeof child.method === "string") {
      output[`${category}.${nextPath.join(".")}`] = child;
    } else {
      flattenSource(category, child, nextPath, output);
    }
  }
  return output;
}

function check() {
  const canonical = readFileSync(canonicalPath);
  const mirror = readFileSync(kotlinMirrorPath);
  if (!canonical.equals(mirror)) {
    throw new Error(
      "API contract copies differ; run ./Scripts/sync_bilibili_api_contracts.mjs --sync",
    );
  }
  const snapshot = JSON.parse(canonical.toString("utf8"));
  validateLocalSnapshot(snapshot);
  process.stdout.write(
    `API contracts are synchronized (${Object.keys(snapshot.endpoints).length} independently maintained endpoints)\n`,
  );
}

function sync() {
  const snapshot = readJSON(canonicalPath);
  validateLocalSnapshot(snapshot);
  mkdirSync(dirname(kotlinMirrorPath), { recursive: true });
  copyFileSync(canonicalPath, kotlinMirrorPath);
  process.stdout.write("Synchronized local API contract mirror\n");
}

function validateSource(sourceRootArgument) {
  const sourceRoot = resolve(projectRoot, sourceRootArgument ?? "../bilibili-api");
  const sourceApiDirectory = resolve(sourceRoot, "bilibili_api/data/api");
  const local = readJSON(canonicalPath);
  validateLocalSnapshot(local);

  const categories = new Set(
    Object.keys(local.endpoints).map((key) => key.split(".", 1)[0]),
  );
  const sourceEndpoints = {};
  for (const category of categories) {
    flattenSource(
      category,
      readJSON(resolve(sourceApiDirectory, `${category}.json`)),
      [],
      sourceEndpoints,
    );
  }

  const mismatches = [];
  for (const [key, endpoint] of Object.entries(local.endpoints)) {
    const source = sourceEndpoints[key];
    if (!source) {
      mismatches.push(`${key}: missing from sibling source`);
      continue;
    }
    if (source.url !== endpoint.url || source.method.toUpperCase() !== endpoint.method) {
      mismatches.push(
        `${key}: local ${endpoint.method} ${endpoint.url}; sibling ${source.method} ${source.url}`,
      );
    }
  }
  if (mismatches.length > 0) {
    throw new Error(`API contract validation failed:\n${mismatches.join("\n")}`);
  }

  const commit = execFileSync("git", ["-C", sourceRoot, "rev-parse", "HEAD"], {
    encoding: "utf8",
  }).trim();
  process.stdout.write(
    `Validated ${Object.keys(local.endpoints).length} local endpoint facts against sibling bilibili-api ${commit}\n`,
  );
}

const [mode, sourceRoot] = process.argv.slice(2);
try {
  switch (mode) {
    case "--check":
      check();
      break;
    case "--sync":
      sync();
      break;
    case "--validate-source":
      validateSource(sourceRoot);
      break;
    case "--help":
    case "-h":
      usage();
      break;
    default:
      usage();
      process.exitCode = 2;
  }
} catch (error) {
  process.stderr.write(`${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
}
