import assert from "node:assert/strict";
import { pathToFileURL } from "node:url";
import rtk from "../../modules/dev/opencode-plugins-v2/rtk/index.js";

const hooks = [];
await rtk.setup({ shell: { hook: async (...args) => hooks.push(args) } });
assert.equal(hooks.length, 1, "RTK binary required for this check");
assert.equal(hooks[0][0], "create.before");
const event = { shell: "/bin/bash", env: {}, command: "git status --short" };
hooks[0][1](event);
assert.equal(event.command, "git status --short", "permission input must stay unchanged");
assert.equal(event.env.OPENCODE_RTK_REAL_SHELL, "/bin/bash");
assert.ok(event.shell.endsWith("/opencode-plugins-v2/rtk/zsh"));
const unsupported = { shell: "/bin/fish", env: {} };
hooks[0][1](unsupported);
assert.deepEqual(unsupported, { shell: "/bin/fish", env: {} });

const packageRoot = process.argv[2];
assert.ok(packageRoot, "Pass realized Ponytail V2 adapter package root");
const { default: ponytail } = await import(pathToFileURL(`${packageRoot}/index.js`));
assert.equal(ponytail.id, "ponytail");
assert.equal(typeof ponytail.setup, "function");
const skills = [];
const commands = [];
const contextHooks = [];
await ponytail.setup({
  skill: { transform: async (f) => f({ add: (skill) => skills.push(skill) }) },
  command: { transform: async (f) => f({ add: (command) => commands.push(command) }) },
  session: { hook: async (...args) => contextHooks.push(args) },
});
assert.ok(skills.some((skill) => skill.id === "ponytail"));
assert.ok(commands.some((command) => command.name === "ponytail"));
assert.deepEqual(contextHooks.map(([name]) => name), ["context"]);
for (const [, callback] of contextHooks) {
  const event = { system: [{ type: "text", text: "existing" }] };
  callback(event);
  assert.ok(event.system[0].text.startsWith("existing\n\n"));
  assert.match(event.system[0].text, /PONYTAIL MODE ACTIVE/);
}
console.log("RTK pre-permission input preserved; Ponytail V2 adapter setup/transforms/injection passed");
