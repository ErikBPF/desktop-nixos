#!/usr/bin/env node
/**
 * CLI for the pi durable harness.
 *
 * ask "<task>"   submit one input, wait, print the answer and usage
 * resume         reopen storage, continue pending work, print the latest state
 * status         conversations, live tasks, and spend
 * watch [id]     stream one conversation's committed entries (root by default)
 */
import { randomUUID } from "node:crypto";
import { pathToFileURL } from "node:url";
import { parseArgs } from "node:util";
import type { AssistantMessage } from "@earendil-works/pi-ai";
import type {
	ConversationId,
	ConversationRecord,
	Cursor,
	EntryId,
	EntryRecord,
	Harness,
	LiveState,
	Page,
	SettledSubmissionRecord,
} from "@earendil-works/pi-durable";
import { LiveDoc } from "@earendil-works/pi-durable";
import { openHarness, type HarnessConfig, type OpenedHarness } from "./harness.js";
import { modelRefToString, parseModelRef } from "./providers.js";

const STATUS_PAGE_SIZE = 100;
const STATUS_MAX_PAGES = 10;

const USAGE = `usage: pi-harness <command> [options]

commands:
  ask "<task>"   submit one task, wait for the answer, print answer and usage
  resume         continue pending tasks after a restart, print the latest state
  status         list conversations, live tasks, and spend
  watch [id]     stream a conversation (root when no id is given)

options:
  --project <dir>     project directory (default: cwd)
  --model <p/id>      litellm/<id> or work/<id> (first creation: litellm/deepseek-v4.1-flash;
                      a stored model wins on reopen)
  --thinking <level>  off|minimal|low|medium|high|xhigh|max (first creation: high;
                      a stored level wins on reopen)
  --state-dir <dir>   override XDG_STATE_HOME
  --no-mcp            do not start the donsetch/graphify MCP servers

status lists at most ${STATUS_MAX_PAGES * STATUS_PAGE_SIZE} conversations and says
"at least N (more pages)" when the store holds more.`;

type CliOptions = {
	project: string;
	model?: string;
	thinking?: string;
	"state-dir"?: string;
	"no-mcp": boolean;
};

const THINKING_LEVELS = ["off", "minimal", "low", "medium", "high", "xhigh", "max"] as const;

function configFrom(values: CliOptions): HarnessConfig {
	if (values.thinking !== undefined && !(THINKING_LEVELS as readonly string[]).includes(values.thinking)) {
		throw new Error(`invalid thinking level: ${values.thinking}`);
	}
	return {
		projectDir: values.project,
		model: values.model === undefined ? undefined : parseModelRef(values.model),
		thinkingLevel: values.thinking as HarnessConfig["thinkingLevel"],
		stateDir: values["state-dir"],
		mcpServers: values["no-mcp"] ? false : undefined,
	};
}

function assistantText(entry: EntryRecord | undefined): string {
	const message = entry?.model?.[0] as AssistantMessage | undefined;
	if (message?.role !== "assistant") return "";
	return message.content.flatMap((part) => (part.type === "text" ? [part.text] : [])).join("");
}

async function recentEntries(opened: OpenedHarness): Promise<readonly EntryRecord[]> {
	const page = await opened.root.entries({ order: "descending" }, 200, undefined, opened.context);
	return page.items;
}

export async function findEntry(opened: OpenedHarness, id: EntryId): Promise<EntryRecord | undefined> {
	const page = await opened.root.entries({ minEntryId: id, maxEntryId: id }, 1, undefined, opened.context);
	return page.items[0];
}

function formatFailureDetail(detail: unknown): string {
	const text = typeof detail === "string" ? detail : JSON.stringify(detail);
	return `: ${(text ?? "").slice(0, 300)}`;
}

