# Security

## Secrets

Never commit `.env`, an Apps Script deployment URL paired with its token, or exported tracker data. Local secrets belong in `.env` or exported environment variables. Google-side secrets and spreadsheet identifiers belong in Apps Script project properties.

If a token is exposed, replace `ENZO_API_TOKEN` in Apps Script Project Settings and in the local environment immediately. Existing deployments do not need a new URL after token rotation.

## Endpoint access model

The simple deployment model uses an Apps Script web app accessible to **Anyone** so a local CLI can call it without Google OAuth. Every action requires a long random shared token. Someone who obtains both the endpoint URL and token can append tracker events, update the latest feeding, and read tracker status.

For a higher-security deployment, restrict the web app to authenticated Google users and add OAuth to the client instead of using the shared-token mode.

## Reporting vulnerabilities

Do not include real tracker data, tokens, deployment URLs, spreadsheet IDs, or personal account information in a public issue. Use a private maintainer contact when the repository defines one.
