#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
zhangwa.py —— 掌上无畏契约（掌瓦）协议层复刻
============================================

本文件把 APK 里逆向出来的协议细节 1:1 复刻成一个可独立运行的客户端，
方便做「独立的每日商店 App」。所有常量都来自对 com.tencent.apps.valorant (2.10.1)
的静态分析，出处见 analysis/掌瓦数据链路分析.md。

复刻的关键点
------------
1. 域名重写   mlol.qt.qq.com -> app.mval.qq.com              (§1.3)
2. 响应信封   {"result":0,"msg":"","data":{}}，999999 = 票据异常  (§1.2)
3. game_zone  非白名单域名自动注入 game_zone=val              (§1.4)
4. Cookie     clientType/acctype/uin/appid/openid/access_token/userId/accountType/tid  (§1.5)
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import time
from dataclasses import dataclass, field, asdict
from typing import Any, Dict, Iterable, List, Optional, Tuple

import httpx

log = logging.getLogger("zhangwa")

# ---------------------------------------------------------------------------
# 常量（全部来自 AndroidManifest.xml / build 配置）
# ---------------------------------------------------------------------------
HOST_PROD = os.getenv("ZW_HOST", "app.mval.qq.com")
HOST_TEST = "apptest.mval.qq.com"
HOST_OLD = "mlol.qt.qq.com"          # 掌盟域名，ValUrlTransformer 会替换掉
HOST_OLD_PRE = "mlolpre.qt.qq.com"

CLIENT_TYPE = "9"
APPID_QQ = "102061775"               # manifest: openqq_appid
APPID_WX = "wxcbb49f1f39656c2a"      # manifest: wx_appid
MAPPID = 10200                       # manifest: login_mappid

# accountType（com.tencent.container.app.AppContext 的 authType -> accountType 映射）
ACCT_QQ = 5
ACCT_WX = 2
ACCT_GUEST = 1

AUTH_TYPE_MAP = {0: 1, 1: 2, 4: 5}   # authType(0游客/1微信/4QQ) -> accountType

DEFAULT_UA = (
    "Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Version/4.0 Chrome/120.0.0.0 Mobile Safari/537.36"
)

# game_zone 常量
ZONE_VAL = "val"        # 无畏契约端游
ZONE_CODEV = "codev"    # 无畏契约手游 / 共创

RESULT_OK = 0
RESULT_TICKET_INVALID = 999999


class ZhangwaError(RuntimeError):
    def __init__(self, code: int, msg: str, data: Any = None):
        super().__init__(f"[{code}] {msg}")
        self.code = code
        self.msg = msg
        self.data = data


