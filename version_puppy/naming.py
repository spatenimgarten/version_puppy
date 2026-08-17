import os
import re

VERSION_PATTERN = re.compile(r"^(.*_V)(\d+)$")


class NamingError(Exception):
    pass


def parse_version_name(dir_name):
    match = VERSION_PATTERN.match(dir_name)
    if not match:
        raise NamingError(
            f"Ordnername '{dir_name}' passt nicht auf das Muster '..._V<Nummer>' "
            f"(z.B. '123456_TIA19_V001')."
        )
    prefix, digits = match.groups()
    return prefix, int(digits), len(digits)


def next_version_dir_name(dir_name):
    prefix, number, width = parse_version_name(dir_name)
    return f"{prefix}{str(number + 1).zfill(width)}"


def split_project_dir(source_dir):
    """Gibt (prefix_ohne_'_V', basisverzeichnis) fuer ein bestehendes Projektverzeichnis zurueck."""
    source_dir = os.path.abspath(source_dir)
    current_name = os.path.basename(source_dir.rstrip(os.sep))
    prefix_with_v, _number, _width = parse_version_name(current_name)
    prefix = prefix_with_v[:-2]  # "..._V" -> "..."
    basis = os.path.dirname(source_dir)
    return prefix, basis
