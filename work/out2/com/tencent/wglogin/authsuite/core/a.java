package com.tencent.wglogin.authsuite.core;

/* JADX INFO: compiled from: A */
/* JADX INFO: loaded from: D:\DSHDev\Reverse\Valorant App\work\apk\classes5.dex */
public class a {
    private com.tencent.wglogin.authsuite.core.c a;
    private java.lang.String b;
    private java.util.List<com.tencent.wglogin.authsuite.core.Account> c;
    private com.tencent.wglogin.authsuite.core.b d;
    private android.os.Handler e;





    /* JADX INFO: renamed from: com.tencent.wglogin.authsuite.core.a$a, reason: collision with other inner class name */
    /* JADX INFO: compiled from: A */
    private static class C0091a {
        private static com.tencent.wglogin.authsuite.core.a a;

        static {
                com.tencent.wglogin.authsuite.core.a r0 = new com.tencent.wglogin.authsuite.core.a
                r1 = 0
                r0.<init>(r1)
                com.tencent.wglogin.authsuite.core.a.C0091a.a = r0
                return
        }

        static /* synthetic */ com.tencent.wglogin.authsuite.core.a a() {
                com.tencent.wglogin.authsuite.core.a r0 = com.tencent.wglogin.authsuite.core.a.C0091a.a
                return r0
        }
    }

    private a() {
            r2 = this;
            r2.<init>()
            com.tencent.wglogin.authsuite.core.a$1 r0 = new com.tencent.wglogin.authsuite.core.a$1
            android.os.Looper r1 = android.os.Looper.getMainLooper()
            r0.<init>(r2, r1)
            r2.e = r0
            return
    }

    /* synthetic */ a(com.tencent.wglogin.authsuite.core.a.AnonymousClass1 r1) {
            r0 = this;
            r0.<init>()
            return
    }

    public static com.tencent.wglogin.authsuite.core.a a() {
            com.tencent.wglogin.authsuite.core.a r0 = com.tencent.wglogin.authsuite.core.a.C0091a.a()
            return r0
    }

    static /* synthetic */ void a(com.tencent.wglogin.authsuite.core.a r0) {
            r0.j()
            return
    }

    static /* synthetic */ void b(com.tencent.wglogin.authsuite.core.a r0) {
            r0.k()
            return
    }

    static /* synthetic */ android.os.Handler c(com.tencent.wglogin.authsuite.core.a r0) {
            android.os.Handler r0 = r0.e
            return r0
    }

    private void j() {
            r2 = this;
            java.lang.String r0 = "ZMLogin.Session"
            java.lang.String r1 = "定时刷新WebTicket票据"
            com.tencent.common.log.a.c(r0, r1)
            com.tencent.wglogin.authsuite.core.a$2 r0 = new com.tencent.wglogin.authsuite.core.a$2
            r0.<init>(r2)
            com.tencent.wglogin.authsuite.d.a(r0)
            return
    }

