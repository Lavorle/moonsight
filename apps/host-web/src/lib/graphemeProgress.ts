const segmenter = new Intl.Segmenter(undefined, { granularity: "grapheme" });

function boundaries(text: string): number[] {
  const out = [0];
  for (const part of segmenter.segment(text)) {
    out.push(part.index + part.segment.length);
  }
  return out;
}

/** Remap reveal progress and return a grapheme-safe UTF-16 boundary. */
export function remapGraphemeProgress(
  oldText: string,
  oldVisibleUtf16: number,
  newText: string,
  completed: boolean,
): number {
  if (completed) return newText.length;
  const oldBounds = boundaries(oldText);
  const newBounds = boundaries(newText);
  const clamped = Math.max(0, Math.min(oldText.length, oldVisibleUtf16));
  let oldRevealed = 0;
  for (let i = 1; i < oldBounds.length && oldBounds[i] <= clamped; i += 1) {
    oldRevealed = i;
  }
  const oldTotal = oldBounds.length - 1;
  const newTotal = newBounds.length - 1;
  if (oldTotal === 0 || newTotal === 0) return 0;
  const next = Math.min(
    newTotal,
    Math.floor((oldRevealed / oldTotal) * newTotal),
  );
  return newBounds[next];
}
