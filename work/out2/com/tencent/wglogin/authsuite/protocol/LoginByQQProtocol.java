package com.tencent.wglogin.authsuite.protocol;

/* JADX INFO: compiled from: A */
/* JADX INFO: loaded from: D:\DSHDev\Reverse\Valorant App\work\apk\classes5.dex */
@com.tencent.container.protocol.Protocol(path = "/go/auth/login_by_qq")
public class LoginByQQProtocol extends com.tencent.container.protocol.a<com.tencent.wglogin.authsuite.protocol.LoginByQQProtocol.Params, com.tencent.wglogin.authsuite.protocol.LoginResult> {

    /* JADX INFO: compiled from: A */
    public static class Params {
        public int clienttype;
        public com.tencent.wglogin.authsuite.protocol.LoginByQQProtocol.Params.ConfigParams config_params;
        public com.tencent.wglogin.authsuite.protocol.LoginByQQProtocol.Params.LoginInfo login_info;
        public int mappid;
        public java.lang.String mcode;

        /* JADX INFO: compiled from: A */
        public static class ConfigParams {
            public java.lang.String client_dev_name;
            public int lang_type;

            public ConfigParams() {
                    r1 = this;
                    r1.<init>()
                    r0 = 0
                    r1.lang_type = r0
                    return
            }
        }

        /* JADX INFO: compiled from: A */
        public static class LoginInfo {
            public long appid;
            public java.lang.String openid;
            public int qq_info_type;
            public java.lang.String sig;
            public long uin;

            public LoginInfo() {
                    r0 = this;
                    r0.<init>()
                    return
            }
        }

        public Params() {
                r1 = this;
                r1.<init>()
                int r0 = com.tencent.container.app.AppContext.h()
                r1.clienttype = r0
                int r0 = com.tencent.wglogin.authsuite.util.a.c
                r1.mappid = r0
                return
        }
    }

    public LoginByQQProtocol(com.tencent.wglogin.authsuite.protocol.LoginByQQProtocol.Params r1) {
            r0 = this;
            r0.<init>(r1)
            return
    }
}