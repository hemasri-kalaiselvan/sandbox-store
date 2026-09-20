# STEPS — two new features

Two independent add-ons. Do them in any order.

---

## FEATURE 1 — Region privilege (managers see only their region)

**What it does:** an *admin* sees all data; a *manager* logs in and the dashboard
shows only their region's rows. Enforced in the database (Row Level Security), so
it's real security, not just a hidden UI.

**File:** `sql/07_privilege.sql`

1. **Turn on login** in Supabase: left menu **Authentication → Providers → Email →**
   enable. (Turn OFF "Confirm email" while testing so logins work instantly.)
2. **Run the SQL:** open **SQL Editor**, paste all of `sql/07_privilege.sql`, **Run**.
   (Creates the `app_users` table + the region-scoped read rules.)
3. **Create the users:** **Authentication → Users → Add user** (email + password) for
   yourself (admin) and each manager. After adding, click each user and **copy their
   User UID**.
4. **Map users to regions:** in **SQL Editor** run (use the UIDs from step 3):
   ```sql
   insert into app_users(user_id, email, role, region) values
     ('YOUR-UID',    'you@example.com',   'admin',   null),
     ('MANAGER-UID', 'priya@example.com', 'manager', 'Tamil Nadu');
   ```
   `region` must match the state name exactly as it appears in your data.
5. **Add login to the dashboard:** in `index.html`, just before `</head>`, add:
   ```html
   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
   ```
   and near the top of your main `<script>` add (uses your existing URL + anon key):
   ```js
   const _auth = supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
   const email = prompt("Login email:"); const pass = prompt("Password:");
   await _auth.auth.signInWithPassword({ email, password: pass });
   ```
   Then make your data `fetch()` calls send the logged-in token instead of the anon key:
   `Authorization: "Bearer " + (await _auth.auth.getSession()).data.session.access_token`.
   Now the database returns only that user's region automatically.

**Test:** log in as the manager → every state chart/table shows one region.
Log in as admin → everything. (Verified locally: admin = all 15 states, TN manager = only Tamil Nadu.)

**Honest limitation:** tables without a state column (category/product/cohort summaries)
stay visible to all logged-in users. For strict per-region everywhere, a manager view
should aggregate from the now-region-scoped raw `orders` table, or add region-grained
summary tables. Admin is always fully correct.

---

## FEATURE 2 — Pluggable data source (sell the design as a template)

**What it does:** the buyer connects **their own** data (Google Sheet, CSV/Excel, or
Supabase) by editing **one file**. No coding. The dashboard aggregates in the browser.

**Folder:** `template/` — ship these three files to a buyer:
`dashboard-template.html`, `config.js`, `sample-data.csv`.

**The data contract (what their data must contain):** one row per order, these columns
(names can differ — they map them in config). See `sample-data.csv`.

| field | meaning | required |
|---|---|---|
| order_date | date (YYYY-MM-DD) | yes |
| amount | order value (number) | yes |
| category | product category | yes |
| state | region | yes |
| payment_method | text | optional |
| status | text; `cancelled`/`returned`/`refunded` excluded from revenue | optional |
| customer_id | any id (counts unique customers) | optional |

**Buyer steps:**
1. Put all three files in one folder.
2. Open `config.js`, set **SOURCE** to one of:
   - **`"googlesheets"`** → in their sheet: **File → Share → Publish to web → (sheet) →
     Comma-separated values (.csv)** → paste that link into `SHEETS_CSV_URL`.
   - **`"csv"`** → nothing else; the page shows an **Upload CSV** button (Excel: Save As → CSV).
   - **`"supabase"`** → fill `SUPABASE_URL`, `SUPABASE_KEY` (anon), `SUPABASE_TABLE`.
3. In `config.js` → **COLUMNS**, set the right-hand names to *their* column names.
4. Open `dashboard-template.html` (double-click, or host on GitHub Pages). It loads,
   aggregates, and draws KPIs + trend + category/region/payment/status charts.

**Test:** set SOURCE `"csv"`, open the page, upload `sample-data.csv` → revenue ₹5,500
(the ₹500 Cancelled row is excluded), 4 orders, 4 customers. (Verified.)

---

### Sync note
Both features are in the repo (`sql/07_privilege.sql`, `template/`). Feature 1 changes
the live dashboard's login; Feature 2 is a separate standalone product you can zip and sell.
