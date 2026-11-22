/**
 * Harness assembly: providers, durable storage, extensions, and the default agent.
 *
 * Pi durable owns conversations, tasks, gates, and restart recovery. This module
 * only wires the home gateways, coding tools, code mode, MCP tools, and
 * background subagents into one registry.
 */
import { mkdir, readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
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
	const project = basename(resolve(projectDir)).replace(/[^A-Za-z0-9._-]/g, "-") || "project";
	return join(stateDir, "pi-harness", `${project}.db`);
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
 * model sees them only after `tool_search`, and code mode can call them directly.
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
				execute: async (args) => {
					const result = await client.callTool(tool.name, args as Record<string, unknown>);
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
): Promise<{ client: McpClient; extension: Extension }> {
	const transport = new StdioTransport({
		command: spec.command,
		args: spec.args,
		cwd: spec.cwd,
		env: spec.env,
		inheritEnv: true,
	});
	const client = new McpClient({ name: "pi-harness", version: "0.1.0" });
	await client.connect(transport);
	return { client, extension: await createMcpExtension(spec.name, client) };
}

async function installMcpServers(
	registry: ReturnType<typeof createRegistry>,
	servers: readonly McpServerSpec[],
): Promise<McpClient[]> {
	const clients: McpClient[] = [];
	for (const spec of servers) {
		try {
			const connection = await connectMcpServer(spec);
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
	const clients = await installMcpServers(registry, mcpServers);

	const dbPath = config.dbPath ?? resolveDbPath(projectDir, config.stateDir);
	await mkdir(dirname(dbPath), { recursive: true });
	const storage = await openNodeSqliteStorage(dbPath);
	const harness = await Harness.open(storage, { models, registry }, CONTEXT);
	const instructions = config.instructions ?? (await readProjectInstructions(projectDir));
	const root = await harness.root(CONTEXT, {
		agent: {
			model: modelRef,
			thinkingLevel: config.thinkingLevel ?? "high",
			cwd: projectDir,
			instructions,
		},
	});

	return {
		harness,
		root,
		model: modelRef,
		dbPath,
		context: CONTEXT,
		async close() {
			for (const client of clients) await client.close();
			await harness.close(CONTEXT);
		},
	};
}
