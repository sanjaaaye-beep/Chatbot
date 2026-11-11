import logging
import os
from datetime import date, datetime, timedelta

from django.utils import timezone
from django.utils.dateparse import parse_datetime
from supabase import create_client

logger = logging.getLogger(__name__)


def get_demo_dashboard_data():
    return {
        "data_state": "demo",
        "data_notice": "Sample figures are shown below. Configure Supabase to load live inventory data.",
        "inventory_value": "$248,620",
        "active_products": "1,284",
        "products_to_reorder": "18",
        "open_orders": "42",
        "inbound_total": 438,
        "outbound_total": 342,
        "movement": [
            {"day": "Mon", "received": 70, "dispatched": 45},
            {"day": "Tue", "received": 46, "dispatched": 62},
            {"day": "Wed", "received": 82, "dispatched": 54},
            {"day": "Thu", "received": 57, "dispatched": 37},
            {"day": "Fri", "received": 91, "dispatched": 66},
            {"day": "Sat", "received": 34, "dispatched": 49},
            {"day": "Sun", "received": 58, "dispatched": 29},
        ],
        "products": [
            {"sku": "LC-LT-042", "name": "Dell XPS 13 Plus", "category": "Laptops", "stock": 8, "minimum": 12, "status": "Reorder"},
            {"sku": "LC-AC-118", "name": "Logitech MX Master 3S", "category": "Accessories", "stock": 6, "minimum": 10, "status": "Reorder"},
            {"sku": "LC-LT-031", "name": "Lenovo ThinkPad T14", "category": "Laptops", "stock": 19, "minimum": 12, "status": "Healthy"},
            {"sku": "LC-ST-206", "name": "Samsung T7 Shield 1TB", "category": "Storage", "stock": 31, "minimum": 10, "status": "Healthy"},
            {"sku": "LC-MN-077", "name": "LG UltraFine 27UQ850", "category": "Monitors", "stock": 4, "minimum": 8, "status": "Reorder"},
        ],
        "reorder_alerts": [
            {"name": "Dell XPS 13 Plus", "sku": "LC-LT-042", "stock": 8, "minimum": 12},
            {"name": "Logitech MX Master 3S", "sku": "LC-AC-118", "stock": 6, "minimum": 10},
            {"name": "LG UltraFine 27UQ850", "sku": "LC-MN-077", "stock": 4, "minimum": 8},
        ],
        "activity": [
            {"kind": "received", "title": "Purchase order received", "detail": "PO-1048 · Lenovo ThinkPad T14", "time": "12 min ago"},
            {"kind": "order", "title": "Order packed for dispatch", "detail": "ORD-2831 · 3 items", "time": "48 min ago"},
            {"kind": "alert", "title": "Reorder point reached", "detail": "Dell XPS 13 Plus · 8 units left", "time": "1 hr ago"},
        ],
    }


def _time_ago(value):
    timestamp = parse_datetime(value) if isinstance(value, str) else value
    if timestamp is None:
        return "Recently"
    if timezone.is_naive(timestamp):
        timestamp = timezone.make_aware(timestamp, timezone=timezone.utc)
    elapsed = max(0, int((timezone.now() - timestamp).total_seconds()))
    if elapsed < 3600:
        return f"{max(1, elapsed // 60)} min ago"
    if elapsed < 86400:
        return f"{elapsed // 3600} hr ago"
    return f"{elapsed // 86400} days ago"


