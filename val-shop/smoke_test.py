#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""离线冒烟测试：不联网，验证协议层拼装 + 全部 REST 路由可用。"""
import asyncio
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from fastapi.testclient import TestClient  # noqa: E402

from server import zhangwa  # noqa: E402
from server.app import app  # noqa: E402


def test_cookie_build():
    s = zhangwa.ZhangwaSession(user_id="u-abc", ct="CT1", account_type=zhangwa.ACCT_QQ,
                               openid="OID1", uin=10001, access_token="TOK1", tid="TID1")
    ck = s.cookie_header()
    print("QQ   Cookie:", ck)
    assert "clientType=9" in ck
    assert "acctype=qc" in ck
    assert "uin=o10001" in ck           # 关键：QQ 号要带 o 前缀
    assert "appid=102061775" in ck
    assert "accountType=5" in ck
    assert "userId=u-abc" in ck
    assert "tid=TID1" in ck

    w = zhangwa.ZhangwaSession(user_id="u-abc", account_type=zhangwa.ACCT_WX,
                               openid="OID2", access_token="TOK2")
    ck2 = w.cookie_header()
    print("WX   Cookie:", ck2)
    assert "acctype=wx" in ck2
    assert "wxcbb49f1f39656c2a" in ck2
    assert "uin=" not in ck2


def test_cookie_parse():
    raw = ("clientType=9; acctype=qc; uin=o10001; appid=102061775; openid=OID; "
           "access_token=TOK; userId=u-123; accountType=5; tid=TID")
    s = zhangwa.ZhangwaSession.from_cookie_string(raw)
    print("parsed:", s.dump())
    assert s.user_id == "u-123"
    assert s.uin == 10001
    assert s.account_type == 5
    assert s.tid == "TID"
    # 原样回放，保证抓包数据零损耗
    assert s.cookie_header() == raw.replace("; ", "; ")


def test_host_rewrite():
    c = zhangwa.ZhangwaClient(zhangwa.ZhangwaSession())
    assert c.rewrite_host("https://mlol.qt.qq.com/go/x").startswith("https://app.mval.qq.com")
    assert c.rewrite_host("/go/x") == "https://app.mval.qq.com/go/x"


def test_envelope_parse():
    """用假的响应验证 result / data / 999999 分支。"""
    import httpx

    sess = zhangwa.ZhangwaSession(user_id="u-1", tid="T")
    client = zhangwa.ZhangwaClient(sess)

    class FakeResp:
        def __init__(self, payload): self.text = payload; self.status_code = 200

    seen = {"post": 0, "get": 0}

    async def fake_post(url, headers=None, content=None):
        seen["post"] += 1
        return FakeResp(json.dumps({"result": 0, "msg": "ok", "data": {"items": [1, 2]}}))

    async def fake_get(url, headers=None, params=None):
        seen["get"] += 1
        assert params and params.get("game_zone") == "val", params   # game_zone 注入
        return FakeResp(json.dumps({"result": 0, "msg": "ok", "data": {"ok": True}}))

    client._client.post = fake_post
    client._client.get = fake_get

    # body 非 None → POST（并把 game_zone 注入 JSON body）
    data = asyncio.run(client.request("/go/x", {}))
    assert data == {"items": [1, 2]}, data
    assert seen["post"] == 1
    # body is None → GET（game_zone 走 query）
    data2 = asyncio.run(client.request("/go/y", None))
    assert data2 == {"ok": True}, data2
    assert seen["get"] == 1
    print("envelope 解析 + game_zone 注入 OK")

    async def fake_err(url, headers=None, content=None):
        return FakeResp(json.dumps({"result": 10001, "msg": "no auth", "data": None}))
    client._client.post = fake_err
    try:
        asyncio.run(client.request("/go/z", {"a": 1}))
        raise AssertionError("应当抛 ZhangwaError")
    except zhangwa.ZhangwaError as exc:
        assert exc.code == 10001
        print("错误码透传 OK ->", exc)


def test_routes():
    client = TestClient(app)
    r = client.get("/api/health"); assert r.status_code == 200, r.text
    print("health:", r.json())

    r = client.get("/api/session"); assert r.status_code == 200
    print("session:", r.json())

    r = client.post("/api/session/cookie", json={"cookie": "clientType=9; acctype=qc; uin=o1; appid=102061775; openid=O; access_token=T; userId=u-9; accountType=5; tid=TT"})
    assert r.status_code == 200, r.text
    print("set cookie:", r.json())

    r = client.get("/api/session")
    assert r.json()["valid"] is True

    # 未配置商店路径 → 期望 400 + 明确提示
    r = client.get("/api/store")
    print("store (expected 400):", r.status_code, r.json())
    assert r.status_code == 400
    assert "ZW_SHOP_PATH" in r.json()["detail"]

    # 抓包解析
    log = Path(__file__).resolve().parent / "state" / "fake_capture.log"
    log.parent.mkdir(exist_ok=True)
    log.write_text("\n".join([
        json.dumps({"dir": "REQ", "method": "POST",
                    "url": "https://app.mval.qq.com/go/account/mval_index_new",
                    "cookie": "clientType=9; acctype=qc; uin=o10001; appid=102061775; "
                              "openid=OID; access_token=TOK; userId=u-777; accountType=5; tid=TID9",
                    "body": '{"game_zone":"val"}'}),
        json.dumps({"dir": "RESP", "url": "https://app.mval.qq.com/go/account/mval_index_new",
                    "body": '{"result":0,"msg":"success","data":{"a":1}}'}),
    ]), encoding="utf-8")

    r = client.post("/api/session/import-capture", json={"file": str(log)})
    assert r.status_code == 200, r.text
    print("import capture:", r.json())
    assert r.json()["user_id"] == "u-777"

    r = client.get("/api/capture/endpoints", params={"file": str(log)})
    assert r.status_code == 200, r.text
    print("endpoints:", json.dumps(r.json(), ensure_ascii=False, indent=2))

    r = client.get("/")
    assert r.status_code == 200 and "每日商店" in r.text
    print("index.html OK,", len(r.text), "bytes")

    client.post("/api/session/logout")
    print("ALL ROUTES OK")


if __name__ == "__main__":
    test_cookie_build()
    test_cookie_parse()
    test_host_rewrite()
    test_envelope_parse()
    test_routes()
    print("\n=== 冒烟测试全部通过 ===")
