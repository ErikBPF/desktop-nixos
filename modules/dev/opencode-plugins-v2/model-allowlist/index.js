export default {
  id: "homelab-model-allowlist",
  async setup(ctx) {
    const approved = ctx.options?.models ?? {};
    await ctx.model.transform((editor) => {
      for (const model of editor.list()) {
        if (!approved[model.providerID]?.includes(model.id)) {
          editor.remove(model.providerID, model.id);
        }
      }
    });
  },
};