def _build_live_dashboard(client):
    summary_rows = client.table("inventory_dashboard_summary").select("*").limit(1).execute().data
    if not summary_rows:
        raise ValueError("The inventory dashboard summary view returned no rows")
    summary = summary_rows[0]

    products = client.table("products").select(
        "sku,product_name,category,stock_quantity,reorder_point"
    ).eq("is_active", True).order("product_name").limit(200).execute().data or []

    reorder_alerts = client.table("inventory_reorder_alerts").select(
        "product_id,sku,product_name,stock_quantity,reorder_point,suggested_shortage"
    ).order("suggested_shortage", desc=True).limit(3).execute().data or []

    week_start = date.today() - timedelta(days=6)
    movement_rows = client.table("inventory_movement_daily").select(
        "movement_date,movement_type,net_units"
    ).gte("movement_date", week_start.isoformat()).order("movement_date").execute().data or []

    days = {}
    for offset in range(7):
        movement_date = week_start + timedelta(days=offset)
        days[movement_date.isoformat()] = {
            "day": movement_date.strftime("%a"), "received": 0, "dispatched": 0
        }
    for row in movement_rows:
        day = days.get(str(row["movement_date"]))
        if day is None:
            continue
        quantity = int(row.get("net_units") or 0)
        if row["movement_type"] in ("opening", "receipt", "return"):
            day["received"] += max(0, quantity)
        elif row["movement_type"] == "dispatch":
            day["dispatched"] += abs(min(0, quantity))

    inbound_total = sum(day["received"] for day in days.values())
    outbound_total = sum(day["dispatched"] for day in days.values())
    highest_movement = max(
        [day[key] for day in days.values() for key in ("received", "dispatched")],
        default=0,
    )
    movement = [
        {
            **day,
            "received": round(day["received"] / highest_movement * 92) if highest_movement else 0,
            "dispatched": round(day["dispatched"] / highest_movement * 92) if highest_movement else 0,
        }
        for day in days.values()
    ]

    order_count = client.table("orders").select(
        "order_id", count="exact"
    ).in_("order_status", ["pending", "confirmed", "processing"]).execute().count or 0

    activity_rows = client.table("inventory_movements").select(
        "movement_type,quantity_delta,reason,reference_code,created_at,products(product_name)"
    ).order("created_at", desc=True).limit(5).execute().data or []
    activity = []
    for row in activity_rows:
        product = row.get("products") or {}
        if isinstance(product, list):
            product = product[0] if product else {}
        movement_type = row["movement_type"]
        kind = "received" if movement_type in ("opening", "receipt", "return") else (
            "order" if movement_type == "dispatch" else "alert"
        )
        title = {
            "opening": "Opening stock recorded",
            "receipt": "Stock received",
            "return": "Stock returned",
            "dispatch": "Stock dispatched",
            "adjustment": "Stock adjusted",
        }.get(movement_type, "Inventory updated")
        product_name = product.get("product_name") or "Product"
        detail = row.get("reason") or f"{product_name} · {row['quantity_delta']:+} units"
        if row.get("reference_code"):
            detail = f"{row['reference_code']} · {detail}"
        activity.append({
            "kind": kind,
            "title": title,
            "detail": detail,
            "time": _time_ago(row.get("created_at")),
        })

    return {
        "data_state": "live",
        "data_notice": "Supabase is connected. Inventory figures update each time this page loads.",
        "inventory_value": f"${float(summary.get('inventory_cost_value') or 0):,.0f}",
        "active_products": f"{int(summary.get('active_products') or 0):,}",
        "products_to_reorder": f"{int(summary.get('products_to_reorder') or 0):,}",
        "open_orders": f"{int(order_count):,}",
        "inbound_total": inbound_total,
        "outbound_total": outbound_total,
        "movement": movement,
        "products": [
            {
                "sku": row.get("sku") or "—",
                "name": row["product_name"],
                "category": row.get("category") or "Uncategorized",
                "stock": int(row.get("stock_quantity") or 0),
                "minimum": int(row.get("reorder_point") or 0),
                "status": "Reorder" if int(row.get("stock_quantity") or 0) <= int(row.get("reorder_point") or 0) else "Healthy",
            }
            for row in products
        ],
        "reorder_alerts": [
            {
                "name": row["product_name"],
                "sku": row.get("sku") or "—",
                "stock": int(row["stock_quantity"]),
                "minimum": int(row["reorder_point"]),
            }
            for row in reorder_alerts
        ],
        "activity": activity,
    }


def get_dashboard_data():
    demo_data = get_demo_dashboard_data()
    supabase_url = os.getenv("SUPABASE_URL")
    service_key = os.getenv("SUPABASE_SERVICE_ROLE_KEY")
    if not supabase_url or not service_key:
        return demo_data

    try:
        return _build_live_dashboard(create_client(supabase_url, service_key))
    except Exception:
        logger.exception("Unable to load the live Supabase dashboard")
        demo_data["data_state"] = "error"
        demo_data["data_notice"] = "Supabase could not be reached. Showing sample data; check the server configuration and database setup."
        return demo_data