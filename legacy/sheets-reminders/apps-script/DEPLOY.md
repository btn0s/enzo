# Deploy the Apps Script endpoint

The endpoint writes private baby-tracker data. Deploy it only after choosing its access model.

## Recommended simple setup

1. Open the tracker spreadsheet using the Google account that should own the automation.
2. Choose **Extensions → Apps Script** and replace `Code.gs` with this folder's `Code.gs`.
3. In the function selector, choose `configureBoundSpreadsheet`, click **Run**, and approve the requested spreadsheet access. This stores the bound spreadsheet ID as `ENZO_SHEET_ID` without putting it in source code.
4. In **Project Settings → Script properties**, add:

   - `ENZO_API_TOKEN`: a long random value, for example `openssl rand -hex 32`
   - `ENZO_TRACKER_SHEET`: optional; defaults to `Tracker`
   - `ENZO_FEED_INTERVAL_MINUTES`: optional; defaults to `180`

5. Choose **Deploy → New deployment → Web app**.
6. Execute as **Me**. To allow the local CLI to call it without Google OAuth, access must be **Anyone**; the random token is the authorization layer.
7. Copy `.env.example` to `.env`, add the `/exec` URL and the same token, then run `bin/enzo doctor`.

Using **Anyone** creates a public network endpoint. The token is required for all actions and is sent only in the HTTPS POST body. The ignored local `.env` file is written with user-only permissions when created by `bin/enzo configure`. A private OAuth deployment is possible but needs a larger Google OAuth client setup.
