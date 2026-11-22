// Replaces the built-in bash tool so every command passes through `rtk
// rewrite` first. Pi has no approval step to bypass, so the OpenCode shell
// shim is unnecessary: the rewrite happens in the spawn hook, synchronously,
// and an unavailable or failing rtk leaves the command unchanged.
import {execFileSync} from "node:child_process";
import {createBashTool} from "@earendil-works/pi-coding-agent";

function rewrite(command) {
  if (typeof command !== "string" || command.length === 0) return command;
  try {
    const rewritten = execFileSync("rtk", ["rewrite", command], {
      encoding: "utf8",
      timeout: 2000,
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    return rewritten.length > 0 ? rewritten : command;
  } catch {
    return command;
  }
}

export default function (pi) {
  const bashTool = createBashTool(process.cwd(), {
    spawnHook: ({command, cwd, env}) => ({command: rewrite(command), cwd, env}),
  });
  pi.registerTool({...bashTool, name: "bash"});
}

export const __test = {rewrite};
