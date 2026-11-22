import type { FauxResponseStep } from "@earendil-works/pi-ai";
import { createModels } from "@earendil-works/pi-ai";
import { fauxAssistantMessage, fauxProvider, fauxText, fauxToolCall } from "@earendil-works/pi-ai/providers/faux";
import {
	createRegistry,
	defineExtension,
	defineTool,
	Harness,
	MemoryStorage,
	type ConversationId,
} from "@earendil-works/pi-durable";
import { obj } from "@earendil-works/pi-schema";
import { describe, expect, it } from "vitest";
import { CONTEXT } from "../src/harness.js";
import { createSubagentExtension } from "../src/subagent.js";

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

function textOf(message: { content: string | readonly { type: string; text?: string }[] }): string {
	return typeof message.content === "string"
		? message.content
		: message.content.flatMap((part) => (part.text === undefined ? [] : [part.text])).join("");
}

function routeFor(request: { messages: readonly { role: string; content: unknown }[] }): FauxResponseStep {
	const last = request.messages.findLast((message) => message.role !== "system");
	const text = last === undefined ? "" : textOf(last as { content: string | { type: string; text?: string }[] });
	if (last?.role === "toolResult") return fauxAssistantMessage([fauxText("Tool finished.")]);
	if (text.includes("spawn a reader")) {
		return fauxAssistantMessage(
			[fauxToolCall("subagent", { action: "spawn", name: "reader", message: "child-task" })],
			{ stopReason: "toolUse" },
		);
	}
	if (text.includes("spawn twice")) {
		return fauxAssistantMessage([fauxToolCall("spawn_twice", {})], { stopReason: "toolUse" });
	}
	if (text.includes("[subagent")) return fauxAssistantMessage([fauxText("Noted.")]);
	if (text.includes("child-task")) return fauxAssistantMessage([fauxText("2, 3, 5")]);
	return fauxAssistantMessage([fauxText("ok")]);
}

async function openSubagentHarness() {
	const faux = fauxProvider();
	const models = createModels();
	models.setProvider(faux.provider);
	faux.setResponses(Array.from({ length: 60 }, () => routeFor));

	const spawnTwice = defineTool({
		name: "spawn_twice",
		description: "Spawn the same subagent twice through nested calls.",
		parameters: obj({}),
		execute: async (_args, api, context) => {
			const first = await api.executeTool(
				"subagent",
				{ action: "spawn", name: "twin", message: "child-task" },
				context,
			);
			const second = await api.executeTool(
				"subagent",
				{ action: "spawn", name: "twin", message: "child-task" },
				context,
			);
			return {
				output: [{ type: "text", text: `first=${first.isError} second=${second.isError}` }],
			};
		},
	});

	const registry = createRegistry();
	registry.install(createSubagentExtension({ childModel: { provider: "faux", modelId: "faux-1" } }));
	registry.install(defineExtension({ name: "test-spawn-twice", tools: [spawnTwice] }));
	const harness = await Harness.open(new MemoryStorage(), { models, registry }, CONTEXT);
	const root = await harness.root(CONTEXT, { agent: { model: { provider: "faux", modelId: "faux-1" } } });
	return { harness, root };
}

async function conversations(harness: Harness) {
	const page = await harness.commit((tx) => tx.scanConversations({}, 100), CONTEXT);
	return page.items;
}

describe("subagents", () => {
	it("spawns a separate owned conversation and reports its answer to the parent", async () => {
		const { harness, root } = await openSubagentHarness();
		try {
			const settled = await (
				await root.submit({ type: "input", content: "spawn a reader", requestId: "spawn" }, CONTEXT)
			).wait(CONTEXT);
			expect(settled.status).toBe("done");

			let report = "";
			for (let attempt = 0; attempt < 300 && report === ""; attempt++) {
				await sleep(10);
				const page = await root.entries({ order: "descending" }, 50, undefined, CONTEXT);
				report = page.items.map((entry) => JSON.stringify(entry.model ?? [])).find((text) => text.includes("[subagent")) ?? "";
			}
			expect(report).toContain("[subagent reader answered");
			expect(report).toContain("2, 3, 5");

			const all = await conversations(harness);
			const owned = all.filter((conversation) => conversation.owner !== undefined);
			expect(owned).toHaveLength(1);
			expect(owned[0]?.owner?.taskId).toBeTypeOf("number");
			expect(owned[0]?.id).not.toBe(root.id);

			const anchor = await harness.getTask(owned[0]!.owner!.taskId, CONTEXT);
			expect(anchor?.kind).toBe("app.pi-harness.subagent-anchor");
			expect(anchor?.background).toBe(true);

			const child = await harness.conversation(owned[0]!.id as ConversationId, CONTEXT);
			const childEntries = await child!.entries({ order: "ascending" }, 50, undefined, CONTEXT);
			expect(JSON.stringify(childEntries.items)).toContain("2, 3, 5");
		} finally {
			await harness.close(CONTEXT);
		}
	});

	it("does not create a second child for the same name", async () => {
		const { harness, root } = await openSubagentHarness();
		try {
			const settled = await (
				await root.submit({ type: "input", content: "spawn twice", requestId: "spawn-twice" }, CONTEXT)
			).wait(CONTEXT);
			expect(settled.status).toBe("done");
			const owned = (await conversations(harness)).filter((conversation) => conversation.owner !== undefined);
			expect(owned).toHaveLength(1);
		} finally {
			await harness.close(CONTEXT);
		}
	});
});