export function describeRunFailure(
	settled: SettledSubmissionRecord,
	live: Readonly<LiveState> | undefined,
): string {
	if (settled.status !== "unanswered") return settled.status;
	// The live failure names the newest failed run, which may belong to an earlier
	// submission. Trust it only when it lists this submission among its inputs.
	const failure = live?.runFailure;
	if (settled.reason === "" && failure !== undefined && failure.inputs.includes(settled.id)) {
		return `${failure.reason}${failure.detail === undefined ? "" : `: ${failure.detail.slice(0, 300)}`}`;
	}
	return `${settled.reason}${settled.detail === undefined ? "" : formatFailureDetail(settled.detail)}`;
}

export type ConversationScan = {
	readonly items: readonly ConversationRecord[];
	/** The store had more pages than the bound allowed. */
	readonly truncated: boolean;
};

export async function scanConversationPages(
	scan: (cursor: Cursor | undefined) => Promise<Page<ConversationRecord, Cursor>>,
	maxPages = STATUS_MAX_PAGES,
): Promise<ConversationScan> {
	const items: ConversationRecord[] = [];
	let cursor: Cursor | undefined;
	let pages = 0;
	for (;;) {
		const page = await scan(cursor);
		items.push(...page.items);
		pages += 1;
		if (page.next === undefined) return { items, truncated: false };
		if (pages >= maxPages) return { items, truncated: true };
		cursor = page.next;
	}
}

async function latestAssistant(opened: OpenedHarness): Promise<EntryRecord | undefined> {
	return (await recentEntries(opened)).find((entry) => assistantText(entry) !== "");
}

function printUsage(usage: Awaited<ReturnType<Harness["usage"]>>): void {
	const models = Object.entries(usage.models);
	if (models.length === 0) {
		console.log("usage: none");
		return;
	}
	for (const [name, totals] of models) {
		console.log(
			`usage ${name}: input=${totals.input} output=${totals.output} cache_read=${totals.cacheRead} total=${totals.totalTokens} cost=$${totals.cost.total.toFixed(6)}`,
		);
	}
}

async function commandAsk(values: CliOptions, task: string): Promise<void> {
	const opened = await openHarness(configFrom(values));
	try {
		console.log(`model: ${modelRefToString(opened.model)}`);
		const submission = await opened.root.submit(
			{ type: "input", content: task, requestId: randomUUID() },
			opened.context,
		);
		const settled = await submission.wait(opened.context);
		if (settled.status !== "done" || settled.type !== "input") {
			const live = await opened.harness.snapshot(LiveDoc, opened.root.id, opened.context);
			console.error(`run did not answer: ${describeRunFailure(settled, live)}`);
			process.exitCode = 1;
		} else {
			const answer = await findEntry(opened, settled.answer);
			console.log(assistantText(answer) || "(no assistant text)");
		}
		printUsage(await opened.harness.usage(opened.context));
	} finally {
		await opened.close();
	}
}

async function commandResume(values: CliOptions): Promise<void> {
	const opened = await openHarness(configFrom(values));
	try {
		opened.harness.resume();
		await opened.harness.waitForIdle(opened.context);
		const live = await opened.harness.snapshot(LiveDoc, opened.root.id, opened.context);
		console.log(`model: ${modelRefToString(opened.model)}`);
		console.log(assistantText(await latestAssistant(opened)) || "(no answer yet)");
		if (live?.runFailure !== undefined) {
			const detail = live.runFailure.detail === undefined ? "" : ` (${live.runFailure.detail.slice(0, 300)})`;
			console.log(`unsettled: run failed: ${live.runFailure.reason}${detail}`);
		}
		if (live?.run !== undefined) console.log("unsettled: run in progress");
		printUsage(await opened.harness.usage(opened.context));
	} finally {
		await opened.close();
	}
}

