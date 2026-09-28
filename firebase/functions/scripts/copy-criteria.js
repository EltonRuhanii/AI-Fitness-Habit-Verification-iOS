// Copies the verification criteria catalog from DisciplineCore (the single source of truth)
// into the compiled function, so the app and the server always use identical criteria.
const fs = require("node:fs");
const path = require("node:path");

const source = path.resolve(__dirname, "../../../Packages/DisciplineCore/Sources/DisciplineCore/Resources/verification-criteria.json");
const target = path.resolve(__dirname, "../lib/generated/verification-criteria.json");

fs.mkdirSync(path.dirname(target), { recursive: true });
fs.copyFileSync(source, target);
console.log(`Copied criteria catalog -> ${path.relative(process.cwd(), target)}`);
