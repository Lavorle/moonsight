import { getLLMText, getPageMarkdownUrl, source } from '@/lib/source';
import { notFound } from 'next/navigation';
import { i18n } from '@/lib/i18n';

export const revalidate = false;

export async function GET(
  _req: Request,
  { params }: RouteContext<'/llms.mdx/docs/[[...slug]]'>,
) {
  const { slug } = await params;
  if (!slug?.length) notFound();

  // URL: /llms.mdx/docs/{locale}/...slugs/content.md
  const [locale, ...rest] = slug;
  if (!locale || !i18n.languages.includes(locale as 'zh' | 'en')) notFound();

  const page = source.getPage(rest.slice(0, -1), locale);
  if (!page) notFound();

  return new Response(await getLLMText(page), {
    headers: {
      'Content-Type': 'text/markdown',
    },
  });
}

export function generateStaticParams() {
  return source.getLanguages().flatMap((entry) =>
    source.getPages(entry.language).map((page) => ({
      slug: [entry.language, ...getPageMarkdownUrl(page).segments],
    })),
  );
}
