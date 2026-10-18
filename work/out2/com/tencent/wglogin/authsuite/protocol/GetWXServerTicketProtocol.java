package com.tencent.wglogin.authsuite.protocol;

/* JADX INFO: compiled from: A */
/* JADX INFO: loaded from: D:\DSHDev\Reverse\Valorant App\work\apk\classes5.dex */
@com.tencent.container.protocol.Protocol(path = "/go/auth/get_sdk_ticket")
public class GetWXServerTicketProtocol extends com.tencent.container.protocol.b<com.tencent.wglogin.authsuite.protocol.GetWXServerTicketProtocol.GetWXServerTicketResult> {

    /* JADX INFO: compiled from: A */
    public static class GetWXServerTicketResult {
        public java.lang.String ticket;

        public GetWXServerTicketResult() {
                r0 = this;
                r0.<init>()
                return
        }
    }

    public GetWXServerTicketProtocol() {
            r0 = this;
            r0.<init>()
            return
    }

    protected java.lang.String getProtocolBody() {
            r1 = this;
            java.lang.String r0 = "{}"
            return r0
    }
}