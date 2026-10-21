import json, urllib.request, urllib.error
UID="JA-3095d6174193457a-b8d058817457ae26"; OID="A44A6AA89A42ECA6909C2492C2193D14"; UIN="2751275315"
CT=("8418A93A9C7DCE05D6F877227275163173867551666557B0B48BEDE369A4A60CBE162AC0AD086EBE3490305"
    "DA46072AAC8AFBC0071DD37E54698B1578BCBD29E970802B124A9DFF4816568176D9E8E71F28FA3661AD"
    "B8E421553BA9682AC673D8B0DD6DA36CAA51ADC7E94A4E347C48B649E99D97DF3A88306C6074633353D4"
    "384D6A7BC5670BE88699895F8A88D08AC5C223645B49893FB8D1DBB6D776BCA937BC66806E80F50789"
    "BFD7E5BAF362EE48E47074E38CE514D705B6CA2EBB252941AECB7672B2F68207F8B1626BF6CAC3E6E3"
    "06AFF262BC9085B446EFAEAD18988905F1C2DA655A97D")
H="https://app.mval.qq.com"
def post(p,b,c=None,limit=400):
    h={"User-Agent":"okhttp/4.9.2","Content-Type":"application/json; charset=utf-8"}
    if c: h["Cookie"]=c
    r=urllib.request.Request(H+p,data=json.dumps(b).encode(),headers=h,method="POST")
    try:
        with urllib.request.urlopen(r,timeout=20) as x: s=x.read().decode("utf-8","replace")
    except urllib.error.HTTPError as e: s=e.read().decode("utf-8","replace")
    try: return json.loads(s)
    except Exception: return {"_raw": s[:limit]}
st=post("/go/auth/get_web_ticket",{"ct":CT,"user_id":UID,"config_params":{"lang_type":0}},limit=2000)
tid=(st.get("data") or {}).get("wt")
print("wt ok:", bool(tid), "result:", st.get("result"))
ck=f"clientType=9; uin=o{UIN}; appid=102061775; acctype=qc; openid={OID}; userId={UID}; accountType=5; tid={tid};"
for body in ({}, {"goods_id":"00000000-0000-0000-0000-000000000000"}, {"goods_id":"00000000-0000-0000-0000-000000000000","guid":""}):
    r=post("/go/mlol_store/agame/flip_goods_card", body, ck)
    print("flip_goods_card", json.dumps(body,ensure_ascii=False)[:80], "->", json.dumps(r,ensure_ascii=False)[:300])
