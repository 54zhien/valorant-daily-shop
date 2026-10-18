package com.tencent.wglogin.authsuite.protocol;

/* JADX INFO: compiled from: A */
/* JADX INFO: loaded from: D:\DSHDev\Reverse\Valorant App\work\apk\classes5.dex */
@com.tencent.container.protocol.Protocol(path = "/go/auth/refresh_third_token")
public class a extends com.tencent.container.protocol.b<com.tencent.wglogin.authsuite.protocol.ThirdTokenResult> {
    private java.lang.String a;
    private java.lang.String b;
    private java.lang.String c;

    public a(java.lang.String r1, java.lang.String r2, java.lang.String r3) {
            r0 = this;
            r0.<init>()
            r0.a = r1
            r0.b = r2
            r0.c = r3
            return
    }

    protected java.lang.String getProtocolBody() {
            r3 = this;
            com.google.gson.JsonObject r0 = new com.google.gson.JsonObject
            r0.<init>()
            java.lang.String r1 = r3.c
            java.lang.String r2 = "type"
            r0.addProperty(r2, r1)
            java.lang.String r1 = r3.a
            boolean r1 = com.blankj.utilcode.util.t.b(r1)
            if (r1 == 0) goto L1b
            java.lang.String r1 = r3.a
            java.lang.String r2 = "uuid"
            r0.addProperty(r2, r1)
        L1b:
            java.lang.String r1 = r3.b
            boolean r1 = com.blankj.utilcode.util.t.b(r1)
            if (r1 == 0) goto L2a
            java.lang.String r1 = r3.b
            java.lang.String r2 = "openid"
            r0.addProperty(r2, r1)
        L2a:
            java.lang.String r0 = com.blankj.utilcode.util.o.a(r0)
            return r0
    }
}