/**
 * MoonBit wasm-gc instantiation — matching archived vanilla boot.js loadWasm.
 */

/**
 * MoonBit wasm-gc import object.
 *
 * With `use-js-builtin-string`, current host_web only imports `console.log`.
 * Keep spectest / ffi helpers for older/other artifacts.
 */
export function moonbitImports(): WebAssembly.Imports {
  let printBuf = "";
  const spectest: WebAssembly.ModuleImports = {
    print_char: (c: number) => {
      if (c === 10) {
        console.log(printBuf || "");
        printBuf = "";
      } else {
        printBuf += String.fromCharCode(c);
      }
    },
  };
  return {
    console: {
      log: (...args: unknown[]) => console.log("[moonbit]", ...args),
    },
    spectest,
    "moonbit:ffi": {
      make_closure: (funcref: (...a: unknown[]) => unknown, closure: unknown) =>
        funcref.bind(null, closure),
    },
  };
}

/**
 * Instantiate MoonBit wasm-gc module with js-string builtins.
 * Mirrors boot.js loadWasm options (builtins + importedStringConstants).
 */
export async function loadWasm(url: string): Promise<WebAssembly.Exports> {
  const imports = moonbitImports();
  // TypeScript DOM lib lacks the extended instantiateStreaming options
  // used by MoonBit wasm-gc (builtins / importedStringConstants).
  const result = await (
    WebAssembly.instantiateStreaming as (
      source: Response | PromiseLike<Response>,
      importObject?: WebAssembly.Imports,
      options?: { builtins?: string[]; importedStringConstants?: string },
    ) => Promise<WebAssembly.WebAssemblyInstantiatedSource>
  )(fetch(url), imports, {
    builtins: ["js-string"],
    importedStringConstants: "_",
  });
  return result.instance.exports;
}

/**
 * Build a binary Latin-1 string from Uint8Array (one code unit per byte).
 * Used to pass MSB bytes into MoonBit `load_msb` under js-builtin-string.
 */
export function bytesToBinaryString(buf: Uint8Array): string {
  const chunk = 0x8000;
  let raw = "";
  for (let i = 0; i < buf.length; i += chunk) {
    raw += String.fromCharCode.apply(
      null,
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      buf.subarray(i, i + chunk) as any as number[],
    );
  }
  return raw;
}

export type ContentMode = "production" | "demo";

export type ContentLoaderExports = {
  load_msb?: (raw: string) => number;
  load_source?: (source: string) => number;
  init_demo?: () => void;
};

type ContentResponse = Pick<
  Response,
  "ok" | "status" | "arrayBuffer" | "text"
>;

type FetchContent = (url: string) => Promise<ContentResponse>;
type DigestContent = (bytes: Uint8Array) => Promise<string>;

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest), (byte) =>
    byte.toString(16).padStart(2, "0"),
  ).join("");
}

