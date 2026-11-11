from django.http import JsonResponse
from django.shortcuts import render
from django.views.decorators.http import require_http_methods

from .services import get_dashboard_data


def get_assistant_reply(message):
    text = message.casefold()

    if any(word in text for word in ("hello", "hi", "hey", "good morning")):
        return "Hello. I can guide you through LaptopCare's inventory dashboard and automation setup. I'm in demo mode, so I can't see live stock or order records yet."
    if any(word in text for word in ("stock", "inventory", "quantity", "product")):
        return "Live inventory lookup isn't connected yet. The n8n workflow in ai_inventory_management_workflow.json can check Supabase stock after it's imported, configured with server-side credentials, and activated."
    if any(word in text for word in ("order", "shipment", "delivery")):
        return "I don't have access to live order or shipment records yet. Connect the dashboard to your database before relying on order-specific answers."
    if any(word in text for word in ("return", "refund", "warranty", "repair")):
        return "I don't have your service, return, or warranty policies configured, so I don't want to guess. Add an approved policy knowledge base to provide accurate answers here."
    if any(word in text for word in ("automation", "n8n", "workflow", "supabase")):
        return "The included n8n workflow checks a requested quantity against a Supabase product record and recommends a reorder quantity when stock is short. Configure its Supabase credentials in n8n; keep the service-role key server-side."
    if any(word in text for word in ("help", "what can", "do")):
        return "I can explain the included inventory workflow and help identify what needs connecting. Live database lookups, order access, and generative AI aren't configured in this demo."
    return "I can help with inventory workflow setup and dashboard questions. This demo doesn't have a connected AI model or live business data, so I can't answer account-specific questions yet."


def index(request):
    return render(request, "dashboard.html", get_dashboard_data())


@require_http_methods(["GET", "POST"])
def chat(request):
    if request.method == "POST":
        message = request.POST.get("message", "").strip()
        if not message:
            return JsonResponse({"error": "Type a message first."}, status=400)
        if len(message) > 1000:
            return JsonResponse({"error": "Messages must be 1,000 characters or fewer."}, status=400)
        return JsonResponse({"reply": get_assistant_reply(message)})

    return render(request, "chat.html")