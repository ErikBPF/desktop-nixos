import { execFile } from "node:child_process";
import { basename } from "node:path";
import { fileURLToPath } from "node:url";

// Rewrite in the shell shim AFTER OpenCode checks the original command's
// permissions. A plain `execute.before` rewrite can bypass bare-command deny
// rules in v2.0.21 (rtk-ai/rtk#4197).
export default {
  id: "rtk",
  async setup(ctx) {
    const available = await new Promise((resolve) => {
      execFile("rtk", ["--version"], { timeout: 5_000 }, (error) => resolve(!error));
    });
    if (!available) {
      console.warn("[rtk] binary not found in PATH — plugin disabled");
      return;
    }
    await ctx.shell.hook("create.before", (event) => {
      if (!["bash", "zsh", "sh"].includes(basename(event.shell))) return;
      event.env.OPENCODE_RTK_REAL_SHELL = event.shell;
      event.shell = fileURLToPath(new URL("./zsh", import.meta.url));
    });
  },
};
