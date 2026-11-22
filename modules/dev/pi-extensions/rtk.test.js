// Assert-based check for the rtk rewrite hook. No framework: register a stub
// for the Pi package so the real rtk.js loads outside a Pi process.
import assert from "node:assert/strict";
import {execFileSync} from "node:child_process";
import {mkdtempSync, writeFileSync, chmodSync} from "node:fs";
import {registerHooks} from "node:module";
import {tmpdir} from "node:os";
import {join} from "node:path";

registerHooks({
  resolve(specifier, context, nextResolve) {
    if (specifier === "@earendil-works/pi-coding-agent") {
      return {
        url: "data:text/javascript,export function createBashTool(){return {name: 'bash', execute() {}};}",
        shortCircuit: true,
      };
    }
    return nextResolve(specifier, context);
  },
});

const {__test} = await import("./rtk.js");
const {rewrite} = __test;
const originalPath = process.env.PATH;

function fakeRtk(body) {
  const dir = mkdtempSync(join(tmpdir(), "rtk-test-"));
  const file = join(dir, "rtk");
  writeFileSync(file, `#!/bin/sh\n${body}\n`);
  chmodSync(file, 0o755);
  process.env.PATH = dir;
}

try {
  process.env.PATH = "/nonexistent";
  assert.equal(rewrite("cat big.log"), "cat big.log", "missing rtk keeps command");

  fakeRtk('test "$2" = "cat big.log" && echo "rtk read big.log"');
  assert.equal(rewrite("cat big.log"), "rtk read big.log", "successful rewrite applies");
  assert.equal(execFileSync("rtk", ["rewrite", "cat big.log"], {encoding: "utf8"}).trim(), "rtk read big.log");

  fakeRtk("exit 3");
  assert.equal(rewrite("cat big.log"), "cat big.log", "non-zero status keeps command");

  fakeRtk("printf ''");
  assert.equal(rewrite("cat big.log"), "cat big.log", "empty rewrite keeps command");
} finally {
  process.env.PATH = originalPath;
}

console.log("ok - rtk rewrite fallback checks");