@dataclass
class ZhangwaSession:
    """掌瓦登录态。

    字段与 com.tencent.container.app.AppContext 一一对应：
        user_id      <- AppContext.b   (Cookie: userId)
        ct           <- AppContext.c   (Client Ticket)
        tid          <- AppContext.e   (Cookie: tid，本地按 tid_<userId> 缓存)
        auth_type    <- AppContext.f   (0 游客 / 1 微信 / 4 QQ)
        account_type <- AppContext.g   (1 / 2 / 5)
        openid       <- AppContext.h   (Cookie: openid)
        uin          <- AppContext.i   (Cookie: uin=o<uin>)
        access_token <- AppContext.j   (Cookie: access_token)
    """

    user_id: str = ""
    ct: str = ""
    wt: str = ""
    ctt: str = ""
    sk: str = ""
    auth_type: int = 4                  # 默认 QQ
    account_type: int = ACCT_QQ
    openid: str = ""
    uin: int = 0
    access_token: str = ""
    tid: str = ""
    login_uuid: str = ""
    expires_at: float = 0.0
    extra_cookies: Dict[str, str] = field(default_factory=dict)
    raw_cookie_header: str = ""         # 抓包直接拿到的原始 Cookie（最高优先级）

    # ---- 派生 ----
    @property
    def is_qq(self) -> bool:
        return self.account_type == ACCT_QQ

    @property
    def is_valid(self) -> bool:
        if self.raw_cookie_header:
            return True
        return bool(self.user_id and (self.ct or self.tid))

    # ---- Cookie 拼装：严格复刻 com.tencent.container.c.a.a#a(String) ----
    def cookie_pairs(self) -> List[Tuple[str, str]]:
        if self.raw_cookie_header:
            out: List[Tuple[str, str]] = []
            for part in self.raw_cookie_header.split(";"):
                if "=" in part:
                    k, v = part.split("=", 1)
                    out.append((k.strip(), v.strip()))
            return out

        pairs: List[Tuple[str, str]] = [("clientType", CLIENT_TYPE)]

        if self.account_type == ACCT_QQ:
            if self.uin:
                pairs.append(("uin", f"o{self.uin}"))      # 注意前缀 o
            pairs.append(("appid", APPID_QQ))
            pairs.append(("acctype", "qc"))
        elif self.account_type == ACCT_WX:
            pairs.append(("appid", APPID_WX))
            pairs.append(("acctype", "wx"))
        else:
            pairs.append(("acctype", "qc"))
            pairs.append(("appid", APPID_QQ))

        if self.openid:
            pairs.append(("openid", self.openid))
        if self.access_token:
            pairs.append(("access_token", self.access_token))
        if self.user_id:
            pairs.append(("userId", self.user_id))
            pairs.append(("accountType", str(self.account_type)))
        if self.tid:
            pairs.append(("tid", self.tid))

        pairs.extend(self.extra_cookies.items())
        return pairs

    def cookie_header(self) -> str:
        return "; ".join(f"{k}={v}" for k, v in self.cookie_pairs())

    # ---- 序列化 ----
    def dump(self) -> Dict[str, Any]:
        d = asdict(self)
        for secret in ("ct", "wt", "ctt", "sk", "access_token", "tid", "raw_cookie_header"):
            if d.get(secret):
                d[secret] = d[secret][:8] + "***"
        return d

    def save(self, path: str) -> None:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(asdict(self), f, ensure_ascii=False, indent=2)

    @classmethod
    def load(cls, path: str) -> "ZhangwaSession":
        with open(path, encoding="utf-8") as f:
            return cls(**json.load(f))

    @classmethod
    def from_cookie_string(cls, cookie: str) -> "ZhangwaSession":
        """从抓包得到的 Cookie 头直接构造（最省事的接入方式）。"""
        s = cls()
        # 保留完整原始串，避免漏字段
        s.raw_cookie_header = cookie.strip()
        kv: Dict[str, str] = {}
        for part in cookie.split(";"):
            if "=" in part:
                k, v = part.split("=", 1)
                kv[k.strip().lower()] = v.strip()

        s.user_id = kv.get("userid", "")
        s.tid = kv.get("tid", "")
        s.openid = kv.get("openid", "")
        s.access_token = kv.get("accesstoken", kv.get("access_token", ""))
        uin = kv.get("uin", "")
        if uin.startswith("o"):
            uin = uin[1:]
        s.uin = int(uin) if uin.isdigit() else 0
        try:
            s.account_type = int(kv.get("accounttype", ACCT_QQ))
        except ValueError:
            s.account_type = ACCT_QQ
        if "acctype" in kv:
            s.account_type = ACCT_QQ if kv["acctype"] == "qc" else ACCT_WX
        s.auth_type = 4 if s.account_type == ACCT_QQ else 1
        return s


