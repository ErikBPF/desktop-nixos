import type { FauxResponseStep } from "@earendil-works/pi-ai";
import { createModels } from "@earendil-works/pi-ai";
import { fauxAssistantMessage, fauxProvider, fauxText, fauxToolCall } from "@earendil-works/pi-ai/providers/faux";
import { createRegistry, defineExtension, defineTool, Harness, MemoryStorage } from "@earendil-works/pi-durable";
import { CODEMODE_TOOL_NAME, createCodemodeExtension } from "@earendil-works/pi-durable/codemode";
import { arr, num, obj } from "@earendil-works/pi-schema";
import { CodemodeSandbox } from "@earendil-works/pi-codemode";
import { describe, expect, it } from "vitest";
import { CONTEXT } from "../src/harness.js";

describe("code mode", () => {
	it("calls a nested tool and returns only the filtered script output", async () => {
		const faux = fauxProvider();
		const models = createModels();
		models.setProvider(faux.provider);
		faux.setResponses([
			fauxAssistantMessage(
				[
					fauxToolCall(CODEMODE_TOOL_NAME, {
						code: "const r = await tools.values({}); return r.values.filter((n) => n > 2).length;",
					}),
				],
				{ stopReason: "toolUse" },
			),
			fauxAssistantMessage([fauxText("filtered 2")]),
		] satisfies FauxResponseStep[]);

		const values = defineTool({
			name: "values",
			description: "Return four numbers.",
			parameters: obj({}),
			structuredOutputSchema: obj({ values: arr(num()) }),
			execute: async () => ({
				output: [{ type: "text", text: "[1,2,3,4]" }],
				structuredOutput: { values: [1, 2, 3, 4] },
			}),
		});

		const registry = createRegistry();
		registry.install(createCodemodeExtension({ sandbox: new CodemodeSandbox({ memoryLimitBytes: 64 * 1024 * 1024 }) }));
		registry.install(defineExtension({ name: "test-values", tools: [values] }));
		const harness = await Harness.open(new MemoryStorage(), { models, registry }, CONTEXT);
		const root = await harness.root(CONTEXT, { agent: { model: { provider: "faux", modelId: "faux-1" } } });

		const settled = await (
			await root.submit({ type: "input", content: "filter the numbers", requestId: "codemode" }, CONTEXT)
		).wait(CONTEXT);
		expect(settled.status).toBe("done");

		const page = await root.entries({ order: "ascending" }, 50, undefined, CONTEXT);
		const codemodeResult = page.items.find(
			(entry) =>
				entry.model?.[0]?.role === "toolResult" &&
				(entry.model[0] as { toolName?: string }).toolName === CODEMODE_TOOL_NAME,
		);
		const serialized = JSON.stringify(codemodeResult?.model?.[0]);
		const content = (codemodeResult?.model?.[0] as { content: { type: string; text?: string }[] } | undefined)?.content;
		const text = (content ?? []).flatMap((part) => (part.text === undefined ? [] : [part.text])).join("\n").trim();
		expect(text.endsWith("2")).toBe(true);
		// The raw array stayed inside the sandbox; only the script output reached the model.
		expect(serialized).not.toContain("1,2,3,4");

		await harness.close(CONTEXT);
	});
});
