#!/usr/bin/env python3
import base64
import io
import json
import os
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.parse import quote, unquote, urlencode, urlsplit, urlunsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener


nexus_url = os.environ.get("NEXUS_URL", "").rstrip("/") + "/"
nexus_user = os.environ.get("NEXUS_USER", "")
nexus_pass = os.environ.get("NEXUS_PASS", "")
cloudflare_id = os.environ.get("CF_ACCESS_CLIENT_ID", "")
cloudflare_secret = os.environ.get("CF_ACCESS_CLIENT_SECRET", "")
user_agent = "Apache-Maven/3.9.6"
if not nexus_user or not nexus_pass:
    raise SystemExit("NEXUS_USER and NEXUS_PASS must be set")
if bool(cloudflare_id) != bool(cloudflare_secret):
    raise SystemExit("CF_ACCESS_CLIENT_ID and CF_ACCESS_CLIENT_SECRET must be set together")
parts = urlsplit(nexus_url)
if not parts.scheme or "/repository/" not in parts.path:
    raise SystemExit("NEXUS_URL must include /repository/<name>/")

context_path, repository_path = parts.path.split("/repository/", 1)
repository = unquote(repository_path.split("/", 1)[0])
repository_url = urlunsplit((parts.scheme, parts.netloc, f"{context_path}/repository/{repository}/", "", ""))
search_url = urlunsplit((parts.scheme, parts.netloc, f"{context_path}/service/rest/v1/search/assets", "", ""))
auth_header = "Basic " + base64.b64encode(f"{nexus_user}:{nexus_pass}".encode()).decode()


class SameOriginRedirectHandler(HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, new_url):
        old = urlsplit(request.full_url)
        new = urlsplit(new_url)
        if (old.scheme, old.hostname, old.port) != (new.scheme, new.hostname, new.port):
            return None
        return super().redirect_request(request, response, code, message, headers, new_url)


nexus_opener = build_opener(SameOriginRedirectHandler)


def nexus_headers():
    headers = {
        "Accept": "application/json",
        "Authorization": auth_header,
        "User-Agent": user_agent,
    }
    if cloudflare_id and cloudflare_secret:
        headers["CF-Access-Client-Id"] = cloudflare_id
        headers["CF-Access-Client-Secret"] = cloudflare_secret
    return headers


def search_assets():
    assets = []
    token = None
    while True:
        params = {"repository": repository}
        if token:
            params["continuationToken"] = token
        request = Request(search_url + "?" + urlencode(params), headers=nexus_headers())
        with nexus_opener.open(request, timeout=60) as response:
            payload = json.load(response)
        items = payload.get("items")
        if not isinstance(items, list):
            raise ValueError("Nexus asset search response is missing its items list")
        assets.extend(items)
        token = payload.get("continuationToken")
        if not token:
            return assets


def artifactory_results():
    results = []
    for asset in search_assets():
        path = asset.get("path", "").strip("/")
        name = path.rsplit("/", 1)[-1]
        if not path or not name.lower().endswith((".hpi", ".jpi", ".pom", ".war")):
            continue
        directory = path.rpartition("/")[0]
        if not directory:
            continue
        checksums = asset.get("checksum") or {}
        results.append({
            "path": directory,
            "name": name,
            "modified": asset.get("lastModified") or asset.get("blobCreated"),
            "created": asset.get("blobCreated") or asset.get("lastModified"),
            "actual_sha1": checksums.get("sha1"),
            "sha256": checksums.get("sha256"),
            "size": asset.get("fileSize"),
        })
    return {"results": results}


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/healthz":
            self.send_response(200)
            self.end_headers()
            return
        prefix = "/releases/"
        if not self.path.startswith(prefix):
            self.send_error(404)
            return
        artifact_path = unquote(urlsplit(self.path).path[len(prefix):])
        artifact_path, separator, archive_entry = artifact_path.partition("!")
        if any(part in ("", ".", "..") for part in artifact_path.split("/")):
            self.send_error(400)
            return
        target = repository_url + quote(artifact_path, safe="/")
        request = Request(target, headers={
            "Authorization": auth_header,
            "User-Agent": user_agent,
            **({"CF-Access-Client-Id": cloudflare_id, "CF-Access-Client-Secret": cloudflare_secret}
               if cloudflare_id and cloudflare_secret else {}),
        })
        try:
            with nexus_opener.open(request, timeout=120) as response:
                content = response.read()
                status = response.status
                content_type = response.headers.get("Content-Type", "application/octet-stream")
            if separator:
                with zipfile.ZipFile(io.BytesIO(content)) as archive:
                    content = archive.read(archive_entry.lstrip("/"))
                content_type = "application/octet-stream"
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(content)))
            self.end_headers()
            self.wfile.write(content)
        except KeyError:
            self.send_error(404, "Nexus archive entry not found")
        except (HTTPError, URLError, TimeoutError, zipfile.BadZipFile) as error:
            status = f"HTTP {error.code}" if isinstance(error, HTTPError) else type(error).__name__
            print(f"Nexus artifact download failed: {status}")
            self.send_error(502, "Nexus artifact download failed")

    def do_POST(self):
        if urlsplit(self.path).path != "/api/search/aql":
            self.send_error(404)
            return
        self.rfile.read(int(self.headers.get("Content-Length", "0")))
        try:
            body = json.dumps(artifactory_results()).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        except (HTTPError, URLError, TimeoutError, ValueError, KeyError) as error:
            status = f"HTTP {error.code}" if isinstance(error, HTTPError) else type(error).__name__
            print(f"Nexus asset search failed: {status}")
            self.send_error(502, "Nexus asset search failed")

    def log_message(self, format, *args):
        print("update-center Nexus adapter: " + format % args)


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8765), Handler).serve_forever()