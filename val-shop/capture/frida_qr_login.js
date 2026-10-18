/*
 * 抓 qrconnect 的 signature
 * ============================================================================
 *
 * 目标：拿到掌瓦「扫码登录」请求里那个 signature 参数。
 *
 * 为什么值得抓：如果 signature 是客户端拿 ticket 算出来的，那我们就能自己
 * 实现整套扫码登录（AppSecret 是掌瓦服务器用的，客户端不需要）。
 *
 * 三层 hook，不管它走哪条路都能抓到：
 *
 *   ① com.tencent.mm.opensdk.diffdev.a.a.auth(...)
 *      —— 微信 SDK 扫码模块的入口，5 个 String 参数里就有 signature。
 *         这是最直接的：抓到就能看清 appid/scope/noncestr/timestamp/signature
 *         分别是什么。
 *
 *   ② java.net.URL 的构造器
 *      —— 兜底。只要有人拼出含 qrconnect 的 URL，这里就能截到完整 URL。
 *         不依赖具体 HTTP 库（HttpURLConnection / OkHttp / 自研都能截）。
 *
 *   ③ okhttp3.Request$Builder.build
 *      —— 再兜一层，万一它走的是 OkHttp 且 URL 是拼出来的。
 *
 * 用法：
 *   frida -U -f com.tencent.apps.valorant -l frida_qr_login.js
 * 或
 *   python frida_attach.py --script frida_qr_login.js
 *
 * 然后：App 里进「账号管理 → 添加账号 → 扫码登录」，日志会写文件。
 */

'use strict';

var LOG_PATH = '/data/data/com.tencent.apps.valorant/files/qr_capture.log';

function now() {
    var d = new Date();
    function p(n, w) { return ('0'.repeat(w) + n).slice(-w); }
    return p(d.getHours(), 2) + ':' + p(d.getMinutes(), 2) + ':' + p(d.getSeconds(), 2)
         + '.' + p(d.getMilliseconds(), 3);
}

function write(line) {
    var s = '[' + now() + '] ' + line;
    console.log(s);
    // 每次都重新开文件再关 —— 长驻脚本里拿着一个 File 句柄很容易失效，
    // 而且失效是静默的（catch 吞掉了），表现就是「hook 明明装好了却一个字都没抓到」。
    try {
        var f = new File(LOG_PATH, 'a');
        f.write(s + '\n');
        f.flush();
        f.close();
    } catch (e) {
        // 写不进去就只能靠 console 了
    }
}

function dumpUrl(u, tag) {
    write('★★★ ' + tag + ' 命中 qrconnect');
    write('    ' + u);
    var q = u.split('?')[1];
    if (q) {
        q.split('&').forEach(function (kv) {
            var i = kv.indexOf('=');
            var k = i < 0 ? kv : kv.slice(0, i);
            var v = i < 0 ? '' : kv.slice(i + 1);
            write('      ' + k + ' = ' + v + '   (len=' + v.length + ')');
        });
    }
    return u;
}

// --- 别被反调试搞掉 ------------------------------------------------------

var hooked = { auth: false, url: false, okhttp: false };
var TICKET = '';

