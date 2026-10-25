import assert from "node:assert/strict";
import test from "node:test";

test("online smoke opt-in, bounded streaming and healthy response stay offline in fixtures", async () => {
  const originalFetch = globalThis.fetch;
  const originalError = console.error;
  const failures = [];
  const originalOptIn = process.env.FOCUS_ONLINE_SMOKE;
  const originalCookie = process.env.FOCUS_BILIBILI_COOKIE;
  const originalExitCode = process.exitCode;
  let sequence = 0;
  async function run() {
    process.exitCode = undefined;
    await import(`./run_online_smoke.mjs?fixture=${sequence++}`);
    return process.exitCode ?? 0;
  }
  try {
    console.error = (message) => failures.push(message);
    delete process.env.FOCUS_ONLINE_SMOKE;
    globalThis.fetch = () => { throw new Error("Default path must not fetch"); };
    assert.equal(await run(), 0);

    process.env.FOCUS_ONLINE_SMOKE = "1";
    process.env.FOCUS_BILIBILI_COOKIE = "SESSDATA=fixture; bili_jct=fixture";
    let pulls = 0;
    let cancelled = false;
    globalThis.fetch = async (_url, options) => {
      assert.equal(options.redirect, "error");
      return new Response(new ReadableStream({
        pull(controller) {
          pulls += 1;
          controller.enqueue(new Uint8Array(64 * 1024));
          if (pulls === 64) controller.close();
        },
        cancel() { cancelled = true; },
      }));
    };
    assert.equal(await run(), 1);
    assert.equal(cancelled, true, "Stop the stream instead of buffering its remaining body");
    assert.ok(pulls <= 18, `Expected bounded reads, received ${pulls} chunks`);
    assert.deepEqual(failures, ["FAIL online smoke: contract_mismatch"]);

    cancelled = false;
    globalThis.fetch = async () => new Response(new ReadableStream({
      cancel() { cancelled = true; },
    }), { headers: { "Content-Length": String(2 * 1024 * 1024) } });
    assert.equal(await run(), 1);
    assert.equal(cancelled, true, "Reject and cancel a declared oversized body before reading it");

    globalThis.fetch = async () => new Response(JSON.stringify({
      code: 0,
      data: { isLogin: true, wbi_img: { img_url: "fixture-img", sub_url: "fixture-sub" } },
    }));
    assert.equal(await run(), 0);
  } finally {
    globalThis.fetch = originalFetch;
    console.error = originalError;
    if (originalOptIn === undefined) delete process.env.FOCUS_ONLINE_SMOKE;
    else process.env.FOCUS_ONLINE_SMOKE = originalOptIn;
    if (originalCookie === undefined) delete process.env.FOCUS_BILIBILI_COOKIE;
    else process.env.FOCUS_BILIBILI_COOKIE = originalCookie;
    process.exitCode = originalExitCode;
  }
});