    private void k() {
            r5 = this;
            java.lang.String r0 = "ZMLogin.Session"
            java.lang.String r1 = "定时刷新SSO票据"
            com.tencent.common.log.a.c(r0, r1)
            com.tencent.wglogin.authsuite.core.b r1 = com.tencent.wglogin.authsuite.d.a()
            if (r1 != 0) goto Le
            return
        Le:
            java.lang.StringBuilder r2 = new java.lang.StringBuilder
            r2.<init>()
            java.lang.String r3 = "定时刷新SSO票据. type = "
            r2.append(r3)
            com.tencent.wglogin.datastruct.SsoAuthType r3 = r1.d()
            r2.append(r3)
            java.lang.String r3 = " , account = "
            r2.append(r3)
            java.lang.String r3 = r1.f()
            r2.append(r3)
            java.lang.String r2 = r2.toString()
            com.tencent.common.log.a.c(r0, r2)
            com.tencent.wglogin.datastruct.SsoAuthType r2 = r1.d()
            com.tencent.wglogin.datastruct.SsoAuthType r3 = com.tencent.wglogin.datastruct.SsoAuthType.WX
            if (r2 != r3) goto L63
            boolean r2 = com.tencent.container.app.AppContext.b()
            if (r2 == 0) goto L5d
            java.lang.String r2 = "微信票据过期，准备刷新。"
            com.tencent.common.log.a.c(r0, r2)
            com.tencent.wglogin.authsuite.protocol.a r0 = new com.tencent.wglogin.authsuite.protocol.a
            java.lang.String r2 = r1.i()
            java.lang.String r3 = r1.f()
            java.lang.String r4 = "wx"
            r0.<init>(r2, r3, r4)
            com.tencent.wglogin.authsuite.core.a$3 r2 = new com.tencent.wglogin.authsuite.core.a$3
            r2.<init>(r5, r1)
            r0.post(r2)
            goto L93
        L5d:
            java.lang.String r1 = "微信票据没有过期，不用刷新。 "
            com.tencent.common.log.a.c(r0, r1)
            goto L93
        L63:
            com.tencent.wglogin.datastruct.SsoAuthType r2 = r1.d()
            com.tencent.wglogin.datastruct.SsoAuthType r3 = com.tencent.wglogin.datastruct.SsoAuthType.OPEN_QQ
            if (r2 != r3) goto L93
            boolean r2 = com.tencent.container.app.AppContext.b()
            if (r2 == 0) goto L8e
            java.lang.String r2 = "QQ互联票据过期，准备刷新。"
            com.tencent.common.log.a.c(r0, r2)
            com.tencent.wglogin.authsuite.protocol.a r0 = new com.tencent.wglogin.authsuite.protocol.a
            java.lang.String r2 = r1.i()
            java.lang.String r3 = r1.f()
            java.lang.String r4 = "qc"
            r0.<init>(r2, r3, r4)
            com.tencent.wglogin.authsuite.core.a$4 r2 = new com.tencent.wglogin.authsuite.core.a$4
            r2.<init>(r5, r1)
            r0.post(r2)
            goto L93
        L8e:
            java.lang.String r1 = "QQ互联票据没有过期，不用刷新。 "
            com.tencent.common.log.a.c(r0, r1)
        L93:
            return
    }

    public void a(com.tencent.wglogin.authsuite.core.c r1) {
            r0 = this;
            r0.a = r1
            return
    }

