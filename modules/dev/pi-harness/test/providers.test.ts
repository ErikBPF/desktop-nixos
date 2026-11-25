import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it, vi } from "vitest";
import approvedModels from "../src/approved-models.json" with { type: "json" };
import {
	CREDENTIAL_SOURCES,
	createHarnessProviders,
	createHarnessModels,
	parseModelRef,
	resolveKey,
} from "../src/providers.js";

describe("providers", () => {
	it("exposes only approved providers and models despite ambient credentials", async () => {
		vi.stubEnv("PI_CODING_AGENT_DIR", await mkdtemp(join(tmpdir(), "pi-harness-catalog-")));
		vi.stubEnv("OPENAI_API_KEY", "ambient-unapproved-fixture");
		vi.stubEnv("GEMINI_API_KEY", "ambient-unapproved-fixture");
		try {
			const models = await createHarnessModels();
			expect(models.getProviders().map(provider => provider.id).sort()).toEqual([
				"anthropic", "litellm", "openai-codex", "opencode-go", "work",
			]);
			const approved = Object.entries(approvedModels).flatMap(([provider, ids]) => ids.map(id =>
				`${provider === "openai" ? "openai-codex" : provider}/${id}`,
			));
			expect(models.getModels().map(model => `${model.provider}/${model.id}`).sort()).toEqual(approved.sort());
			expect(models.getModelsOfType("image")).toEqual([]);
			expect(models.getModelsOfType("classifier")).toEqual([]);
			expect(models.getAllModels()).toHaveLength(approved.length);
			for (const model of await models.getAllAvailable()) {
				expect(approved).toContain(`${model.provider}/${model.id}`);
			}
			expect(await models.getAuth("openai")).toBeUndefined();
			expect(await models.getAuth("google")).toBeUndefined();
		} finally {
			vi.unstubAllEnvs();
		}
	});

	it("uses the shared Pi account store and observes rotated credentials", async () => {
		const dir = await mkdtemp(join(tmpdir(), "pi-harness-auth-"));
		const file = join(dir, "auth.json");
		const credentials = {
			litellm: { type: "api_key", key: "fixture-gateway", env: { PI_FIXTURE_ENV: "preserved" } },
			"openai-codex": { type: "oauth", access: "fixture-codex", refresh: "fixture-refresh", expires: Date.now() + 3_600_000 },
			anthropic: { type: "oauth", access: "fixture-claude", refresh: "fixture-refresh", expires: Date.now() + 3_600_000 },
		};
		await writeFile(file, JSON.stringify(credentials));
		vi.stubEnv("PI_CODING_AGENT_DIR", dir);
		try {
			const models = await createHarnessModels();
			expect((await models.getAuth("openai-codex"))?.auth.apiKey).toBe("fixture-codex");
			expect((await models.getAuth("openai-codex"))?.source).toBe("OAuth");
			expect((await models.getAuth("anthropic"))?.auth.apiKey).toBe("fixture-claude");
			expect((await models.getAuth("litellm"))?.env).toEqual({ PI_FIXTURE_ENV: "preserved" });
			expect((await models.getAuth("litellm"))?.source).toBe("stored credential");
			const model = models.getModel("litellm", "deepseek-v4.1-flash")!;
			expect((await models.getAuth(model))?.auth.headers?.["x-opencode-session"]).toMatch(/^pi-harness-/);
			credentials.anthropic.access = "fixture-claude-rotated";
			await writeFile(file, JSON.stringify(credentials));
			expect((await models.getAuth("anthropic"))?.auth.apiKey).toBe("fixture-claude-rotated");
		} finally {
			vi.unstubAllEnvs();
		}
	});

	it("registers native Codex and Claude providers with subscription login", () => {
		const providers = createHarnessProviders();
		expect(providers.map((provider) => provider.id)).toEqual(["litellm", "work", "openai-codex", "anthropic", "opencode-go"]);
		expect(providers.find((provider) => provider.id === "openai-codex")?.auth.oauth).toBeDefined();
		expect(providers.find((provider) => provider.id === "anthropic")?.auth.oauth).toBeDefined();
	});

	it("accepts native subscription model references", () => {
		for (const provider of ["openai-codex", "anthropic", "opencode-go"]) {
			expect(parseModelRef(`${provider}/approved-model`)).toEqual({ provider, modelId: "approved-model" });
		}
	});

	it("registers the approved direct Go fallback with native protocol routing", () => {
		const go = createHarnessProviders().find(provider => provider.id === "opencode-go");
		expect(go?.getModels().map(model => model.id).sort()).toEqual(["deepseek-v4.1-flash", "glm-5.3"]);
		expect(CREDENTIAL_SOURCES["opencode-go"]).toEqual({ file: "/run/secrets/opencode/zen_key", env: "OPENCODE_API_KEY" });
		expect(go?.getModels().find(model => model.id === "glm-5.3")?.api).toBe("openai-completions");
	});

	it("limits subscription providers to approved models", () => {
		const providers = createHarnessProviders();
		expect(providers.find((provider) => provider.id === "openai-codex")?.getModels().map(model => model.id).sort()).toEqual([
			"gpt-5.6-luna", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-6-astra",
		]);
		expect(providers.find((provider) => provider.id === "anthropic")?.getModels().map(model => model.id).sort()).toEqual([
			"claude-haiku-5-5", "claude-opus-5-5", "claude-sonnet-5-5",
		]);
	});

	it("registers both gateways with the documented models and reasoning flags", () => {
		const [litellm, work] = createHarnessProviders();
		expect(litellm.id).toBe("litellm");
		expect(work.id).toBe("work");
		const litellmModels = litellm.getModels();
		const workModels = work.getModels();
		expect(litellmModels.map((model) => model.id).sort()).toEqual([
			"codex-gpt-5.6-luna", "codex-gpt-5.6-sol", "codex-gpt-5.6-terra", "codex-gpt-6-astra", "deepseek-v4.1-flash", "glm-5.3",
		]);
		expect(workModels.map((model) => model.id).sort()).toEqual([
			"chatgpt-5.6-luna", "chatgpt-5.6-sol", "chatgpt-5.6-terra", "deepseek-v4.1-flash", "glm-5.3-flash",
		]);
		expect(litellmModels.every((model) => model.reasoning)).toBe(true);
		expect(workModels.every((model) => model.reasoning === false)).toBe(true);
		expect(litellmModels[0]?.baseUrl).toBe("https://litellm.homelab.pastelariadev.com/v1");
		expect(workModels[0]?.baseUrl).toBe("https://llm-gateway-dataplatform-dev.nstech.com.br/v1");
	});

	it("keeps gateway alias endpoints, limits, and Work pricing", () => {
		const [litellm, work] = createHarnessProviders();
		expect(litellm.getModels().find(model => model.id === "codex-gpt-6-astra")?.api).toBe("openai-responses");
		const sol = work.getModels().find(model => model.id === "chatgpt-5.6-sol");
		expect(sol?.cost).toEqual({ input: 4, output: 20, cacheRead: 0.5, cacheWrite: 0 });
		expect(sol?.contextWindow).toBe(1_050_000);
		expect(sol?.maxTokens).toBe(128_000);
	});

	it("reads a key from the file at resolution time", async () => {
		const dir = await mkdtemp(join(tmpdir(), "pi-harness-key-"));
		const file = join(dir, "key");
		await writeFile(file, "file-key\n");
		expect(await resolveKey({ file, env: "PI_HARNESS_UNUSED" })).toBe("file-key");
	});

	it("falls back to the documented environment variable", async () => {
		const previous = process.env.PI_HARNESS_TEST_KEY;
		process.env.PI_HARNESS_TEST_KEY = "env-key";
		try {
			expect(await resolveKey({ file: "/nonexistent/pi-harness-key", env: "PI_HARNESS_TEST_KEY" })).toBe(
				"env-key",
			);
		} finally {
			if (previous === undefined) delete process.env.PI_HARNESS_TEST_KEY;
			else process.env.PI_HARNESS_TEST_KEY = previous;
		}
	});

	it("parses model references and rejects other providers", () => {
		expect(parseModelRef("work/glm-5.3-flash")).toEqual({ provider: "work", modelId: "glm-5.3-flash" });
		expect(() => parseModelRef("openai/gpt")).toThrow();
		expect(CREDENTIAL_SOURCES.litellm.file).toBe("/run/secrets/opencode/litellm_key");
		expect(CREDENTIAL_SOURCES.work.env).toBe("OPENCODE_WORK_KEY");
	});
});
