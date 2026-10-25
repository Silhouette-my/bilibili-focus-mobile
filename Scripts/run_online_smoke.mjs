#!/usr/bin/env node

/**
 * Explicitly opt-in, read-only Bilibili API smoke check.
 *
 * Secrets are accepted only through the process environment and are never
 * printed, placed in a URL, or included in thrown error output.
 */

const OPT_IN_VARIABLE = "FOCUS_ONLINE_SMOKE";
const COOKIE_VARIABLE = "FOCUS_BILIBILI_COOKIE";
const NAV_URL = "https://api.bilibili.com/x/web-interface/nav";
const MAX_COOKIE_BYTES = 16 * 1024;
const MAX_RESPONSE_BYTES = 1024 * 1024;

if (process.env[OPT_IN_VARIABLE] !== "1") {
  console.log(`SKIP online smoke: set ${OPT_IN_VARIABLE}=1 to opt in`);
} else {
  const cookieHeader = process.env[COOKIE_VARIABLE] ?? "";
  const cookieValues = validateCookieHeader(cookieHeader);
  if (!cookieValues) {
    fail(`configuration_invalid (set ${COOKIE_VARIABLE} to a Cookie header value)`, 2);
  } else if (!(cookieValues.get("sessdata")?.length > 0)) {
    fail("login_health=not_logged_in", 2);
  } else {
    await runSmoke(cookieHeader, cookieValues);
  }
}

async function runSmoke(cookie, values) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 15_000);
  try {
    const response = await fetch(NAV_URL, {
      method: "GET",
      redirect: "error",
      cache: "no-store",
      signal: controller.signal,
      headers: {
        Accept: "application/json, text/plain, */*",
        Cookie: cookie,
        Referer: "https://www.bilibili.com/",
        "User-Agent":
          "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 " +
          "(KHTML, like Gecko) Version/18.0 Safari/605.1.15",
      },
    });

    const declaredLength = Number(response.headers.get("content-length") ?? "0");
    if (Number.isFinite(declaredLength) && declaredLength > MAX_RESPONSE_BYTES) {
      await response.body?.cancel();
      fail("contract_mismatch", 1);
      return;
    }

    const body = await readBoundedBody(response);
    if (body === null) {
      fail("contract_mismatch", 1);
      return;
    }

    let payload;
    try {
      payload = JSON.parse(body);
    } catch {
      fail("contract_mismatch", 1);
      return;
    }

    const health = classifyHealth(
      response.status,
      payload,
      (values.get("bili_jct")?.length ?? 0) > 0,
    );
    if (health !== "healthy") {
      fail(`login_health=${health}`, 1);
      return;
    }

    const wbi = payload?.data?.wbi_img;
    const hasWbiBootstrap =
      typeof wbi?.img_url === "string" &&
      wbi.img_url.length > 0 &&
      typeof wbi?.sub_url === "string" &&
      wbi.sub_url.length > 0;
    if (!hasWbiBootstrap) {
      fail("contract_mismatch", 1);
      return;
    }

    console.log("PASS online smoke: login_health=healthy; wbi_bootstrap=available");
  } catch {
    fail("login_health=network_unavailable", 1);
  } finally {
    clearTimeout(timeout);
  }
}

async function readBoundedBody(response) {
  if (!response.body) return "";
  const reader = response.body.getReader();
  const chunks = [];
  let bytes = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) return Buffer.concat(chunks, bytes).toString("utf8");
      bytes += value.byteLength;
      if (bytes > MAX_RESPONSE_BYTES) {
        await reader.cancel();
        return null;
      }
      chunks.push(Buffer.from(value));
    }
  } finally {
    reader.releaseLock();
  }
}

function classifyHealth(status, payload, hasCsrf) {
  if (status === 401) return "session_expired";
  if (status === 403) return "wbi_risk_controlled";
  if (status < 200 || status >= 300) return "unknown";

  const code = Number(payload?.code);
  if (code === -403 || code === -352) return "wbi_risk_controlled";
  if (code === -101) return "session_expired";
  if (code !== 0 || typeof payload?.data?.isLogin !== "boolean") return "unknown";
  if (!payload.data.isLogin) return "session_expired";
  return hasCsrf ? "healthy" : "missing_csrf";
}

function validateCookieHeader(value) {
  if (
    value.length === 0 ||
    Buffer.byteLength(value, "utf8") > MAX_COOKIE_BYTES ||
    /[\u0000-\u001F\u007F]/u.test(value)
  ) {
    return null;
  }

  const values = new Map();
  for (const part of value.split(";")) {
    const separator = part.indexOf("=");
    if (separator <= 0) return null;
    const name = part.slice(0, separator).trim();
    const cookieValue = part.slice(separator + 1).trim();
    if (!/^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$/u.test(name)) {
      return null;
    }
    values.set(name.toLowerCase(), cookieValue);
  }
  return values;
}

function fail(reason, exitCode) {
  console.error(`FAIL online smoke: ${reason}`);
  process.exitCode = exitCode;
}
