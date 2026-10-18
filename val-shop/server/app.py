#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
app.py —— 独立「每日商店」App 后端
=================================

把掌瓦逆向出来的协议层（server/zhangwa.py）包成一组 REST 接口，
前端（web/index.html）只渲染，不关心鉴权细节。

运行：
    pip install -r requirements.txt
    python -m uvicorn server.app:app --reload --port 8787
    浏览器打开 http://127.0.0.1:8787

接入登录态（三选一）：
    1) 抓包最省事：
         frida -U -f com.tencent.apps.valorant -l capture/frida_okhttp_dump.js
         → 拉取 /data/local/tmp/mval_capture.log
         POST /api/session/import-capture {"file": "mval_capture.log"}
    2) 手动粘贴 Cookie：
         POST /api/session/cookie {"cookie": "clientType=9; acctype=qc; ...; tid=..."}
    3) 自己实现 QQ/微信 SSO 换票（见 zhangwa.ZhangwaClient 里的 /go/auth/* 方法）
"""

from __future__ import annotations

import json
import logging
import os
import re
from pathlib import Path
from typing import Any, Dict, List, Optional

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from . import zhangwa
from .zhangwa import ZhangwaClient, ZhangwaError, ZhangwaSession

logging.basicConfig(level=logging.INFO,
                    format="%(asctime)s %(levelname)s %(name)s | %(message)s")
log = logging.getLogger("app")

ROOT = Path(__file__).resolve().parent.parent
WEB = ROOT / "web"
STATE = ROOT / "state"
STATE.mkdir(exist_ok=True)
SESSION_FILE = STATE / "session.json"

app = FastAPI(title="无畏契约 · 每日商店（独立实现）", version="0.1.0")

_session: Optional[ZhangwaSession] = None
_client: Optional[ZhangwaClient] = None


# ---------------------------------------------------------------------------
# 会话管理
# ---------------------------------------------------------------------------
def get_session() -> ZhangwaSession:
    global _session
    if _session is None:
        if SESSION_FILE.exists():
            try:
                _session = ZhangwaSession.load(str(SESSION_FILE))
                log.info("已从 %s 恢复会话", SESSION_FILE)
            except Exception as exc:  # noqa: BLE001
                log.warning("会话文件损坏：%s", exc)
        if _session is None:
            _session = ZhangwaSession()
    return _session


async def get_client() -> ZhangwaClient:
    global _client
    if _client is None:
        _client = ZhangwaClient(get_session(), host=os.getenv("ZW_HOST", zhangwa.HOST_PROD))
    return _client


def persist() -> None:
    get_session().save(str(SESSION_FILE))
    try:
        os.chmod(SESSION_FILE, 0o600)
    except OSError:
        pass


# ---------------------------------------------------------------------------
# 抓包文件解析：从 Frida / mitmproxy 日志里把 Cookie 抠出来
# ---------------------------------------------------------------------------
COOKIE_KEYS = ("clientType", "acctype", "userId", "tid", "openid", "access_token")


def extract_cookie_from_capture(path: Path) -> Optional[str]:
    """支持两种格式：
    - frida_okhttp_dump.js 的 ndjson（{"dir":"REQ","cookie":"..."}）
    - mitm_zhangwa.py 的 jsonl（{"dir":"REQ","cookies":{...}}）
    - 纯文本（日志里包含 'Cookie: xxx'）
    """
    best: Optional[str] = None
    best_score = 0

    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line or not line.startswith("{"):
            # 纯文本兜底
            m = re.search(r"Cookie:\s*([^\"']+)", line)
            if m:
                c = m.group(1).strip()
                score = sum(1 for k in COOKIE_KEYS if k in c)
                if score > best_score:
                    best, best_score = c, score
            continue
        try:
            obj = json.loads(line)
        except Exception:  # noqa: BLE001
            continue
        if obj.get("dir") != "REQ":
            continue
        cookie = obj.get("cookie")
        if not cookie and isinstance(obj.get("cookies"), dict):
            cookie = "; ".join(f"{k}={v}" for k, v in obj["cookies"].items())
        if not cookie and isinstance(obj.get("headers"), dict):
            for k, v in obj["headers"].items():
                if k.lower() == "cookie":
                    cookie = v
                    break
        if not cookie:
            continue
        score = sum(1 for k in COOKIE_KEYS if k in cookie)
        if score > best_score:
            best, best_score = cookie, score

    return best


def collect_endpoints(path: Path) -> List[Dict[str, Any]]:
    """顺手把抓到的 /go/ 接口列出来，方便一眼找到商店路径。"""
    out: Dict[str, Dict[str, Any]] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            obj = json.loads(line)
        except Exception:  # noqa: BLE001
            continue
        url = obj.get("url") or ""
        if "/go/" not in url:
            continue
        key = url.split("?")[0]
        rec = out.setdefault(key, {"url": key, "methods": set(), "bodies": [], "resp": None})
        if obj.get("dir") == "REQ":
            rec["methods"].add(obj.get("method", "?"))
            if obj.get("body"):
                rec["bodies"].append(str(obj["body"])[:500])
        else:
            rec["resp"] = obj.get("body")
    for rec in out.values():
        rec["methods"] = sorted(rec["methods"])
        rec["bodies"] = rec["bodies"][:2]
    return sorted(out.values(), key=lambda r: r["url"])


# ---------------------------------------------------------------------------
# API models
# ---------------------------------------------------------------------------
class CookieIn(BaseModel):
    cookie: str


class CaptureIn(BaseModel):
    file: str


class StoreIn(BaseModel):
    path: Optional[str] = None
    body: Optional[Dict[str, Any]] = None
    method: Optional[str] = None


# ---------------------------------------------------------------------------
# 路由
# ---------------------------------------------------------------------------
@app.get("/api/health")
async def health() -> Dict[str, Any]:
    s = get_session()
    return {
        "ok": True,
        "has_session": s.is_valid,
        "host": os.getenv("ZW_HOST", zhangwa.HOST_PROD),
        "shop_path_configured": bool(ZhangwaClient.SHOP_PATH),
    }


@app.get("/api/session")
async def session_info() -> Dict[str, Any]:
    s = get_session()
    if s.account_type == zhangwa.ACCT_QQ:
        account = "QQ"
    elif s.account_type == zhangwa.ACCT_WX:
        account = "微信"
    else:
        account = "游客/未知"

    return {
        "valid": s.is_valid,
        "account_type": s.account_type,
        "account": account,
        "user_id": s.user_id,
        "uin": s.uin,
        "cookie_preview": s.cookie_header()[:160],
        "has_tid": bool(s.tid),
        "has_ct": bool(s.ct),
        "expires_at": s.expires_at,
    }


@app.post("/api/session/cookie")
async def set_cookie(body: CookieIn) -> Dict[str, Any]:
    global _session, _client
    s = ZhangwaSession.from_cookie_string(body.cookie)
    _session = s
    _client = None
    persist()
    return {"ok": True, "user_id": s.user_id, "account_type": s.account_type}


@app.post("/api/session/import-capture")
async def import_capture(body: CaptureIn) -> Dict[str, Any]:
    global _session, _client
    p = Path(body.file)
    if not p.exists():
        raise HTTPException(404, f"找不到抓包文件：{p}")
    cookie = extract_cookie_from_capture(p)
    if not cookie:
        raise HTTPException(400, "抓包文件里没有找到 Cookie 头（请求过 /go/ 接口吗？）")
    s = ZhangwaSession.from_cookie_string(cookie)
    _session = s
    _client = None
    persist()
    return {"ok": True, "user_id": s.user_id, "cookie_len": len(cookie)}


@app.post("/api/session/logout")
async def logout() -> Dict[str, Any]:
    global _session, _client
    _session = ZhangwaSession()
    _client = None
    if SESSION_FILE.exists():
        SESSION_FILE.unlink()
    return {"ok": True}


@app.get("/api/capture/endpoints")
async def capture_endpoints(file: str) -> List[Dict[str, Any]]:
    p = Path(file)
    if not p.exists():
        raise HTTPException(404, f"找不到文件：{p}")
    return collect_endpoints(p)


@app.post("/api/refresh")
async def refresh() -> Dict[str, Any]:
    c = await get_client()
    try:
        ok = await c.refresh_client_ticket()
    except ZhangwaError as exc:
        raise HTTPException(400, str(exc)) from exc
    persist()
    return {"ok": ok}


@app.get("/api/roles")
async def roles(game_id: str = zhangwa.ZONE_VAL) -> Any:
    c = await get_client()
    try:
        return await c.get_roles_by_game(game_id)
    except ZhangwaError as exc:
        raise HTTPException(400, str(exc)) from exc


@app.get("/api/gamelist")
async def gamelist() -> Any:
    c = await get_client()
    try:
        return await c.get_role_list()
    except ZhangwaError as exc:
        raise HTTPException(400, str(exc)) from exc


# ---- 商店 ----
@app.get("/api/store")
async def store(path: Optional[str] = None,
                method: Optional[str] = None) -> Any:
    c = await get_client()
    if path:
        c.SHOP_PATH = path
    if method:
        c.SHOP_METHOD = method
    try:
        data = await c.fetch_store()
    except ZhangwaError as exc:
        raise HTTPException(400, str(exc)) from exc
    return normalize_store(data)


@app.post("/api/store/raw")
async def store_raw(body: StoreIn) -> Any:
    """任意接口原样调用（用于确认/调试商店接口）。"""
    c = await get_client()
    if not body.path:
        raise HTTPException(400, "path 必填")
    try:
        return await c.request(body.path, body.body, method=body.method or "auto")
    except ZhangwaError as exc:
        raise HTTPException(400, str(exc)) from exc


@app.post("/api/store/probe")
async def store_probe() -> Any:
    c = await get_client()
    return await c.probe_shop()


# ---- 游戏数据 ----
@app.get("/api/asset/gun-skin")
async def gun_skin(arm_id: str, game_zone: str = zhangwa.ZONE_VAL) -> Any:
    c = await get_client()
    try:
        return await c.gun_skin_detail(arm_id, game_zone=game_zone)
    except ZhangwaError as exc:
        raise HTTPException(400, str(exc)) from exc


@app.get("/api/asset/showcase")
async def showcase() -> Any:
    c = await get_client()
    try:
        return await c.showcase_get()
    except ZhangwaError as exc:
        raise HTTPException(400, str(exc)) from exc


@app.get("/api/card")
async def card() -> Any:
    c = await get_client()
    try:
        return await c.val_card_v2()
    except ZhangwaError as exc:
        raise HTTPException(400, str(exc)) from exc


# ---------------------------------------------------------------------------
# 归一化：把不同可能字段名统一成前端契约
#   { items: [ {name, icon, price, quality, owned, weaponName, skinUuid} ],
#     expiresAt, remaining, currency }
# ---------------------------------------------------------------------------
QUALITY_BY_TIER = {1: "select", 2: "deluxe", 3: "premium", 4: "exquisite", 5: "ultra"}


def _pick(d: Dict[str, Any], *names: str, default: Any = None) -> Any:
    for n in names:
        if n in d and d[n] not in (None, ""):
            return d[n]
    return default


def normalize_store(data: Any) -> Dict[str, Any]:
    if not isinstance(data, dict):
        return {"raw": data, "items": []}

    # 常见的几种容器命名都兼容一下
    container = None
    for key in ("SkinsPanelLayout", "skins_panel_layout", "storefront", "panel",
                "singleItemOffers", "SingleItemOffers", "items", "list", "offers"):
        node = data.get(key)
        if isinstance(node, dict):
            container = node
            break
        if isinstance(node, list):
            container = {"offers": node}
            break
    if container is None:
        container = data

    offers = None
    for key in ("SingleItemOffers", "singleItemOffers", "offers", "items", "list"):
        node = container.get(key)
        if isinstance(node, list):
            offers = node
            break
    if offers is None:
        offers = []

    items: List[Dict[str, Any]] = []
    for idx, off in enumerate(offers):
        if not isinstance(off, dict):
            continue
        items.append({
            "index": idx,
            "offerId": _pick(off, "OfferID", "offer_id", "offerId", "id"),
            "skinUuid": _pick(off, "ItemID", "item_id", "skinUuid", "sku"),
            "name": _pick(off, "Name", "name", "skin_name", "displayName",
                          "ItemName", "item_name", default="未知商品"),
            "weaponName": _pick(off, "weapon", "weaponName", "gun_name", "armName"),
            "icon": _pick(off, "IconUrl", "icon", "icon_url", "skin_icon",
                          "displayIcon", "image", "img"),
            "price": _pick(off, "Cost", "cost", "price", "vp", "point", "Price"),
            "quality": _pick(off, "quality", "Quality", "rarity", "tier"),
            "owned": bool(_pick(off, "owned", "is_owned", "Owned", default=False)),
        })

    return {
        "items": items,
        "expiresAt": _pick(data, "expiresAt", "expire_ts", "expire_ts_ms", "next_refresh",
                            "NextRefreshAt", "refreshTime"),
        "remaining": _pick(data, "remaining", "remain", "left_time", "time_left"),
        "currency": _pick(data, "currency", "VP", "vp", "wallet", default="VP"),
        "raw_keys": sorted(data.keys()),
    }


# ---------------------------------------------------------------------------
# 静态前端
# ---------------------------------------------------------------------------
if WEB.exists():
    app.mount("/static", StaticFiles(directory=str(WEB)), name="static")


@app.get("/")
async def index() -> Any:
    idx = WEB / "index.html"
    if idx.exists():
        return FileResponse(str(idx))
    return JSONResponse({"msg": "web/index.html 不存在"})