async function commandStatus(values: CliOptions): Promise<void> {
	const opened = await openHarness(configFrom(values));
	try {
		const scan = await scanConversationPages(async (cursor) =>
			opened.harness.commit(
				(tx) => tx.scanConversations({ order: "ascending" }, STATUS_PAGE_SIZE, cursor),
				opened.context,
			),
		);
		console.log(
			scan.truncated
				? `conversations: at least ${scan.items.length} (more pages)`
				: `conversations: ${scan.items.length}`,
		);
		for (const conversation of scan.items) {
			const owner = conversation.owner === undefined ? "" : ` owner_task=${conversation.owner.taskId}`;
			console.log(`  ${conversation.id}${owner}`);
		}
		const graph = await opened.harness.watchTaskGraph(opened.context);
		const tasks = Object.values(graph.value.tasks);
		console.log(`live tasks: ${tasks.length}`);
		for (const task of tasks) {
			const state =
				task.state.status === "waiting"
					? `waiting on ${task.state.on.join(",")}`
					: task.state.status === "sleeping"
						? `sleeping${task.state.until === undefined ? "" : ` until ${task.state.until}`}`
						: task.state.status;
			const owner = task.owner === undefined ? "" : ` owner=${task.owner}`;
			console.log(`  ${task.id} ${task.kind} ${state} conversation=${task.conversationId}${owner}`);
		}
		await graph.stop();
		printUsage(await opened.harness.usage(opened.context));
	} finally {
		await opened.close();
	}
}

async function commandWatch(values: CliOptions, id: string | undefined): Promise<void> {
	const opened = await openHarness(configFrom(values));
	try {
		const conversation =
			id === undefined
				? opened.root
				: await opened.harness.conversation(Number(id) as ConversationId, opened.context);
		if (conversation === undefined) {
			console.error(`unknown conversation: ${id}`);
			process.exitCode = 1;
			return;
		}
		const watch = await conversation.watch(opened.context);
		let newest = watch.value.entries.at(-1)?.id ?? 0;
		console.log(`watching ${conversation.id}`);
		watch.start(async (call) => {
			if (call.kind !== "value") return;
			const entries = call.value.entries.filter((entry) => entry.id > newest);
			newest = call.value.entries.at(-1)?.id ?? newest;
			for (const entry of entries) {
				const message = entry.model?.[0];
				if (message?.role === "user") {
					const content =
						typeof message.content === "string"
							? message.content
							: message.content.flatMap((part) => (part.type === "text" ? [part.text] : [])).join("");
					console.log(`user: ${content}`);
				} else if (message?.role === "assistant") {
					for (const part of message.content) {
						if (part.type === "text" && part.text !== "") console.log(`assistant: ${part.text}`);
						if (part.type === "toolCall") console.log(`tool: ${part.name} ${JSON.stringify(part.arguments)}`);
					}
				} else if (message?.role === "toolResult") {
					const content = message.content.flatMap((part) => (part.type === "text" ? [part.text] : [])).join("");
					console.log(`result: ${content.slice(0, 500)}`);
				}
			}
		});
		await new Promise<void>((resolve) => {
			const stop = () => {
				watch.stop().catch(() => {}).finally(resolve);
			};
			process.once("SIGINT", stop);
			process.once("SIGTERM", stop);
			watch.closed.then(() => resolve());
		});
	} finally {
		await opened.close();
	}
}

async function main(): Promise<void> {
	const { values, positionals } = parseArgs({
		args: process.argv.slice(2),
		allowPositionals: true,
		options: {
			project: { type: "string", default: process.cwd() },
			model: { type: "string" },
			thinking: { type: "string" },
			"state-dir": { type: "string" },
			"no-mcp": { type: "boolean", default: false },
		},
	});
	const options = values as CliOptions;
	const command = positionals[0];
	if (command === undefined) {
		console.log(USAGE);
		return;
	}
	if (command === "ask") {
		const task = positionals[1];
		if (task === undefined || task.trim() === "") throw new Error("ask needs a task");
		return commandAsk(options, task);
	}
	if (command === "resume") return commandResume(options);
	if (command === "status") return commandStatus(options);
	if (command === "watch") return commandWatch(options, positionals[1]);
	throw new Error(`unknown command: ${command}`);
}

const invoked = process.argv[1];
if (invoked !== undefined && import.meta.url === pathToFileURL(invoked).href) {
	main().catch((error: unknown) => {
		console.error(error instanceof Error ? error.message : String(error));
		process.exitCode = 1;
	});
}
