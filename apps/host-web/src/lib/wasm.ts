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

export async function loadManifest(url: string): Promise<unknown | null> {
  try {
    const res = await fetch(url);
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  }
}
