import json
import os


def _settings_path():
    appdata = os.environ.get("APPDATA")
    if appdata:
        base = os.path.join(appdata, "version_puppy")
    else:
        base = os.path.join(os.path.expanduser("~"), ".version_puppy")
    return os.path.join(base, "setup_defaults.json")


def load_setup_defaults():
    path = _settings_path()
    if not os.path.isfile(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return {}


def save_setup_defaults(**values):
    path = _settings_path()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(values, f, indent=2, ensure_ascii=False)
