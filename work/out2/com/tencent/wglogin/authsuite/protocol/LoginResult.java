package com.tencent.wglogin.authsuite.protocol;

/* JADX INFO: compiled from: A */
/* JADX INFO: loaded from: D:\DSHDev\Reverse\Valorant App\work\apk\classes5.dex */
public class LoginResult {
    public java.util.List<com.tencent.wglogin.authsuite.core.Account> bind_info;
    public com.tencent.wglogin.authsuite.protocol.LoginResult.LoginResultInfo login_info;

    /* JADX INFO: compiled from: A */
    public static class LoginResultInfo {
        public java.lang.String ct;
        public java.lang.String ctt;
        public int is_new_user;
        public java.lang.String login_uuid;
        public java.lang.String openid;
        public int refresh_ct_span;
        public int refresh_wt_span;
        public java.lang.String third_openid;
        public int third_type;
        public long uin;
        public java.lang.String user_id;
        public java.lang.String wt;

        public LoginResultInfo() {
                r0 = this;
                r0.<init>()
                return
        }
    }

    public LoginResult() {
            r0 = this;
            r0.<init>()
            return
    }
}