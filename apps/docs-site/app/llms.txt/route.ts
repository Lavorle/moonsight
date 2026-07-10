import { source } from '@/lib/source';
import { llms } from 'fumadocs-core/source';

export const revalidate = false;

export function GET() {
  // Default-language index for LLM crawlers
  return new Response(llms(source).index());
}
