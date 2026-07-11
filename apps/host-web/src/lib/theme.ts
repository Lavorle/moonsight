/**
 * Theme loader: registers solid placeholders then optional PNG role textures.
 */

export type ThemeManifest = {
  id: string;
  display_name: string;
  fallback_solids: Record<string, [number, number, number, number]>;
  roles: Record<string, { file?: string }>;
};

export async function loadTheme(
  baseUrl: string, // "/themes/amber_soft"
  registerSolid: (id: string, rgba: number[]) => void,
  registerImage: (id: string, url: string) => Promise<void>,
): Promise<ThemeManifest> {
  const res = await fetch(`${baseUrl}/theme.json`);
  if (!res.ok) throw new Error(`theme load failed: ${res.status}`);
  const manifest = (await res.json()) as ThemeManifest;
  for (const [role, rgba] of Object.entries(manifest.fallback_solids)) {
    registerSolid(role, rgba);
  }
  for (const [role, spec] of Object.entries(manifest.roles)) {
    if (spec.file) {
      try {
        await registerImage(role, `${baseUrl}/${spec.file}`);
      } catch (e) {
        console.warn("[theme] image failed, solid kept", role, e);
      }
    }
  }
  return manifest;
}
