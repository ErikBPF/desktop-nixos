export default {
  id: "homelab-gateway-headers",
  async setup(ctx) {
    for (const providerID of ["litellm", "work"]) {
      await ctx.session.hook("model.request", (event) => {
        event.headers["x-opencode-session"] = event.sessionID;
      }, { providerID });
    }
  },
};
