import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { FauxResponseStep } from "@earendil-works/pi-ai";
import { createModels } from "@earendil-works/pi-ai";
import { fauxAssistantMessage, fauxProvider, fauxText, fauxToolCall } from "@earendil-works/pi-ai/providers/faux";
import { createRegistry, Harness, MemoryStorage } from "@earendil-works/pi-durable";
import { createCodingTools } from "@earendil-works/pi-durable/tools";
import { describe, expect, it } from "vitest";
import { CONTEXT, createExecutionEnv } from "../src/harness.js";

async function harnessWithFile(env: ReturnType<typeof createExecutionEnv> | undefined) {
	const project = await mkdtemp(join(tmpdir(), "pi-harness-tools-"));
	const file = join(project, "hello.txt");
	await writeFile(file, "hello from env\n");

	const faux = fauxProvider();
	const models = createModels();
	models.setProvider(faux.provider);
	faux.setResponses([
		fauxAssistantMessage([fauxToolCall("read", { path: file })], { stopReason: "toolUse" }),
		fauxAssistantMessage([fauxText("read it")]),
	] satisfies FauxResponseStep[]);

	const registry = createRegistry();
	registry.install(createCodingTools());
	const harness = await Harness.open(new MemoryStorage(), { models, registry, ...(env === undefined ? {} : { env }) }, CONTEXT);
	const root = await harness.root(CONTEXT, {
		agent: { model: { provider: "faux", modelId: "faux-1" }, cwd: project },
	});
	await (await root.submit({ type: "input", content: "read hello.txt" }, CONTEXT)).wait(CONTEXT);
	const transcript = JSON.stringify(await root.context(CONTEXT));
	await harness.close(CONTEXT);
	return transcript;
}

describe("coding tools", () => {
	it("reads a project file through the execution environment", async () => {
		const transcript = await harnessWithFile(createExecutionEnv());
		expect(transcript).toContain("hello from env");
		expect(transcript).not.toContain("No execution environment");
	});

	it("fails a coding tool when no environment is configured", async () => {
		// Pins the failure the harness had before the environment was wired:
		// every built-in tool answered "No execution environment is configured".
		const transcript = await harnessWithFile(undefined);
		expect(transcript).toContain("No execution environment");
	});
});
