import json
import os

DEFAULT_CONFIG_PATH = "config.json"


class ConfigError(Exception):
    pass


def load_config(path=DEFAULT_CONFIG_PATH):
    if not os.path.isfile(path):
        raise ConfigError(
            f"Konfigurationsdatei '{path}' nicht gefunden. "
            f"Kopiere config.example.json zu config.json und trage deine Projekte ein."
        )
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    projects = data.get("projects", {})
    if not projects:
        raise ConfigError(f"Keine Projekte in '{path}' definiert.")
    return projects


def get_project(projects, name):
    if name not in projects:
        available = ", ".join(sorted(projects)) or "(keine)"
        raise ConfigError(f"Projekt '{name}' nicht in Konfiguration gefunden. Verfügbar: {available}")
    return projects[name]
