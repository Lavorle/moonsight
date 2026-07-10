import { getLLMText, source } from '@/lib/source';
import { i18n } from '@/lib/i18n';

export const revalidate = false;

export async function GET() {
  const scan = i18n.languages.flatMap((lang) => source.getPages(lang).map(getLLMText));
  const scanned = await Promise.all(scan);

  return new Response(scanned.join('\n\n'));
}
