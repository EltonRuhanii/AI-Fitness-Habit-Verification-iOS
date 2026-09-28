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
  categories: Record<string, Criterion[]>;
}

/** Loads the catalog copied from DisciplineCore at build time (see scripts/copy-criteria.js). */
export function loadCatalog(file = path.join(__dirname, "generated/verification-criteria.json")): CriteriaCatalog {
  return JSON.parse(readFileSync(file, "utf8")) as CriteriaCatalog;
}

/** Shared criteria first, then the category's own; unknown categories fall back to `custom`. */
export function criteriaFor(catalog: CriteriaCatalog, category: string): Criterion[] {
  return [...catalog.sharedCriteria, ...(catalog.categories[category] ?? catalog.categories.custom ?? [])];
}
