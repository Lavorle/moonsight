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

Core pages (Task 12): Getting Started, MoonYuki subset, Play input — zh + en under `content/`.
