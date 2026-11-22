/**
 * Provider definitions for the two home gateways.
 *
 * API keys are resolved when a request is made, never at module load and never
 * logged. A key is read from the sops runtime file first and from the
 * documented environment variable second.
 */
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { createProvider, type ApiKeyAuth, type Model } from "@earendil-works/pi-ai";
import { openAICompletionsApi } from "@earendil-works/pi-ai/api/openai-completions.lazy";

export const LITELLM_BASE_URL = "https://litellm.homelab.pastelariadev.com/v1";
export const WORK_BASE_URL = "https://llm-gateway-dataplatform-dev.nstech.com.br/v1";

export type ProviderId = "litellm" | "work";

/** LiteLLM rejects a request without this routing header; any stable session value works. */
const LITELLM_SESSION = `pi-harness-${randomUUID()}`;

export type CredentialSource = {
	readonly file: string;
	readonly env: string;
};

export const CREDENTIAL_SOURCES: Readonly<Record<ProviderId, CredentialSource>> = {
	litellm: { file: "/run/secrets/opencode/litellm_key", env: "OPENCODE_LITELLM_KEY" },
	work: { file: "/run/secrets/opencode/work_key", env: "OPENCODE_WORK_KEY" },
};

type ModelConfig = {
	readonly name: string;
	readonly reasoning: boolean;
	readonly input: readonly ("text" | "image")[];
	readonly inputCost: number;
	readonly outputCost: number;
	readonly cacheReadCost: number;
	readonly contextWindow: number;
	readonly maxTokens: number;
};

/** Costs and limits copied from modules/dev/opencode.nix. */
const MODELS: Readonly<Record<ProviderId, Readonly<Record<string, ModelConfig>>>> = {
	litellm: {
		"deepseek-v4.1-flash": {
			name: "DeepSeek V4.1 Flash (LiteLLM → OpenCode Go)",
			reasoning: true,
			input: ["text", "image"],
			inputCost: 0.3,
			outputCost: 1.2,
			cacheReadCost: 0.006,
			contextWindow: 1_000_000,
			maxTokens: 384_000,
		},
		"glm-5.3-flash": {
			name: "GLM-5.3 Flash (LiteLLM → OpenCode Go)",
			reasoning: true,
			input: ["text"],
			inputCost: 0.075,
			outputCost: 0.25,
			cacheReadCost: 0,
			contextWindow: 1_000_000,
			maxTokens: 131_072,
		},
	},
	work: {
		"deepseek-v4.1-flash": {
			name: "DeepSeek V4.1 Flash (Work)",
			reasoning: false,
			input: ["text", "image"],
			inputCost: 0.3,
			outputCost: 1.2,
			cacheReadCost: 0,
			contextWindow: 1_048_576,
			maxTokens: 393_216,
		},
		"glm-5.3-flash": {
			name: "GLM-5.3 Flash (Work)",
			reasoning: false,
			input: ["text"],
			inputCost: 0.075,
			outputCost: 0.25,
			cacheReadCost: 0.015,
			contextWindow: 1_048_576,
			maxTokens: 131_072,
		},
	},
};

/** Read the first non-empty value: the sops file, then the environment variable. */
export async function resolveKey(source: CredentialSource, signal?: AbortSignal): Promise<string | undefined> {
	signal?.throwIfAborted();
	try {
		const value = (await readFile(source.file, "utf8")).trim();
		if (value !== "") return value;
	} catch (error) {
		const code = (error as NodeJS.ErrnoException).code;
		if (code !== "ENOENT" && code !== "EACCES") throw error;
	}
	signal?.throwIfAborted();
	const value = process.env[source.env]?.trim();
	return value === "" ? undefined : value;
}

function fileApiKeyAuth(name: string, source: CredentialSource): ApiKeyAuth {
	return {
		name,
		resolve: async ({ credential, signal }) => {
			signal.throwIfAborted();
			if (credential?.key) {
				return { auth: { apiKey: credential.key }, env: credential.env, source: "stored credential" };
			}
			const key = await resolveKey(source, signal);
			if (key === undefined) return undefined;
			return { auth: { apiKey: key }, source: source.env };
		},
	};
}

function buildModel(
	provider: ProviderId,
	id: string,
	baseUrl: string,
	config: ModelConfig,
): Model<"openai-completions"> {
	return {
		id,
		name: config.name,
		api: "openai-completions",
		provider,
		baseUrl,
		reasoning: config.reasoning,
		input: [...config.input],
		cost: {
			input: config.inputCost,
			output: config.outputCost,
			cacheRead: config.cacheReadCost,
			cacheWrite: 0,
		},
		contextWindow: config.contextWindow,
		maxTokens: config.maxTokens,
		...(provider === "litellm" ? { headers: { "x-opencode-session": LITELLM_SESSION } } : {}),
		// The Work gateway rejects reasoning_effort, so keep it out of the request.
		...(config.reasoning ? {} : { compat: { supportsReasoningEffort: false } }),
	};
}

function buildProvider(provider: ProviderId, baseUrl: string) {
	const configs = MODELS[provider];
	return createProvider({
		id: provider,
		name: provider === "litellm" ? "Orion" : "Work",
		baseUrl,
		auth: { apiKey: fileApiKeyAuth(`${provider} API key`, CREDENTIAL_SOURCES[provider]) },
		models: Object.entries(configs).map(([id, config]) => buildModel(provider, id, baseUrl, config)),
		api: openAICompletionsApi(),
	});
}

export function createLitellmProvider() {
	return buildProvider("litellm", LITELLM_BASE_URL);
}

export function createWorkProvider() {
	return buildProvider("work", WORK_BASE_URL);
}

export function createHarnessProviders() {
	return [createLitellmProvider(), createWorkProvider()];
}

export type ModelRef = {
	readonly provider: ProviderId;
	readonly modelId: string;
};

export function parseModelRef(value: string): ModelRef {
	const [provider, ...rest] = value.split("/");
	const modelId = rest.join("/");
	if ((provider !== "litellm" && provider !== "work") || modelId === "") {
		throw new Error(`invalid model "${value}"; expected litellm/<id> or work/<id>`);
	}
	return { provider, modelId };
}

export function modelRefToString(model: ModelRef): string {
	return `${model.provider}/${model.modelId}`;
}
