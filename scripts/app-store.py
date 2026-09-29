#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.12"
# dependencies = ["pyjwt[crypto]", "requests"]
# ///
"""App Store Connect without the website.

    scripts/app-store.py status              what the listing, builds and review are doing
    scripts/app-store.py listing             push docs/app-store.md to the listing
    scripts/app-store.py screenshots         retake the screenshots and replace the listing's set
    scripts/app-store.py submit              attach this version's newest build and submit it for review
    scripts/app-store.py withdraw            take the version out of review, to submit a newer build of it

The version is MARKETING_VERSION in project.yml; `listing` and `submit` create it in App Store Connect when it doesn't
exist yet. App Privacy, trader status and agreements have no API and were set once on the website.

Authenticates with ASC_KEY_ID and ASC_ISSUER_ID (set in mise.toml) and the key itself, from ASC_KEY (its contents, as
on CI) or ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8, where Xcode's tools also look for it.
"""

import hashlib
import os
import pathlib
import re
import subprocess
import sys
import tempfile
import time

import jwt
import requests

ROOT = pathlib.Path(__file__).resolve().parent.parent
BUNDLE_ID = "cc.blit.groglog"
API = "https://api.appstoreconnect.apple.com"
# 6.9-inch iPhone: the one size App Store Connect requires, scaled down for the smaller ones.
SCREENSHOT_TYPE = "APP_IPHONE_67"


def key():
    if os.environ.get("ASC_KEY"):
        return os.environ["ASC_KEY"]
    path = pathlib.Path.home() / ".appstoreconnect/private_keys" / f"AuthKey_{os.environ['ASC_KEY_ID']}.p8"
    return path.read_text()


