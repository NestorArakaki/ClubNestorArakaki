"""Dos ZIP de código versionado para Blackboard, sin entorno local ni secretos."""

import subprocess
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

root = Path(__file__).resolve().parents[1]
if subprocess.check_output(["git", "status", "--porcelain"], cwd=root).strip():
    raise SystemExit(
        "Primero revisar y guardar los cambios en commits; no empaquetar una entrega ambigua."
    )
files = (
    subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode().split("\0")
)
commit = (
    subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root).decode().strip()
)
output = root / "dist"
output.mkdir(exist_ok=True)


def safe(name):
    path = Path(name)
    lower = name.lower()
    return (
        name
        and path.name
        not in {
            ".env",
            "google-services.json",
            "GoogleService-Info.plist",
            "key.properties",
            "firebase.json",
            "credentials.json",
        }
        and not (path.name.startswith(".env.") and path.name != ".env.example")
        and not lower.endswith((".jks", ".keystore"))
        and not any(
            part in lower
            for part in ("service-account", "service_account", "firebase-adminsdk")
        )
        and name != "config/firebase.json"
    )


for project in ("flutter", "backend"):
    target = output / f"ClubNestorArakaki_{project}.zip"
    with ZipFile(target, "w", ZIP_DEFLATED) as archive:
        for name in files:
            if not safe(name):
                continue
            shared = name.startswith("docs/") or name == "README.md"
            include = (
                name.startswith("backend/")
                if project == "backend"
                else not name.startswith(("backend/", ".github/", "tools/"))
            )
            if include or shared:
                archive.write(root / name, name)
        archive.writestr(
            "ENTREGA_COMMIT.txt",
            f"ClubNestorArakaki - {project}\nCommit: {commit}\nSin credenciales: configurar según docs/INSTALACION_WINDOWS.md\n",
        )
    print(target)
