"""Lucrător al punții Resolve (stdlib-only). Rulat de aplicație cu interpretorul Python livrat în Resolve (ResolvePython), JSON pe linii: o cerere pe stdin -> un răspuns pe stdout.
Cereri: {"id":N,"op":"hello"} | {"op":"ensure_project","name":S,"allowSwitch":B} | {"op":"process", ...}. Răspuns: {"id":N,"ok":true,...} sau {"id":N,"ok":false,"code":S,"message":S}.
Fapte verificate (Resolve Studio 21.1.1.10, macOS): lanțul OFX se construiește în comp.Lock()/Unlock(), parametrii se setează DUPĂ Unlock și se citesc înapoi (altfel pass-through tăcut);
GetInput nu validează opțiunile FuID => liveness verificat de aplicație pe imaginea randată. Nimic din originalele utilizatorului nu e atins; proiectul Resolve e al produsului."""
import sys, os, json, time, glob, shutil, traceback, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import drx_chain

def reply(obj): sys.stdout.write(json.dumps(obj) + "\n"); sys.stdout.flush()
def fail(rid, code, msg, **kw): reply(dict({"id": rid, "ok": False, "code": code, "message": msg}, **kw))

def connect():
    api = os.environ.get("RESOLVE_SCRIPT_API")
    if not api: raise RuntimeError("RESOLVE_SCRIPT_API lipsește")
    sys.path.append(os.path.join(api, "Modules"))
    import DaVinciResolveScript as dvr
    r = dvr.scriptapp("Resolve")
    if r is None: raise ConnectionError("Resolve nu răspunde (pornit? scripting local permis?)")
    return r

def op_hello(r, req):
    pm = r.GetProjectManager(); cur = pm.GetCurrentProject()
    return {"version": r.GetVersionString(), "product": r.GetProductName(), "python": sys.version.split()[0], "currentProject": cur.GetName() if cur else None}

def op_ensure_project(r, req):
    pm = r.GetProjectManager(); cur = pm.GetCurrentProject(); name = req["name"]
    if cur and cur.GetName() == name: return {"project": name, "switched": False, "created": False}
    if cur and not req.get("allowSwitch", False): return {"_fail": ("switch_not_allowed", "Resolve are deschis alt proiect; schimbarea cere acord", {"currentProject": cur.GetName()})}
    created = False
    if cur: pm.SaveProject()
    proj = pm.LoadProject(name) if name in (pm.GetProjectListInCurrentFolder() or []) else None
    if proj is None:
        proj = pm.CreateProject(name); created = proj is not None
    if proj is None: return {"_fail": ("project_failed", "Nu am putut deschide/crea proiectul " + name, {})}
    proj.SetSetting("colorScienceMode", "davinciYRGB")
    return {"project": name, "switched": cur is not None, "created": created}

def op_process(r, req):
    """Ruta legacy «Resolve STYLE»: încărcată doar dacă `resolve_worker_legacy.py` e prezent (build de dezvoltare)."""
    try: import resolve_worker_legacy as legacy
    except ImportError: return {"_fail": ("legacy_not_included", "Calea «Resolve STYLE» nu e inclusă în acest pachet (doar build-uri de dezvoltare)", {})}
    return legacy.op_process(r, req)

# ---------- „Continuă în Resolve”: lanț de noduri-etapă FotoAsist în pagina Color, într-o VERSIUNE de culoare proprie ----------
# Fapte verificate (Resolve 21.1.1): AddVersion/LoadVersionByName/DeleteVersionByName; GrabStill + ExportStills(drx) dau gradul curent; `ApplyGradeFromDRX` aplică un graf (șablon DRX din ACELAȘI clip, Body înlocuit — drx_chain.py);
# API NU adaugă OFX pe noduri și nu setează parametrii lor, deci mecanismul e DRX. Aplicarea se face din pagina Edit; graful NU se citește în același apel (două blocări Resolve observate la STYLE) — citirea e un apel separat, ulterior.
_STILL_EXT = {".drx", ".png", ".jpg", ".jpeg", ".tif", ".tiff", ".dpx", ".exr"}
def _pid_alive(pid):
    try: os.kill(pid, 0); return True
    except ProcessLookupError: return False
    except PermissionError: return True
def _purge_own_stills(base):
    """Curăță DOAR directoare proprii (prefix + marcaj cu PID), regenerabile (doar stills), ale căror proprietar nu mai rulează și mai vechi de 24 h; doar în folderul temporar dat de aplicație (FOTOASIST_TEMP_ROOT), niciodată în TMPDIR-ul de sistem."""
    if os.environ.get("FOTOASIST_TEMP_ROOT") != base: return
    now = time.time()
    for d in glob.glob(os.path.join(base, "fotoasist_drx_*")):
        try:
            mk = os.path.join(d, ".fotoasist-owner")
            if os.path.islink(d) or not os.path.isfile(mk): continue
            pid = int(open(mk).read().split()[0])
            if _pid_alive(pid) or now - os.path.getmtime(d) <= 86400: continue
            names = os.listdir(d)
            if any(n != ".fotoasist-owner" and os.path.splitext(n)[1].lower() not in _STILL_EXT for n in names): continue
            shutil.rmtree(d, ignore_errors=True)
        except (OSError, ValueError): pass
