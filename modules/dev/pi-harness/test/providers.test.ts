import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import {
	CREDENTIAL_SOURCES,
	createHarnessProviders,
	parseModelRef,
	resolveKey,
} from "../src/providers.js";

describe("providers", () => {
	it("registers both gateways with the documented models and reasoning flags", () => {
		const [litellm, work] = createHarnessProviders();
		expect(litellm.id).toBe("litellm");
		expect(work.id).toBe("work");
		const litellmModels = litellm.getModels();
		const workModels = work.getModels();
		expect(litellmModels.map((model) => model.id).sort()).toEqual(["deepseek-v4.1-flash", "glm-5.3-flash"]);
		expect(workModels.map((model) => model.id).sort()).toEqual(["deepseek-v4.1-flash", "glm-5.3-flash"]);
		expect(litellmModels.every((model) => model.reasoning)).toBe(true);
		expect(workModels.every((model) => model.reasoning === false)).toBe(true);
		expect(litellmModels[0]?.baseUrl).toBe("https://litellm.homelab.pastelariadev.com/v1");
		expect(workModels[0]?.baseUrl).toBe("https://llm-gateway-dataplatform-dev.nstech.com.br/v1");
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
