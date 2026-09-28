import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import { test } from "node:test";
import type { Criterion } from "../criteria";
import { decide, MalformedResponseError, parseAssessment } from "../policy";

interface Fixture {
  criteria: Criterion[];
  threshold: number;
  cases: {
    name: string;
    response: string;
    expected: { status?: string; confidence?: number; flagsInclude?: string; error?: string };
  }[];
}

// Same file the Swift tests run, so both policy implementations must agree.
const fixturePath = path.resolve(
  __dirname,
  "../../../../Packages/DisciplineCore/Tests/DisciplineCoreTests/Fixtures/verification-policy-cases.json",
);
const fixture = JSON.parse(readFileSync(fixturePath, "utf8")) as Fixture;

test("shared vectors are present", () => {
  assert.ok(fixture.cases.length >= 10);
});

for (const testCase of fixture.cases) {
  test(`shared vector: ${testCase.name}`, () => {
    const run = () => decide(parseAssessment(testCase.response), fixture.criteria, fixture.threshold);
    if (testCase.expected.error) {
      assert.throws(run, (error: unknown) => error instanceof MalformedResponseError && error.code === testCase.expected.error);
      return;
    }
    const decision = run();
    assert.equal(decision.status, testCase.expected.status);
    assert.equal(decision.confidence, testCase.expected.confidence);
    assert.equal(decision.criteria.length, fixture.criteria.length);
    if (testCase.expected.flagsInclude) assert.ok(decision.flags.includes(testCase.expected.flagsInclude));
  });
}

test("rejects wrongly typed fields", () => {
  assert.throws(() => parseAssessment(`{"criteria":[{"id":"a","passed":"yes"}],"confidence":0.9,"reason":"","flags":[]}`), MalformedResponseError);
  assert.throws(() => parseAssessment(`{"criteria":[],"confidence":"high","reason":"","flags":[]}`), MalformedResponseError);
  assert.throws(() => parseAssessment(`[]`), MalformedResponseError);
});
