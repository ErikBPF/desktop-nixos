import assert from "node:assert/strict";
import test from "node:test";
import plugin from "../../modules/dev/opencode-plugins-v2/three-level/index.js";

function fixture() {
  const tools = new Map(), sessions = new Map(), prompts = [], notices = [];
  const waiters = new Map();
  sessions.set("l1", { id: "l1", agent: "pilot-l1", location: { directory: "/project" } });
  const ctx = {
    location: { directory: "/wrong-plugin-location" },
    tool: { transform: async fn => fn({ add: tool => tools.set(tool.name, tool) }) },
    session: {
      get: async ({ sessionID }) => sessions.get(sessionID),
      create: async input => {
        const session = { ...input, id: `l2-${sessions.size}` };
        sessions.set(session.id, session);
        return session;
      },
      prompt: async input => prompts.push(input),
      wait: ({ sessionID }, { signal } = {}) => new Promise((resolve, reject) => {
        waiters.set(sessionID, resolve);
        signal?.addEventListener("abort", () => reject(new Error("aborted")), { once: true });
      }),
      context: async () => [{ type: "assistant", content: [{ type: "text", text: "Verified slice result" }] }],
      synthetic: async input => notices.push(input),
    },
  };
  return { ctx, tools, sessions, prompts, notices, waiters };
}
const caller = { sessionID: "l1", agent: "pilot-l1", messageID: "message", id: "call" };

function withL2Model(value, run) {
  const previous = process.env.OPENCODE_THREE_LEVEL_L2_MODEL;
  if (value === undefined) delete process.env.OPENCODE_THREE_LEVEL_L2_MODEL;
  else process.env.OPENCODE_THREE_LEVEL_L2_MODEL = value;
  return run().finally(() => {
    if (previous === undefined) delete process.env.OPENCODE_THREE_LEVEL_L2_MODEL;
    else process.env.OPENCODE_THREE_LEVEL_L2_MODEL = previous;
  });
}

test("cancellation during authorization cannot create a new slice", async () => {
  const f = fixture();
  let release;
  f.ctx.session.get = () => new Promise(resolve => { release = resolve; });
  const cleanup = await plugin.setup(f.ctx);
  const controller = new AbortController();
  const pending = f.tools.get("dispatch_slice").execute(
    { title: "Cancelled", task: "work" }, { ...caller, signal: controller.signal });
  controller.abort();
  await cleanup();
  release(f.sessions.get("l1"));
  await assert.rejects(pending);
  assert.equal(f.sessions.size, 1);
  assert.equal(f.prompts.length, 0);
});

test("dispatch uses the backend L2 model and reports idle outcome", async () => {
  await withL2Model("litellm/deepseek-v4.1-flash#high", async () => {
    const f = fixture();
    const cleanup = await plugin.setup(f.ctx);
    assert.ok(f.tools.has("dispatch_slice"), "real dispatch tool must be registered");
    const result = await f.tools.get("dispatch_slice").execute({ title: "Slice A", task: "Do scoped work" }, caller);
    const { sessionID } = JSON.parse(result.content);
    const child = f.sessions.get(sessionID);
    assert.equal(child.parentID, undefined);
    assert.equal(child.agent, "pilot-l2");
    assert.deepEqual(child.model, { providerID: "litellm", id: "deepseek-v4.1-flash", variant: "high" });
    assert.equal(child.location.directory, "/project");
    assert.equal(f.prompts[0].sessionID, sessionID);
    assert.notEqual(f.prompts[0].resume, false);
    child.outcome = "failed";
    f.waiters.get(sessionID)();
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(f.notices.length, 1);
    assert.equal(f.notices[0].sessionID, "l1");
    assert.match(f.notices[0].text, /failed/);
    assert.match(f.notices[0].text, /Verified slice result/);
    assert.doesNotMatch(f.notices[0].text, /accepted/);
    await cleanup();
  });
});

test("variant-less provider models are passed through unchanged", async () => {
  await withL2Model("work/deepseek-v4.1-flash", async () => {
    const f = fixture();
    const cleanup = await plugin.setup(f.ctx);
    await f.tools.get("dispatch_slice").execute({ title: "Slice", task: "work" }, caller);
    const child = f.sessions.get("l2-1");
    assert.deepEqual(child.model, { providerID: "work", id: "deepseek-v4.1-flash" });
    await cleanup();
  });
});

test("without an override the OpenAI pilot default is kept", async () => {
  await withL2Model(undefined, async () => {
    const f = fixture();
    const cleanup = await plugin.setup(f.ctx);
    await f.tools.get("dispatch_slice").execute({ title: "Slice", task: "work" }, caller);
    assert.deepEqual(f.sessions.get("l2-1").model, { providerID: "openai", id: "gpt-6.1-sol", variant: "high" });
    await cleanup();
  });
});

test("only invoking L1 can dispatch or inspect its associated L2 sessions", async () => {
  const f = fixture();
  const cleanup = await plugin.setup(f.ctx);
  assert.ok(f.tools.has("dispatch_slice"));
  await assert.rejects(f.tools.get("dispatch_slice").execute({ title: "Bad", task: "work" }, { ...caller, agent: "pilot-l3" }));
  assert.equal(f.prompts.length, 0);
  const result = await f.tools.get("dispatch_slice").execute({ title: "Slice", task: "work" }, caller);
  const { sessionID } = JSON.parse(result.content);
  f.sessions.set("other-l1", { ...f.sessions.get("l1"), id: "other-l1" });
  assert.ok(f.tools.has("slice_status"));
  await assert.rejects(f.tools.get("slice_status").execute({ sessionID }, { ...caller, sessionID: "other-l1" }));
  const status = await f.tools.get("slice_status").execute({ sessionID }, caller);
  assert.equal(JSON.parse(status.content).sessionID, sessionID);
  await cleanup();
});
