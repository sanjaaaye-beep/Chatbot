"""
LaptopCare Django project launcher.

This file is a convenience entry point. It delegates to Django's manage.py.
It does not start a separate Flask/FastAPI application.
Usage:
    python app.py runserver
    python app.py migrate
    python app.py createsuperuser
"""
import os
import sys
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
MANAGE_PY = BASE_DIR / "manage.py"

def main():
    if not MANAGE_PY.exists():
        raise SystemExit(
            "manage.py was not found. Place app.py in the Django project root, "
            "beside manage.py."
        )
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
    from django.core.management import execute_from_command_line
    args = [str(MANAGE_PY), *(sys.argv[1:] or ["runserver"])]
    execute_from_command_line(args)

if __name__ == "__main__":
    main()