    public void a(com.tencent.wglogin.authsuite.protocol.RefreshClientTicketProtocol.Result r20) {
            r19 = this;
            r0 = r19
            r1 = r20
            com.tencent.wglogin.authsuite.protocol.RefreshClientTicketProtocol$Result$RefreshCTInfo r2 = r1.ct_info
            java.lang.String r2 = r2.user_id
            com.tencent.wglogin.authsuite.protocol.RefreshClientTicketProtocol$Result$RefreshCTInfo r3 = r1.ct_info
            java.lang.String r3 = r3.openid
            com.tencent.wglogin.authsuite.protocol.RefreshClientTicketProtocol$Result$RefreshCTInfo r4 = r1.ct_info
            java.lang.String r4 = r4.ct
            com.tencent.wglogin.authsuite.protocol.RefreshClientTicketProtocol$Result$RefreshCTInfo r5 = r1.ct_info
            java.lang.String r5 = r5.wt
            com.tencent.wglogin.authsuite.protocol.RefreshClientTicketProtocol$Result$RefreshCTInfo r6 = r1.ct_info
            java.lang.String r6 = r6.login_uuid
            com.tencent.wglogin.authsuite.protocol.RefreshClientTicketProtocol$Result$RefreshCTInfo r7 = r1.ct_info
            long r7 = r7.uin
            com.tencent.wglogin.authsuite.protocol.RefreshClientTicketProtocol$Result$RefreshCTInfo r9 = r1.ct_info
            int r9 = r9.is_new_user
            r10 = 1
            if (r9 != r10) goto L25
            r9 = 1
            goto L26
        L25:
            r9 = 0
        L26:
            java.lang.StringBuilder r11 = new java.lang.StringBuilder
            r11.<init>()
            java.lang.String r12 = "刷新CT票据成功, userId = "
            r11.append(r12)
            r11.append(r2)
            java.lang.String r11 = r11.toString()
            java.lang.String r12 = "ZMLogin.Session"
            com.tencent.common.log.a.c(r12, r11)
            java.lang.StringBuilder r11 = new java.lang.StringBuilder
            r11.<init>()
            java.lang.String r13 = "刷新CT票据成功, login userId = "
            r11.append(r13)
            r11.append(r6)
            java.lang.String r11 = r11.toString()
            com.tencent.common.log.a.c(r12, r11)
            java.lang.StringBuilder r11 = new java.lang.StringBuilder
            r11.<init>()
            java.lang.String r13 = "刷新CT票据成功, ct = "
            r11.append(r13)
            r11.append(r4)
            java.lang.String r11 = r11.toString()
            com.tencent.common.log.a.c(r12, r11)
            java.lang.StringBuilder r11 = new java.lang.StringBuilder
            r11.<init>()
            java.lang.String r13 = "刷新CT票据成功, wt = "
            r11.append(r13)
            r11.append(r5)
            java.lang.String r11 = r11.toString()
            com.tencent.common.log.a.c(r12, r11)
            com.tencent.wglogin.authsuite.core.b r11 = r0.d
            if (r11 == 0) goto L12c
            java.lang.String r11 = r11.b()
            if (r11 == 0) goto L12c
            com.tencent.wglogin.authsuite.core.b r11 = r0.d
            java.lang.String r11 = r11.b()
            boolean r11 = r11.equals(r2)
            if (r11 == 0) goto L12c
            com.tencent.wglogin.authsuite.core.b r11 = r0.d
            r11.a(r2)
            com.tencent.wglogin.authsuite.core.b r2 = r0.d
            r2.b(r3)
            com.tencent.wglogin.authsuite.core.b r2 = r0.d
            r2.d(r4)
            com.tencent.wglogin.authsuite.core.b r2 = r0.d
            r2.a(r9)
            com.tencent.wglogin.authsuite.core.b r2 = r0.d
            r2.e(r5)
            com.tencent.wglogin.authsuite.core.b r2 = r0.d
            r2.f(r6)
            com.tencent.wglogin.authsuite.core.b r2 = r0.d
            r2.a(r7)
            com.tencent.wglogin.authsuite.core.b r2 = r0.d
            com.tencent.wglogin.authsuite.util.b.a(r2)
            java.util.List<com.tencent.wglogin.authsuite.core.Account> r2 = r1.bind_info
            boolean r2 = com.blankj.utilcode.util.t.a(r2)
            if (r2 == 0) goto Lc6
            java.util.ArrayList r2 = new java.util.ArrayList
            r2.<init>()
            r0.c = r2
            goto Lcf
        Lc6:
            java.util.ArrayList r2 = new java.util.ArrayList
            java.util.List<com.tencent.wglogin.authsuite.core.Account> r3 = r1.bind_info
            r2.<init>(r3)
            r0.c = r2
        Lcf:
            com.tencent.wglogin.authsuite.core.b r2 = r0.d
            java.lang.String r11 = r2.b()
            com.tencent.wglogin.authsuite.core.b r2 = r0.d
            java.lang.String r12 = r2.c()
            com.tencent.wglogin.authsuite.core.b r2 = r0.d
            com.tencent.wglogin.datastruct.SsoAuthType r2 = r2.d()
            int r13 = r2.getCode()
            com.tencent.wglogin.authsuite.core.b r2 = r0.d
            java.lang.String r14 = r2.f()
            com.tencent.wglogin.authsuite.core.b r2 = r0.d
            long r15 = r2.a()
            com.tencent.wglogin.authsuite.core.b r2 = r0.d
            java.lang.String r17 = r2.e()
            com.tencent.wglogin.authsuite.core.b r2 = r0.d
            java.lang.String r18 = r2.h()
            com.tencent.container.app.AppContext.a(r11, r12, r13, r14, r15, r17, r18)
            com.tencent.wglogin.authsuite.core.b r2 = r0.d
            java.lang.String r2 = r2.h()
            com.tencent.container.app.AppContext.a(r2)
            com.tencent.wglogin.authsuite.core.c r2 = r0.a
            r2.b()
            android.os.Handler r2 = r0.e
            r3 = 2
            r2.removeMessages(r3)
            android.os.Handler r2 = r0.e
            r4 = 1000(0x3e8, double:4.94E-321)
            r2.sendEmptyMessageDelayed(r3, r4)
            android.os.Handler r2 = r0.e
            r2.removeMessages(r10)
            android.os.Handler r2 = r0.e
            com.tencent.wglogin.authsuite.protocol.RefreshClientTicketProtocol$Result$RefreshCTInfo r1 = r1.ct_info
            int r1 = r1.refresh_wt_span
            int r1 = r1 * 1000
            long r3 = (long) r1
            r2.sendEmptyMessageDelayed(r10, r3)
        L12c:
            return
    }

