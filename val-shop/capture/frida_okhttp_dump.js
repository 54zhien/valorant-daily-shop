/*
 * 掌瓦（com.tencent.apps.valorant）OkHttp 全量抓包
 * -------------------------------------------------
 * 目的：抓出「每日商店」的真实接口路径 / 参数 / Cookie。
 * 原理：掌瓦的业务请求全部走 OkHttp（见 com.tencent.base.http.c），
 *       直接 hook okhttp3.Request$Builder.build() 和 BridgeInterceptor.intercept()，
 *       拿到请求 + 响应，绕开 TL S 证书固定与自研加密，不需要 root（frida 注入即可）。
 *
 * 用法：
 *   1) 手机 root 或使用 frida-server；或用 objection / 已 root 模拟器
 *   2) frida -U -f com.tencent.apps.valorant -l frida_okhttp_dump.js --no-pause
 *      或   frida -U -n 掌上无畏契约 -l frida_okhttp_dump.js
 *   3) 在 App 里打开「每日商店」，然后把关键行复制出来
 *   4) 想只抓目标域名：修改下面 FILTER 正则
 *
 * 输出：
 *   console                                 实时打印
 *   /data/local/tmp/mval_capture.log        每条一行 JSON（请求 + 响应 + Cookie）
 *   /data/local/tmp/mval_session.json       完整登录态（user_id/ct/openid/uin/access_token/tid）
 *                                           ← 这个文件就是 iOS App 需要的全部东西
 */

'use strict';

// 只记录命中这里的 URL（留空 = 全量）
const FILTER = /mval\.qq\.com|\/go\/|store|shop|commodity|goods/i;
// 是否打印响应体（可能较大）
const LOG_BODY = true;
// 响应体最大字符数
const MAX_BODY = 20000;

// ---------------------------------------------------------------------------
// 输出路径
//
// ⚠️ 脚本是跑在**目标 app 进程**里的（uid 是 u0_a47 这种），不是 root。
//    `/data/local/tmp` 的权限是 drwxrwx--x shell shell —— 普通 app 只有执行位，
//    没有写权限，直接写会拿到 EACCES。
//    所以第一顺位是 app 自己的 files 目录（owner 就是它自己，一定能写），
//    pull 的时候用 root 读出来即可。
// ---------------------------------------------------------------------------
const OUT_CANDIDATES = [
    '/data/data/com.tencent.apps.valorant/files/mval_capture.log',
    '/data/user/0/com.tencent.apps.valorant/files/mval_capture.log',
    '/sdcard/Android/data/com.tencent.apps.valorant/files/mval_capture.log',
    '/data/local/tmp/mval_capture.log',
];

let OUT = OUT_CANDIDATES[0];

function now() {
    return new Date().toISOString();
}

function safe(fn, dflt) {
    try {
        const v = fn();
        return v === undefined ? dflt : v;
    } catch (e) {
        return dflt;
    }
}

function toStr(ptr) {
    try {
        if (ptr === null || ptr === undefined) return null;
        return ptr.toString();
    } catch (e) {
        return null;
    }
}

/** 读 OkHttp RequestBody / ResponseBody 为字符串 */
function bodyToString(body) {
    if (!body || body === null) return null;
    // 排除一次性 body
    try {
        if (body.isOneShot && body.isOneShot()) return '<one-shot body>';
    } catch (e) { /* ignore */ }

    // 优先 contentType 判断文本
    try {
        const ct = body.contentType ? body.contentType() : null;
        if (ct && ct.toString().indexOf('octet-stream') >= 0) return '<binary>';
    } catch (e) { /* ignore */ }

    try {
        const Buffer = Java.use('okio.Buffer');
        const buf = Buffer.$new();
        body.writeTo(buf);
        const s = buf.readUtf8();
        buf.clear();
        if (s.length > MAX_BODY) return s.substring(0, MAX_BODY) + '...<truncated>';
        return s;
    } catch (e) {
        return '<unreadable body: ' + e + '>';
    }
}

let file = null;
for (const candidate of OUT_CANDIDATES) {
    try {
        file = new File(candidate, 'a');
        file.write('=== session start ' + now() + ' ===\n');
        file.flush();
        OUT = candidate;
        console.log('[+] 抓到的东西写到 ' + OUT);
        break;
    } catch (e) {
        console.log('[!] 写不了 ' + candidate + ' : ' + e);
        file = null;
    }
}
if (!file) {
    console.log('[!] 一个都写不了，只往 stdout 打。检查 app 的 files 目录权限。');
}

function emit(obj) {
    const line = JSON.stringify(obj);
    console.log(line);
    if (file) {
        try {
            file.write(line + '\n');
            file.flush();
        } catch (e) { /* ignore */ }
    }
}

// ---------------------------------------------------------------------------
// 1) 请求侧：hook okhttp3.Request$Builder.build()
// ---------------------------------------------------------------------------
function hookRequests() {
    let RequestBuilder;
    try {
        RequestBuilder = Java.use('okhttp3.Request$Builder');
    } catch (e) {
        console.log('[!] okhttp3.Request$Builder not found: ' + e);
        return;
    }

    RequestBuilder.build.implementation = function () {
        const req = this.build();
        try {
            const url = safe(() => req.url().toString(), '');
            if (!FILTER.test(url)) return req;

            const headers = {};
            const hs = req.headers();
            for (let i = 0; i < hs.size(); i++) {
                headers[hs.name(i)] = hs.value(i);
            }

            const rec = {
                t: now(),
                dir: 'REQ',
                method: safe(() => req.method(), ''),
                url: url,
                headers: headers,
                cookie: headers['Cookie'] || headers['cookie'] || null,
                body: LOG_BODY ? safe(() => bodyToString(req.body()), null) : null,
                tag: safe(() => req.tag() ? req.tag().toString() : null, null)
            };
            emit(rec);
        } catch (e) {
            console.log('[!] request hook error: ' + e);
        }
        return req;
    };
    console.log('[*] hooked okhttp3.Request$Builder.build');
}

