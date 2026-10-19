#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
拉当前登录用户的游戏 ID

## 接口来源

com/tencent/qtl/module_account/game_role/b/a.java:5

    @Protocol(path = "/go/account/getallgameroles")
    public final class a extends BaseProtocol<AllRoleResult>
    protected String getProtocolBody() { return new JsonObject().toString(); }   // = "{}"

返回（com/.../game_role/data/AllRoleResult.java）：

    AllRoleResult {
        List<AllRoleData>   accGameRoles;    // 按账号分组
        List<RoleNumData>   gameRoleNum;     // 每个游戏有多少角色
        List<MainRoleInfo>  mainRoleList;    // ★ 主角色 —— 这里才有游戏 ID
    }

    MainRoleInfo {
        String gameId;        // ★ "角色名#TAG"，就是我们要的
        String roleName;
        String areaName;      // 大区
        String icon;
        int    level;
        String roleText;
        String game_role_id;  // 游戏内角色 ID
        ...
    }

## 这个脚本干嘛

用之前抓的 ct 换一张新 wt，然后调 getallgameroles，
**把原始响应原样打出来** —— 这样就知道 JSON 里字段到底是
main_role_list 还是 mainRoleList、game_id 还是 gameId，
不用去猜 Gson 的命名策略。
"""
from __future__ import annotations

import json
import pathlib
import sys
import urllib.error
import urllib.request

HOST = "https://app.mval.qq.com"
DUMP = pathlib.Path(__file__).parent / "_dump"

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def load_session() -> dict:
    for name in ("session_rolled.json", "session_fresh.json"):
        p = DUMP / name
        if p.exists():
            return json.loads(p.read_text(encoding="utf-8"))
    raise SystemExit("找不到 session 文件")


def build_cookie(s: dict) -> str:
    """顺序和大小写都要跟真机一致（服务端按原样解析）"""
    auth = s.get("auth_type", "wechat")
    if auth == "qq":
        appid, acctype, account_type = "102061775", "qc", "5"
    else:
        appid, acctype, account_type = "wxcbb49f1f39656c2a", "wx", "2"
    return (
        f"clientType=9; uin=o{s.get('uin','')}; appid={appid}; "
        f"acctype={acctype}; openid={s.get('openid','')}; "
        f"access_token={s.get('access_token','')}; "
        f"userId={s.get('user_id','')}; accountType={account_type}; "
        f"tid={s.get('tid','')}"
    )


def call(path: str, body: dict, s: dict, cookie: str | None = None) -> tuple[int, dict]:
    data = json.dumps(body).encode()
    req = urllib.request.Request(HOST + path, data=data, method="POST")
    req.add_header("Content-Type", "application/json; charset=utf-8")
    req.add_header("Cookie", cookie or build_cookie(s))
    req.add_header("User-Agent", "okhttp/4.9.2")
    try:
        with urllib.request.urlopen(req, timeout=25) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        raw = e.read().decode(errors="replace") if e.fp else ""
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"_raw": raw}


def main():
    s = load_session()
    print(f"用 session：user_id={s.get('user_id','?')} auth={s.get('auth_type','?')}")
    print(f"  uin={str(s.get('uin',''))[:14]}… ct={str(s.get('ct',''))[:24]}…\n")

    # ① 先换一张新 wt —— 抓包存下来的 wt 早过期了（寿命只有 30 分钟）
    print("[1] /go/auth/get_web_ticket  （刷新 wt）")
    st, resp = call("/go/auth/get_web_ticket",
                    {"ct": s.get("ct", ""), "user_id": s.get("user_id", ""),
                     "config_params": {"lang_type": 0}}, s, cookie=
                    "clientType=9; openid=null; access_token=null;")
    print(f"    HTTP {st}  result={resp.get('result')}  msg={resp.get('msg','')!r}")
    if resp.get("result") != 0:
        print(f"    完整响应：{json.dumps(resp, ensure_ascii=False)[:600]}")
        print("\n    ⚠️ wt 没换到，后面的调用大概率会 999999")
        return 1
    new_wt = (resp.get("data") or {}).get("wt", "")
    print(f"    新 wt = {new_wt[:24]}…（{len(new_wt)} 字符）")

    s2 = dict(s)
    s2["tid"] = new_wt
    cookie = build_cookie(s2)

    # ② 游戏角色列表 —— 这里才有游戏 ID
    print("\n[2] /go/account/getallgameroles   ★ 要的就是这个")
    st, resp = call("/go/account/getallgameroles", {}, s2, cookie=cookie)
    print(f"    HTTP {st}  result={resp.get('result')}  msg={resp.get('msg','')!r}")
    print("\n    原始响应（前 2500 字）：")
    print("    " + json.dumps(resp, ensure_ascii=False, indent=2)[:2500].replace("\n", "\n    "))

    out = DUMP / "game_roles.json"
    out.write_text(json.dumps(resp, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n已存 -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
