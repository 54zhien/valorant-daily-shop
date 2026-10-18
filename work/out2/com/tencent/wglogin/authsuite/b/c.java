package com.tencent.wglogin.authsuite.b;

/* JADX INFO: compiled from: A */
/* JADX INFO: loaded from: D:\DSHDev\Reverse\Valorant App\work\apk\classes5.dex */
public class c implements com.tencent.wglogin.authsuite.b.b {


    public c(android.app.Activity r2) {
            r1 = this;
            r1.<init>()
            java.lang.String r0 = com.tencent.wglogin.authsuite.util.a.b
            com.tencent.wglogin.sso.a.a.a(r2, r0)
            return
    }

    @Override // com.tencent.wglogin.authsuite.b.b
    public void a(int r1, int r2, android.content.Intent r3) {
            r0 = this;
            return
    }

    @Override // com.tencent.wglogin.authsuite.b.b
    public void a(android.app.Activity r2, com.tencent.wglogin.authsuite.a.e r3) {
            r1 = this;
            com.tencent.wglogin.authsuite.b.c$1 r0 = new com.tencent.wglogin.authsuite.b.c$1
            r0.<init>(r1, r3)
            com.tencent.wglogin.sso.a.a.a(r2, r0)
            return
    }
}