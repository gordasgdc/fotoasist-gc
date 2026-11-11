"""FotoAsist GC — lanț de noduri-etapă pentru pagina Color a DaVinci Resolve, prin DRX (șablon de grad exportat din ACELAȘI proiect, `<Body>` înlocuit).
Stdlib-only (Python 3.14 din Resolve: `compression.zstd`; rezervă: CLI `zstd` pentru teste în afara Resolve). Nu atinge instalarea GDC STYLE și nu depinde de ea.
Formatul (dedus din DRX/DRP exportate de Resolve 21.1.1, verificat pe pluginul propriu `dev.gordas.photo.develop`): `<Body>` = 0x81 + cadru zstd; conținutul = protobuf (graf de noduri).
  parametru: double → {2: double} · string → {5} · choice → {4:{1: zigzag(index)}} · bool → {3: 0/1}; nodul: câmpul 6 = ETICHETA nodului (vizibilă în pagina Color); contextul OFX = `OfxImageEffectContextFilter_<GUID versiune>_<index nod>`,
  GUID-ul = DbId-ul primului `ListMgt::LmVersion` al DRX-ului (versiunea de culoare căreia îi aparține graful). Resolve scrie în DRX doar parametrii ≠ implicit.
Adaptare a uneltei proprii de probă STYLE (drxkit): codificările sunt aceleași; aici sunt reimplementate în pachetul fotografic (fără dependență de fișierele STYLE)."""
import binascii, re, struct, subprocess

try:
    from compression import zstd as _zstd
    def _zd(b): return _zstd.decompress(b)
    def _zc(b): return _zstd.compress(b)
except Exception:   # în afara Resolve (teste): CLI zstd
    def _zd(b): return subprocess.run(["zstd", "-d", "-q", "-c"], input=b, capture_output=True, check=True).stdout
    def _zc(b): return subprocess.run(["zstd", "-q", "-c"], input=b, capture_output=True, check=True).stdout

PLUGIN_ID = "dev.gordas.photo.develop"
CONTEXT = "OfxImageEffectContextFilter"
STAGE_LABELS = {1: "FotoAsist · 1 Liniar", 2: "FotoAsist · 2 Log", 3: "FotoAsist · 3 GDC DRT"}

def rv(b, i):
    r = s = 0
    while True:
        c = b[i]; i += 1; r |= (c & 0x7F) << s; s += 7
        if not c & 0x80: return r, i
def wv(n):
    out = bytearray()
    while True:
        b = n & 0x7F; n >>= 7
        if n: out.append(b | 0x80)
        else: out.append(b); return bytes(out)
def parse(b):
    i = 0; out = []
    while i < len(b):
        k, i = rv(b, i); f, w = k >> 3, k & 7
        if w == 0: v, i = rv(b, i)
        elif w == 1: v = b[i:i + 8]; i += 8
        elif w == 5: v = b[i:i + 4]; i += 4
        elif w == 2: n, i = rv(b, i); v = b[i:i + n]; i += n
        else: raise ValueError("wire type %d" % w)
        out.append((f, w, v))
    return out
def enc(msg):
    out = bytearray()
    for f, w, v in msg:
        out += wv((f << 3) | w)
        if w == 0: out += wv(v)
        elif w == 2: out += wv(len(v)) + v
        else: out += v
    return bytes(out)
def S(f, text): return (f, 2, text.encode("utf-8"))
def V(f, n): return (f, 0, n)
def M(f, msg): return (f, 2, enc(msg))
def D(f, x): return (f, 1, struct.pack("<d", x))

def param_entry(name, kind, value):
    if kind == "d": val = [D(2, float(value))]
    elif kind == "s": val = [S(5, value)]
    elif kind == "c": i = int(value); val = [M(4, [V(1, 2 * i if i >= 0 else -2 * i - 1)])]
    elif kind == "b": val = [V(3, 1 if value else 0)]
    else: raise ValueError(kind)
    return (5, 2, enc([S(1, name), M(2, val)]))

def read_drx(path):
    """(xml, [hex Body…], [DbId versiuni…])."""
    s = open(path, encoding="utf-8").read()
    return s, re.findall(r"<Body>([0-9a-fA-F]+)</Body>", s), re.findall(r'<ListMgt::LmVersion DbId="([^"]+)"', s)

def _star(s):   # câmp 5 (string) împachetat în valoarea atributului
    b = s.encode("utf-8"); return b"\x2a" + wv(len(b)) + b

def _node(index, x, y, label, version_guid, params):
    ctx = "%s_%s_%d" % (CONTEXT, version_guid, index)
    entries = [(1, 2, enc([V(1, 3221225473), M(2, [V(2, 2)])])), (1, 2, enc([V(1, 3221225545), (2, 2, _star(PLUGIN_ID))])), (1, 2, enc([V(1, 3221225566), (2, 2, _star(ctx))])),
               (1, 2, enc([V(1, 3221225571), M(2, [V(4, 1)])]))]
    p = [V(1, 5195353), S(2, PLUGIN_ID), S(3, CONTEXT), V(4, 1)] + [param_entry(n, k, v) for n, k, v in params]
    entries.append((1, 2, enc([V(1, 3221225607), M(2, [M(21, p)])]))); entries.append((1, 2, enc([V(1, 3221225682), M(2, [V(4, 1)])])))
    return M(7, [V(1, index), V(2, index), V(4, x), V(5, y), S(6, label), V(7, 1), V(8, 44), M(9, [(2, 2, b"\x03\x04\x05\x06\x12")]),
                 (10, 2, b"".join(wv(0x0a) + wv(len(e[2])) + e[2] for e in entries)), V(12, 1281929600 + index)])

