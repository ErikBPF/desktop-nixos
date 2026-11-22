/**
 * Harness assembly: providers, durable storage, extensions, and the default agent.
 *
 * Pi durable owns conversations, tasks, gates, and restart recovery. This module
 * only wires the home gateways, coding tools, code mode, MCP tools, and
 * background subagents into one registry.
 */
import { mkdir, readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import { homedir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import type { Context } from "@earendil-works/chord/context";
import type { JsonValue } from "@earendil-works/chord/json";
import { BACKGROUND_CONTEXT } from "@earendil-works/chord/context";
import { createModels } from "@earendil-works/pi-ai";
import { CodemodeSandbox } from "@earendil-works/pi-codemode";
import {
	createRegistry,
	defineExtension,
	defineTool,
	Harness,
	type Conversation,
	type Extension,
} from "@earendil-works/pi-durable";
import { createCodemodeExtension } from "@earendil-works/pi-durable/codemode";
import { createFitImagesExtension } from "@earendil-works/pi-durable/images/fit";
import { createNodePhotonImages } from "@earendil-works/pi-durable/images/node";
import { openNodeSqliteStorage } from "@earendil-works/pi-durable/storage/sqlite/node";
import { NodeExecutionEnv } from "@earendil-works/pi-durable/env/node";
import { createCodingTools } from "@earendil-works/pi-durable/tools";
import { createToolSearchExtension } from "@earendil-works/pi-durable/tool-search";
import {
	createMcpToolName,
	McpClient,
	normalizeMcpInputSchema,
	StdioTransport,
	toLlmContent,
} from "@earendil-works/pi-mcp";
import { createHarnessProviders, modelRefToString, type ModelRef } from "./providers.js";
import { createSubagentExtension } from "./subagent.js";

export const CONTEXT = BACKGROUND_CONTEXT;
export const DEFAULT_MODEL: ModelRef = { provider: "litellm", modelId: "deepseek-v4.1-flash" };
export const DEFAULT_CHILD_MODEL: ModelRef = { provider: "litellm", modelId: "glm-5.3-flash" };

export type McpServerSpec = {
	readonly name: string;
	readonly command: string;
	readonly args?: readonly string[];
	readonly env?: Record<string, string>;
	readonly cwd?: string;
};

/** Commands installed by modules/dev/opencode.nix, with deferred tools. */
export const DEFAULT_MCP_SERVERS: readonly McpServerSpec[] = [
	{ name: "donsetch", command: "donsetch", args: ["mcp", "--supervised"] },
	{ name: "graphify", command: "graphify-mcp" },
];

export type HarnessConfig = {
	readonly projectDir: string;
	readonly model?: ModelRef;
	readonly thinkingLevel?: "off" | "minimal" | "low" | "medium" | "high" | "xhigh" | "max";
	readonly childModel?: ModelRef;
	readonly dbPath?: string;
	readonly stateDir?: string;
	readonly instructions?: string;
	/** Omit for the defaults, `false` to disable, or pass explicit servers. */
	readonly mcpServers?: readonly McpServerSpec[] | false;
};

export type OpenedHarness = {
	readonly harness: Harness;
	readonly root: Conversation;
	readonly model: ModelRef;
	readonly dbPath: string;
	readonly context: typeof CONTEXT;
	close(): Promise<void>;
};

export function resolveStateDir(): string {
	return process.env.XDG_STATE_HOME ?? join(homedir(), ".local", "state");
}

export function resolveDbPath(projectDir: string, stateDir = resolveStateDir()): string {
	const absolute = resolve(projectDir);
	const project = basename(absolute).replace(/[^A-Za-z0-9._-]/g, "-") || "project";
	const pathHash = createHash("sha256").update(absolute).digest("hex").slice(0, 8);
	return join(stateDir, "pi-harness", `${project}-${pathHash}.db`);
}

/**
 * Execution environment for durable tool calls. Without one, every built-in
 * tool answers "No execution environment is configured"; the harness's live
 * smoke answered text anyway, which hid that failure.
 */
export function createExecutionEnv(fallbackCwd?: string) {
	return ({ cwd }: { cwd?: string }) => new NodeExecutionEnv({ cwd: cwd ?? fallbackCwd ?? process.cwd() });
}

export async function readProjectInstructions(projectDir: string): Promise<string> {
	try {
		return await readFile(join(projectDir, "AGENTS.md"), "utf8");
	} catch (error) {
		if ((error as NodeJS.ErrnoException).code === "ENOENT") return "";
		throw error;
	}
}

/**
 * Wrap a connected MCP client as a durable extension. Tools are deferred, so the
 * model finds them with `tool_search`; code-mode scripts call them once loaded.
 */
export async function createMcpExtension(name: string, client: McpClient): Promise<Extension> {
	const mcpTools = await client.listTools();
	return defineExtension({
		name: `mcp-${name}`,
		namespace: { name, description: `Tools from the ${name} MCP server.` },
		tools: mcpTools.map((tool) =>
			defineTool({
				name: createMcpToolName(name, tool.name),
				description: tool.description ?? tool.title ?? `${name} tool ${tool.name}`,
				parameters: normalizeMcpInputSchema(tool.inputSchema),
				...(tool.outputSchema === undefined
					? {}
					: { structuredOutputSchema: normalizeMcpInputSchema(tool.outputSchema) }),
				deferred: true,
				execute: async (args, _api, callContext) => {
					const result = await client.callTool(tool.name, args as Record<string, unknown>, {
						timeoutMs: 300_000,
						signal: callContext.abortSignal,
					});
					return {
						output: toLlmContent(result),
						...(result.structuredContent === undefined
							? {}
							: { structuredOutput: result.structuredContent as JsonValue }),
						isError: result.isError === true,
					};
				},
			}),
		),
	});
}

export async function connectMcpServer(
	spec: McpServerSpec,
	projectDir?: string,
): Promise<{ client: McpClient; extension: Extension }> {
	const transport = new StdioTransport({
		command: spec.command,
		args: spec.args,
		cwd: spec.cwd ?? projectDir,
		env: spec.env,
		inheritEnv: true,
	});
	const client = new McpClient({ name: "pi-harness", version: "0.1.0" });
	try {
		await client.connect(transport);
		return { client, extension: await createMcpExtension(spec.name, client) };
	} catch (error) {
		// A connect or tools/list failure must not leave the stdio child running.
		await client.close().catch(() => {});
		throw error;
	}
}

async function installMcpServers(
	registry: ReturnType<typeof createRegistry>,
	servers: readonly McpServerSpec[],
	projectDir: string,
): Promise<McpClient[]> {
	const clients: McpClient[] = [];
	for (const spec of servers) {
		try {
			const connection = await connectMcpServer(spec, projectDir);
			registry.install(connection.extension);
			clients.push(connection.client);
		} catch (error) {
			// A missing local server must not block a plain ask; report the name and reason, never a secret.
			console.error(
				`pi-harness: MCP server "${spec.name}" unavailable: ${error instanceof Error ? error.message : String(error)}`,
			);
		}
	}
	return clients;
}

export async function openHarness(config: HarnessConfig): Promise<OpenedHarness> {
	const projectDir = resolve(config.projectDir);
	const modelRef = config.model ?? DEFAULT_MODEL;
	const childModel = config.childModel ?? DEFAULT_CHILD_MODEL;

	const models = createModels();
	for (const provider of createHarnessProviders()) models.setProvider(provider);
	const model = models.getModel(modelRef.provider, modelRef.modelId);
	if (model === undefined) {
		throw new Error(`model not found in the harness catalog: ${modelRefToString(modelRef)}`);
	}

	const registry = createRegistry();
	const images = await createNodePhotonImages();
	registry.install(createCodingTools({ images }));
	registry.install(createFitImagesExtension(images));
	registry.install(
		createCodemodeExtension({ sandbox: new CodemodeSandbox({ memoryLimitBytes: 256 * 1024 * 1024 }) }),
	);
	registry.install(createToolSearchExtension());
	registry.install(createSubagentExtension({ childModel }));

	const mcpServers =
		config.mcpServers === false || process.env.PI_HARNESS_MCP === "off"
			? []
			: (config.mcpServers ?? DEFAULT_MCP_SERVERS);
	const clients = await installMcpServers(registry, mcpServers, projectDir);

	const dbPath = config.dbPath ?? resolveDbPath(projectDir, config.stateDir);
	let harness: Harness | undefined;
	try {
		await mkdir(dirname(dbPath), { recursive: true });
		const storage = await openNodeSqliteStorage(dbPath);
		harness = await Harness.open(storage, { models, registry, env: createExecutionEnv(projectDir) }, CONTEXT);
		const instructions = config.instructions ?? (await readProjectInstructions(projectDir));
		const thinkingLevel = config.thinkingLevel ?? "high";
		const root = await harness.root(CONTEXT, {
			agent: { model: modelRef, thinkingLevel, cwd: projectDir, instructions },
		});
		// `root()` applies `agent` only when it creates the conversation. On reopen, change only
		// what the caller passed explicitly or what changed on disk.
		const current = await root.agent(CONTEXT);
		const change: {
			model?: ModelRef;
			thinkingLevel?: NonNullable<HarnessConfig["thinkingLevel"]>;
			cwd?: string;
			instructions?: string;
		} = {};
		if (
			config.model !== undefined &&
			(current.model?.provider !== config.model.provider || current.model.modelId !== config.model.modelId)
		) {
			change.model = config.model;
		}
		if (config.thinkingLevel !== undefined && current.thinkingLevel !== config.thinkingLevel) {
			change.thinkingLevel = config.thinkingLevel;
		}
		if (current.cwd !== projectDir) change.cwd = projectDir;
		if (current.instructions !== instructions) change.instructions = instructions;
		if (Object.keys(change).length > 0) await root.configure(change, CONTEXT);
		const stored = (await root.agent(CONTEXT)).model;
		const effective: ModelRef =
			stored !== undefined && (stored.provider === "litellm" || stored.provider === "work")
				? { provider: stored.provider, modelId: stored.modelId }
				: modelRef;

		return {
			harness,
			root,
			model: effective,
			dbPath,
			context: CONTEXT,
			async close() {
				for (const client of clients) await client.close();
				await harness!.close(CONTEXT);
			},
		};
	} catch (error) {
		for (const client of clients) await client.close().catch(() => {});
		if (harness !== undefined) await harness.close(CONTEXT).catch(() => {});
		throw error;
	}
}
