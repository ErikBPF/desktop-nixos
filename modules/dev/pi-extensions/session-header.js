// Adds the opencode-compatible session header to the two gateways that
// attribute traffic per session. `before_provider_headers` carries only
// `headers`; the provider comes from `ctx.model`.
export default function (pi) {
  pi.on("before_provider_headers", (event, ctx) => {
    try {
      const provider = ctx?.model?.provider;
      if (provider !== "litellm" && provider !== "work") return;
      const sessionId = ctx?.sessionManager?.getSessionId?.();
      if (!event?.headers || typeof sessionId !== "string" || sessionId.length === 0) return;
      event.headers["x-opencode-session"] = sessionId;
    } catch {
      // Pi logs header-hook errors and continues; leave the headers untouched.
    }
  });
}
