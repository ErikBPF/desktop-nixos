/**
 * Background subagents, adapted from pi-durable example 22.
 *
 * One `subagent` tool spawns, messages, waits for, stops, and lists children.
 * Each child is its own conversation owned by a background anchor task, so a
 * parent abort or idle wait does not reach it. A reporter task delivers one
 * message, waits for the child's answer, and posts that answer to the parent as
 * a follow-up input. Request IDs make a restart reuse the same submission and
 * report instead of sending twice.
 */
import type { AssistantMessage } from "@earendil-works/pi-ai";
import { bool, obj, oneOf, opt, str } from "@earendil-works/pi-schema";
import {
	AssistantEntry,
	type ConversationId,
	configure,
	defineDoc,
	defineExtension,
	defineTask,
	defineTool,
	type EntryId,
	LiveDoc,
	type TaskId,
} from "@earendil-works/pi-durable";
import type { ModelRef } from "./providers.js";

export const SUBAGENT_TOOL_NAME = "subagent";

type Subagent = {
	conversationId: ConversationId;
	/** Answers already reported to the parent: several messages can end in one answer. */
	reported: EntryId[];
};

type Reporter = {
	taskId: TaskId;
	name: string;
};

const Subagents = defineDoc<{
	agents: Record<string, Subagent>;
	reporters: Record<string, Reporter>;
}>({
	checkpointWhen: () => false,
	kind: "app.pi-harness.subagents",
	version: 1,
	scope: "conversation",
	history: "latest",
	fork: "initial",
	initial: () => ({ agents: {}, reporters: {} }),
});

const Anchor = defineTask<null, { phase: "done" }, null>({
	name: "app.pi-harness.subagent-anchor",
	version: 1,
	initial: () => ({ phase: "done" }),
	phases: {
		done: (_anchor, runtime, taskContext) =>
			runtime.commit(() => ({ status: "terminal", outcome: { status: "completed", result: null } }), taskContext),
	},
	abort: (_anchor, runtime, taskContext) =>
		runtime.commit(() => ({ status: "terminal", outcome: { status: "aborted" } }), taskContext),
});

type ReporterInput = { name: string; conversationId: ConversationId; message: string; followUp: boolean };
type ReporterState = { phase: "deliver" } | { phase: "report"; report?: string };

const ReporterTask = defineTask<ReporterInput, ReporterState, null>({
	name: "app.pi-harness.subagent-reporter",
	version: 1,
	initial: () => ({ phase: "deliver" }),
	phases: {
		deliver: async (reporter, runtime, taskContext) => {
			const { name, conversationId, message, followUp } = reporter.input;
			const child = (await runtime.conversation(conversationId, taskContext))!;
			const request = {
				type: "input",
				content: message,
				whenBusy: followUp ? "followUp" : "steer",
			} as const;
			const submission = await child.submit({ ...request, requestId: `subagent:${reporter.id}` }, taskContext);
			const settled = await submission.wait(taskContext);
			await runtime.commit(async (tx) => {
				const next = (report?: string) =>
					({ status: "running", checkpoint: { phase: "report", report } }) as const;
				if (settled.status === "unanswered") {
					return next(settled.reason === "aborted" ? undefined : `[subagent ${name} failed: ${settled.reason}]`);
				}
				if (settled.type !== "input") return next();
				const agent = (await tx.doc(Subagents, runtime.conversationId)).agents[name]!;
				if (agent.reported.includes(settled.answer)) return next();
				agent.reported.push(settled.answer);
				const answer = (await tx.entry(AssistantEntry, settled.answer))?.model?.[0] as AssistantMessage;
				return next(`[subagent ${name} answered, no reply needed] ${textOf(answer)}`);
			}, taskContext);
		},
		report: async (reporter, runtime, taskContext) => {
			const report = reporter.state.checkpoint.report;
			if (report !== undefined) {
				const parent = (await runtime.conversation(runtime.conversationId, taskContext))!;
				const input = { type: "input", content: report, whenBusy: "followUp" } as const;
				await parent.submit({ ...input, requestId: `subagent-report:${reporter.id}` }, taskContext);
			}
			await runtime.commit(
				() => ({ status: "terminal", outcome: { status: "completed", result: null } }),
				taskContext,
			);
		},
	},
	abort: (_reporter, runtime, taskContext) =>
		runtime.commit(() => ({ status: "terminal", outcome: { status: "aborted" } }), taskContext),
});

function textOf(message: AssistantMessage | undefined): string {
	return (message?.content ?? []).flatMap((part) => (part.type === "text" ? [part.text] : [])).join("");
}

export type SubagentOptions = {
	/** Model for children. Defaults to litellm/glm-5.3. */
	readonly childModel?: ModelRef;
};

