import assert from "node:assert/strict";
import { GatewayHeaders } from "../../modules/dev/opencode-plugins/gateway-headers.mjs";

const hooks = await GatewayHeaders();
for (const providerID of ["litellm", "work", "other"]) {
  for (const sessionID of ["ses_first", "ses_second"]) {
    const output = { headers: { existing: "preserved" } };
    await hooks["chat.headers"]({ model: { providerID }, sessionID }, output);
    assert.deepEqual(output.headers, {
      existing: "preserved",
      ...(providerID === "other" ? {} : { "x-opencode-session": sessionID }),
    });
  }
}
console.log("Gateway session headers: both gateways, distinct sessions, unrelated provider, preserved headers passed");
