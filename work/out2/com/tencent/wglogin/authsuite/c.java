package com.tencent.wglogin.authsuite;

/* JADX INFO: compiled from: A */
/* JADX INFO: loaded from: D:\DSHDev\Reverse\Valorant App\work\apk\classes5.dex */
public class c {





    /* JADX INFO: compiled from: A */
    public interface a {
        void a();

        void a(com.tencent.mm.opensdk.diffdev.OAuthErrCode r1, java.lang.String r2);

        void a(byte[] r1, com.tencent.wglogin.datastruct.SsoAuthType r2);
    }

    public c() {
            r0 = this;
            r0.<init>()
            return
    }

    private static com.tencent.wglogin.authsuite.a.e a(com.tencent.wglogin.datastruct.SsoAuthType r1, com.tencent.wglogin.authsuite.a.f r2, com.tencent.wglogin.authsuite.a.a r3) {
            com.tencent.wglogin.authsuite.c$3 r0 = new com.tencent.wglogin.authsuite.c$3
            r0.<init>(r2, r3, r1)
            return r0
    }

    private static com.tencent.wglogin.authsuite.a.f a(com.tencent.wglogin.datastruct.SsoAuthType r1, com.tencent.wglogin.authsuite.a.a r2) {
            com.tencent.wglogin.authsuite.c$4 r0 = new com.tencent.wglogin.authsuite.c$4
            r0.<init>(r1, r2)
            return r0
    }

    public static void a(android.app.Activity r2, com.tencent.wglogin.authsuite.c.a r3) {
            if (r2 != 0) goto L10
            java.lang.String r2 = "ZMLogin.LoginHelper"
            java.lang.String r0 = "loginWXByQRCode, activity must not be null"
            com.tencent.common.log.a.e(r2, r0)
            com.tencent.mm.opensdk.diffdev.OAuthErrCode r2 = com.tencent.mm.opensdk.diffdev.OAuthErrCode.WechatAuth_Err_NormalErr
            r0 = 0
            r3.a(r2, r0)
            return
        L10:
            com.tencent.wglogin.authsuite.protocol.GetWXServerTicketProtocol r0 = new com.tencent.wglogin.authsuite.protocol.GetWXServerTicketProtocol
            r0.<init>()
            com.tencent.wglogin.authsuite.c$1 r1 = new com.tencent.wglogin.authsuite.c$1
            r1.<init>(r3)
            r0.post(r2, r1)
            return
    }

    public static void a(android.app.Activity r1, com.tencent.wglogin.datastruct.SsoAuthType r2, com.tencent.wglogin.authsuite.a.a r3) {
            if (r1 != 0) goto La
            java.lang.String r1 = "ZMLogin.LoginHelper"
            java.lang.String r2 = "login, activity must not be null"
            com.tencent.common.log.a.e(r1, r2)
            return
        La:
            com.tencent.wglogin.authsuite.a.f r0 = a(r2, r3)
            com.tencent.wglogin.authsuite.a.e r3 = a(r2, r0, r3)
            com.tencent.wglogin.authsuite.b.b r2 = com.tencent.wglogin.authsuite.b.a(r1, r2)
            r2.a(r1, r3)
            return
    }

    public static void a(java.lang.String r1, com.tencent.wglogin.authsuite.a.a r2) {
            boolean r0 = android.text.TextUtils.isEmpty(r1)
            if (r0 == 0) goto Ld
            r1 = -1
            java.lang.String r0 = "获取票据失败"
            r2.a(r1, r0)
            return
        Ld:
            com.tencent.wglogin.datastruct.SsoAuthType r0 = com.tencent.wglogin.datastruct.SsoAuthType.WX
            com.tencent.wglogin.authsuite.a.f r2 = a(r0, r2)
            com.tencent.wglogin.authsuite.c$2 r0 = new com.tencent.wglogin.authsuite.c$2
            r0.<init>(r1)
            com.tencent.wglogin.authsuite.d.a(r0, r2)
            return
    }
}