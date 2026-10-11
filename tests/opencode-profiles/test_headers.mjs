import assert from "node:assert/strict";
import plugin from "../../modules/dev/opencode-plugins-v2/gateway-headers/index.js";

// v2 plugin API: setup(ctx) registers per-provider model.request hooks that
// stamp OpenCode Go's session routing header onto gateway-bound requests.
const hooks = [];
await plugin.setup({ session: { hook: async (...args) => hooks.push(args) } });

assert.equal(hooks.length, 2);
for (const [name, callback, filter] of hooks) {
  assert.equal(name, "model.request");
  assert.ok(["litellm", "work"].includes(filter.providerID));
  for (const sessionID of ["ses_first", "ses_second"]) {
    const event = { sessionID, headers: { existing: "preserved" } };
    callback(event);
    assert.deepEqual(event.headers, { existing: "preserved", "x-opencode-session": sessionID });
  }
}
assert.deepEqual(hooks.map((hook) => hook[2].providerID).sort(), ["litellm", "work"]);
console.log("Gateway session headers: both gateways, distinct sessions, preserved headers passed");