Java.perform(function () {

    // ① 微信 SDK 扫码模块入口 ----------------------------------------------
    try {
        var Cls = Java.use('com.tencent.mm.opensdk.diffdev.a.a');
        var overloads = Cls.auth.overloads;
        overloads.forEach(function (ov) {
            var argc = ov.argumentTypes.length;
            // 6 参那个才是 (5×String, OAuthListener)
            if (argc !== 6) { return; }
            ov.implementation = function () {
                var args = Array.prototype.slice.call(arguments);
                write('★ IDiffDevOAuth.auth 被调用');
                for (var i = 0; i < 5; i++) {
                    var v = args[i];
                    write('    arg' + i + ' (len=' + (v ? String(v).length : 0) + ') = ' + v);
                }

                // ★ 关键：打出调用栈。
                // 静态分析找不到 auth() 的调用方（jadx 在差异包外一个引用都没有），
                // 但运行时一定知道是谁调的。栈里那个「非 a.a / 非 Java 框架」的帧
                // 就是算 signature 的地方。
                try {
                    var Throwable = Java.use('java.lang.Throwable');
                    var Log = Java.use('android.util.Log');
                    var stack = Log.getStackTraceString(Throwable.$new());
                    write('    ---- 调用栈 ----');
                    stack.split('\n').slice(0, 30).forEach(function (line) {
                        if (line.trim().length > 0) {
                            write('      ' + line.trim());
                        }
                    });
                    write('    ----------------');
                } catch (e) {
                    write('    ⚠️ 打栈失败: ' + e);
                }

                return ov.apply(this, args);
            };
            hooked.auth = true;
        });
        if (hooked.auth) {
            write('✅ 已 hook diffdev.a.a.auth');
        } else {
            write('⚠️ diffdev.a.a.auth 没有 6 参的重载');
        }
    } catch (e) {
        write('⚠️ hook diffdev 失败: ' + e);
    }

    // ①b 掌瓦自己的 ticket 链路 ---------------------------------------------
    //   loginWXByQRCode 的流程（authsuite/c.java）：
    //       GetWXServerTicketProtocol.post()  -> {ticket}      ← c$1 回调
    //       c.a(ticket, cb)                   -> c$2 持有 ticket
    //       authsuite.d.a(c$2, f)             -> 进入扫码
    //   所以 ticket 一定是这个流程里的关键材料，把它的值抓下来，
    //   才能验证 signature 是不是 sha1(ticket + 参数)。
    try {
        var C = Java.use('com.tencent.wglogin.authsuite.c');
        var n1 = 0;
        C.a.overloads.forEach(function (ov) {
            var ts = ov.argumentTypes.map(function (t) { return t.className; });
            if (ts.length !== 2 || ts[0] !== 'java.lang.String') { return; }
            ov.implementation = function () {
                var args = Array.prototype.slice.call(arguments);
                write('★ authsuite.c.a 收到 ticket（len=' + String(args[0]).length + '）');
                write('    ticket = ' + args[0]);
                TICKET = String(args[0]);
                return ov.apply(this, args);
            };
            n1++;
        });
        write(n1 ? ('✅ 已 hook authsuite.c.a（' + n1 + ' 个重载）') : '⚠️ authsuite.c.a 没找到合适的重载');
    } catch (e) {
        write('⚠️ hook authsuite.c 失败: ' + e);
    }

    // ①c 掌瓦侧的 ticket 协议 —— 直接看返回体里有没有 ticket
    try {
        var P = Java.use('com.tencent.wglogin.authsuite.protocol.GetWXServerTicketProtocol');
        write('✅ 找到 GetWXServerTicketProtocol（协议路径 /go/auth/get_sdk_ticket）');
    } catch (e) {
        write('⚠️ 没找到 GetWXServerTicketProtocol: ' + e);
    }

    // ② java.net.URL 构造器（兜底，不挑 HTTP 库）---------------------------
    //    微信 SDK 的 diffdev.a.e 就是这么发请求的：
    //        java.net.URL r3 = new java.net.URL(r9);
    //        java.net.URLConnection r9 = r3.openConnection();
    //    所以把 URL 的所有构造重载都挂上，一个都别漏。
    try {
        var URL = Java.use('java.net.URL');
        var sigs = [
            ['java.lang.String'],
            ['java.lang.String', 'java.lang.String', 'java.lang.String'],
            ['java.lang.String', 'java.lang.String', 'int', 'java.lang.String'],
            ['java.net.URL', 'java.lang.String'],
            ['java.net.URL', 'java.lang.String', 'java.net.URLStreamHandler'],
        ];
        var done = 0;
        sigs.forEach(function (sig) {
            if (sig.length >= 3 && sig[0] === 'java.net.URL') { return; }   // 那几种不常用，跳过
            try {
                var ov = URL.$init.overload.apply(URL.$init, sig);
                ov.implementation = function () {
                    var args = Array.prototype.slice.call(arguments);
                    var joined = args.map(function (a) { return String(a); }).join('|');
                    if (joined.indexOf('qrconnect') >= 0) {
                        dumpUrl(joined.replace(/\|/g, ''), 'URL(' + sig.length + '参)');
                        hooked.url = true;
                    }
                    return ov.apply(this, args);
                };
                done++;
            } catch (e) { /* 没这个重载 */ }
        });
        write('✅ 已 hook java.net.URL（' + done + ' 个构造重载）');
    } catch (e) {
        write('⚠️ hook java.net.URL 失败: ' + e);
    }

    // ②b HttpURLConnection —— 就算 URL 那层漏了，连接总能截到
    try {
        var HUC = Java.use('java.net.HttpURLConnection');
        HUC.connect.implementation = function () {
            try {
                var u = String(this.getURL().toString());
                if (u.indexOf('weixin.qq.com') >= 0 || u.indexOf('qrconnect') >= 0) {
                    dumpUrl(u, 'HttpURLConnection');
                    hooked.url = true;
                }
            } catch (e) { }
            return this.connect();
        };
        write('✅ 已 hook HttpURLConnection.connect');
    } catch (e) {
        write('⚠️ hook HttpURLConnection 失败: ' + e);
    }

    // ③ OkHttp 兜底 ---------------------------------------------------------
    try {
        var Builder = Java.use('okhttp3.Request$Builder');
        Builder.build.implementation = function () {
            var req = this.build();
            try {
                var u = String(req.url().toString());
                if (u.indexOf('qrconnect') >= 0) {
                    write('★★★ OkHttp 命中 qrconnect');
                    write('    ' + u);
                    hooked.okhttp = true;
                }
            } catch (e) { }
            return req;
        };
        write('✅ 已 hook okhttp3.Request$Builder.build');
    } catch (e) {
        write('⚠️ hook OkHttp 失败（可能没加载）: ' + e);
    }

    write('--------------------------------------------------');
    write('等用户点「扫码登录」…');
    write('hook 状态: auth=' + hooked.auth + ' url=' + hooked.url + ' okhttp=' + hooked.okhttp);
});

// 每隔一会儿把 hook 状态落盘，方便判断有没有生效
setInterval(function () {
    Java.perform(function () {
        try {
            var f = new File(LOG_PATH + '.status', 'w');
            f.write(JSON.stringify(hooked) + '\n');
            f.flush();
            f.close();
        } catch (e) { }
    });
}, 5000);