    public void a(com.tencent.wglogin.datastruct.SsoAuthType r13, com.tencent.wglogin.authsuite.protocol.LoginResult r14) {
            r12 = this;
            if (r14 == 0) goto Lf0
            com.tencent.wglogin.authsuite.protocol.LoginResult$LoginResultInfo r0 = r14.login_info
            java.lang.String r1 = r0.user_id
            com.tencent.wglogin.authsuite.protocol.LoginResult$LoginResultInfo r0 = r14.login_info
            java.lang.String r2 = r0.openid
            com.tencent.wglogin.authsuite.protocol.LoginResult$LoginResultInfo r0 = r14.login_info
            java.lang.String r4 = r0.third_openid
            com.tencent.wglogin.authsuite.protocol.LoginResult$LoginResultInfo r0 = r14.login_info
            java.lang.String r7 = r0.ct
            com.tencent.wglogin.authsuite.protocol.LoginResult$LoginResultInfo r0 = r14.login_info
            java.lang.String r8 = r0.wt
            com.tencent.wglogin.authsuite.protocol.LoginResult$LoginResultInfo r0 = r14.login_info
            java.lang.String r0 = r0.login_uuid
            com.tencent.wglogin.authsuite.protocol.LoginResult$LoginResultInfo r3 = r14.login_info
            long r5 = r3.uin
            com.tencent.wglogin.authsuite.protocol.LoginResult$LoginResultInfo r3 = r14.login_info
            int r3 = r3.is_new_user
            r9 = 1
            if (r3 != r9) goto L27
            r3 = 1
            goto L28
        L27:
            r3 = 0
        L28:
            java.lang.StringBuilder r10 = new java.lang.StringBuilder
            r10.<init>()
            java.lang.String r11 = "onZMAuthSuccess, userId = "
            r10.append(r11)
            r10.append(r1)
            java.lang.String r11 = " openId = "
            r10.append(r11)
            r10.append(r2)
            java.lang.String r11 = " loginUuid = "
            r10.append(r11)
            r10.append(r0)
            java.lang.String r11 = " token = "
            r10.append(r11)
            r10.append(r7)
            java.lang.String r11 = " ssoOpenId = "
            r10.append(r11)
            r10.append(r4)
            java.lang.String r11 = ", webToken="
            r10.append(r11)
            r10.append(r8)
            java.lang.String r11 = " isNewUser = "
            r10.append(r11)
            r10.append(r3)
            java.lang.String r10 = r10.toString()
            java.lang.String r11 = "ZMLogin.Session"
            com.tencent.common.log.a.c(r11, r10)
            com.tencent.wglogin.authsuite.core.b r10 = new com.tencent.wglogin.authsuite.core.b
            r10.<init>()
            r10.a(r1)
            r10.b(r2)
            r10.a(r13)
            r10.d(r7)
            r10.c(r4)
            r10.a(r3)
            r10.e(r8)
            r10.a(r5)
            r10.f(r0)
            r12.d = r10
            com.tencent.wglogin.authsuite.core.b r0 = r12.d
            com.tencent.wglogin.authsuite.util.b.a(r0)
            java.lang.StringBuilder r0 = new java.lang.StringBuilder
            r0.<init>()
            java.lang.String r3 = "notifyAuthSuccess mWGLicense:"
            r0.append(r3)
            com.tencent.wglogin.authsuite.core.b r3 = r12.d
            r0.append(r3)
            java.lang.String r0 = r0.toString()
            com.tencent.common.log.a.c(r11, r0)
            r12.b = r1
            java.util.List<com.tencent.wglogin.authsuite.core.Account> r0 = r14.bind_info
            boolean r0 = com.blankj.utilcode.util.t.a(r0)
            if (r0 == 0) goto Lbd
            java.util.ArrayList r0 = new java.util.ArrayList
            r0.<init>()
            r12.c = r0
            goto Lc6
        Lbd:
            java.util.ArrayList r0 = new java.util.ArrayList
            java.util.List<com.tencent.wglogin.authsuite.core.Account> r3 = r14.bind_info
            r0.<init>(r3)
            r12.c = r0
        Lc6:
            int r3 = r13.getCode()
            com.tencent.container.app.AppContext.a(r1, r2, r3, r4, r5, r7, r8)
            com.tencent.wglogin.authsuite.core.c r13 = r12.a
            r13.b()
            android.os.Handler r13 = r12.e
            r0 = 2
            r13.removeMessages(r0)
            android.os.Handler r13 = r12.e
            r1 = 1000(0x3e8, double:4.94E-321)
            r13.sendEmptyMessageDelayed(r0, r1)
            android.os.Handler r13 = r12.e
            r13.removeMessages(r9)
            android.os.Handler r13 = r12.e
            com.tencent.wglogin.authsuite.protocol.LoginResult$LoginResultInfo r14 = r14.login_info
            int r14 = r14.refresh_wt_span
            int r14 = r14 * 1000
            long r0 = (long) r14
            r13.sendEmptyMessageDelayed(r9, r0)
        Lf0:
            return
    }

