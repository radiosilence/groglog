#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["google-auth[requests]==2.58.1", "requests==2.34.2"]
# ///
"""Google Play Console without the website.

    scripts/play.py status                         what each track holds
    scripts/play.py upload AAB TRACK [--draft]     upload a bundle and release it on internal, alpha, beta or production
    scripts/play.py listing                        push android/store/listing.toml and its graphics to the listing

`upload` takes the release notes from CHANGELOG.md: the Unreleased section, or the newest version when there is none.
`--draft` leaves the release as a draft to roll out by hand, which is also what happens until the app has been published
to a track once, since Play refuses anything else before then. Every command is one Play edit, committed only when all of it succeeded.

Authenticates with a service account: the contents of its JSON key in PLAY_SERVICE_ACCOUNT_JSON, or a path to it in
PLAY_SERVICE_ACCOUNT_FILE. The account needs access to the app in Play Console; see docs/play-store.md.
"""

import json
import os
import pathlib
import re
import sys
import tomllib

import google.auth.transport.requests
import requests
from google.oauth2 import service_account

ROOT = pathlib.Path(__file__).resolve().parent.parent
STORE = ROOT / "android/store"
PACKAGE = "cc.blit.groglog"
API = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}"
UPLOAD = f"https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/{PACKAGE}"
TRACKS = ("internal", "alpha", "beta", "production")
LIMITS = {"title": 30, "short_description": 80, "full_description": 4000}


def credentials():
    if os.environ.get("PLAY_SERVICE_ACCOUNT_JSON"):
        info = json.loads(os.environ["PLAY_SERVICE_ACCOUNT_JSON"])
    elif os.environ.get("PLAY_SERVICE_ACCOUNT_FILE"):
        info = json.loads(pathlib.Path(os.environ["PLAY_SERVICE_ACCOUNT_FILE"]).read_text())
    else:
        sys.exit("Set PLAY_SERVICE_ACCOUNT_JSON to the service account's key, or PLAY_SERVICE_ACCOUNT_FILE to its path.")
    creds = service_account.Credentials.from_service_account_info(info, scopes=["https://www.googleapis.com/auth/androidpublisher"])
    creds.refresh(google.auth.transport.requests.Request())
    return creds


class Edit:
    """A Play edit: changes are staged in it and land together on commit, or not at all."""

    def __init__(self):
        self.token = credentials().token
        self.id = self.request("POST", f"{API}/edits")["id"]

    def request(self, method, url, body=None, content_type=None, failed=None, **kwargs):
        headers = {"Authorization": f"Bearer {self.token}"}
        if content_type:
            headers["Content-Type"] = content_type
        r = requests.request(method, url, headers=headers, json=body, timeout=600, **kwargs)
        if r.status_code >= 400:
            if failed:
                return failed(r)
            sys.exit(f"{method} {url}: {r.status_code}\n{r.text}")
        return r.json() if r.text else {}

    def call(self, method, path, body=None, base=API, **kwargs):
        return self.request(method, f"{base}/edits/{self.id}{path}", body, **kwargs)

    def upload(self, path, file, content_type):
        return self.call("POST", path, base=UPLOAD, params={"uploadType": "media"}, data=file.read_bytes(), content_type=content_type)

    def commit(self):
        self.call("POST", ":commit")

    def abandon(self):
        self.call("DELETE", "")


def changelog_notes():
    """CHANGELOG.md's Unreleased section, or the newest version's, as plain text within Play's 500 characters."""
    text = (ROOT / "CHANGELOG.md").read_text()
    sections = re.findall(r"^## ([^\n]+)\n(.*?)(?=^## |\Z)", text, re.S | re.M)
    if not sections:
        return ""
    body = dict(sections).get("Unreleased") or sections[0][1]
    # CI and tooling notes are of no interest to testers; section headings and markup are dropped.
    body = re.sub(r"^### Internal\n.*?(?=^### |\Z)", "", body, flags=re.S | re.M)
    body = re.sub(r"^### .+\n", "", body, flags=re.M)
    body = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", body)
    body = re.sub(r"\*\*|`", "", body)
    body = re.sub(r"\n{2,}", "\n", body).strip()
    if len(body) > 500:
        body = body[:body.rfind("\n", 0, 470)] + "\n…and more in CHANGELOG.md"
    return body