def chain_body(template_body, nodes, version_guid):
    """template_body: corpul DECOMPRIMAT al unui grad GOL al aceluiași clip/versiune (dă dimensiunile cadrului). nodes: [{"label": str, "params": [(nume, "d"|"c"|"b", valoare)]}] în ordinea lanțului."""
    root = parse(template_body); g = parse(root[0][2]); frame = [x for x in g if x[0] == 3][0]; n = len(nodes)
    out = [V(1, n), V(2, 1), frame]
    for i, nd in enumerate(nodes, 1): out.append(_node(i, 190 + 200 * (i - 1), 180, nd["label"], version_guid, nd["params"]))
    for i in range(1, n): out.append(M(8, [V(1, i), V(3, i + 1), V(5, 64), V(6, 64), V(7, i)]))      # legături cu id-uri UNICE (același id ⇒ Resolve păstrează o singură legătură)
    out += [M(9, [V(1, 1), V(2, 80), M(3, [V(1, 1), V(2, 64), V(3, 1), V(4, 1)])]), M(10, [V(1, 2), V(2, 64), M(3, [V(1, n + 1), V(2, 64), V(3, 2), V(4, n)])]), V(12, 953662088)]
    return enc([(1, 2, enc(out))] + [x for x in root[1:]])

def write_chain_drx(template_drx, out_drx, nodes):
    """Citește șablonul (DRX exportat), înlocuiește graful din primul `<Body>` și scrie `out_drx`. Întoarce GUID-ul versiunii."""
    xml, bodies, guids = read_drx(template_drx)
    if not bodies or not guids: raise ValueError("șablon DRX fără Body/versiune")
    raw = bytes.fromhex(bodies[0]); assert raw[:1] == b"\x81"
    new = chain_body(_zd(raw[1:]), nodes, guids[0]); newhex = (b"\x81" + _zc(new)).hex()
    open(out_drx, "w", encoding="utf-8").write(xml.replace(bodies[0], newhex, 1)); return guids[0]

def read_chain(path):
    """Citire pură: pentru fiecare Body cu pluginul FotoAsist → lista nodurilor [{index, label, params{nume: valoare}}] (doar parametrii schimbați față de implicit; choice → ('choice', index))."""
    res = []
    xml, bodies, _ = read_drx(path)
    for h in bodies:
        b = bytes.fromhex(h)
        if b[:1] != b"\x81": continue
        raw = _zd(b[1:])
        if PLUGIN_ID.encode() not in raw: continue
        g = parse(parse(raw)[0][2]); nodes = []
        for f, w, v in g:
            if f != 7: continue
            n = parse(v); d = {"index": None, "label": "", "params": {}}
            for nf, nw, nv in n:
                if nf == 1 and nw == 0: d["index"] = nv
                elif nf == 6 and nw == 2: d["label"] = nv.decode("utf-8", "replace")
                elif nf == 10 and nw == 2:
                    for af, aw, av in parse(nv):
                        a = parse(av)
                        for kf, kw, kv in a:
                            if kf == 2 and kw == 2:
                                try: inner = parse(kv)
                                except Exception: continue
                                for sf, sw, sv in inner:
                                    if sf == 21 and sw == 2:
                                        for pf, pw, pv in parse(sv):
                                            if pf != 5: continue
                                            pm = parse(pv); name = next((x[2].decode() for x in pm if x[0] == 1), None); val = None
                                            for x in pm:
                                                if x[0] == 2:
                                                    for y in parse(x[2]):
                                                        if y[0] == 2 and y[1] == 1: val = struct.unpack("<d", y[2])[0]
                                                        elif y[0] == 3: val = bool(y[2])
                                                        elif y[0] == 4: z = parse(y[2])[0][2]; val = ("choice", (z >> 1) ^ -(z & 1))
                                            if name and val is not None: d["params"][name] = val
            nodes.append(d)
        res.append(nodes)
    return res

# --- hartă reglaje FotoAsist → noduri-etapă (nume vizibile în Resolve; parametrii ≠ implicit) ---
def stage_nodes(adj, stage_param=True, output=0):
    """adj: dict cu exposure, temperature, tint, shadows, highlights, contrast, saturation (valorile FotoAsist). Întoarce cele 3 noduri-etapă 1 Liniar · 2 Log · 3 GDC DRT.
    stage_param=False: pentru OFX 0.2.0 (fără `phStage`): nodurile poartă doar parametrii lor (proba mecanismului; etapele nu sunt separate până la OFX 0.3.0)."""
    def d(name, key, default=0.0):
        v = adj.get(key, default); return [(name, "d", v)] if abs(v - default) > 1e-12 else []
    fam = int(adj.get("family", 0) or 0)   # familia de lucru (0 DWG/DI implicit; 1 ACES AP1/ACEScct; 2 AWG3/LogC3; 3 AWG4/LogC4): aceeași pe TOATE nodurile; intermediarul EXR e codat în familia ei
    famp = [("phFamily", "c", fam)] if fam else []
    st = (lambda k: [("phStage", "c", k)] + famp) if stage_param else (lambda k: famp)
    lin = st(1) + d("phTemperature", "temperature") + d("phTint", "tint") + d("phExposure", "exposure") + d("phShadows", "shadows") + d("phHighlights", "highlights")
    log = st(2) + d("phContrast", "contrast", 1.0) + d("phSaturation", "saturation", 1.0)
    disp = st(3) + ([("phOutput", "c", output)] if output else [])
    return [{"label": STAGE_LABELS[1], "params": lin}, {"label": STAGE_LABELS[2], "params": log}, {"label": STAGE_LABELS[3], "params": disp}]
