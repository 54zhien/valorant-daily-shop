package com.tencent.wglogin.authsuite.util;

/* JADX INFO: compiled from: A */
/* JADX INFO: loaded from: D:\DSHDev\Reverse\Valorant App\work\apk\classes5.dex */
public class NetStateReceiver extends android.content.BroadcastReceiver {
    private static boolean a = false;
    private static java.util.concurrent.CopyOnWriteArrayList<com.tencent.wglogin.authsuite.util.c> b;
    private static android.content.BroadcastReceiver c;

    static {
            java.util.concurrent.CopyOnWriteArrayList r0 = new java.util.concurrent.CopyOnWriteArrayList
            r0.<init>()
            com.tencent.wglogin.authsuite.util.NetStateReceiver.b = r0
            return
    }

    public NetStateReceiver() {
            r0 = this;
            r0.<init>()
            return
    }

    public static void a(android.content.Context r2) {
            android.content.IntentFilter r0 = new android.content.IntentFilter
            r0.<init>()
            java.lang.String r1 = "android.net.conn.CONNECTIVITY_CHANGE"
            r0.addAction(r1)
            android.content.Context r2 = r2.getApplicationContext()
            android.content.BroadcastReceiver r1 = b()
            r2.registerReceiver(r1, r0)
            return
    }

    public static void a(com.tencent.wglogin.authsuite.util.c r1) {
            java.util.concurrent.CopyOnWriteArrayList<com.tencent.wglogin.authsuite.util.c> r0 = com.tencent.wglogin.authsuite.util.NetStateReceiver.b
            if (r0 != 0) goto Lb
            java.util.concurrent.CopyOnWriteArrayList r0 = new java.util.concurrent.CopyOnWriteArrayList
            r0.<init>()
            com.tencent.wglogin.authsuite.util.NetStateReceiver.b = r0
        Lb:
            java.util.concurrent.CopyOnWriteArrayList<com.tencent.wglogin.authsuite.util.c> r0 = com.tencent.wglogin.authsuite.util.NetStateReceiver.b
            r0.add(r1)
            return
    }

    public static boolean a() {
            boolean r0 = com.tencent.wglogin.authsuite.util.NetStateReceiver.a
            return r0
    }

    private static android.content.BroadcastReceiver b() {
            android.content.BroadcastReceiver r0 = com.tencent.wglogin.authsuite.util.NetStateReceiver.c
            if (r0 != 0) goto L17
            java.lang.Class<com.tencent.wglogin.authsuite.util.NetStateReceiver> r0 = com.tencent.wglogin.authsuite.util.NetStateReceiver.class
            monitor-enter(r0)
            android.content.BroadcastReceiver r1 = com.tencent.wglogin.authsuite.util.NetStateReceiver.c     // Catch: java.lang.Throwable -> L14
            if (r1 != 0) goto L12
            com.tencent.wglogin.authsuite.util.NetStateReceiver r1 = new com.tencent.wglogin.authsuite.util.NetStateReceiver     // Catch: java.lang.Throwable -> L14
            r1.<init>()     // Catch: java.lang.Throwable -> L14
            com.tencent.wglogin.authsuite.util.NetStateReceiver.c = r1     // Catch: java.lang.Throwable -> L14
        L12:
            monitor-exit(r0)     // Catch: java.lang.Throwable -> L14
            goto L17
        L14:
            r1 = move-exception
            monitor-exit(r0)     // Catch: java.lang.Throwable -> L14
            throw r1
        L17:
            android.content.BroadcastReceiver r0 = com.tencent.wglogin.authsuite.util.NetStateReceiver.c
            return r0
    }

    public static void b(com.tencent.wglogin.authsuite.util.c r1) {
            java.util.concurrent.CopyOnWriteArrayList<com.tencent.wglogin.authsuite.util.c> r0 = com.tencent.wglogin.authsuite.util.NetStateReceiver.b
            if (r0 == 0) goto L7
            r0.remove(r1)
        L7:
            return
    }

    private void c() {
            r4 = this;
            java.util.concurrent.CopyOnWriteArrayList<com.tencent.wglogin.authsuite.util.c> r0 = com.tencent.wglogin.authsuite.util.NetStateReceiver.b
            boolean r0 = r0.isEmpty()
            if (r0 != 0) goto L2b
            java.util.concurrent.CopyOnWriteArrayList<com.tencent.wglogin.authsuite.util.c> r0 = com.tencent.wglogin.authsuite.util.NetStateReceiver.b
            int r0 = r0.size()
            r1 = 0
        Lf:
            if (r1 >= r0) goto L2b
            java.util.concurrent.CopyOnWriteArrayList<com.tencent.wglogin.authsuite.util.c> r2 = com.tencent.wglogin.authsuite.util.NetStateReceiver.b
            java.lang.Object r2 = r2.get(r1)
            com.tencent.wglogin.authsuite.util.c r2 = (com.tencent.wglogin.authsuite.util.c) r2
            if (r2 == 0) goto L28
            boolean r3 = a()
            if (r3 == 0) goto L25
            r2.a()
            goto L28
        L25:
            r2.b()
        L28:
            int r1 = r1 + 1
            goto Lf
        L2b:
            return
    }

    @Override // android.content.BroadcastReceiver
    public void onReceive(android.content.Context r2, android.content.Intent r3) {
            r1 = this;
            com.tencent.wglogin.authsuite.util.NetStateReceiver.c = r1
            java.lang.String r0 = r3.getAction()
            if (r0 == 0) goto L3e
            java.lang.String r3 = r3.getAction()
            java.lang.String r0 = "android.net.conn.CONNECTIVITY_CHANGE"
            boolean r3 = r3.equalsIgnoreCase(r0)
            if (r3 == 0) goto L3e
            boolean r2 = com.tencent.wglogin.authsuite.util.d.a(r2)
            if (r2 != 0) goto L2b
            java.lang.Class r2 = r1.getClass()
            java.lang.String r2 = r2.getName()
            java.lang.String r3 = "<--- network disconnected --->"
            com.tencent.common.log.a.e(r2, r3)
            r2 = 0
            com.tencent.wglogin.authsuite.util.NetStateReceiver.a = r2
            goto L3b
        L2b:
            java.lang.Class r2 = r1.getClass()
            java.lang.String r2 = r2.getName()
            java.lang.String r3 = "<--- network connected --->"
            com.tencent.common.log.a.e(r2, r3)
            r2 = 1
            com.tencent.wglogin.authsuite.util.NetStateReceiver.a = r2
        L3b:
            r1.c()
        L3e:
            return
    }
}