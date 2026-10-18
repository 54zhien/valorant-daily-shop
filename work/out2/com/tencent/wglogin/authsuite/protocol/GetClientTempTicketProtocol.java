package com.tencent.wglogin.authsuite.protocol;

/* JADX INFO: compiled from: A */
/* JADX INFO: loaded from: D:\DSHDev\Reverse\Valorant App\work\apk\classes5.dex */
@com.tencent.container.protocol.Protocol(path = "/go/auth/get_client_tmp_ticket")
public class GetClientTempTicketProtocol extends com.tencent.container.protocol.a<com.tencent.wglogin.authsuite.protocol.GetClientTempTicketProtocol.Params, com.tencent.wglogin.authsuite.protocol.GetClientTempTicketProtocol.Result> {

    /* JADX INFO: compiled from: A */
    public static class Params {
        public com.tencent.wglogin.authsuite.protocol.GetClientTempTicketProtocol.Params.ConfigParams config_params;
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
        public java.lang.String ctt;
        public int is_timeout;
        public java.lang.String openid;
        public java.lang.String sk;
        public java.lang.String user_id;

        public Result() {
                r0 = this;
                r0.<init>()
                return
        }
    }

    public GetClientTempTicketProtocol(com.tencent.wglogin.authsuite.protocol.GetClientTempTicketProtocol.Params r1) {
            r0 = this;
            r0.<init>(r1)
            return
    }
}