// ---------------------------------------------------------------------------
// 2) 响应侧：hook okhttp3.internal.http.BridgeInterceptor.intercept()
//    peekBody() 不会消费原 body，安全
// ---------------------------------------------------------------------------
function hookResponses() {
    let Bridge;
    try {
        Bridge = Java.use('okhttp3.internal.http.BridgeInterceptor');
    } catch (e) {
        console.log('[!] BridgeInterceptor not found: ' + e);
        return;
    }

    Bridge.intercept.implementation = function (chain) {
        const resp = this.intercept(chain);

        try {
            const req = chain.request();
            const url = safe(() => req.url().toString(), '');
            const method = safe(() => req.method(), '');
            if (!FILTER.test(url)) return resp;

            let code = -1;
            try { code = resp.code(); } catch (e) { /* ignore */ }

            let text = null;
            if (LOG_BODY) {
                // App 用的是 okhttp/4.9.2（Kotlin）。
                // 3.x 的 `BufferSource.buffer()` 在 4.x 变成了属性 `getBuffer()`，
                // 所以不要再走 buffer()/clone()/readUtf8() 那套。
                // peekBody() 返回的是内存副本，直接 .string() 读它不会消费真实流。
                try {
                    const body = resp.body();
                    const ct = safe(() => body.contentType() ? body.contentType().toString() : '', '');
                    const len = safe(() => body.contentLength(), -1);

                    if (len === 0) {
                        text = '';
                    } else if (ct && !/json|text|xml|urlencoded|javascript|plain/i.test(ct)) {
                        text = '<' + ct + (len > 0 ? ', ' + len + 'B' : '') + '>';
                    } else if (len > 2 * 1024 * 1024) {
                        text = '<too large: ' + len + ' bytes>';
                    } else {
                        const peeked = resp.peekBody(1024 * 1024);
                        text = peeked.string();
                        if (text && text.length > MAX_BODY) {
                            text = text.substring(0, MAX_BODY) + '...<truncated>';
                        }
                    }
                } catch (e) {
                    text = '<peek failed: ' + e + '>';
                }
            }

            emit({
                t: now(),
                dir: 'RESP',
                method: method,
                url: url,
                code: code,
                body: text
            });
        } catch (e) {
            console.log('[!] response hook error: ' + e);
        }
        return resp;
    };
    console.log('[*] hooked okhttp3.internal.http.BridgeInterceptor.intercept');
}

// ---------------------------------------------------------------------------
// 3) 兜底：把 CookieHelper / AppContext 的关键字段也打出来
//    （对应分析报告 §1.5，能直接确认 Cookie 拼装结果）
// ---------------------------------------------------------------------------
function hookCookieHelper() {
    try {
        const CookieHelper = Java.use('com.tencent.container.c.a.a');
        CookieHelper.a.overload('java.lang.String').implementation = function (host) {
            const list = this.a(host);
            try {
                const arr = [];
                for (let i = 0; i < list.size(); i++) {
                    const kv = list.get(i);
                    arr.push(kv[0] + '=' + kv[1]);
                }
                console.log('[COOKIE] host=' + host + '  ' + arr.join('; '));
            } catch (e) { /* ignore */ }
            return list;
        };
        console.log('[*] hooked CookieHelper.a(String)');
    } catch (e) {
        console.log('[i] CookieHelper not hooked: ' + e);
    }
}

function hookAppContext() {
    try {
        const Ctx = Java.use('com.tencent.container.app.AppContext');
        // 和日志同目录：app 自己的 files 目录（app uid 有写权限）
        const SESSION = OUT.replace(/mval_capture\.log$/, 'mval_session.json');

        // AppContext.a(user_id, ct, authType, openid, uin, access_token, tid)
        // —— 这就是完整登录态，抓到它 iOS 端就能自刷新（见 README · iOS 路线）
        Ctx.a.overload('java.lang.String', 'java.lang.String', 'int',
                        'java.lang.String', 'long', 'java.lang.String',
                        'java.lang.String').implementation = function (userId, ct, authType,
                                                                     openid, uin, token, tid) {
            const rec = {
                t: now(),
                kind: 'SESSION',
                user_id: userId,
                ct: ct,
                auth_type: authType,
                openid: openid,
                uin: uin,
                access_token: token,
                tid: tid,
            };
            emit(rec);
            try {
                const f = new File(SESSION, 'w');
                f.write(JSON.stringify(rec, null, 2));
                f.flush();
                f.close();
                console.log('[SESSION] 已写入 ' + SESSION + '（把它交给 iOS App 即可，无需再登录）');
            } catch (e) {
                console.log('[!] 写 session 文件失败: ' + e);
            }
            return this.a(userId, ct, authType, openid, uin, token, tid);
        };

        // AppContext.a(String) —— 刷新 wt 时被调用；Cookie 里的 tid 就是它
        Ctx.a.overload('java.lang.String').implementation = function (wt) {
            console.log('[SESSION] tid(=wt) 更新: ' + wt);
            return this.a(wt);
        };

        console.log('[*] hooked AppContext.a(...)  → 完整登录态 + tid');
    } catch (e) {
        console.log('[i] AppContext not hooked: ' + e);
    }
}

// ---------------------------------------------------------------------------
Java.perform(function () {
    console.log('[*] === frida okhttp dump for 掌瓦 ===');
    hookRequests();
    hookResponses();
    hookCookieHelper();
    hookAppContext();
    console.log('[*] ready. 现在去 App 里点开「每日商店」，然后看日志。');
});
