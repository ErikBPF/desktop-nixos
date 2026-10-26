// L2 runs on the backend's own provider, not the OpenAI pilot default.
function l2Model() {
  const raw = process.env.OPENCODE_THREE_LEVEL_L2_MODEL?.trim();
  if (!raw) return { providerID: "openai", id: "gpt-6.1-sol", variant: "high" };
  const [head, variant] = raw.split("#");
  const split = head.indexOf("/");
  if (split < 1 || split === head.length - 1) {
    throw new Error(`Invalid OPENCODE_THREE_LEVEL_L2_MODEL: ${raw}`);
  }
  return {
    providerID: head.slice(0, split),
    id: head.slice(split + 1),
    ...(variant ? { variant } : {}),
  };
}

export default {
  id: "three-level",
  async setup(ctx) {
    const lifetime = new AbortController();

    async function authorize(context) {
      const origin = await ctx.session.get({ sessionID: context.sessionID });
      if (context.agent !== "pilot-l1" || origin.agent !== "pilot-l1") {
        throw new Error("Only L1 may coordinate independent slices");
      }
      return origin;
    }

    async function status(sessionID, originID) {
      const session = await ctx.session.get({ sessionID });
      if (session.agent !== "pilot-l2" || session.metadata?.threeLevelOrigin !== originID) {
        throw new Error("Slice does not belong to this L1 session");
      }
      const messages = await ctx.session.context({ sessionID });
      const last = messages.filter(message => message.type === "assistant").at(-1);
      return {
        sessionID, outcome: session.outcome ?? "pending",
        report: last?.content.filter(part => part.type === "text").map(part => part.text).join("\n") ?? "",
      };
    }

    async function notify(sessionID, originID) {
      let report;
      try {
        await ctx.session.wait({ sessionID }, { signal: lifetime.signal });
        report = await status(sessionID, originID);
      } catch {
        if (lifetime.signal.aborted) return;
        report = { sessionID, outcome: "observation failed; inspect with slice_status" };
      }
      if (lifetime.signal.aborted) return;
      await ctx.session.synthetic({
        sessionID: originID, delivery: "queue",
        text: `L2 execution stopped. Evaluate its evidence; idle is not acceptance.\n${JSON.stringify(report)}`,
      });
    }

    await ctx.tool.transform(editor => {
      editor.add({
        name: "dispatch_slice",
        description: "Start an independent L2 slice session in this project. Supply scope, acceptance, paths, budgets and report location. Returns immediately; completion is reported to L1. Use slice_status to inspect after reconnecting.",
        input: {
          type: "object",
          properties: { title: { type: "string", minLength: 1 }, task: { type: "string", minLength: 1 } },
          required: ["title", "task"], additionalProperties: false,
        },
        execute: async (input, context) => {
          const signal = AbortSignal.any([lifetime.signal, ...(context.signal ? [context.signal] : [])]);
          signal.throwIfAborted();
          if (typeof input.title !== "string" || !input.title.trim() || typeof input.task !== "string" || !input.task.trim()) {
            throw new Error("Nonempty title and task required");
          }
          const origin = await authorize(context);
          signal.throwIfAborted();
          const slice = await ctx.session.create({
            title: input.title, agent: "pilot-l2", location: origin.location,
            model: l2Model(),
            metadata: { threeLevelOrigin: origin.id },
          }, { signal });
          try {
            signal.throwIfAborted();
            await ctx.session.prompt({ sessionID: slice.id, text: input.task }, { signal });
          } catch {
            return { content: JSON.stringify({ sessionID: slice.id, outcome: "prompt delivery uncertain; inspect this session before dispatching again" }) };
          }
          // Notifications live with this private server; durable sessions remain inspectable after restart.
          void notify(slice.id, origin.id).catch(() => {});
          return { content: JSON.stringify({ sessionID: slice.id, outcome: "dispatched" }) };
        },
      });
      editor.add({
        name: "slice_status",
        description: "Inspect a previously dispatched L2 session and its latest report. Execution outcome is not task acceptance.",
        input: {
          type: "object", properties: { sessionID: { type: "string", minLength: 1 } },
          required: ["sessionID"], additionalProperties: false,
        },
        execute: async (input, context) => {
          await authorize(context);
          return { content: JSON.stringify(await status(input.sessionID, context.sessionID)) };
        },
      });
    });
    return () => lifetime.abort();
  },
};
