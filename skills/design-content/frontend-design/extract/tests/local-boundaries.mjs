// VFT-added boundary checks, not an upstream snapshot; no network, browser, or file writes.
import assert from "node:assert/strict";
import { normalizeExtractedStyles } from "../lib/normalize.mjs";
import { generateDesignMarkdown } from "../lib/generate-design-md.mjs";
import { generateSkillMarkdown } from "../lib/generate-skill-md.mjs";
import { validateMarkdownOutput } from "../lib/validate.mjs";

const base = { source: { url: "approved-public-surface", title: "Public fixture" }, sampledElements: 40, totalElements: 40 };
const normalize = (fields) => normalizeExtractedStyles({ ...base, ...fields });
let checks = 0;
function check(name, fn) {
  fn();
  checks += 1;
  console.log(`PASS ${name}`);
}

check("rgba alpha is lost: transparent black becomes opaque candidate", () => {
  const result = normalize({ colors: [{ backgroundColor: "rgba(0, 0, 0, 0)" }] });
  assert.equal(result.colorPalette[0].value, "#000000");
});
check("RGB percent channels are parsed as bytes, not percentages", () => {
  const result = normalize({ colors: [{ textColor: "rgb(100%, 0%, 0%)" }] });
  assert.equal(result.colorPalette[0].value, "#640000");
});
check("parsePx accepts rem and composite radius without resolving units", () => {
  const result = normalize({ typography: [{ fontSize: "1.5rem" }], radius: ["50%", "8px 24px"] });
  assert.equal(result.typographyScale[0].value, "1.5px");
  assert.deepEqual(result.radiusTokens.map((row) => row.value), ["8px", "50px"]);
});
check("zero transition masks nonzero animation duration", () => {
  const result = normalize({ motion: [{ transitionDuration: "0s", animationDuration: "2s" }] });
  assert.equal(result.motionDurationTokens.length, 0);
});
check("only first comma-separated duration is retained", () => {
  const result = normalize({ motion: [{ transitionDuration: "150ms, 1s" }] });
  assert.deepEqual(result.motionDurationTokens.map((row) => row.value), ["150ms"]);
});
check("same-value deduplication can discard text or surface role", () => {
  const result = normalize({ colors: [{ textColor: "#ffffff", backgroundColor: "#ffffff", outlineColor: "#ffffff" }] });
  assert.equal(result.colorPalette.length, 1);
  assert.equal(result.colorPalette[0].token, "color.text.primary");
});
check("empty profiling still returns a low-confidence specific label", () => {
  const result = normalize({ source: { url: "", title: "" } });
  assert.equal(result.siteProfile.confidence, "low");
  assert.equal(result.siteProfile.productSurface, "documentation site");
});
check("validator accepts headings and keywords without real design evidence", () => {
  const headings = ["Mission", "Brand", "Style Foundations", "Accessibility", "Writing Tone", "Rules: Do", "Rules: Don't", "Guideline Authoring Workflow", "Required Output Structure", "Component Rule Expectations", "Quality Gates"];
  const markdown = headings.map((name) => `## ${name}`).join("\n") + "\nWCAG 2.2 AA must should";
  const result = validateMarkdownOutput("design", markdown);
  assert.equal(result.isValid, true);
  assert.ok(result.warnings.length > 0);
});
check("CJK-only system name produces empty generated skill slug", () => {
  const result = generateSkillMarkdown({ normalized: normalize({}), metadata: { systemName: "中文设计" } });
  assert.ok(result.includes("name: design-system-\n"));
});
check("reviewed metadata and corrected in-memory tokens generate valid local draft", () => {
  const normalized = normalize({
    typography: [{ fontFamily: "system-ui, sans-serif", fontSize: "16px", fontWeight: "400", lineHeight: "24px" }],
    colors: [{ textColor: "rgb(17, 24, 39)", backgroundColor: "rgb(255, 255, 255)" }],
    spacing: [{ paddingTop: "16px" }],
    radius: ["8px"]
  });
  normalized.colorPalette = [
    { token: "text.default", value: "#111827", usage: 1 },
    { token: "surface.canvas", value: "#ffffff", usage: 1 }
  ];
  const markdown = generateDesignMarkdown({ normalized, metadata: { systemName: "Reviewed fixture", brand: "Fixture", audience: "confirmed audience", productSurface: "confirmed public surface" } });
  assert.equal(validateMarkdownOutput("design", markdown).isValid, true);
  assert.ok(markdown.includes("- Audience: confirmed audience"));
  assert.ok(!markdown.includes("https://"));
  assert.equal(base.source.url, "approved-public-surface");
});
console.log(`Local boundary checks passed: ${checks}/10. Known limitations are reproduced, not fixed.`);
