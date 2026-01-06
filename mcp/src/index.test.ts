import { resolvePath, TOOLS, CliResult } from "./index";

describe("resolvePath", () => {
  const originalEnv = process.env;

  beforeEach(() => {
    jest.resetModules();
    process.env = { ...originalEnv };
  });

  afterAll(() => {
    process.env = originalEnv;
  });

  it("returns input path when provided", () => {
    const result = resolvePath("/custom/path.mv2");
    expect(result).toBe("/custom/path.mv2");
  });

  it("throws when no path provided and no default set", () => {
    // Clear the env var
    delete process.env.MEMVID_DEFAULT_PATH;

    // Need to re-import to get fresh module with cleared env
    // For this test, we test that it throws with undefined input
    expect(() => resolvePath(undefined)).toThrow("No memory file path provided");
  });

  it("prefers input path over environment default", () => {
    process.env.MEMVID_DEFAULT_PATH = "/default/path.mv2";
    const result = resolvePath("/custom/path.mv2");
    expect(result).toBe("/custom/path.mv2");
  });
});

describe("TOOLS", () => {
  it("exports 5 tools", () => {
    expect(TOOLS).toHaveLength(5);
  });

  it("has memory_remember tool with required content field", () => {
    const tool = TOOLS.find((t) => t.name === "memory_remember");
    expect(tool).toBeDefined();
    expect(tool?.inputSchema.required).toContain("content");
    expect(tool?.description).toContain("Store knowledge");
  });

  it("has memory_recall tool with required query field", () => {
    const tool = TOOLS.find((t) => t.name === "memory_recall");
    expect(tool).toBeDefined();
    expect(tool?.inputSchema.required).toContain("query");
    expect(tool?.description).toContain("Search memory");
  });

  it("has memory_list tool for browsing", () => {
    const tool = TOOLS.find((t) => t.name === "memory_list");
    expect(tool).toBeDefined();
    expect(tool?.description).toContain("chronologically");
  });

  it("has memory_stats tool", () => {
    const tool = TOOLS.find((t) => t.name === "memory_stats");
    expect(tool).toBeDefined();
    expect(tool?.description).toContain("statistics");
  });

  it("has memory_create tool with required path field", () => {
    const tool = TOOLS.find((t) => t.name === "memory_create");
    expect(tool).toBeDefined();
    expect(tool?.inputSchema.required).toContain("path");
  });

  it("all tools have valid inputSchema type", () => {
    for (const tool of TOOLS) {
      expect(tool.inputSchema.type).toBe("object");
      expect(tool.inputSchema.properties).toBeDefined();
    }
  });

  it("all tools have descriptions", () => {
    for (const tool of TOOLS) {
      expect(tool.description).toBeTruthy();
      expect(tool.description.length).toBeGreaterThan(10);
    }
  });
});

describe("Tool schema validation", () => {
  it("memory_remember supports uri, title, and tags", () => {
    const tool = TOOLS.find((t) => t.name === "memory_remember");
    const props = tool?.inputSchema.properties;

    expect(props?.uri).toBeDefined();
    expect(props?.title).toBeDefined();
    expect(props?.tags).toBeDefined();
    expect(props?.tags?.type).toBe("array");
  });

  it("memory_recall supports scope and limit", () => {
    const tool = TOOLS.find((t) => t.name === "memory_recall");
    const props = tool?.inputSchema.properties;

    expect(props?.scope).toBeDefined();
    expect(props?.limit).toBeDefined();
    expect(props?.limit?.type).toBe("number");
  });

  it("memory_list supports limit, since, and until", () => {
    const tool = TOOLS.find((t) => t.name === "memory_list");
    const props = tool?.inputSchema.properties;

    expect(props?.limit).toBeDefined();
    expect(props?.since).toBeDefined();
    expect(props?.until).toBeDefined();
    expect(props?.since?.type).toBe("number");
    expect(props?.until?.type).toBe("number");
  });
});

describe("CliResult interface", () => {
  it("can create valid CliResult objects", () => {
    const successResult: CliResult = {
      success: true,
      stdout: '{"frame_id": 42}',
      stderr: "",
    };

    expect(successResult.success).toBe(true);
    expect(JSON.parse(successResult.stdout)).toEqual({ frame_id: 42 });

    const errorResult: CliResult = {
      success: false,
      stdout: "",
      stderr: "File not found",
    };

    expect(errorResult.success).toBe(false);
    expect(errorResult.stderr).toBe("File not found");
  });
});
