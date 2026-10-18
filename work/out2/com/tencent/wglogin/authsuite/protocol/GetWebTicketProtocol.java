package com.tencent.wglogin.authsuite.protocol;

/* JADX INFO: compiled from: A */
/* JADX INFO: loaded from: D:\DSHDev\Reverse\Valorant App\work\apk\classes5.dex */
@com.tencent.container.protocol.Protocol(path = "/go/auth/get_web_ticket")
public class GetWebTicketProtocol extends com.tencent.container.protocol.a<com.tencent.wglogin.authsuite.protocol.GetWebTicketProtocol.Params, com.tencent.wglogin.authsuite.protocol.GetWebTicketProtocol.Result> {

    /* JADX INFO: compiled from: A */
    public static class Params {
        public com.tencent.wglogin.authsuite.protocol.GetWebTicketProtocol.Params.ConfigParams config_params;
        public java.lang.String ct;
        public java.lang.String user_id;

        /* JADX INFO: compiled from: A */
        public static class ConfigParams {
            public int lang_type;

            public ConfigParams() {
                    r1 = this;
                    r1.<init>()
                    r0 = 0
                    r1.lang_type = r0
                    return
            }
        }

        public Params() {
                r0 = this;
                r0.<init>()
                return
        }
    }

    /* JADX INFO: compiled from: A */
    public static class Result {
        public int is_timeout;
        public java.lang.String openid;
        public int refresh_wt_span;
        public java.lang.String user_id;
        public java.lang.String wt;

        public Result() {
                r0 = this;
                r0.<init>()
                return
        }
    }

    public GetWebTicketProtocol(com.tencent.wglogin.authsuite.protocol.GetWebTicketProtocol.Params r1) {
            r0 = this;
            r0.<init>(r1)
            return
    }
}