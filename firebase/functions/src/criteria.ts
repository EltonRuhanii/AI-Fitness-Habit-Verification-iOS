import { readFileSync } from "node:fs";
import path from "node:path";

export interface Criterion {
  id: string;
  name: string;
  question: string;
  isRequired: boolean;
}

export interface CriteriaCatalog {
  version: string;
  defaultConfidenceThreshold: number;
  flags: string[];
  sharedCriteria: Criterion[];
  /** Shared criteria a category replaces with its own (mirrors the Swift catalog). */
  sharedCriteriaExemptions?: Record<string, string[]>;
  categories: Record<string, Criterion[]>;
}

/** Loads the catalog copied from DisciplineCore at build time (see scripts/copy-criteria.js). */
export function loadCatalog(file = path.join(__dirname, "generated/verification-criteria.json")): CriteriaCatalog {
  return JSON.parse(readFileSync(file, "utf8")) as CriteriaCatalog;
}

/** Shared criteria first, then the category's own; unknown categories fall back to `custom`. */
export function criteriaFor(catalog: CriteriaCatalog, category: string): Criterion[] {
  const exempt = new Set(catalog.sharedCriteriaExemptions?.[category] ?? []);
  return [
    ...catalog.sharedCriteria.filter((c) => !exempt.has(c.id)),
    ...(catalog.categories[category] ?? catalog.categories.custom ?? []),
  ];
}