    public synchronized void a(com.tencent.wglogin.datastruct.SsoAuthType r4, java.lang.String r5, java.util.Map<java.lang.String, byte[]> r6, long r7) {
            r3 = this;
            monitor-enter(r3)
            com.tencent.wglogin.authsuite.core.b r0 = r3.d     // Catch: java.lang.Throwable -> L56
            if (r0 != 0) goto Le
            java.lang.String r4 = "ZMLogin.Session"
            java.lang.String r5 = "onSSOSuccess mWGLicense is empty"
            com.tencent.common.log.a.e(r4, r5)     // Catch: java.lang.Throwable -> L56
            monitor-exit(r3)
            return
        Le:
            if (r5 != 0) goto L12
            java.lang.String r5 = ""
        L12:
            java.lang.String r0 = "ZMLogin.Session"
            java.lang.StringBuilder r1 = new java.lang.StringBuilder     // Catch: java.lang.Throwable -> L56
            r1.<init>()     // Catch: java.lang.Throwable -> L56
            java.lang.String r2 = "onSSOSuccess thirdToken:"
            r1.append(r2)     // Catch: java.lang.Throwable -> L56
            r1.append(r5)     // Catch: java.lang.Throwable -> L56
            java.lang.String r2 = ",extractTickets:"
            r1.append(r2)     // Catch: java.lang.Throwable -> L56
            r1.append(r6)     // Catch: java.lang.Throwable -> L56
            java.lang.String r6 = r1.toString()     // Catch: java.lang.Throwable -> L56
            com.tencent.common.log.a.c(r0, r6)     // Catch: java.lang.Throwable -> L56
            com.tencent.wglogin.datastruct.SsoAuthType r6 = com.tencent.wglogin.datastruct.SsoAuthType.WX     // Catch: java.lang.Throwable -> L56
            int r6 = r6.getCode()     // Catch: java.lang.Throwable -> L56
            int r0 = r4.getCode()     // Catch: java.lang.Throwable -> L56
            if (r6 != r0) goto L40
            com.tencent.container.app.AppContext.a(r5, r7)     // Catch: java.lang.Throwable -> L56
            goto L4f
        L40:
            com.tencent.wglogin.datastruct.SsoAuthType r6 = com.tencent.wglogin.datastruct.SsoAuthType.OPEN_QQ     // Catch: java.lang.Throwable -> L56
            int r6 = r6.getCode()     // Catch: java.lang.Throwable -> L56
            int r4 = r4.getCode()     // Catch: java.lang.Throwable -> L56
            if (r6 != r4) goto L4f
            com.tencent.container.app.AppContext.b(r5, r7)     // Catch: java.lang.Throwable -> L56
        L4f:
            com.tencent.wglogin.authsuite.core.c r4 = r3.a     // Catch: java.lang.Throwable -> L56
            r4.a()     // Catch: java.lang.Throwable -> L56
            monitor-exit(r3)
            return
        L56:
            r4 = move-exception
            monitor-exit(r3)
            throw r4
    }

    public void a(java.lang.String r2) {
            r1 = this;
            com.tencent.wglogin.authsuite.core.b r0 = r1.d
            if (r0 != 0) goto Lc
            java.lang.String r2 = "ZMLogin.Session"
            java.lang.String r0 = "onRefreshWebTicketSuccess mWGLicense is null"
            com.tencent.common.log.a.e(r2, r0)
            return
        Lc:
            r0.e(r2)
            com.tencent.container.app.AppContext.a(r2)
            com.tencent.wglogin.authsuite.core.c r2 = r1.a
            r2.c()
            return
    }