def listing_file():
    listing = tomllib.loads((STORE / "listing.toml").read_text())
    for field, limit in LIMITS.items():
        value = listing["listing"][field].strip()
        if len(value) > limit:
            sys.exit(f"listing.toml: {field} is {len(value)} characters; Play allows {limit}.")
    return listing


def unwrap(text):
    """Paragraphs are separated by blank lines in the file and by one blank line on Play."""
    return "\n\n".join(p.strip() for p in text.strip().split("\n\n"))


# Commands


def status():
    edit = Edit()
    for track in edit.call("GET", "/tracks").get("tracks", []):
        for release in track.get("releases", []):
            codes = ", ".join(release.get("versionCodes", [])) or "no bundle"
            print(f"{track['track']}: {release.get('name', '')} ({codes}) {release['status']}")
    edit.abandon()


def upload(aab, track, *flags):
    if track not in TRACKS:
        sys.exit(f"Track must be one of {', '.join(TRACKS)}.")
    language = listing_file()["language"]
    edit = Edit()
    version_code = edit.upload("/bundles", pathlib.Path(aab), "application/octet-stream")["versionCode"]
    release = {"versionCodes": [str(version_code)], "status": "draft" if "--draft" in flags else "completed"}
    if notes := changelog_notes():
        release["releaseNotes"] = [{"language": language, "text": notes}]
    def draft_app(r):
        # Until the app has been published to a track once, Play takes only drafts; the release is left for Play
        # Console rather than failing the upload.
        if r.status_code == 400 and "draft app" in r.text and release["status"] != "draft":
            release["status"] = "draft"
            return edit.call("PUT", f"/tracks/{track}", {"track": track, "releases": [release]})
        sys.exit(f"PUT /tracks/{track}: {r.status_code}\n{r.text}")

    edit.call("PUT", f"/tracks/{track}", {"track": track, "releases": [release]}, failed=draft_app)
    edit.commit()
    print(f"Version code {version_code} released to {track} ({release['status']})")


def listing():
    listing = listing_file()
    language = listing["language"]
    edit = Edit()
    details = listing["details"]
    edit.call("PUT", "/details", {"defaultLanguage": language, "contactEmail": details["contact_email"], "contactWebsite": details["contact_website"]})
    edit.call("PUT", f"/listings/{language}", {
        "language": language,
        "title": listing["listing"]["title"].strip(),
        "shortDescription": listing["listing"]["short_description"].strip(),
        "fullDescription": unwrap(listing["listing"]["full_description"]),
    })

    graphics = listing["graphics"]
    images = {"icon": [STORE / graphics["icon"]], "featureGraphic": [STORE / graphics["feature_graphic"]]}
    shots = sorted((STORE / graphics["phone_screenshots"]).glob("*.png"))
    if shots:
        images["phoneScreenshots"] = shots
    for kind, files in images.items():
        # Uploading adds to a set, so the old images go first.
        edit.call("DELETE", f"/listings/{language}/{kind}")
        for f in files:
            edit.upload(f"/listings/{language}/{kind}", f, "image/png")
            print(f"Uploaded {kind} {f.name}")
    edit.commit()
    print("Play listing matches android/store/listing.toml")


if __name__ == "__main__":
    commands = {"status": status, "upload": upload, "listing": listing}
    if len(sys.argv) < 2 or sys.argv[1] not in commands:
        sys.exit(__doc__)
    commands[sys.argv[1]](*sys.argv[2:])
