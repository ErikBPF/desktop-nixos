import { mkdir, mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createModels } from "@earendil-works/pi-ai";
import type { FauxResponseStep } from "@earendil-works/pi-ai";
import { fauxAssistantMessage, fauxProvider, fauxText, fauxToolCall } from "@earendil-works/pi-ai/providers/faux";
import {
	createRegistry,
	defineExtension,
	defineTool,
	Harness,
	MemoryStorage,
} from "@earendil-works/pi-durable";
import { obj, str } from "@earendil-works/pi-schema";
import { describe, expect, it } from "vitest";
import { CONTEXT } from "../src/harness.js";
import { openHarness, resolveDbPath } from "../src/harness.js";

const echo = defineTool({
	name: "echo",
	description: "Return the input text.",
	parameters: obj({ text: str() }),
	execute: async (args) => ({ output: [{ type: "text", text: args.text }] }),
});

describe("durable conversation", () => {
	it("gives projects with the same basename different databases", () => {
		expect(resolveDbPath("/work/foo", "/state")).not.toBe(resolveDbPath("/personal/foo", "/state"));
	});

	it("keeps a stored agent on reopen unless a flag is explicit", async () => {
		const root = await mkdtemp(join(tmpdir(), "pi-harness-agent-"));
		const project = join(root, "project");
		const dbPath = join(root, "session.db");
		await mkdir(project);

		const first = await openHarness({
			projectDir: project,
			dbPath,
			mcpServers: false,
			model: { provider: "work", modelId: "glm-5.3-flash" },
			thinkingLevel: "low",
		});
		try {
			expect((await first.root.agent(CONTEXT)).model).toEqual({ provider: "work", modelId: "glm-5.3-flash" });
		} finally {
			await first.close();
		}

		const reopened = await openHarness({ projectDir: project, dbPath, mcpServers: false });
		try {
			expect(reopened.model).toEqual({ provider: "work", modelId: "glm-5.3-flash" });
			expect((await reopened.root.agent(CONTEXT)).thinkingLevel).toBe("low");
		} finally {
			await reopened.close();
		}

		const explicit = await openHarness({
			projectDir: project,
			dbPath,
			mcpServers: false,
			model: { provider: "litellm", modelId: "deepseek-v4.1-flash" },
			thinkingLevel: "high",
		});
		try {
			expect(explicit.model).toEqual({ provider: "litellm", modelId: "deepseek-v4.1-flash" });
			expect((await explicit.root.agent(CONTEXT)).thinkingLevel).toBe("high");
		} finally {
			await explicit.close();
		}
	});

	it("runs a two-turn conversation with a tool call and prints the final answer", async () => {
		const faux = fauxProvider();
		const models = createModels();
		models.setProvider(faux.provider);
		faux.setResponses([
			fauxAssistantMessage([fauxToolCall("echo", { text: "from the tool" })], { stopReason: "toolUse" }),
			fauxAssistantMessage([fauxText("The tool said: from the tool")]),
		] satisfies FauxResponseStep[]);

		const registry = createRegistry();
		registry.install(defineExtension({ name: "test-echo", tools: [echo] }));
		const harness = await Harness.open(new MemoryStorage(), { models, registry }, CONTEXT);
		const root = await harness.root(CONTEXT, { agent: { model: { provider: "faux", modelId: "faux-1" } } });

		const settled = await (
			await root.submit({ type: "input", content: "Use the echo tool.", requestId: "two-turn" }, CONTEXT)
		).wait(CONTEXT);
		expect(settled.status).toBe("done");
		if (settled.status !== "done" || settled.type !== "input") throw new Error("run failed");

		const answer = (
			await root.entries({ order: "ascending" }, 50, undefined, CONTEXT)
		).items.find((entry) => entry.id === settled.answer);
		expect(answer?.model?.[0]?.role).toBe("assistant");
		const text = (answer?.model?.[0] as { content: { type: string; text?: string }[] }).content
			.map((part) => part.text ?? "")
			.join("");
		expect(text).toBe("The tool said: from the tool");

		const page = await root.entries({ order: "ascending" }, 50, undefined, CONTEXT);
		const toolResult = page.items.find((entry) => entry.model?.[0]?.role === "toolResult");
		expect(JSON.stringify(toolResult?.model?.[0])).toContain("from the tool");

		await harness.close(CONTEXT);
	});
});
