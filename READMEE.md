# LaptopCare – Enterprise Automation Starter Files

This bundle contains:
- `database.sql` – Supabase/PostgreSQL schema for suppliers, products, customers, orders, order items, supplier-product mapping, shipments and AI agent logs.
- `templates/dashboard/dashboard.html` – responsive Bootstrap dashboard template for a Django project.
- `app.py` – convenience launcher for an existing Django project (expects `manage.py` and `config/settings.py`).

## 1. Supabase database setup

1. Create a Supabase project.
2. Open **SQL Editor → New query**.
3. Copy and run `database.sql`.
4. Review access requirements and configure Row Level Security (RLS) policies before exposing data to a frontend.

The schema uses UUID primary keys, foreign keys, timestamps, check constraints, indexes and an automatic `updated_at` trigger.

## 2. Django setup

Create a Django project if you do not already have one:

```bash
python -m venv .venv
# Windows:
.venv\Scripts\activate
# macOS/Linux:
source .venv/bin/activate

pip install django
django-admin startproject config .
python manage.py startapp dashboard
```

Place `app.py` beside `manage.py`. Place `dashboard.html` at:
`templates/dashboard/dashboard.html`

In `config/settings.py`, configure the template directory and install the dashboard app:

```python
INSTALLED_APPS = [
    # existing Django apps...
    "dashboard",
]

TEMPLATES[0]["DIRS"] = [BASE_DIR / "templates"]
```

Create a dashboard view in `dashboard/views.py`:

```python
from django.shortcuts import render

def index(request):
    return render(request, "dashboard/dashboard.html", {
        "total_customers": 0,
        "total_products": 0,
        "total_orders": 0,
        "total_ai_logs": 0,
        "recent_orders": [],
        "recent_ai_logs": [],
    })
```

Create `dashboard/urls.py`:

```python
from django.urls import path
from . import views

urlpatterns = [
    path("", views.index, name="dashboard"),
]
```

Connect it in `config/urls.py`:

```python
from django.contrib import admin
from django.urls import path, include

urlpatterns = [
    path("admin/", admin.site.urls),
    path("", include("dashboard.urls")),
]
```

The template extends `base.html`. Create a base template that loads Bootstrap 5 CSS and defines a `{% block content %}`.

Run the project:

```bash
python app.py migrate
python app.py createsuperuser
python app.py runserver
```

Open http://127.0.0.1:8000/

## 3. Supabase connection from Python

Install the client:

```bash
pip install supabase python-dotenv
```

Store credentials in `.env` (never commit this file):

```env
SUPABASE_URL=https://YOUR_PROJECT.supabase.co
SUPABASE_SERVICE_ROLE_KEY=YOUR_SERVER_ONLY_SERVICE_ROLE_KEY
```

Example server-side connection:

```python
import os
from dotenv import load_dotenv
from supabase import create_client

load_dotenv()
supabase = create_client(
    os.environ["SUPABASE_URL"],
    os.environ["SUPABASE_SERVICE_ROLE_KEY"]
)
```

**Security:** The service-role key bypasses RLS. Use it only on a trusted server, never in browser JavaScript or a public repository. For customer-facing access, use Supabase Auth and restrictive RLS policies.

## 4. Important production notes

- The dashboard template is a UI starter, not a complete finished admin system.
- Connect the view to your Django models or Supabase queries to display live data.
- Add role-based permissions for admins, staff, technicians and customers.
- Add transactional stock deduction and order-total calculation logic before processing real orders.
- AI logs should not contain passwords, payment credentials, API keys or unnecessary personal data.
- For true 24/7 chatbot availability, deploy Django and the AI service to always-on hosting with process monitoring, backups and alerting.
- The SQL schema does not enable permissive RLS policies. Design policies around your actual user roles before production.
