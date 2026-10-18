package com.tencent.wglogin.authsuite.core;

/* JADX INFO: compiled from: A */
/* JADX INFO: loaded from: D:\DSHDev\Reverse\Valorant App\work\apk\classes5.dex */
public class b {
    private java.lang.String a;
    private java.lang.String b;
    private com.tencent.wglogin.datastruct.SsoAuthType c;
    private java.lang.String d;
    private long e;
    private java.lang.String f;
    private java.lang.String g;
    private boolean h;
    private java.lang.String i;

    public b() {
            r1 = this;
            r1.<init>()
            java.lang.String r0 = ""
            r1.d = r0
            r1.f = r0
            return
    }

    public static com.tencent.wglogin.authsuite.core.b a(com.tencent.wglogin.authsuite.core.b r1) {
            com.tencent.wglogin.authsuite.core.b r0 = new com.tencent.wglogin.authsuite.core.b
            r0.<init>()
            r0.b(r1)
            return r0
    }

    public long a() {
            r2 = this;
            long r0 = r2.e
            return r0
    }

    public void a(long r1) {
            r0 = this;
            r0.e = r1
            return
    }

    public void a(com.tencent.wglogin.datastruct.SsoAuthType r1) {
            r0 = this;
            r0.c = r1
            return
    }

    public void a(java.lang.String r1) {
            r0 = this;
            r0.a = r1
            return
    }

    public void a(boolean r1) {
            r0 = this;
            r0.h = r1
            return
    }

    public java.lang.String b() {
            r1 = this;
            java.lang.String r0 = r1.a
            return r0
    }

    public void b(com.tencent.wglogin.authsuite.core.b r3) {
            r2 = this;
            java.lang.String r0 = r3.a
            r2.a = r0
            java.lang.String r0 = r3.b
            r2.b = r0
            com.tencent.wglogin.datastruct.SsoAuthType r0 = r3.c
            r2.c = r0
            java.lang.String r0 = r3.g
            r2.g = r0
            java.lang.String r0 = r3.d
            r2.d = r0
            boolean r0 = r3.h
            r2.h = r0
            java.lang.String r0 = r3.i
            r2.i = r0
            java.lang.String r0 = r3.f
            r2.f = r0
            long r0 = r3.e
            r2.e = r0
            return
    }

    public void b(java.lang.String r1) {
            r0 = this;
            r0.b = r1
            return
    }

    public java.lang.String c() {
            r1 = this;
            java.lang.String r0 = r1.b
            return r0
    }

    public void c(java.lang.String r1) {
            r0 = this;
            r0.d = r1
            return
    }

    public com.tencent.wglogin.datastruct.SsoAuthType d() {
            r1 = this;
            com.tencent.wglogin.datastruct.SsoAuthType r0 = r1.c
            return r0
    }

    public void d(java.lang.String r1) {
            r0 = this;
            r0.g = r1
            return
    }

    public java.lang.String e() {
            r1 = this;
            java.lang.String r0 = r1.g
            return r0
    }

    public void e(java.lang.String r1) {
            r0 = this;
            r0.i = r1
            return
    }

    public java.lang.String f() {
            r1 = this;
            java.lang.String r0 = r1.d
            return r0
    }

    public void f(java.lang.String r1) {
            r0 = this;
            r0.f = r1
            return
    }

    public boolean g() {
            r1 = this;
            boolean r0 = r1.h
            return r0
    }

    public java.lang.String h() {
            r1 = this;
            java.lang.String r0 = r1.i
            return r0
    }

    public java.lang.String i() {
            r1 = this;
            java.lang.String r0 = r1.f
            return r0
    }

    public com.tencent.wglogin.authsuite.core.b j() {
            r1 = this;
            com.tencent.wglogin.authsuite.core.b r0 = new com.tencent.wglogin.authsuite.core.b
            r0.<init>()
            r0.b(r1)
            return r0
    }

    public boolean k() {
            r1 = this;
            java.lang.String r0 = r1.a
            boolean r0 = android.text.TextUtils.isEmpty(r0)
            if (r0 != 0) goto L20
            java.lang.String r0 = r1.b
            boolean r0 = android.text.TextUtils.isEmpty(r0)
            if (r0 != 0) goto L20
            java.lang.String r0 = r1.g
            if (r0 == 0) goto L20
            boolean r0 = android.text.TextUtils.isEmpty(r0)
            if (r0 != 0) goto L20
            com.tencent.wglogin.datastruct.SsoAuthType r0 = r1.c
            if (r0 == 0) goto L20
            r0 = 1
            goto L21
        L20:
            r0 = 0
        L21:
            return r0
    }

    public java.lang.String toString() {
            r4 = this;
            java.lang.StringBuilder r0 = new java.lang.StringBuilder
            r0.<init>()
            java.lang.String r1 = "WGLicense{userId='"
            r0.append(r1)
            java.lang.String r1 = r4.a
            r0.append(r1)
            r1 = 39
            r0.append(r1)
            java.lang.String r2 = ", openId='"
            r0.append(r2)
            java.lang.String r2 = r4.b
            r0.append(r2)
            r0.append(r1)
            java.lang.String r2 = ", authType="
            r0.append(r2)
            com.tencent.wglogin.datastruct.SsoAuthType r2 = r4.c
            r0.append(r2)
            java.lang.String r2 = ", ssoOpenId='"
            r0.append(r2)
            java.lang.String r2 = r4.d
            r0.append(r2)
            r0.append(r1)
            java.lang.String r2 = ", ssoUin="
            r0.append(r2)
            long r2 = r4.e
            r0.append(r2)
            java.lang.String r2 = ", ssoUuid='"
            r0.append(r2)
            java.lang.String r2 = r4.f
            r0.append(r2)
            r0.append(r1)
            java.lang.String r2 = ", ticket='"
            r0.append(r2)
            java.lang.String r2 = r4.g
            r0.append(r2)
            r0.append(r1)
            java.lang.String r2 = ", isNewUser="
            r0.append(r2)
            boolean r2 = r4.h
            r0.append(r2)
            java.lang.String r2 = ", webToken='"
            r0.append(r2)
            java.lang.String r2 = r4.i
            r0.append(r2)
            r0.append(r1)
            r1 = 125(0x7d, float:1.75E-43)
            r0.append(r1)
            java.lang.String r0 = r0.toString()
            return r0
    }
}