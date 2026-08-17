import os
import tkinter as tk
from tkinter import messagebox, simpledialog

from .core import create_version
from .naming import NamingError


def run_gui(source_dir, data_dir, user):
    root = tk.Tk()
    root.title("version_puppy")
    root.resizable(False, False)

    project_name = os.path.basename(os.path.normpath(source_dir))

    tk.Label(
        root, text=f"Projekt: {project_name}", font=("Segoe UI", 10, "bold"), padx=20, pady=10
    ).pack()

    def handle(typ):
        comment = simpledialog.askstring("Kommentar", "Kommentar (optional):", parent=root) or ""
        try:
            result = create_version(source_dir, data_dir, user, typ, comment)
        except (NamingError, NotADirectoryError, OSError) as exc:
            messagebox.showerror("Fehler", str(exc), parent=root)
            return

        msg = f"Archiv erstellt:\n{os.path.basename(result.zip_path)}"
        if result.renamed_to:
            msg += f"\n\nProjektverzeichnis umbenannt nach:\n{result.renamed_to}"
        if result.rename_error:
            msg += (
                f"\n\nWARNUNG: Umbenennen fehlgeschlagen ({result.rename_error}). "
                f"Bitte manuell umbenennen."
            )
        messagebox.showinfo("Fertig", msg, parent=root)
        root.destroy()

    button_frame = tk.Frame(root, padx=20, pady=10)
    button_frame.pack()

    tk.Button(
        button_frame, text="Version erstellen", width=28, height=2, command=lambda: handle("version")
    ).pack(pady=4)
    tk.Button(
        button_frame,
        text="Zwischenversion / Backup",
        width=28,
        height=2,
        command=lambda: handle("zwischenversion"),
    ).pack(pady=4)
    tk.Button(button_frame, text="Beenden", width=28, height=2, command=root.destroy).pack(pady=4)

    root.mainloop()
