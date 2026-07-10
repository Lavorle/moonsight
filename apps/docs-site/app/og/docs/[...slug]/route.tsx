import { getPageImage, source } from '@/lib/source';
import { notFound } from 'next/navigation';
import { ImageResponse } from 'next/og';
import { generate as DefaultImage } from 'fumadocs-ui/og';
import { appName } from '@/lib/shared';
import { i18n } from '@/lib/i18n';

export const revalidate = false;

export async function GET(_req: Request, { params }: RouteContext<'/og/docs/[...slug]'>) {
  const { slug } = await params;
  // URL: /og/docs/{locale}/...slugs/image.png
  const [locale, ...rest] = slug;
  if (!locale || !i18n.languages.includes(locale as 'zh' | 'en')) notFound();

  const page = source.getPage(rest.slice(0, -1), locale);
  if (!page) notFound();

  return new ImageResponse(
    <DefaultImage title={page.data.title} description={page.data.description} site={appName} />,
    {
      width: 1200,
      height: 630,
    },
  );
}

export function generateStaticParams() {
  return source.getLanguages().flatMap((entry) =>
    source.getPages(entry.language).map((page) => ({
      slug: [entry.language, ...getPageImage(page).segments],
    })),
  );
}
