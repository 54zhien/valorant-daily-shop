/*
 * 直接抓 SHA-1 的**输入字符串**
 * ============================================================================
 *
 * jadx 反编译 c$1 失败（产出空文件），所以不读代码了，改成**问运行时**。
 *
 * 已知：
 *   · 签名计算点是 com.tencent.wglogin.authsuite.c$1.a(A:78)
 *   · wglogin 里唯一做 SHA-1 的工具是 com.tencent.wglogin.authsuite.util.f
 *     （f.a(String) -> SHA-1 十六进制）
 *
 * 那么只要 hook 这个工具类，**它收到的那个字符串就是要签名的原文**。
 * 拿到原文后，算法就不再是黑盒了 —— 看一眼就知道 ticket 怎么参与的。
 *
 * 同时挂上 MessageDigest，防止它绕过这个工具类自己算。
 */

'use strict';

var LOG = '/data/data/com.tencent.apps.valorant/files/qr_sha1.log';

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

Java.perform(function () {
    W('==================================================');
    W('SHA-1 输入抓取开始');

    // ① wglogin 自己的 SHA-1 工具
    try {
        var F = Java.use('com.tencent.wglogin.authsuite.util.f');
        var names = ['a'];
        var n = 0;
        names.forEach(function (mn) {
            if (!F[mn]) { return; }
            F[mn].overloads.forEach(function (ov) {
                var sig = ov.argumentTypes.map(function (t) { return t.className; }).join(',');
                ov.implementation = function () {
                    var args = Array.prototype.slice.call(arguments);
                    var out = ov.apply(this, args);
                    W('★ util.f.' + mn + '(' + sig + ')');
                    for (var i = 0; i < args.length; i++) {
                        var v = args[i];
                        if (v === null) { W('    arg' + i + ' = null'); continue; }
                        if (typeof v === 'string') {
                            W('    arg' + i + ' (String, len=' + v.length + ') = ' + v);
                        } else {
                            W('    arg' + i + ' = ' + v + ' (' + sig.split(',')[i] + ')');
                        }
                    }
                    W('    → 输出 ' + out);
                    return out;
                };
                n++;
            });
        });
        W('✅ 已 hook util.f 的 ' + n + ' 个重载');
    } catch (e) {
        W('⚠️ hook util.f 失败: ' + e);
    }

    // ② 兜底：有人在别处自己 new MessageDigest 也不会漏
    try {
        var MD = Java.use('java.security.MessageDigest');
        MD.digest.overload('[B').implementation = function (b) {
            var out = this.digest(b);
            try {
                var algo = String(this.getAlgorithm());
                if (algo === 'SHA-1' || algo === 'SHA1') {
                    var s = '';
                    if (b !== null) {
                        for (var i = 0; i < b.length; i++) {
                            var c = (b[i] + 256) % 256;
                            s += (c >= 32 && c < 127) ? String.fromCharCode(c) : '.';
                        }
                    }
                    W('★ MessageDigest(SHA-1).digest(byte[' + (b ? b.length : 0) + '])');
                    W('    原文(可见字符) = ' + s);
                }
            } catch (e) { }
            return out;
        };
        W('✅ 已 hook MessageDigest.digest');
    } catch (e) {
        W('⚠️ hook MessageDigest 失败: ' + e);
    }

    W('等触发扫码…');
    W('==================================================');
});
