import assert from "node:assert/strict";
import test from "node:test";

import {
  DEFAULT_PREFS,
  isFormalLocale,
  parsePrefsJson,
  resolveLocale,
} from "./prefs.ts";

test("prefs preserve a valid locale and remain backward compatible", () => {
  assert.equal(parsePrefsJson('{"locale":"zh-Hans-CN"}').locale, "zh-Hans-CN");
  assert.equal(parsePrefsJson("{}").locale, DEFAULT_PREFS.locale);
});

test("formal locale validation and resolution match the runtime contract", () => {
  assert.equal(isFormalLocale("en"), true);
  assert.equal(isFormalLocale("zh-Hans-CN"), true);
  assert.equal(isFormalLocale("es-419"), true);
  assert.equal(isFormalLocale("EN-us"), false);
  assert.equal(resolveLocale("zh-CN", ["en", "zh-CN"], "en"), "zh-CN");
  assert.equal(resolveLocale("fr", ["en", "zh-CN"], "en"), "en");
  assert.throws(() => resolveLocale("en", ["en", "bad_tag"], "en"), RangeError);
});

test("invalid persisted locale falls back without corrupting other prefs", () => {
  const prefs = parsePrefsJson('{"locale":"zh_cn","master_volume":0.25}');
  assert.equal(prefs.locale, DEFAULT_PREFS.locale);
  assert.equal(prefs.master_volume, 0.25);
});