    public void b() {
            r11 = this;
            com.tencent.wglogin.authsuite.core.b r0 = com.tencent.wglogin.authsuite.util.b.a()
            boolean r1 = r0.k()
            java.lang.String r2 = "ZMLogin.Session"
            if (r1 == 0) goto L7d
            com.tencent.wglogin.datastruct.SsoAuthType r1 = r0.d()
            com.tencent.wglogin.datastruct.SsoAuthType r3 = com.tencent.wglogin.datastruct.SsoAuthType.WT
            if (r1 == r3) goto L7d
            com.tencent.wglogin.authsuite.core.b r0 = com.tencent.wglogin.authsuite.core.b.a(r0)
            r11.d = r0
            com.tencent.wglogin.authsuite.core.b r0 = r11.d
            java.lang.String r0 = r0.b()
            r11.b = r0
            java.lang.StringBuilder r0 = new java.lang.StringBuilder
            r0.<init>()
            java.lang.String r1 = "init Session。 有缓存登录态，Cache License:"
            r0.append(r1)
            com.tencent.wglogin.authsuite.core.b r1 = r11.d
            r0.append(r1)
            java.lang.String r0 = r0.toString()
            com.tencent.common.log.a.c(r2, r0)
            com.tencent.wglogin.authsuite.core.b r0 = r11.d
            java.lang.String r3 = r0.b()
            com.tencent.wglogin.authsuite.core.b r0 = r11.d
            java.lang.String r4 = r0.c()
            com.tencent.wglogin.authsuite.core.b r0 = r11.d
            com.tencent.wglogin.datastruct.SsoAuthType r0 = r0.d()
            int r5 = r0.getCode()
            com.tencent.wglogin.authsuite.core.b r0 = r11.d
            java.lang.String r6 = r0.f()
            com.tencent.wglogin.authsuite.core.b r0 = r11.d
            long r7 = r0.a()
            com.tencent.wglogin.authsuite.core.b r0 = r11.d
            java.lang.String r9 = r0.e()
            com.tencent.wglogin.authsuite.core.b r0 = r11.d
            java.lang.String r10 = r0.h()
            com.tencent.container.app.AppContext.a(r3, r4, r5, r6, r7, r9, r10)
            com.tencent.wglogin.authsuite.core.b r0 = r11.d
            java.lang.String r0 = r0.b()
            java.lang.String r1 = "$UUID$"
            com.tencent.container.c.b.a.a(r1, r0)
            java.lang.String r0 = "自动刷新ClientTicket票据"
            com.tencent.common.log.a.c(r2, r0)
            com.tencent.wglogin.authsuite.d.c()
            goto L82
        L7d:
            java.lang.String r0 = "init Session。 没有缓存登录态"
            com.tencent.common.log.a.c(r2, r0)
        L82:
            return
    }

    public void b(java.lang.String r5) {
            r4 = this;
            boolean r0 = com.blankj.utilcode.util.t.a(r5)
            if (r0 == 0) goto L8
            java.lang.String r5 = "票据过期，请重新登录"
        L8:
            java.lang.String r0 = "ZMLogin.Session"
            java.lang.String r1 = "Session kickUserOff"
            com.tencent.common.log.a.c(r0, r1)
            boolean r1 = r4.g()
            if (r1 != 0) goto L2e
            java.lang.StringBuilder r5 = new java.lang.StringBuilder
            r5.<init>()
            java.lang.String r1 = "kickUserOff isAuthorized = "
            r5.append(r1)
            boolean r1 = r4.g()
            r5.append(r1)
            java.lang.String r5 = r5.toString()
            com.tencent.common.log.a.c(r0, r5)
            return
        L2e:
            java.lang.String r1 = r4.d()
            com.tencent.wglogin.authsuite.util.b.b()
            java.lang.StringBuilder r2 = new java.lang.StringBuilder
            r2.<init>()
            java.lang.String r3 = "清理票据 userId = "
            r2.append(r3)
            r2.append(r1)
            java.lang.String r1 = r2.toString()
            com.tencent.common.log.a.c(r0, r1)
            r0 = 0
            r4.d = r0
            r4.b = r0
            r4.c = r0
            android.os.Handler r0 = r4.e
            r1 = 2
            r0.removeMessages(r1)
            android.os.Handler r0 = r4.e
            r1 = 1
            r0.removeMessages(r1)
            com.tencent.wglogin.authsuite.core.c r0 = r4.a
            if (r0 == 0) goto L63
            r0.a(r5)
        L63:
            return
    }

