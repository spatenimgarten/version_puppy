import os
import tkinter as tk
from tkinter import messagebox, simpledialog

from .core import create_version
from .naming import NamingError
from .server_sync import server_reachable
from .sync import run_sync


def run_gui(source_dir, data_dir, user, server_dir):
    root = tk.Tk()
    root.title("version_puppy")
    root.resizable(False, False)

    project_name = os.path.basename(os.path.normpath(source_dir))

    tk.Label(
        root, text=f"Projekt: {project_name}", font=("Segoe UI", 10, "bold"), padx=20, pady=10
    ).pack()

    status_frame = tk.Frame(root, padx=20, pady=4)
    status_frame.pack(fill="x")
    status_canvas = tk.Canvas(status_frame, width=14, height=14, highlightthickness=0)
    status_dot = status_canvas.create_oval(2, 2, 12, 12, fill="grey")
    status_canvas.pack(side="left")
    status_label = tk.Label(status_frame, text="Server wird geprüft ...")
    status_label.pack(side="left", padx=(6, 0))

    def set_status(reachable, extra=""):
        status_canvas.itemconfig(status_dot, fill="#2ecc71" if reachable else "#e74c3c")
        text = "Server erreichbar" if reachable else "Server nicht erreichbar"
        if extra:
            text += f" – {extra}"
        status_label.config(text=text)

    def sync_now():
        if not server_reachable(server_dir):
            set_status(False)
            return False

        summary = run_sync(data_dir, server_dir)
        parts = []
        if summary.synced:
            parts.append(f"{len(summary.synced)} synchronisiert")
        if summary.conflicts:
            parts.append(f"{len(summary.conflicts)} Konflikt(e)")
        if summary.pruned:
            parts.append(f"{len(summary.pruned)} aufgeräumt")
        set_status(True, ", ".join(parts))

        if summary.conflicts:
            lines = [f"{new}\n   (Konflikt mit vorhandenem {old})" for new, old in summary.conflicts]
            messagebox.showwarning(
                "Konflikt",
                "Diese Dateien kollidieren mit bereits vorhandenen, anderen Dateien auf dem "
                "Server und wurden zusätzlich unter eigenem Namen abgelegt (nichts wurde "
                "überschrieben). Bitte manuell klären, welche Version gültig ist:\n\n"
                + "\n\n".join(lines),
                parent=root,
            )
        return True

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
        sync_now()
        root.destroy()

    button_frame = tk.Frame(root, padx=20, pady=10)
    button_frame.pack()

    # takefocus=0: Knoepfe loesen nur per Mausklick aus, nicht ueber
    # Tastaturfokus. Enter ist bewusst separat auf "Beenden" gelegt (siehe
    # unten) - das ist der sichere Default, falls Enter aus Versehen
    # gedrueckt wird, soll im Normalfall nichts passieren.
    tk.Button(
        button_frame, text="Version erstellen", width=28, height=2, takefocus=0,
        command=lambda: handle("version"),
    ).pack(pady=4)
    tk.Button(
        button_frame, text="Zwischenversion / Backup", width=28, height=2, takefocus=0,
        command=lambda: handle("zwischenversion"),
    ).pack(pady=4)
    tk.Button(
        button_frame, text="Beenden", width=28, height=2, takefocus=0, command=root.destroy
    ).pack(pady=4)

    root.bind("<Return>", lambda e: root.destroy())

    root.after(100, sync_now)
    root.mainloop()
