// Grants (or revokes) researcher access for an existing account.
//
//   GOOGLE_APPLICATION_CREDENTIALS=service-account.json node scripts/set-researcher-claim.js researcher@uni.edu
//   GOOGLE_APPLICATION_CREDENTIALS=service-account.json node scripts/set-researcher-claim.js researcher@uni.edu --revoke
//
// Researchers can read all pseudonymous daily records and export CSVs; they cannot read any
// participant's private documents or photos. The user must sign out and in again (or the app
// refreshes the token) for the change to apply.
const { initializeApp, applicationDefault } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");

async function main() {
  const [email, flag] = process.argv.slice(2);
  if (!email) {
    console.error("Usage: node scripts/set-researcher-claim.js <email> [--revoke]");
    process.exit(1);
  }
  initializeApp({ credential: applicationDefault() });
  const user = await getAuth().getUserByEmail(email);
  const claims = { ...(user.customClaims ?? {}) };
  if (flag === "--revoke") delete claims.researcher;
  else claims.researcher = true;
  await getAuth().setCustomUserClaims(user.uid, claims);
  console.log(`${flag === "--revoke" ? "Revoked" : "Granted"} researcher access for ${email}.`);
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
