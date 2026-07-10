import { DynamicLink } from 'fumadocs-core/dynamic-link';

export default async function HomePage({ params }: PageProps<'/[lang]'>) {
  const { lang } = await params;
  const isZh = lang === 'zh';

  return (
    <div className="flex flex-col justify-center text-center flex-1">
      <h1 className="text-2xl font-bold mb-4">
        {isZh ? 'MoonSight 文档' : 'MoonSight Docs'}
      </h1>
      <p>
        {isZh ? '打开 ' : 'Open '}
        <DynamicLink href="/[lang]/docs" className="font-medium underline">
          /docs
        </DynamicLink>
        {isZh
          ? ' 查看快速开始、MoonYuki 与游玩输入文档。'
          : ' for Getting Started, MoonYuki, and play-input docs.'}
      </p>
    </div>
  );
}