def token():
    now = int(time.time())
    claims = {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"}
    return jwt.encode(claims, key(), algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"]})


def call(method, path, body=None, **kwargs):
    url = path if path.startswith("http") else API + path
    r = requests.request(method, url, headers={"Authorization": f"Bearer {token()}"}, json=body, **kwargs)
    if r.status_code >= 400:
        sys.exit(f"{method} {path}: {r.status_code}\n{r.text}")
    return r.json() if r.text else {}


def get(path, **params):
    return call("GET", path, params=params)


def patch(kind, id, attributes=None, relationships=None):
    data = {"type": kind, "id": id}
    if attributes:
        data["attributes"] = attributes
    if relationships:
        data["relationships"] = relationships
    return call("PATCH", f"/v1/{kind}/{id}", {"data": data})


def create(kind, attributes=None, relationships=None):
    data = {"type": kind, "attributes": attributes or {}, "relationships": relationships or {}}
    return call("POST", f"/v1/{kind}", {"data": data})["data"]


def rel(kind, id):
    return {"data": {"type": kind, "id": id}}


def marketing_version():
    return re.search(r"MARKETING_VERSION: (\S+)", (ROOT / "project.yml").read_text()).group(1)


def app():
    return get("/v1/apps", **{"filter[bundleId]": BUNDLE_ID})["data"][0]


def editable_version(app_id, create_if_missing=False):
    """The App Store version for project.yml's version, if it can still be edited."""
    wanted = marketing_version()
    versions = get(f"/v1/apps/{app_id}/appStoreVersions", **{"filter[platform]": "IOS", "limit": 20})["data"]
    # Only a version nobody has submitted, or one Apple sent back, can be changed. One in review blocks a new one.
    editable = ("PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY")
    busy = ("WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_DEVELOPER_RELEASE", "PROCESSING_FOR_APP_STORE", "PENDING_APPLE_RELEASE")
    for v in versions:
        state = v["attributes"]["appStoreState"]
        if state in busy:
            sys.exit(f"{v['attributes']['versionString']} is {state}; a new version can't be prepared until it's released or rejected.")
        if state in editable:
            if v["attributes"]["versionString"] != wanted:
                # An unreleased version is renamed rather than left beside a second one; Apple allows only one.
                v = patch("appStoreVersions", v["id"], {"versionString": wanted})["data"]
            return v
    if not create_if_missing:
        sys.exit(f"No editable App Store version; {wanted} is already released. Raise MARKETING_VERSION.")
    return create("appStoreVersions", {"platform": "IOS", "versionString": wanted}, {"app": rel("apps", app_id)})


# docs/app-store.md


def doc_section(name):
    doc = (ROOT / "docs/app-store.md").read_text()
    m = re.search(rf"^## {re.escape(name)}\b.*?\n\n(.*?)(?=\n## |\Z)", doc, re.S | re.M)
    return m.group(1).strip() if m else None


def doc_field(label):
    # "- **Name:** GrogLog", or with Apple's length limit after the label: "- **Subtitle** (30): ...".
    pattern = rf"^- \*\*{re.escape(label)}(?::\*\*|\*\*(?: \(\d+\))?:) (.+)$"
    return re.search(pattern, doc_section("App information"), re.M).group(1)


def unwrap(text):
    """The doc is wrapped for reading in an editor; the store wants paragraphs on one line. A line in capitals is a
    heading and keeps its own line."""
    paragraphs = []
    for para in text.split("\n\n"):
        lines = para.split("\n")
        if re.fullmatch(r"[A-Z][A-Z ,'&-]+", lines[0]):
            paragraphs.append(lines[0] + "\n" + " ".join(lines[1:]))
        else:
            paragraphs.append(" ".join(lines))
    return "\n\n".join(paragraphs)


# Commands


def status():
    a = app()
    print(f"{a['attributes']['name']} ({a['id']})")
    for v in get(f"/v1/apps/{a['id']}/appStoreVersions", limit=5)["data"]:
        build = get(f"/v1/appStoreVersions/{v['id']}/build").get("data")
        attached = f", build {build['attributes']['version']}" if build else ", no build attached"
        print(f"  version {v['attributes']['versionString']}: {v['attributes']['appStoreState']}{attached}")
    print("Recent builds:")
    for b in get("/v1/builds", **{"filter[app]": a["id"], "sort": "-uploadedDate", "limit": 5, "include": "preReleaseVersion"})["data"]:
        print(f"  {b['attributes']['version']}  {b['attributes']['processingState']}  {b['attributes']['uploadedDate'][:16]}")
    for s in get("/v1/reviewSubmissions", **{"filter[app]": a["id"], "limit": 3})["data"]:
        print(f"Review submission {s['attributes']['submittedDate'] or '(unsent)'}: {s['attributes']['state']}")


def listing():
    a = app()
    version = editable_version(a["id"], create_if_missing=True)
    info = next(i for i in get(f"/v1/apps/{a['id']}/appInfos")["data"] if i["attributes"]["state"] != "READY_FOR_DISTRIBUTION")
    locale = a["attributes"]["primaryLocale"]

    info_loc = next(l for l in get(f"/v1/appInfos/{info['id']}/appInfoLocalizations")["data"] if l["attributes"]["locale"] == locale)
    patch("appInfoLocalizations", info_loc["id"], {
        "name": doc_field("Name"),
        "subtitle": doc_field("Subtitle"),
        "privacyPolicyUrl": doc_field("Privacy Policy URL"),
    })
    patch("appInfos", info["id"], relationships={
        "primaryCategory": rel("appCategories", doc_field("Primary category").upper().replace(" & ", "_AND_").replace(" ", "_")),
        "secondaryCategory": rel("appCategories", doc_field("Secondary category").upper().replace(" & ", "_AND_").replace(" ", "_")),
    })

    attributes = {
        "description": unwrap(doc_section("Description")),
        "keywords": doc_section("Keywords"),
        "promotionalText": unwrap(doc_section("Promotional text")),
        "marketingUrl": doc_field("Marketing URL"),
        "supportUrl": doc_field("Support URL"),
    }
    # Apple refuses release notes on an app's first version, and requires them on every later one.
    whats_new = doc_section("What's new")
    released = any(v["attributes"]["appStoreState"] == "READY_FOR_SALE" for v in get(f"/v1/apps/{a['id']}/appStoreVersions")["data"])
    if released:
        if not whats_new:
            sys.exit("An update needs release notes: add a \"What's new\" section to docs/app-store.md.")
        attributes["whatsNew"] = unwrap(whats_new)
    version_loc = next(l for l in get(f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"] if l["attributes"]["locale"] == locale)
    patch("appStoreVersionLocalizations", version_loc["id"], attributes)
    patch("appStoreVersions", version["id"], {"copyright": doc_field("Copyright")})

    # The contact details are left as set: a phone number doesn't belong in a public repository.
    review = get(f"/v1/appStoreVersions/{version['id']}/appStoreReviewDetail").get("data")
    notes = unwrap(doc_section("Review notes"))
    if review:
        patch("appStoreReviewDetails", review["id"], {"notes": notes})
    else:
        print("No review contact on this version yet; notes not set. Add the contact once with the API or website.")
    print(f"Listing for {version['attributes']['versionString']} matches docs/app-store.md")


def screenshots():
    a = app()
    version = editable_version(a["id"], create_if_missing=True)
    locale = a["attributes"]["primaryLocale"]
    version_loc = next(l for l in get(f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"] if l["attributes"]["locale"] == locale)
    with tempfile.TemporaryDirectory() as out:
        subprocess.run([ROOT / "scripts/store-screenshots.sh", out, "light"], check=True)
        files = sorted(pathlib.Path(out).glob("*.png"))

        sets = get(f"/v1/appStoreVersionLocalizations/{version_loc['id']}/appScreenshotSets")["data"]
        existing = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == SCREENSHOT_TYPE), None)
        if existing:
            for shot in get(f"/v1/appScreenshotSets/{existing['id']}/appScreenshots")["data"]:
                call("DELETE", f"/v1/appScreenshots/{shot['id']}")
            set_id = existing["id"]
        else:
            set_id = create("appScreenshotSets", {"screenshotDisplayType": SCREENSHOT_TYPE},
                            {"appStoreVersionLocalization": rel("appStoreVersionLocalizations", version_loc["id"])})["id"]

        for f in files:
            data = f.read_bytes()
            shot = create("appScreenshots", {"fileName": f.name, "fileSize": len(data)}, {"appScreenshotSet": rel("appScreenshotSets", set_id)})
            for op in shot["attributes"]["uploadOperations"]:
                headers = {h["name"]: h["value"] for h in op["requestHeaders"]}
                requests.request(op["method"], op["url"], headers=headers, data=data[op["offset"]:op["offset"] + op["length"]]).raise_for_status()
            patch("appScreenshots", shot["id"], {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()})
            print(f"Uploaded {f.name}")


def submit():
    a = app()
    version = editable_version(a["id"], create_if_missing=True)
    wanted = marketing_version()
    builds = get("/v1/builds", **{
        "filter[app]": a["id"], "filter[preReleaseVersion.version]": wanted,
        "filter[processingState]": "VALID", "sort": "-uploadedDate", "limit": 1,
    })["data"]
    if not builds:
        sys.exit(f"No processed build of {wanted} yet. CI uploads one on every push to main; processing takes a while.")
    build = builds[0]
    call("PATCH", f"/v1/appStoreVersions/{version['id']}/relationships/build", {"data": {"type": "builds", "id": build["id"]}})
    print(f"Attached build {build['attributes']['version']} to {wanted}")

    pending = [s for s in get("/v1/reviewSubmissions", **{"filter[app]": a["id"], "filter[state]": "READY_FOR_REVIEW"})["data"]]
    submission = pending[0] if pending else create("reviewSubmissions", {"platform": "IOS"}, {"app": rel("apps", a["id"])})
    items = get(f"/v1/reviewSubmissions/{submission['id']}/items")["data"]
    if not items:
        create("reviewSubmissionItems", relationships={
            "reviewSubmission": rel("reviewSubmissions", submission["id"]),
            "appStoreVersion": rel("appStoreVersions", version["id"]),
        })
    patch("reviewSubmissions", submission["id"], {"submitted": True})
    print(f"{wanted} submitted for review; it is released when Apple approves it")


def withdraw():
    a = app()
    waiting = get("/v1/reviewSubmissions", **{"filter[app]": a["id"], "filter[state]": "WAITING_FOR_REVIEW,IN_REVIEW"})["data"]
    if not waiting:
        sys.exit("Nothing is in review.")
    for s in waiting:
        patch("reviewSubmissions", s["id"], {"canceled": True})
    # Apple cancels in the background; the version can't be submitted again until it has.
    for _ in range(30):
        states = {s["attributes"]["state"] for s in get("/v1/reviewSubmissions", **{"filter[app]": a["id"], "limit": 5})["data"]}
        if not states & {"WAITING_FOR_REVIEW", "IN_REVIEW", "CANCELING"}:
            print("Withdrawn from review; `submit` sends it again with the newest build")
            return
        time.sleep(10)
    sys.exit("Still cancelling after five minutes; check `status` before submitting again.")


if __name__ == "__main__":
    commands = {"status": status, "listing": listing, "screenshots": screenshots, "submit": submit, "withdraw": withdraw}
    if len(sys.argv) != 2 or sys.argv[1] not in commands:
        sys.exit(__doc__)
    commands[sys.argv[1]]()
