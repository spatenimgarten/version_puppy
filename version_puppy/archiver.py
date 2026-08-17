import os
import zipfile


def zip_directory(source_dir, dest_zip_path):
    source_dir = os.path.abspath(source_dir)
    if not os.path.isdir(source_dir):
        raise NotADirectoryError(f"Quellverzeichnis nicht gefunden: {source_dir}")

    base_name = os.path.basename(source_dir.rstrip(os.sep))
    os.makedirs(os.path.dirname(dest_zip_path), exist_ok=True)

    with zipfile.ZipFile(dest_zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, _dirs, files in os.walk(source_dir):
            for file in files:
                full_path = os.path.join(root, file)
                rel_path = os.path.join(base_name, os.path.relpath(full_path, source_dir))
                zf.write(full_path, rel_path)

    return dest_zip_path