def _stills_tmp():
    base = tempfile.gettempdir(); _purge_own_stills(base)
    d = tempfile.mkdtemp(prefix="fotoasist_drx_")
    with open(os.path.join(d, ".fotoasist-owner"), "w") as f: f.write("%d\n" % os.getpid())
    return d

def op_handoff(r, req):
    pm = r.GetProjectManager(); proj = pm.GetCurrentProject()
    if not proj or proj.GetName() != req["project"]: return {"_fail": ("wrong_project", "Proiectul curent nu e proiectul FotoAsist (%s)" % (proj.GetName() if proj else None), {})}
    exr = req["exr"]; stem = os.path.splitext(os.path.basename(exr))[0]; mp = proj.GetMediaPool(); tl_name = req.get("timelineName") or ("FotoAsist · " + stem)
    pm.SaveProject()                                   # starea curentă a proiectului e salvată ÎNAINTE de orice modificare
    clip = next((c for c in (mp.GetRootFolder().GetClipList() or []) if c.GetClipProperty("File Path") == exr), None)
    if clip is None:
        imp = mp.ImportMedia([exr]); clip = imp[0] if imp else None
    if clip is None: return {"_fail": ("import_failed", "Resolve nu a importat " + exr, {})}
    tl = next((proj.GetTimelineByIndex(i) for i in range(1, proj.GetTimelineCount() + 1) if proj.GetTimelineByIndex(i).GetName() == tl_name), None)
    if tl is not None:   # protecție: o cronologie existentă își păstrează media; dacă nu e EXACT intermediarul cerut, nu se aplică o versiune nouă peste media veche
        its0 = tl.GetItemListInTrack("video", 1) or []; mpi = its0[0].GetMediaPoolItem() if its0 else None
        if mpi is None or mpi.GetClipProperty("File Path") != exr:
            return {"_fail": ("timeline_media_mismatch", "Cronologia «%s» există dar are altă media decât intermediarul cerut (%s)" % (tl_name, exr), {})}
    created = tl is None
    if created:
        proj.SetSetting("timelineResolutionWidth", str(req["width"])); proj.SetSetting("timelineResolutionHeight", str(req["height"]))   # setările de rezoluție sunt GLOBALE în proiect; se impun înaintea creării
        tl = mp.CreateTimelineFromClips(tl_name, [clip])
        if tl is None: return {"_fail": ("timeline_failed", "Nu am putut crea cronologia", {})}
        try: tl.SetSetting("useCustomSettings", "1"); tl.SetSetting("timelineResolutionWidth", str(req["width"])); tl.SetSetting("timelineResolutionHeight", str(req["height"]))
        except Exception: pass
    proj.SetCurrentTimeline(tl); items = tl.GetItemListInTrack("video", 1)
    if not items: return {"_fail": ("no_clip", "Cronologia nu are clip", {})}
    item = items[0]; vname = "FotoAsist · " + time.strftime("%Y-%m-%d %H:%M:%S")
    r.OpenPage("color"); tl.SetCurrentTimecode(tl.GetStartTimecode())
    if not item.AddVersion(vname, 0): return {"_fail": ("version_failed", "AddVersion a eșuat", {})}   # versiunea fotografului („Version 1” etc.) rămâne neatinsă
    album = proj.GetGallery().GetCurrentStillAlbum(); still = tl.GrabStill()
    if still is None: return {"_fail": ("still_failed", "GrabStill a eșuat", {})}
    d = _stills_tmp(); ok = album.ExportStills([still], d, "tpl", "drx"); album.DeleteStills([still])
    tpl = next(iter(glob.glob(os.path.join(d, "*.drx"))), None)
    if not ok or not tpl: return {"_fail": ("template_failed", "Șablonul DRX nu s-a exportat", {})}
    nodes = req.get("customNodes") or drx_chain.stage_nodes(req["adjustments"], stage_param=bool(req.get("stageParam", False)), output=int(req.get("output", 0)))   # customNodes: doar teste
    out = os.path.join(d, "chain.drx"); guid = drx_chain.write_chain_drx(tpl, out, nodes)
    r.OpenPage("edit"); time.sleep(1.0)
    applied = bool(item.GetNodeGraph().ApplyGradeFromDRX(out, 0))
    time.sleep(1.0); r.OpenPage("color"); pm.SaveProject()
    return {"timeline": tl_name, "version": vname, "applied": applied, "createdTimeline": created, "versionGuid": guid, "nodes": [n["label"] for n in nodes], "drx": out, "stageParam": bool(req.get("stageParam", False))}

