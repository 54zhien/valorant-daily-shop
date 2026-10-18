/*
 * 抓 QQ扫码 打开的网页地址
 * ============================================================================
 *
 * 静态分析结论：QQ扫码 = QQ互联 SDK 的 force-QR 模式
 *
 *     QuickLoginFirstActivity: intent.putExtra("KEY_FORCE_QR_LOGIN", true)
 *     AuthAgent:  if (forceQR) bundle.putString("style", "qr");
 *                 url = "https://openmobile.qq.com/oauth2.0/m_authorize?"
 *                       + HttpUtils.encodeUrl(bundle)
 *     → 塞进 TDialog（一个 WebView）
 *
 * 也就是说这是一条**纯网页**流程，不需要任何签名。比微信那条好做得多 ——
 * 我们只要在自己的 WKWebView 里加载同一个 URL 就行。
 *
 * 现在要做的就是把那个 URL 原样抓下来。挂三层：
 *   ① WebView.loadUrl          —— 最直接
 *   ② java.net.URL             —— 兜底（WebView 内部也会建 URL）
 *   ③ WebView 的 shouldOverrideUrlLoading 走不到，跳过
 */

'use strict';

var LOG = '/data/data/com.tencent.apps.valorant/files/qq_qr.log';

function now() {
    var d = new Date();
    function p(n, w) { return ('0'.repeat(w) + n).slice(-w); }
    return p(d.getHours(), 2) + ':' + p(d.getMinutes(), 2) + ':' + p(d.getSeconds(), 2)
         + '.' + p(d.getMilliseconds(), 3);
}

function W(line) {
    var s = '[' + now() + '] ' + line;
    console.log(s);
    try {
        var f = new File(LOG, 'a');
        f.write(s + '\n');
        f.flush();
        f.close();
    } catch (e) { }
}

/// 只关心和登录有关的 URL，别被一堆图片请求淹没
function interesting(u) {
    if (!u) { return false; }
    return u.indexOf('m_authorize') >= 0
        || u.indexOf('graph.qq.com') >= 0
        || u.indexOf('ptlogin2') >= 0
        || u.indexOf('openmobile.qq.com') >= 0
        || u.indexOf('xui.ptlogin') >= 0
        || u.indexOf('qrcode') >= 0
        || u.indexOf('check_sig') >= 0
        || u.indexOf('appid=') >= 0;
}

function dump(u, tag) {
    W('★★★ [' + tag + '] ' + u);
    // query 拆开逐条列，方便直接抄
    var q = u.split('?')[1];
    if (q) {
        q.split('&').forEach(function (kv) {
            var i = kv.indexOf('=');
            if (i < 0) { return; }
            W('      ' + kv.slice(0, i) + ' = ' + decodeURIComponent(kv.slice(i + 1)));
        });
    }
}

Java.perform(function () {
    W('==================================================');
    W('QQ扫码 URL 抓取开始');

    // ① WebView.loadUrl
    try {
        var WV = Java.use('android.webkit.WebView');
        ['loadUrl'].forEach(function (mn) {
            if (!WV[mn]) { return; }
            WV[mn].overloads.forEach(function (ov) {
                ov.implementation = function () {
                    var a = Array.prototype.slice.call(arguments);
                    var u = String(a[0] === null ? '' : a[0]);
                    if (u.length > 0) {
                        W('[WebView.loadUrl] len=' + u.length + '  ' + u.slice(0, 160));
                        if (interesting(u)) { dump(u, 'WebView.loadUrl'); }
                    }
                    return ov.apply(this, a);
                };
            });
        });
        W('✅ 已 hook WebView.loadUrl');
    } catch (e) {
        W('⚠️ hook WebView 失败: ' + e);
    }

    // ①b WebView 带 header 那个重载
    try {
        var WV2 = Java.use('android.webkit.WebView');
        if (WV2.loadUrl.overloads.length > 1) {
            W('   WebView.loadUrl 有 ' + WV2.loadUrl.overloads.length + ' 个重载');
        }
    } catch (e) { }

    // ② java.net.URL
    try {
        var URL = Java.use('java.net.URL');
        URL.$init.overload('java.lang.String').implementation = function (u) {
            try {
                if (interesting(String(u))) { dump(String(u), 'URL'); }
            } catch (e) { }
            return this.$init(u);
        };
        W('✅ 已 hook java.net.URL');
    } catch (e) {
        W('⚠️ hook java.net.URL 失败: ' + e);
    }

    // ③ AuthAgent 本身 —— 直接看它拼出来的 URL
    try {
        var AA = Java.use('com.tencent.connect.auth.AuthAgent');
        W('✅ 找到 AuthAgent（KEY_FORCE_QR_LOGIN 就在这个类里）');
    } catch (e) {
        W('⚠️ AuthAgent 没加载: ' + e);
    }

    W('等点「QQ扫码」…');
    W('==================================================');
});
