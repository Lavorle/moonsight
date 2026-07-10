# MoonSight Docs Site

Bilingual documentation site for MoonSight (Fumadocs + Next.js App Router).

## Locales

| Locale | Prefix | Content root   |
| ------ | ------ | -------------- |
| 中文   | `/zh`  | `content/zh`   |
| English| `/en`  | `content/en`   |

Default locale: **zh** (middleware redirects `/` → `/zh`).

## Scripts

```bash
npm install
npm run dev    # http://localhost:3000
npm run build
npm start
```

## Stack

- Next.js App Router
- fumadocs-ui / fumadocs-mdx / fumadocs-core
- MDX content with `parser: 'dir'` i18n

Placeholder pages only in Task 11 — full docs content is Task 12.
