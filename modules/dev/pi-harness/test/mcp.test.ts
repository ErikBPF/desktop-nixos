import {
	LATEST_PROTOCOL_VERSION,
	McpClient,
	type JsonRpcMessage,
	type JsonRpcRequest,
	McpError,
	createMcpToolName,
} from "@earendil-works/pi-mcp";
import { createInMemoryTransportPair } from "@earendil-works/pi-mcp/testing";
import { describe, expect, it } from "vitest";
import { CONTEXT } from "../src/harness.js";
import { createMcpExtension } from "../src/harness.js";

async function connectTestServer() {
	const pair = createInMemoryTransportPair();
	const handlers = new Map<string, (request: JsonRpcRequest) => unknown>();
	pair.server.onMessage((message: JsonRpcMessage) => {
		if (!("id" in message) || !("method" in message)) return;
		const request = message as JsonRpcRequest;
		queueMicrotask(async () => {
			const handler = handlers.get(request.method);
			try {
				if (handler === undefined) throw new McpError(-32601, `Method not found: ${request.method}`);
				await pair.server.send({ jsonrpc: "2.0", id: request.id, result: handler(request) });
			} catch (error) {
				const mcpError = error instanceof McpError ? error : new McpError(-32603, String(error));
				await pair.server.send({
					jsonrpc: "2.0",
					id: request.id,
					error: { code: mcpError.code, message: mcpError.message },
				});
			}
		});
	});
	handlers.set("initialize", () => ({
		protocolVersion: LATEST_PROTOCOL_VERSION,
		capabilities: { tools: {} },
		serverInfo: { name: "test-server", version: "1.0.0" },
	}));
	handlers.set("tools/list", () => ({
		tools: [
			{
				name: "echo",
				description: "Echo text.",
				inputSchema: { type: "object", properties: { text: { type: "string" } }, required: ["text"] },
			},
		],
	}));
	handlers.set("tools/call", (request) => {
		const params = request.params as { arguments?: { text?: string } };
		return { content: [{ type: "text", text: `echo: ${params.arguments?.text ?? ""}` }] };
	});
	await pair.server.start();
	const client = new McpClient({ name: "test-client", version: "1.0.0" });
	await client.connect(pair.client);
	return client;
}

describe("MCP bridge", () => {
	it("exposes a connected server's tools as deferred durable tools", async () => {
		const client = await connectTestServer();
		try {
			const extension = await createMcpExtension("test", client);
			const tools = extension.tools ?? [];
			expect(tools).toHaveLength(1);
			const tool = tools[0]!;
			expect(tool.name).toBe(createMcpToolName("test", "echo"));
			expect(tool.deferred).toBe(true);
			const result = await tool.execute({ text: "hi" } as never, undefined as never, CONTEXT);
			expect(result.isError).toBe(false);
			expect(result.output?.[0]).toEqual({ type: "text", text: "echo: hi" });
		} finally {
			await client.close();
		}
	});
});
