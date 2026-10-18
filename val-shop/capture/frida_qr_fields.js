/*
 * 把 c$1 的字段和它调 auth() 时用的实参全 dump 出来
 * ============================================================================
 *
 * 背景：栈追踪给出签名计算点是
 *
 *     at com.tencent.mm.opensdk.diffdev.a.a.auth(Native Method)
 *     at com.tencent.wglogin.authsuite.c$1.a(A:78)      ← 这里
 *     at com.tencent.wglogin.authsuite.c$1.onSuccess(A:65)
 *
 * c$1 是 GetWXServerTicketProtocol 的回调，所以 ticket 一定在它的字段里。
 * jadx 没把 c$1 的类体反编译出来，所以直接问运行时：
 *   · 它有哪些字段、值是什么（找 ticket）
 *   · 它调用 auth(...) 时传了什么
 *
 * 拿到同一时刻的 ticket + signature 之后，就能离线验证
 * "signature 是不是 sha1(ticket + 参数)" —— 是的话整条路就通了。
 */

'use strict';

var LOG = '/data/data/com.tencent.apps.valorant/files/qr_fields.log';

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

function dumpFields(obj, label) {
    try {
        var cls = obj.getClass();
        var fields = cls.getDeclaredFields();
        W('  ---- ' + label + ' 的字段（' + cls.getName() + '，共 ' + fields.length + ' 个） ----');
        for (var i = 0; i < fields.length; i++) {
            var f = fields[i];
            try {
                f.setAccessible(true);
                var v = f.get(obj);
                var sv = (v === null) ? 'null' : String(v);
                // 长值截断显示，但长度报出来 —— 方便判断哪个是 ticket
                var shown = sv.length > 120 ? (sv.slice(0, 120) + '…') : sv;
                W('    ' + f.getName() + ' [' + f.getType().getName() + '] len=' + sv.length + ' = ' + shown);
            } catch (e) {
                W('    ' + f.getName() + ' 读取失败: ' + e);
            }
        }
    } catch (e) {
        W('  dumpFields 失败: ' + e);
    }
}

Java.perform(function () {
    W('==================================================');
    W('c$1 字段 dump 开始');

    try {
        var C1 = Java.use('com.tencent.wglogin.authsuite.c$1');

        // 先列出类结构
        try {
            var ms = C1.class.getDeclaredMethods();
            W('c$1 的方法（' + ms.length + ' 个）:');
            for (var i = 0; i < ms.length; i++) {
                var m = ms[i];
                var ps = m.getParameterTypes();
                var names = [];
                for (var j = 0; j < ps.length; j++) { names.push(ps[j].getName()); }
                W('    ' + m.getName() + '(' + names.join(', ') + ')');
            }
        } catch (e) { W('列方法失败: ' + e); }

        // hook 每个方法：进去之前 dump 一次字段
        var hooked = 0;
        C1.class.getDeclaredMethods().forEach(function (m) {
            var name = m.getName();
            try {
                var overloads = C1[name].overloads;
                overloads.forEach(function (ov) {
                    ov.implementation = function () {
                        var args = Array.prototype.slice.call(arguments);
                        W('★ c$1.' + name + ' 被调用，实参 ' + args.length + ' 个');
                        for (var k = 0; k < args.length; k++) {
                            var sv = (args[k] === null) ? 'null' : String(args[k]);
                            W('    arg' + k + ' len=' + sv.length + ' = '
                              + (sv.length > 200 ? sv.slice(0, 200) + '…' : sv));
                            // ★ 参数是对象的话，把它内部的字段也 dump 出来。
                            //   ticket 就在 GetWXServerTicketResult.ticket 里，
                            //   只看参数本身只能得到一个 @hash，看不到内容。
                            if (args[k] !== null && typeof args[k] === 'object') {
                                try {
                                    dumpFields(args[k], 'arg' + k);
                                } catch (e) { }
                            }
                        }
                        dumpFields(this, 'this');
                        return ov.apply(this, args);
                    };
                    hooked++;
                });
            } catch (e) {
                W('hook ' + name + ' 失败: ' + e);
            }
        });
        W('✅ 已 hook c$1 的 ' + hooked + ' 个方法重载');
    } catch (e) {
        W('❌ 找不到 c$1: ' + e);
    }

    // 同时把 auth() 挂上 —— 必须和上面的 c$1 在**同一次调用**里，
    // 才能把 ticket 和 signature 对上号。
    try {
        var AA = Java.use('com.tencent.mm.opensdk.diffdev.a.a');
        var n = 0;
        AA.auth.overloads.forEach(function (ov) {
            if (ov.argumentTypes.length !== 6) { return; }
            ov.implementation = function () {
                var a = Array.prototype.slice.call(arguments);
                W('★★★★ auth() 实参（和上面这次 ticket 是**同一次请求**）');
                var names = ['appid', 'scope', 'noncestr', 'timestamp', 'signature'];
                for (var i = 0; i < 5; i++) {
                    W('    ' + names[i] + ' = ' + a[i] + '   (len=' + String(a[i]).length + ')');
                }
                return ov.apply(this, a);
            };
            n++;
        });
        W('✅ 已 hook diffdev.a.a.auth（' + n + ' 个重载）');
    } catch (e) {
        W('❌ hook auth 失败: ' + e);
    }

    // 同时把 ticket 协议的回调也挂上 —— 协议层可能才是真正拿到 ticket 的地方
    try {
        var P = Java.use('com.tencent.wglogin.authsuite.protocol.GetWXServerTicketProtocol');
        W('GetWXServerTicketProtocol 已加载，父类 ' + P.class.getSuperclass().getName());
    } catch (e) {
        W('GetWXServerTicketProtocol 加载失败: ' + e);
    }

    W('等触发扫码…');
    W('==================================================');
});
