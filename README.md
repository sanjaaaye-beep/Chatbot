# Chatbot: AI-Powered Inventory Management

Automates stock tracking, shortage detection, and reorder recommendations with Python, Supabase, and n8n.

This repository includes a Django inventory dashboard and assistant, a Supabase/PostgreSQL schema, and an importable n8n inventory-check workflow. The dashboard shows sample data until server-side Supabase credentials are configured.

## Django dashboard

```bash
python -m venv .venv
# Windows PowerShell:
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python manage.py migrate
python manage.py runserver
```

Open http://127.0.0.1:8000/. The assistant is available at `/chat/`.

To enable live dashboard data, copy `.env.example` to `.env` and set `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`. Keep the service-role key server-side; never expose it in browser code or commit `.env`.

## Database setup

Run `database.sql` in the Supabase SQL Editor to create the inventory schema and dashboard views. Run `supabase_setup.sql` to add the n8n analysis-results table. Row-level security is enabled; create appropriate staff policies before allowing client access.

## n8n AI Inventory Management Workflow

## Included files
- `ai_inventory_management_workflow.json` — importable n8n workflow.
- `supabase_setup.sql` — creates the table used to save analysis results.

## Workflow steps
1. Webhook receives a POST request.
2. Code node validates `product_id` and `requested_quantity`.
3. HTTP Request retrieves product stock from Supabase `products`.
4. Code node compares requested quantity with current stock and calculates any shortage.
5. IF node checks whether the product exists.
6. If found, the result is inserted into `ai_inventory_analysis_results`.
7. Respond to Webhook returns the analysis as JSON.
8. If the product is not found, the workflow returns HTTP 404.

## Supabase preparation
1. Ensure your existing `public.products` table has:
   - `product_id` (UUID primary key)
   - `product_name`
   - `brand`
   - `model`
   - `stock_quantity` (integer)
   - `price`
   - `primary_supplier_id` (optional)
2. Run `supabase_setup.sql` in Supabase SQL Editor.
3. In your n8n host, set environment variables:
   - `SUPABASE_URL` = `https://YOUR_PROJECT_REF.supabase.co`
   - `SUPABASE_SERVICE_ROLE_KEY` = your Supabase service-role key
4. Import the JSON in n8n: **Workflows → Import from File**.
5. Confirm the expressions in the two HTTP Request nodes can access those environment variables. Some hosted n8n plans restrict `$env`; if so, replace the header values with an n8n Header Auth credential or another secure credential method.
6. Save and activate the workflow after testing.

Never put the Supabase service-role key in browser code or send it to customers. Keep it only in n8n's secure server-side environment/credentials.

## Test request

POST to the n8n webhook test URL with JSON:

```json
{
  "product_id": "YOUR_EXISTING_PRODUCT_UUID",
  "requested_quantity": 12,
  "reorder_buffer": 5,
  "request_id": "REQ-1001"
}
```

Use the **Test URL** while the workflow is in test mode. Activate the workflow and use the **Production URL** for live calls.

## Example response when stock is short

```json
{
  "found": true,
  "product_name": "Dell Inspiron 15",
  "current_stock": 5,
  "requested_quantity": 12,
  "shortage_quantity": 7,
  "stock_sufficient": false,
  "status": "stock_shortage",
  "reorder_recommendation": {
    "recommended_quantity": 12,
    "reason": "Requested 12, but only 5 are in stock. Shortage: 7.",
    "supplier_id": "..."
  }
}
```

## Notes / production hardening
- This workflow recommends reorder quantity; it does not automatically create a supplier purchase order or change product stock.
- To avoid overselling under concurrent orders, perform stock reservation/decrement inside a PostgreSQL transaction or Supabase RPC function, not only in this workflow.
- Add authentication to the webhook (for example, an n8n Header Auth credential), request rate limiting, and input validation before production.
- Configure an Error Trigger workflow for API failures and alerting.
- Confirm the exact `products` column names match your Supabase schema before activation.
