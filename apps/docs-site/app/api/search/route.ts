import { source } from '@/lib/source';
import { createFromSource } from 'fumadocs-core/search/server';

export const { GET } = createFromSource(source, {
  // https://docs.orama.com/docs/orama-js/supported-languages
  // zh uses English tokenizer for scaffold; Task 12 may add @orama/tokenizers
  localeMap: {
    en: { language: 'english' },
    zh: { language: 'english' },
  },
});
