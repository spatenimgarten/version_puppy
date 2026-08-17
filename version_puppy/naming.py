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