def _current_item(proj, name=None):
    if name:   # cronologia fotografiei (nu cea întâmplătoare curentă)
        for i in range(1, proj.GetTimelineCount() + 1):
            t = proj.GetTimelineByIndex(i)
            if t.GetName() == name: proj.SetCurrentTimeline(t); break
    tl = proj.GetCurrentTimeline(); items = tl.GetItemListInTrack("video", 1) if tl else []
    return tl, (items[0] if items else None)

def op_handoff_verify(r, req):
    """Citire SEPARATĂ (apel ulterior): numărul și etichetele nodurilor, pluginul de pe fiecare, versiunea curentă."""
    proj = r.GetProjectManager().GetCurrentProject(); tl, item = _current_item(proj, req.get("timeline"))
    if item is None: return {"_fail": ("no_clip", "Nu există clip curent", {})}
    g = item.GetNodeGraph(); n = g.GetNumNodes()
    return {"timeline": tl.GetName(), "version": item.GetCurrentVersion(), "numNodes": n, "nodes": [{"index": i, "label": g.GetNodeLabel(i), "tools": g.GetToolsInNode(i)} for i in range(1, n + 1)]}

def op_handoff_read(r, req):
    """Recuperare prin DRX a REGLAJELOR MANUALE ale pluginului FotoAsist (doar parametrii ≠ implicit) din gradul curent: GrabStill → ExportStills(drx) → parser. NU citește măști, keyframe-uri sau alte efecte."""
    proj = r.GetProjectManager().GetCurrentProject(); tl, item = _current_item(proj, req.get("timeline"))
    if item is None: return {"_fail": ("no_clip", "Nu există clip curent", {})}
    r.OpenPage("color"); album = proj.GetGallery().GetCurrentStillAlbum(); still = tl.GrabStill()
    if still is None: return {"_fail": ("still_failed", "GrabStill a eșuat", {})}
    d = _stills_tmp(); ok = album.ExportStills([still], d, "rd", "drx"); album.DeleteStills([still]); f = next(iter(glob.glob(os.path.join(d, "*.drx"))), None)
    if not ok or not f: return {"_fail": ("export_failed", "Export DRX eșuat", {})}
    chains = drx_chain.read_chain(f)
    return {"timeline": tl.GetName(), "version": item.GetCurrentVersion(), "chain": chains[0] if chains else [], "drx": f}

def op_handoff_render(r, req):
    """Randează un cadru al clipului curent (rezultatul REAL din Resolve, cu toate nodurile) într-un TIFF 16 biți."""
    proj = r.GetProjectManager().GetCurrentProject(); tl, item = _current_item(proj, req.get("timeline"))
    if item is None: return {"_fail": ("no_clip", "Nu există clip curent", {})}
    outdir = req["outDir"]; base = req["name"]; os.makedirs(outdir, exist_ok=True)
    for f in glob.glob(os.path.join(outdir, base + "*")): os.remove(f)
    proj.SetCurrentRenderFormatAndCodec("tif", "RGB16"); fr = item.GetStart()
    proj.SetRenderSettings({"SelectAllFrames": False, "MarkIn": fr, "MarkOut": fr, "TargetDir": outdir, "CustomName": base, "FormatWidth": int(req["width"]), "FormatHeight": int(req["height"]), "ExportVideo": True, "ExportAudio": False})
    j = proj.AddRenderJob(); proj.StartRendering(j); t0 = time.time()
    while proj.IsRenderingInProgress():
        if time.time() - t0 > 180: proj.StopRendering(); break
        time.sleep(0.2)
    proj.DeleteRenderJob(j); outs = sorted(glob.glob(os.path.join(outdir, base + "*.tif")))
    if not outs: return {"_fail": ("render_failed", "Randarea nu a produs fișier", {})}
    final = os.path.join(outdir, base + ".tif"); os.replace(outs[0], final)
    return {"output": final, "version": item.GetCurrentVersion(), "seconds": round(time.time() - t0, 2)}

OPS = {"hello": op_hello, "ensure_project": op_ensure_project, "process": op_process, "handoff": op_handoff, "handoff_verify": op_handoff_verify, "handoff_read": op_handoff_read, "handoff_render": op_handoff_render}

def main():
    try: r = connect()
    except Exception as e:
        reply({"id": 0, "ok": False, "code": "connect_failed", "message": str(e)}); return
    for line in sys.stdin:
        line = line.strip()
        if not line: continue
        try: req = json.loads(line); rid = req.get("id")
        except Exception: reply({"id": None, "ok": False, "code": "bad_json", "message": "linie ne-JSON"}); continue
        if req.get("op") == "quit": reply({"id": rid, "ok": True}); return
        fn = OPS.get(req.get("op"))
        if not fn: fail(rid, "unknown_op", str(req.get("op"))); continue
        try:
            res = fn(r, req)
            if "_fail" in res: c, m, extra = res["_fail"]; fail(rid, c, m, **extra)
            else: reply(dict({"id": rid, "ok": True}, **res))
        except Exception as e: fail(rid, "exception", "%s: %s" % (type(e).__name__, e), trace=traceback.format_exc(limit=4))

if __name__ == "__main__": main()