export function createSubagentExtension(options: SubagentOptions = {}) {
	const childModel: ModelRef = options.childModel ?? { provider: "litellm", modelId: "glm-5.3" };

	const subagentTool = defineTool({
		name: SUBAGENT_TOOL_NAME,
		description:
			"Manage persistent background subagents. Actions: spawn (name, message), send (name, message; " +
			"followUp queues it after the current answer instead of steering), wait (name, or all), stop (aborts " +
			"its current work), list (name, or all). Answers return to you as follow-up messages.",
		parameters: obj({
			action: oneOf(["spawn", "send", "wait", "stop", "list"]),
			name: opt(str()),
			message: opt(str()),
			followUp: opt(bool()),
		}),
		// Repeating `stop` could stop newer work, so an interrupted call waits for the model to check `list`.
		replay: "unsafe",
		execute: async (args, api, callContext) => {
			const { action, name, message, followUp } = args;
			const reply = (text: string, conversationId?: ConversationId) => ({
				output: [{ type: "text" as const, text }],
				...(conversationId === undefined || name === undefined ? {} : { details: { name, conversationId } }),
			});
			const state = (await api.snapshot(Subagents, api.conversationId, callContext)) ?? {
				agents: {},
				reporters: {},
			};

			const isBusy = async (conversationId: ConversationId) =>
				(await api.snapshot(LiveDoc, conversationId, callContext))?.run !== undefined;

			if (action === "list") {
				const names = name === undefined ? Object.keys(state.agents) : [name];
				const lines: string[] = [];
				for (const each of names) {
					const found = Object.hasOwn(state.agents, each) ? state.agents[each] : undefined;
					if (found === undefined) continue;
					lines.push(`${each}: ${(await isBusy(found.conversationId)) ? "working" : "idle"}`);
				}
				return reply(lines.length === 0 ? "No subagents." : lines.join("\n"));
			}
			if (action === "wait") {
				const names = name === undefined ? Object.keys(state.agents) : [name];
				for (const reporter of Object.values(state.reporters)) {
					if (names.includes(reporter.name)) await api.waitForTask(reporter.taskId, callContext);
				}
				const lines: string[] = [];
				for (const each of names) {
					const found = state.agents[each];
					if (found === undefined) continue;
					lines.push(`${each}: ${(await isBusy(found.conversationId)) ? "working" : "idle"}`);
				}
				return reply(lines.length === 0 ? "No subagents." : lines.join("\n"));
			}
			if (name === undefined) return reply(`${action} needs a name.`);
			if (name === "__proto__" || name === "constructor" || name === "prototype") {
				return reply(`${name} is not a valid subagent name.`);
			}
			const agent = Object.hasOwn(state.agents, name) ? state.agents[name] : undefined;
			if (action !== "spawn" && agent === undefined) return reply(`No subagent named ${name}.`);

			if (action === "stop") {
				await (await api.conversation(agent!.conversationId, callContext))!.abort(callContext);
				return reply(`Stopped ${name}.`, agent!.conversationId);
			}
			if (message === undefined) return reply(`${action} needs a message.`);

			const inherited = (await api.agent(callContext)).instructions;
			const childInstructions =
				inherited === undefined || inherited === ""
					? `You are the subagent "${name}". Answer the main agent's requests.`
					: `${inherited}\n\nYou are the subagent "${name}". Answer the main agent's requests.`;

			const result = await api.commit(async (tx) => {
				const next = await tx.doc(Subagents, api.conversationId);
				const background = { ownership: { kind: "conversation" }, background: true } as const;
				if (action === "spawn") {
					if (Object.hasOwn(next.agents, name)) return `${name} already exists; use send.`;
					const anchor = await tx.createTask(Anchor, null, background);
					// Owned by an anchor, so the child starts as a copy of this agent and outlives parent turns.
					const child = await tx.createConversation({ ownership: { kind: "task", taskId: anchor } });
					await configure(tx, child.id, {
						model: childModel,
						extensions: { remove: [SubagentTools] },
						instructions: childInstructions,
					});
					next.agents[name] = { conversationId: child.id, reported: [] };
				}
				const conversationId = next.agents[name]!.conversationId;
				// Same calling task means a replay: reuse its reporter instead of sending the message twice.
				if (next.reporters[api.taskId] === undefined) {
					const reporter = await tx.createTask(
						ReporterTask,
						{ name, conversationId, message, followUp: action === "send" && followUp === true },
						background,
					);
					next.reporters[api.taskId] = { taskId: reporter, name };
				}
				return action === "send" ? `Sent to ${name}.` : `Started ${name}.`;
			}, callContext);
			const current = (await api.snapshot(Subagents, api.conversationId, callContext))?.agents[name];
			return reply(result, current?.conversationId);
		},
	});

	const SubagentTools = defineExtension({
		name: "subagent-tools",
		tasks: [Anchor, ReporterTask],
		tools: [subagentTool],
	});

	return SubagentTools;
}

export type { Subagent };