# ---------------------------------------------------------------------------
# HTTP 客户端
# ---------------------------------------------------------------------------
class ZhangwaClient:
    """复刻 com.tencent.container.protocol.b / com.tencent.base.http.c 的行为。"""

    def __init__(self, session: ZhangwaSession, host: str = HOST_PROD,
                 ua: str = DEFAULT_UA, timeout: float = 20.0):
        self.session = session
        self.host = host
        self.ua = ua
        self._client = httpx.AsyncClient(timeout=timeout, follow_redirects=True)

    async def aclose(self) -> None:
        await self._client.aclose()

    # ---- URL 处理：等价的 ValUrlTransformer ----
    def rewrite_host(self, url: str) -> str:
        if HOST_OLD in url:
            url = url.replace(HOST_OLD, HOST_PROD)
        if HOST_OLD_PRE in url:
            url = url.replace(HOST_OLD_PRE, HOST_TEST)
        if url.startswith("/"):
            url = f"https://{self.host}{url}"
        return url

    def _inject_zone(self, body: Optional[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
        """等价于 AppEnvironment.a(String, Map)：给 val 域注入 game_zone。"""
        if body is None:
            return None
        b = dict(body)
        b.setdefault("source_game_zone", "")
        b.setdefault("game_zone", ZONE_VAL)
        return b

    async def request(self, path: str, body: Optional[Dict[str, Any]] = None,
                      method: str = "auto", game_zone: str = ZONE_VAL,
                      headers: Optional[Dict[str, str]] = None,
                      retry_on_ticket_error: bool = True) -> Any:
        """返回 data 字段；result != 0 抛 ZhangwaError。"""
        url = self.rewrite_host(path)
        hdrs = {
            "User-Agent": self.ua,
            "Cookie": self.session.cookie_header(),
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "zh-CN,zh;q=0.9",
            "Referer": f"https://{self.host}/",
            "Origin": f"https://{self.host}",
        }
        if headers:
            hdrs.update(headers)

        has_body = body is not None
        use_post = has_body if method == "auto" else (method.upper() == "POST")

        params: Optional[Dict[str, str]] = None
        payload: Optional[Dict[str, Any]] = None
        if use_post:
            payload = self._inject_zone(body if body is not None else {})
            hdrs["Content-Type"] = "application/json"
            resp = await self._client.post(
                url, headers=hdrs,
                content=json.dumps(payload or {}, ensure_ascii=False))
        else:
            # GET：game_zone 走 query（等价 AppEnvironment.a(String, Map)）
            params = {"source_game_zone": "", "game_zone": game_zone}
            if body:
                params.update({k: str(v) for k, v in body.items()})
            resp = await self._client.get(url, headers=hdrs, params=params)

        text = resp.text
        log.debug("%s %s -> %s", "POST" if use_post else "GET", url, resp.status_code)

        try:
            env = json.loads(text)
        except Exception as exc:  # noqa: BLE001
            raise ZhangwaError(-1, f"响应不是 JSON: {text[:300]}") from exc

        result = env.get("result")
        if result == RESULT_TICKET_INVALID and retry_on_ticket_error:
            log.warning("result=999999 票据异常，尝试刷新 wt 后重试")
            if await self.refresh_web_ticket():
                return await self.request(path, body, method, game_zone, headers,
                                          retry_on_ticket_error=False)

        if result != RESULT_OK:
            raise ZhangwaError(int(result if result is not None else -1),
                               str(env.get("msg", "")), env.get("data"))

        return env.get("data")

    # ---- 404 容忍的探测版 ----
    async def try_request(self, path: str, body: Optional[Dict[str, Any]] = None,
                          method: str = "auto") -> Tuple[bool, Any]:
        try:
            return True, await self.request(path, body, method)
        except ZhangwaError as exc:
            return False, exc
        except Exception as exc:  # noqa: BLE001
            return False, exc

    async def try_both_methods(self, path: str,
                               body: Optional[Dict[str, Any]] = None) -> Tuple[bool, str, Any]:
        """先 POST 再 GET，兼容两种协议风格。"""
        last: Any = None
        for m in ("POST", "GET"):
            ok, res = await self.try_request(path, body, method=m)
            if ok:
                return True, m, res
            last = res
        return False, "", last

    # ------------------------------------------------------------------
    # /go/auth/*  —— 票据链（登录后在 App 内由 SSO 完成；这里用于刷新与自建登录）
    # ------------------------------------------------------------------
    async def refresh_client_ticket(self) -> bool:
        """POST /go/auth/refresh_client_ticket"""
        data = await self.request("/go/auth/refresh_client_ticket", {
            "ct": self.session.ct,
            "user_id": self.session.user_id,
            "local_is_new_user": 0,
            "config_params": {"lang_type": 0},
        })
        info = (data or {}).get("ct_info") or {}
        if not info:
            return False
        self.session.ct = info.get("ct", self.session.ct)
        self.session.wt = info.get("wt", self.session.wt)
        self.session.uin = int(info.get("uin", self.session.uin) or 0)
        self.session.openid = info.get("openid", self.session.openid)
        self.session.user_id = info.get("user_id", self.session.user_id)
        span = int(info.get("refresh_ct_span", 3600) or 3600)
        self.session.expires_at = time.time() + span
        return True

    async def refresh_web_ticket(self) -> bool:
        """POST /go/auth/get_web_ticket"""
        try:
            data = await self.request("/go/auth/get_web_ticket", {
                "ct": self.session.ct,
                "user_id": self.session.user_id,
                "config_params": {"lang_type": 0},
            }, retry_on_ticket_error=False)
        except ZhangwaError as exc:
            if exc.code == RESULT_TICKET_INVALID:
                return await self.refresh_client_ticket()
            raise
        self.session.wt = (data or {}).get("wt", "")
        return bool(self.session.wt)

    async def get_client_tmp_ticket(self) -> Dict[str, Any]:
        """POST /go/auth/get_client_tmp_ticket"""
        data = await self.request("/go/auth/get_client_tmp_ticket", {
            "ct": self.session.ct,
            "user_id": self.session.user_id,
            "config_params": {"lang_type": 0},
        })
        self.session.ctt = (data or {}).get("ctt", "")
        self.session.sk = (data or {}).get("sk", "")
        return data or {}

    async def ensure_fresh(self) -> None:
        if self.session.raw_cookie_header:
            return
        if self.session.expires_at and time.time() > self.session.expires_at - 300:
            await self.refresh_client_ticket()

    # ------------------------------------------------------------------
    # 账号 / 角色
    # ------------------------------------------------------------------
    async def get_role_list(self) -> List[Dict[str, Any]]:
        """POST /go/account/getgamelist  —— 可绑定的游戏列表"""
        data = await self.request("/go/account/getgamelist", {})
        if isinstance(data, dict):
            return data.get("items") or data.get("list") or []
        return data or []

    async def get_roles_by_game(self, game_id: str = ZONE_VAL) -> Any:
        """POST /go/account/get_roles_by_game_v2  body {"game_id":"val"}"""
        return await self.request("/go/account/get_roles_by_game_v2", {"game_id": game_id})

    async def get_all_roles(self) -> Any:
        return await self.request("/go/account/getallgameroles", {})

    async def get_grant_list_mval(self) -> Any:
        return await self.request("/go/account/get_grant_list_mval", {})

    # ------------------------------------------------------------------
    # 无畏契约游戏数据
    # ------------------------------------------------------------------
    async def gun_skin_detail(self, arm_id: str, game_zone: str = ZONE_VAL) -> Any:
        """POST /go/agame/asset/gun_skin_detail  body {"armId":"...","from":"gl"}"""
        path = "/go/codev/asset/gun_skin_detail" if game_zone == ZONE_CODEV else "/go/agame/asset/gun_skin_detail"
        return await self.request(path, {"armId": arm_id, "from": "gl"}, game_zone=game_zone)

    async def showcase_get(self) -> Any:
        """POST /go/agame/asset/showcase/get —— 名片橱窗（含已拥有皮肤渲染数据）"""
        return await self.request("/go/agame/asset/showcase/get", {})

    async def val_card_v2(self) -> Any:
        """POST /go/mine/card/val_card_v2 —— 个人名片（皮肤总价值/总数）"""
        return await self.request("/go/mine/card/val_card_v2", {})

    # ------------------------------------------------------------------
    # 每日商店
    # ------------------------------------------------------------------
    # ⚠️ 商店页面由 RN/动态 UI 下发，路径不在 APK 里，需运行时抓包后填这里：
    #     python -m server.app --dump  抓一次打开商店的流量
    #     export ZW_SHOP_PATH=/go/xxx/yyy
    SHOP_PATH: str = os.getenv("ZW_SHOP_PATH", "")
    SHOP_BODY: Dict[str, Any] = json.loads(os.getenv("ZW_SHOP_BODY", "{}") or "{}")
    SHOP_METHOD: str = os.getenv("ZW_SHOP_METHOD", "auto")

    # 候选路径：抓到之后把真实的那条放第一个即可；也可用 probe 自动找
    SHOP_CANDIDATES: List[str] = [
        "/go/agame/store/storefront",
        "/go/agame/store/daily",
        "/go/agame/shop/storefront",
        "/go/agame/shop/daily",
        "/go/agame/asset/storefront",
        "/go/agame/asset/shop",
        "/go/mval_store/agame/storefront",
        "/go/mlol_store/agame/storefront",
        "/go/val_store/storefront",
        "/go/val_shop/storefront",
    ]

    async def fetch_store(self, role: Optional[Dict[str, Any]] = None) -> Any:
        if not self.SHOP_PATH:
            raise ZhangwaError(-1, "尚未配置商店接口路径（ZW_SHOP_PATH）")
        body = dict(self.SHOP_BODY)
        if role:
            for k in ("roleId", "role_id", "game_open_id", "openid", "area", "partition"):
                if k in role:
                    body.setdefault(k, role[k])
        return await self.request(self.SHOP_PATH, body or None, method=self.SHOP_METHOD)

    async def probe_shop(self) -> List[Tuple[str, str]]:
        """逐个尝试候选路径（POST/GET 都试），返回 [(path, 结果描述)]。"""
        out: List[Tuple[str, str]] = []
        for p in self.SHOP_CANDIDATES:
            ok, used, res = await self.try_both_methods(p, {})
            if ok:
                out.append((p, f"OK [{used}] {str(res)[:240]}"))
            else:
                out.append((p, f"FAIL {res}"))
        return out


# ---------------------------------------------------------------------------
# 便捷函数
# ---------------------------------------------------------------------------
def new_client(session: ZhangwaSession, **kw) -> ZhangwaClient:
    return ZhangwaClient(session, **kw)


async def demo() -> None:
    """离线自检：确认 Cookie 拼装与信封解析逻辑。"""
    s = ZhangwaSession(user_id="u-123456", ct="CT-TEST", account_type=ACCT_QQ,
                       openid="OPENID-TEST", uin=10001, access_token="TOKEN-TEST",
                       tid="TID-TEST")
    print("Cookie:", s.cookie_header())
    s2 = ZhangwaSession.from_cookie_string(
        "clientType=9; acctype=qc; uin=o10001; appid=102061775; openid=OID; "
        "access_token=TOK; userId=u-123; accountType=5; tid=TID")
    print("Parsed:", s2.dump())


if __name__ == "__main__":
    logging.basicConfig(level=logging.DEBUG)
    asyncio.run(demo())
