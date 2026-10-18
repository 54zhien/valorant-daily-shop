package com.tencent.wglogin.authsuite.protocol;

/* JADX INFO: compiled from: A */
/* JADX INFO: loaded from: D:\DSHDev\Reverse\Valorant App\work\apk\classes5.dex */
@com.tencent.container.protocol.Protocol(path = "/go/auth/refresh_client_ticket")
public class RefreshClientTicketProtocol extends com.tencent.container.protocol.a<com.tencent.wglogin.authsuite.protocol.RefreshClientTicketProtocol.Params, com.tencent.wglogin.authsuite.protocol.RefreshClientTicketProtocol.Result> {

    /* JADX INFO: compiled from: A */
    public static class Params {
        public com.tencent.wglogin.authsuite.protocol.RefreshClientTicketProtocol.Params.ConfigParams config_params;
        public java.lang.String ct;
        public int local_is_new_user;
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
        public java.util.List<com.tencent.wglogin.authsuite.core.Account> bind_info;
        public com.tencent.wglogin.authsuite.protocol.RefreshClientTicketProtocol.Result.RefreshCTInfo ct_info;

        /* JADX INFO: compiled from: A */
        public static class RefreshCTInfo {
            public java.lang.String ct;
            public java.lang.String errmsg;
            public int expires;
            public int is_new_user;
            public int is_timeout;
            public java.lang.String login_uuid;
            public java.lang.String openid;
            public int refresh_ct_span;
            public int refresh_wt_span;
            public long uin;
            public java.lang.String user_id;
            public java.lang.String wt;

            public RefreshCTInfo() {
                    r0 = this;
                    r0.<init>()
                    return
            }
        }

        public Result() {
                r0 = this;
                r0.<init>()
                return
        }
    }

    public RefreshClientTicketProtocol(com.tencent.wglogin.authsuite.protocol.RefreshClientTicketProtocol.Params r1) {
            r0 = this;
            r0.<init>(r1)
            return
    }
}