    public java.util.List<com.tencent.wglogin.authsuite.core.Account> c() {
            r1 = this;
            java.util.List<com.tencent.wglogin.authsuite.core.Account> r0 = r1.c
            if (r0 == 0) goto L5
            goto La
        L5:
            java.util.ArrayList r0 = new java.util.ArrayList
            r0.<init>()
        La:
            return r0
    }

    public java.lang.String d() {
            r1 = this;
            java.lang.String r0 = r1.b
            return r0
    }

    public java.lang.String e() {
            r1 = this;
            com.tencent.wglogin.authsuite.core.b r0 = r1.d
            if (r0 == 0) goto L11
            boolean r0 = r0.k()
            if (r0 == 0) goto L11
            com.tencent.wglogin.authsuite.core.b r0 = r1.d
            java.lang.String r0 = r0.e()
            return r0
        L11:
            r0 = 0
            return r0
    }

    public synchronized com.tencent.wglogin.authsuite.core.b f() {
            r1 = this;
            monitor-enter(r1)
            com.tencent.wglogin.authsuite.core.b r0 = r1.d     // Catch: java.lang.Throwable -> Lf
            if (r0 != 0) goto L7
            r0 = 0
            goto Ld
        L7:
            com.tencent.wglogin.authsuite.core.b r0 = r1.d     // Catch: java.lang.Throwable -> Lf
            com.tencent.wglogin.authsuite.core.b r0 = r0.j()     // Catch: java.lang.Throwable -> Lf
        Ld:
            monitor-exit(r1)
            return r0
        Lf:
            r0 = move-exception
            monitor-exit(r1)
            throw r0
    }

    public boolean g() {
            r1 = this;
            com.tencent.wglogin.authsuite.core.b r0 = r1.d
            if (r0 == 0) goto L18
            java.lang.String r0 = r0.e()
            boolean r0 = com.blankj.utilcode.util.t.b(r0)
            if (r0 == 0) goto L18
            java.lang.String r0 = r1.b
            boolean r0 = com.blankj.utilcode.util.t.b(r0)
            if (r0 == 0) goto L18
            r0 = 1
            goto L19
        L18:
            r0 = 0
        L19:
            return r0
    }

    public boolean h() {
            r1 = this;
            com.tencent.wglogin.authsuite.core.b r0 = r1.d
            if (r0 == 0) goto Lc
            boolean r0 = r0.g()
            if (r0 == 0) goto Lc
            r0 = 1
            goto Ld
        Lc:
            r0 = 0
        Ld:
            return r0
    }

    public void i() {
            r4 = this;
            java.lang.String r0 = "ZMLogin.Session"
            java.lang.String r1 = "Session logout"
            com.tencent.common.log.a.c(r0, r1)
            boolean r1 = r4.g()
            if (r1 != 0) goto L26
            java.lang.StringBuilder r1 = new java.lang.StringBuilder
            r1.<init>()
            java.lang.String r2 = "onKickOff isAuthorized = "
            r1.append(r2)
            boolean r2 = r4.g()
            r1.append(r2)
            java.lang.String r1 = r1.toString()
            com.tencent.common.log.a.c(r0, r1)
            return
        L26:
            java.lang.String r1 = r4.d()
            com.tencent.wglogin.authsuite.util.b.b()
            java.lang.StringBuilder r2 = new java.lang.StringBuilder
            r2.<init>()
            java.lang.String r3 = "清理票据 userId = "
            r2.append(r3)
            r2.append(r1)
            java.lang.String r1 = r2.toString()
            com.tencent.common.log.a.c(r0, r1)
            r0 = 0
            r4.d = r0
            r4.b = r0
            r4.c = r0
            android.os.Handler r0 = r4.e
            r1 = 2
            r0.removeMessages(r1)
            android.os.Handler r0 = r4.e
            r1 = 1
            r0.removeMessages(r1)
            com.tencent.wglogin.authsuite.core.c r0 = r4.a
            r0.d()
            return
    }
}