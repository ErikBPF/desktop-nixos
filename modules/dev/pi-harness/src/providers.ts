/**
 * Provider definitions for the home gateways and subscription accounts.
 *
 * API keys are resolved when a request is made, never at module load and never
 * logged. A key is read from the sops runtime file first and from the
 * documented environment variable second.
 */
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import { createModels, createProvider, type ApiKeyAuth, type Model, type Provider } from "@earendil-works/pi-ai";
import { openAICompletionsApi } from "@earendil-works/pi-ai/api/openai-completions.lazy";
import { openAIResponsesApi } from "@earendil-works/pi-ai/api/openai-responses.lazy";
import { anthropicProvider } from "@earendil-works/pi-ai/providers/anthropic";
import { openaiCodexProvider } from "@earendil-works/pi-ai/providers/openai-codex";
import { opencodeGoProvider } from "@earendil-works/pi-ai/providers/opencode-go";
import approvedModels from "./approved-models.json" with { type: "json" };
import { ModelRuntime } from "@earendil-works/pi-coding-agent";

export const LITELLM_BASE_URL = "https://litellm.homelab.pastelariadev.com/v1";
export const WORK_BASE_URL = "https://llm-gateway-dataplatform-dev.nstech.com.br/v1";

type GatewayProviderId = "litellm" | "work";
export type ProviderId = GatewayProviderId | "openai-codex" | "anthropic" | "opencode-go";

/** LiteLLM rejects a request without this routing header; any stable session value works. */
const LITELLM_SESSION = `pi-harness-${randomUUID()}`;

export type CredentialSource = {
	readonly file: string;
	readonly env: string;
};

export const CREDENTIAL_SOURCES: Readonly<Record<GatewayProviderId | "opencode-go", CredentialSource>> = {
	litellm: { file: "/run/secrets/opencode/litellm_key", env: "OPENCODE_LITELLM_KEY" },
	work: { file: "/run/secrets/opencode/work_key", env: "OPENCODE_WORK_KEY" },
	"opencode-go": { file: "/run/secrets/opencode/zen_key", env: "OPENCODE_API_KEY" },
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
const MODELS: Readonly<Record<GatewayProviderId, Readonly<Record<string, ModelConfig>>>> = {
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
		"glm-5.3": {
			name: "GLM-5.3 (LiteLLM → OpenCode Go)",
			reasoning: true,
			input: ["text"],
			inputCost: 1.4,
			outputCost: 4.4,
			cacheReadCost: 0.26,
			contextWindow: 1_000_000,
			maxTokens: 131_072,
		},
		"deepseek-flash-local": {
			name: "DeepSeek V4.1 Flash (local)",
			reasoning: true,
			input: ["text"],
			inputCost: 0,
			outputCost: 0,
			cacheReadCost: 0,
			contextWindow: 262_144,
			maxTokens: 8_192,
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
		"glm-5.3": {
			name: "GLM-5.3 (Work)",
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
	provider: GatewayProviderId,
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

function buildProvider(provider: GatewayProviderId, baseUrl: string) {
	const configs = MODELS[provider];
	const workCosts = {
		"chatgpt-5.6-luna": { input: 0.2, output: 1.2, cacheRead: 0.02, cacheWrite: 0 },
		"chatgpt-5.6-sol": { input: 4, output: 20, cacheRead: 0.5, cacheWrite: 0 },
		"chatgpt-5.6-terra": { input: 2, output: 12, cacheRead: 0.2, cacheWrite: 0 },
	};
	const subscriptions = openaiCodexProvider().getModels().flatMap(model => {
		const id = `${provider === "litellm" ? "codex-" : "chat"}${model.id}`;
		if (!approvedModels[provider].includes(id)) return [];
		return [{
			...model, id, provider, baseUrl,
			api: id === "codex-gpt-6.2-astra" ? "openai-responses" as const : "openai-completions" as const,
			name: `${model.name} (${provider === "litellm" ? "Codex via Orion" : "Work"})`,
			reasoning: provider === "litellm",
			contextWindow: provider === "litellm" ? 272_000 : 1_050_000,
			maxTokens: provider === "litellm" ? 32_768 : 128_000,
			cost: provider === "litellm" ? { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } : workCosts[id as keyof typeof workCosts],
			...(provider === "litellm"
				? { headers: { "x-opencode-session": LITELLM_SESSION } }
				: { compat: { supportsReasoningEffort: false } }),
		}];
	});
	return createProvider<"openai-completions" | "openai-responses">({
		id: provider,
		name: provider === "litellm" ? "Orion" : "Work",
		baseUrl,
		auth: { apiKey: fileApiKeyAuth(`${provider} API key`, CREDENTIAL_SOURCES[provider]) },
		models: [...Object.entries(configs).map(([id, config]) => buildModel(provider, id, baseUrl, config)), ...subscriptions],
		api: { "openai-completions": openAICompletionsApi(), "openai-responses": openAIResponsesApi() },
	});
}

export function createLitellmProvider() {
	return buildProvider("litellm", LITELLM_BASE_URL);
}

export function createWorkProvider() {
	return buildProvider("work", WORK_BASE_URL);
}

export function createHarnessProviders() {
	const go = { ...opencodeGoProvider(), auth: { apiKey: fileApiKeyAuth("OpenCode Go API key", CREDENTIAL_SOURCES["opencode-go"]) } };
	const providers: Provider[] = [createLitellmProvider(), createWorkProvider(), openaiCodexProvider(), anthropicProvider(), go];
	return providers.map(provider => {
		const key = provider.id === "openai-codex" ? "openai" : provider.id as keyof typeof approvedModels;
		const models = provider.getModels().filter(model => approvedModels[key].includes(model.id));
		return { ...provider, getModels: () => models, getAllModels: () => models };
	});
}

export async function createHarnessModels() {
	const accounts = await ModelRuntime.create({ modelsPath: null, refreshOnCreate: false });
	const models = createModels();
	for (const provider of createHarnessProviders()) {
		accounts.registerNativeProvider(provider);
		models.setProvider({
			...provider,
			auth: { apiKey: { name: provider.name, resolve: ({ signal }) => accounts.getAuth(provider.id, { signal }) } },
		});
	}
	return Object.assign(models, { settleCredentialWrites: () => accounts.settleCredentialWrites() });
}

export type ModelRef = {
	readonly provider: ProviderId;
	readonly modelId: string;
};

export function parseModelRef(value: string): ModelRef {
	const [provider, ...rest] = value.split("/");
	const modelId = rest.join("/");
	if ((provider !== "litellm" && provider !== "work" && provider !== "openai-codex" && provider !== "anthropic" && provider !== "opencode-go") || modelId === "") {
		throw new Error(`invalid model "${value}"; expected litellm/<id>, work/<id>, openai-codex/<id>, anthropic/<id>, or opencode-go/<id>`);
	}
	return { provider, modelId };
}

export function modelRefToString(model: ModelRef): string {
	return `${model.provider}/${model.modelId}`;
}
