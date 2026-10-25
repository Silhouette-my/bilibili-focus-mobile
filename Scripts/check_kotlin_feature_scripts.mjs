import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { compileFunction } from 'node:vm';

// Kotlin triple-quoted strings are raw: unlike Swift strings, JavaScript
// regex backslashes must not be doubled. Compile every embedded feature so
// serialization/string-presence tests cannot hide a broken injected script.
const source = await readFile(new URL(
  '../focus-core/src/commonMain/kotlin/org/bilibilifocus/core/injection/FocusRuleCatalog.kt',
  import.meta.url,
), 'utf8');
const scripts = [...source.matchAll(/script\s*=\s*"""([\s\S]*?)"""/g)];
assert.ok(scripts.length > 0, 'No Kotlin feature scripts found');
assert.equal(scripts.length, [...source.matchAll(/\bscript\s*=/g)].length,
  'Every feature script must be a checked raw string');
for (const [index, match] of scripts.entries()) {
  const script = match[1].replaceAll("${'$'}", '$');
  compileFunction(script, ['config', 'helpers'], { filename: `Kotlin feature ${index + 1}` });
}
console.log(`Kotlin feature JavaScript syntax passed (${scripts.length} scripts).`);
