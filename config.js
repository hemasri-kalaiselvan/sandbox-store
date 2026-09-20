// ============================================================
// config.js — the ONLY file a buyer edits to connect their data.
// Pick a SOURCE, fill in its settings, and map your column names.
// ============================================================
window.DASH_CONFIG = {

  // "googlesheets" | "csv" | "supabase"
  SOURCE: "googlesheets",

  // --- Google Sheets: in your sheet, File > Share > Publish to web >
  //     (choose the sheet) > Comma-separated values (.csv) > paste the link here.
  SHEETS_CSV_URL: "PASTE_YOUR_PUBLISHED_CSV_LINK_HERE",

  // --- CSV/Excel: nothing to set here; the page shows an Upload button.

  // --- Supabase (or any table exposed via its REST API):
  SUPABASE_URL: "https://YOURPROJECT.supabase.co",
  SUPABASE_KEY: "YOUR_ANON_PUBLIC_KEY",
  SUPABASE_TABLE: "orders",

  // Map YOUR column names -> the fields the dashboard needs.
  // (Left = required field, Right = the column name in YOUR data.)
  COLUMNS: {
    order_date:     "order_date",     // a date, e.g. 2025-03-14
    amount:         "total",          // order value (number)
    category:       "category",       // product category (text)
    state:          "state",          // region/state (text)
    payment_method: "payment_method", // text (optional)
    status:         "status",         // text; "cancelled"/"returned" are excluded from revenue (optional)
    customer_id:    "customer_id"     // any id to count unique customers (optional)
  }
};
