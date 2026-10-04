"""Opt-in deployed API smoke test; synthetic posts only, soft-deleted in finally.

ZAKO_NEWS_LIVE_TEST=1 python3 supabase/tests/zako_news_http.py [--hold-for-ui]
Creates one anonymous test account. No secret key; tokens stay in memory.
"""
import json
import os
import sys
import uuid
from datetime import datetime, timezone
from urllib.error import HTTPError
from urllib.request import Request, urlopen

URL = "https://xlboihwjliebpissioxh.supabase.co"
KEY = "sb_publishable_8E87GiwDHFuJWDkVxLPTBg_eG433h8P"


def request(path, body=None, token=None, expected=200):
    headers = {"apikey": KEY, "Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = Request(URL + path, headers=headers,
                  data=json.dumps(body).encode() if body is not None else None)
    try:
        with urlopen(req, timeout=30) as response:
            status, data = response.status, response.read()
    except HTTPError as error:
        status, data = error.code, error.read()
    if status != expected:
        # Do not log session payloads, tokens, or user identifiers on failure.
        code = json.loads(data).get("code", "unknown") if data else "empty"
        raise AssertionError(f"{path}: expected {expected}, received {status} ({code})")
    return json.loads(data) if data else None


def main():
    if os.environ.get("ZAKO_NEWS_LIVE_TEST") != "1":
        sys.exit("Skipped. Set ZAKO_NEWS_LIVE_TEST=1 to test the configured remote project.")
    settings = request("/auth/v1/settings")
    assert settings["external"]["anonymous_users"]
    session = request("/auth/v1/signup", {})
    token = session["access_token"]
    assert session["user"]["is_anonymous"]
    posts = []

    def rpc(name, body=None, expected=200):
        return request("/rest/v1/rpc/" + name, body or {}, token, expected)

    try:
        for index, title in enumerate(["本を読む（確認用）", "SNS（確認用）", "散歩（確認用）", "勉強（確認用）"]):
            event = dict(p_source_key="smoke:" + str(uuid.uuid4()),
                         p_kind="failure" if index == 1 else "achievement",
                         p_display_name="接続テスト", p_task_title=title,
                         p_occurred_at=datetime.now(timezone.utc).isoformat())
            post_id = rpc("zako_publish", event)
            posts.append(post_id)
            assert rpc("zako_publish", event) == post_id
        rows = rpc("zako_feed", {"p_ids": posts})
        assert len(rows) == 4 and all(row["is_mine"] for row in rows)
        assert all("author_id" not in row and "source_key" not in row for row in rows)
        first = posts[0]
        rpc("zako_comment", {"p_post_id": first, "p_comment": "表示と接続の確認です"}, 204)
        rpc("zako_react", {"p_post_id": first, "p_reaction": "cheer"}, 204)
        rpc("zako_react", {"p_post_id": first, "p_reaction": "cheer"}, 204)
        row = rpc("zako_feed", {"p_ids": [first]})[0]
        assert row["cheer_count"] == 1 and row["comment"] == "表示と接続の確認です"
        rpc("zako_react", {"p_post_id": first, "p_reaction": None}, 204)
        assert rpc("zako_feed", {"p_ids": [first]})[0]["cheer_count"] == 0
        request("/rest/v1/zako_news_posts?select=id&limit=1", token=token, expected=403)
        request("/rest/v1/rpc/zako_feed", {}, expected=401)
        refreshed = request("/auth/v1/token?grant_type=refresh_token",
                            {"refresh_token": session["refresh_token"]})
        assert refreshed["user"]["id"] == session["user"]["id"]
        token = refreshed["access_token"]
        print("PASS: anonymous auth, refresh identity, publish/retry, feed projection, comment, reaction, access denial", flush=True)
        if "--hold-for-ui" in sys.argv:
            input("Four synthetic posts available for UI QA. Press Return to soft-delete them.\n")
    finally:
        for post_id in posts:
            rpc("zako_delete", {"p_post_id": post_id}, 204)
        assert not rpc("zako_feed", {"p_ids": posts})
        print("PASS: test posts soft-deleted; no habit records changed", flush=True)


if __name__ == "__main__":
    main()
