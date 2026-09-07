// Custom gateway providers need OpenCode Go's actual per-session routing header.
export const GatewayHeaders = async () => ({
  "chat.headers": async ({ model, sessionID }, output) => {
    if (model.providerID === "litellm" || model.providerID === "work") {
      output.headers["x-opencode-session"] = sessionID;
    }
  },
});
