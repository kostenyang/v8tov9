#!/usr/bin/env python3
"""等 VCF Installer 的 binary 下載跑完,每 2 分鐘回報一次。

用 /v1/tasks(BUNDLE_DOWNLOAD)看,而不是 /v1/bundles —— 後者有 276 筆
(含所有版本),雜訊太多;tasks 只列這次真的在跑的。
"""
import os, sys
import json, ssl, sys, time, urllib.request

HOST = "10.0.1.71"
USER = "admin@local"
PASS = os.environ.get("LABPASS") or sys.exit("set LABPASS")
CTX = ssl._create_unverified_context()


def req(path, token=None, method="GET", body=None):
    data = json.dumps(body).encode() if body else None
    r = urllib.request.Request(f"https://{HOST}{path}", data=data, method=method)
    r.add_header("Content-Type", "application/json")
    if token:
        r.add_header("Authorization", "Bearer " + token)
    with urllib.request.urlopen(r, context=CTX, timeout=30) as resp:
        return json.loads(resp.read().decode())


def token():
    return req("/v1/tokens", method="POST",
               body={"username": USER, "password": PASS})["accessToken"]


def main():
    tok = token()
    for i in range(400):
        try:
            tasks = req("/v1/tasks", tok).get("elements", [])
        except Exception as e:
            tok = token()
            print(f"{time.strftime('%H:%M:%S')} (重取 token: {e})", flush=True)
            continue
        dl = [t for t in tasks if t.get("type") == "BUNDLE_DOWNLOAD"]
        by = {}
        for t in dl:
            by[t.get("status", "?")] = by.get(t.get("status", "?"), 0) + 1
        running = [t["name"].replace("Download BUNDLE - ", "")
                   for t in dl if t.get("status") == "IN_PROGRESS"]
        print(f"{time.strftime('%H:%M:%S')} {by} 進行中={running[:4]}", flush=True)
        if dl and not by.get("IN_PROGRESS") and not by.get("PENDING"):
            print("BINARIES-DONE", flush=True)
            for t in dl:
                if t.get("status") != "SUCCESSFUL":
                    print("  ⚠", t.get("status"), t.get("name"), flush=True)
            return
        time.sleep(120)
    print("BINARIES-TIMEOUT", flush=True)


if __name__ == "__main__":
    main()
