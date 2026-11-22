import { mkdir, mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { FauxResponseStep } from "@earendil-works/pi-ai";
import { createModels } from "@earendil-works/pi-ai";
import { fauxAssistantMessage, fauxProvider, fauxText, fauxToolCall } from "@earendil-works/pi-ai/providers/faux";
import {
	createRegistry,
	defineExtension,
	defineTool,
	Harness,
	MemoryStorage,
	type ConversationRecord,
	type Cursor,
	type Page,
} from "@earendil-works/pi-durable";
import { CodemodeSandbox } from "@earendil-works/pi-codemode";
import { obj, str } from "@earendil-works/pi-schema";
import { afterEach, describe, expect, it, vi } from "vitest";
import {
	CONTEXT,
	openHarness,
	type OpenedHarness,
} from "../src/harness.js";
import { describeRunFailure, findEntry, scanConversationPages } from "../src/cli.js";

const echo = defineTool({
	name: "echo",
	description: "Return the input text.",
	parameters: obj({ text: str() }),
	execute: async (args) => ({ output: [{ type: "text", text: args.text }] }),
});

async function openFaux(options: { maxTurns?: number; steps: FauxResponseStep[] }): Promise<{
	harness: Harness;
	opened: OpenedHarness;
}> {
	const faux = fauxProvider();
	const models = createModels();
	models.setProvider(faux.provider);
	faux.setResponses(options.steps);
	const registry = createRegistry();
	registry.install(defineExtension({ name: "test-echo", tools: [echo] }));
	const harness = await Harness.open(new MemoryStorage(), { models, registry }, CONTEXT);
	const root = await harness.root(CONTEXT, {
		agent: { model: { provider: "faux", modelId: "faux-1" }, maxTurns: options.maxTurns },
	});
	const opened: OpenedHarness = {
		harness,
		root,
		model: { provider: "faux", modelId: "faux-1" },
		dbPath: ":memory:",
		context: CONTEXT,
		close: () => harness.close(CONTEXT),
	};
	return { harness, opened };
}

describe("cli entry lookup", () => {
	it("finds an answer older than the recent-entry window", async () => {
		const { opened } = await openFaux({ steps: [fauxAssistantMessage([fauxText("the answer")])] });
		try {
			const settled = await (
				await opened.root.submit({ type: "input", content: "go", requestId: "old-answer" }, CONTEXT)
			).wait(CONTEXT);
			if (settled.status !== "done" || settled.type !== "input") throw new Error("run failed");

			for (let index = 0; index < 205; index += 1) {
				await (await opened.root.submit({ type: "write", entry: { kind: "test.filler" } }, CONTEXT)).wait(CONTEXT);
			}

			const recent = await opened.root.entries({ order: "descending" }, 200, undefined, CONTEXT);
			expect(recent.items.some((entry) => entry.id === settled.answer)).toBe(false);

			const answer = await findEntry(opened, settled.answer);
			expect(answer?.id).toBe(settled.answer);
			expect(JSON.stringify(answer?.model?.[0])).toContain("the answer");
		} finally {
			await opened.close();
		}
	});
});

describe("cli failure reporting", () => {
	it("names the settled turn_limit, not a stale live failure", async () => {
		const { opened } = await openFaux({
			maxTurns: 1,
			steps: [
				fauxAssistantMessage([fauxToolCall("echo", { text: "x" })], { stopReason: "toolUse" }),
				fauxAssistantMessage([fauxText("never reached")]),
			],
		});
		try {
			const settled = await (
				await opened.root.submit({ type: "input", content: "go", requestId: "turn-limit" }, CONTEXT)
			).wait(CONTEXT);
			if (settled.status === "done") throw new Error("run should fail");

			const report = describeRunFailure(settled, undefined);
			expect(report).toBe(`${settled.reason}: ${String(settled.detail)}`);
			expect(report).toContain("turn_limit");

			// A live failure from an older submission must not be named for this one.
			const stale = {
				runFailure: {
					taskId: 1,
					inputs: [999],
					reason: "aborted",
				},
			} as unknown as Parameters<typeof describeRunFailure>[1];
			expect(describeRunFailure(settled, stale)).toBe(`${settled.reason}: ${String(settled.detail)}`);
		} finally {
			await opened.close();
		}
	});
});

describe("cli status scan", () => {
	const conversation = (id: number) => ({ id }) as ConversationRecord;

	it("follows pages and counts every printed row", async () => {
		const pages: Page<ConversationRecord, Cursor>[] = [
			{ items: [conversation(1)], next: { after: 1 } },
			{ items: [conversation(2)] },
		];
		const result = await scanConversationPages(async (cursor) => pages[cursor === undefined ? 0 : 1]!);
		expect(result.items.map((item) => item.id)).toEqual([1, 2]);
		expect(result.truncated).toBe(false);
	});

	it("stops at the page bound and says it is truncated", async () => {
		const scan = async () => ({ items: [conversation(1)], next: { after: 1 } });
		const result = await scanConversationPages(scan, 2);
		expect(result.items).toHaveLength(2);
		expect(result.truncated).toBe(true);
	});
});

describe("harness close", () => {
	afterEach(() => {
		vi.restoreAllMocks();
	});

	it("closes the code-mode sandbox with the harness", async () => {
		const close = vi.spyOn(CodemodeSandbox.prototype, "close");
		const root = await mkdtemp(join(tmpdir(), "pi-harness-close-"));
		const project = join(root, "project");
		await mkdir(project);
		const opened = await openHarness({ projectDir: project, dbPath: join(root, "session.db"), mcpServers: false });
		await opened.close();
		expect(close).toHaveBeenCalledTimes(1);
	});
});