export function validateContentManifest(
  manifest: unknown,
  contentMode: ContentMode,
  manifestUrl: string,
): Record<string, unknown> | null {
  const valid =
    typeof manifest === "object" &&
    manifest !== null &&
    !Array.isArray(manifest);
  if (!valid && contentMode === "production") {
    throw new Error(
      `MoonSight: production manifest '${manifestUrl}' is missing or invalid`,
    );
  }
  return valid ? (manifest as Record<string, unknown>) : null;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

async function loadMsb(
  exports_: ContentLoaderExports,
  fetchContent: FetchContent,
): Promise<void> {
  const url = "./game.msb";
  let response: ContentResponse;
  try {
    response = await fetchContent(url);
  } catch (error) {
    throw new Error(
      `MoonSight: failed to fetch production content '${url}': ${errorMessage(error)}`,
    );
  }
  if (!response.ok) {
    throw new Error(
      `MoonSight: production content '${url}' failed with HTTP ${response.status}`,
    );
  }

  let bytes: Uint8Array;
  try {
    bytes = new Uint8Array(await response.arrayBuffer());
  } catch (error) {
    throw new Error(
      `MoonSight: failed to read production content '${url}': ${errorMessage(error)}`,
    );
  }
  if (bytes.length === 0) {
    throw new Error(`MoonSight: production content '${url}' is empty`);
  }
  if (typeof exports_.load_msb !== "function") {
    throw new Error(
      `MoonSight: runtime load_msb export is unavailable for '${url}'`,
    );
  }

  let rc: number;
  try {
    rc = exports_.load_msb(bytesToBinaryString(bytes));
  } catch (error) {
    throw new Error(
      `MoonSight: runtime failed to load production content '${url}': ${errorMessage(error)}`,
    );
  }
  console.info("load_msb game.msb rc=", rc, "bytes=", bytes.length);
  if (rc !== 0) {
    throw new Error(
      `MoonSight: runtime rejected production content '${url}' with return code ${rc}`,
    );
  }
}

/** Validate every declared package artifact before mutating the runtime. */
export async function loadGameBundle(
  exports_: ContentLoaderExports,
  manifest: Record<string, unknown> | null,
  contentMode: ContentMode = "production",
  fetchContent: FetchContent = fetch,
  digestContent: DigestContent = sha256Hex,
): Promise<"game.msb" | "demo.yuki" | "init_demo"> {
  const rawDigests = manifest?.digests;
  if (
    typeof rawDigests !== "object" ||
    rawDigests === null ||
    Array.isArray(rawDigests)
  ) {
    if (contentMode === "production") {
      throw new Error("MoonSight: production manifest digests are missing or invalid");
    }
    return loadGameContent(exports_, contentMode, fetchContent);
  }
  const digests = rawDigests as Record<string, unknown>;
  if (typeof digests["game.msb"] !== "string") {
    throw new Error("MoonSight: production manifest digest for game.msb is missing");
  }
  for (const sectionName of ["resources", "audio"] as const) {
    const section = manifest?.[sectionName];
    if (section == null) continue;
    if (typeof section !== "object" || Array.isArray(section)) {
      throw new Error(`MoonSight: manifest ${sectionName} map is invalid`);
    }
    for (const path of Object.values(section as Record<string, unknown>)) {
      if (typeof path !== "string" || typeof digests[path] !== "string") {
        throw new Error(`MoonSight: manifest ${sectionName} artifact '${String(path)}' has no digest`);
      }
    }
  }
  const paths = [
    "game.msb",
    ...Object.keys(digests).filter((path) => path !== "game.msb").sort(),
  ];
  for (const path of paths) {
    if (
      path === "" ||
      path.startsWith("/") ||
      path.includes("\\") ||
      path.split("/").some((part) => part === "" || part === "." || part === "..")
    ) {
      throw new Error(`MoonSight: unsafe bundle artifact path '${path}'`);
    }
  }
  let gameBytes: Uint8Array | null = null;
  for (const path of paths) {
    const expected = digests[path];
    if (typeof expected !== "string" || !/^[0-9a-f]{64}$/.test(expected)) {
      throw new Error(`MoonSight: invalid SHA-256 digest for '${path}'`);
    }
    const url = `./${path}`;
    let response: ContentResponse;
    try {
      response = await fetchContent(url);
    } catch (error) {
      throw new Error(`MoonSight: failed to fetch bundle artifact '${path}': ${errorMessage(error)}`);
    }
    if (!response.ok) {
      throw new Error(`MoonSight: bundle artifact '${path}' failed with HTTP ${response.status}`);
    }
    const bytes = new Uint8Array(await response.arrayBuffer());
    if (bytes.length === 0) throw new Error(`MoonSight: bundle artifact '${path}' is empty`);
    const actual = await digestContent(bytes);
    if (actual !== expected) {
      throw new Error(`MoonSight: digest mismatch for bundle artifact '${path}'`);
    }
    if (path === "game.msb") gameBytes = bytes;
  }
  if (!gameBytes) throw new Error("MoonSight: validated bundle omitted game.msb");
  if (typeof exports_.load_msb !== "function") {
    throw new Error("MoonSight: runtime load_msb export is unavailable for './game.msb'");
  }
  const rc = exports_.load_msb(bytesToBinaryString(gameBytes));
  if (rc !== 0) {
    throw new Error(`MoonSight: runtime rejected production content './game.msb' with return code ${rc}`);
  }
  return "game.msb";
}

async function loadDemoFallback(
  exports_: ContentLoaderExports,
  fetchContent: FetchContent,
): Promise<"demo.yuki" | "init_demo"> {
  const url = "./demo.yuki";
  try {
    const response = await fetchContent(url);
    if (response.ok && typeof exports_.load_source === "function") {
      const source = await response.text();
      const rc = exports_.load_source(source);
      console.info("load_source demo.yuki rc=", rc);
      if (rc === 0) return "demo.yuki";
    }
  } catch (error) {
    console.warn(`demo content '${url}' load error`, error);
  }

  if (typeof exports_.init_demo !== "function") {
    throw new Error("MoonSight: built-in demo fallback is unavailable");
  }
  exports_.init_demo();
  console.info("init_demo()");
  return "init_demo";
}

/**
 * Load packaged game content. Production is fail-closed; development/demo
 * fallback is available only when the caller explicitly selects demo mode.
 */
export async function loadGameContent(
  exports_: ContentLoaderExports,
  contentMode: ContentMode = "production",
  fetchContent: FetchContent = fetch,
): Promise<"game.msb" | "demo.yuki" | "init_demo"> {
  try {
    await loadMsb(exports_, fetchContent);
    return "game.msb";
  } catch (error) {
    if (contentMode === "production") throw error;
    console.warn(
      "game.msb load failed in demo mode; using fallback:",
      errorMessage(error),
    );
  }
  return loadDemoFallback(exports_, fetchContent);
}

export async function loadManifest(url: string): Promise<unknown | null> {
  try {
    const res = await fetch(url);
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  }
}
