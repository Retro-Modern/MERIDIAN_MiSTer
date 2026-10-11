"""Browser-Ablage fuer Laufwerk 3 (ATLAS, Teil E)

Der Netzdienst DRAHT bietet damit eine Webseite an (http://mister:816/):
die Dateien im Ordner games/MERIDIAN/files mit Herunterladen und Loeschen,
hineinziehen zum Hochladen (mehrere nacheinander, mit Fortschritt). Was
ATLAS mit SEND schickt, laedt die offene Seite gleich herunter.

    GET    /                    die Seite
    GET    /liste               Dateien als JSON (Name, Name am MERIDIAN, Groesse, Zeit)
    GET    /datei/NAME          herunterladen
    PUT    /datei/NAME          hochladen (Inhalt = Datei; Kopfzeile X-Absender optional)
    DELETE /datei/NAME          loeschen
    GET    /ereignisse?ab=N     von ATLAS geschickte Dateien ab Nummer N

Dazu holt der Dienst fuer ATLAS Dateien aus dem Netz (herunterladen(),
nur http und https) - der Stand erscheint wie beim Hochladen.

Nur aus dem Heimnetz (private Adressen), nur im Ordner files, hoechstens
64 MB je Datei. Eine Datei entsteht erst als .NAME.teil und bekommt ihren
Namen, wenn sie ganz da ist - der MERIDIAN sieht nie eine halbe.

Fuer ATLAS steht der Stand im DRAHT-Fenster ab $40 (block()):
    +0  0 nichts, 1 empfaengt gerade, 2 eben fertig, 3 fehlgeschlagen
    +1  Zaehler: aendert sich, sobald sich im Ordner etwas aendert (auch per
        SMB, FTP, scp) - ATLAS liest Laufwerk 3 dann neu
    +2  Nummer der Uebertragung (+1 je neuer)
    +4  Bytes bisher, +8 Gesamtgroesse (je 32 Bit)
    +12 Name am MERIDIAN (8.3, 0 dahinter), +25 Absender (16 Zeichen, 0 dahinter)
    +42 Adresse der Seite ("192.168.178.20:816", 21 Zeichen, 0 dahinter)
"""
import ipaddress
import json
import os
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

GRENZE = 64 * 1024 * 1024
BLOCK = 64


def name_pruefen(name):
    """Nur ein Dateiname, kein Pfad; None, wenn er nicht taugt"""
    name = name.strip()
    if (not name or name in (".", "..") or name.startswith(".") or len(name) > 120
            or any(c in name for c in "/\\\0") or os.path.basename(name) != name):
        return None
    return name


def absender_aus(kopf, adresse):
    a = kopf.get("X-Absender", "").strip()
    if a:
        return a[:16]
    ua = kopf.get("User-Agent", "")
    for wort, name in (("iPhone", "iPhone"), ("iPad", "iPad"), ("Android", "Android"),
                       ("Macintosh", "Mac"), ("Windows", "PC"), ("Linux", "Linux")):
        if wort in ua:
            return name
    return adresse[:16]


class Ablage:
    def __init__(self, ordner, kurzname, zu_meridian):
        self.ordner = ordner
        self.kurzname = kurzname            # Dateiname -> Name am MERIDIAN (8.3)
        self.zu_meridian = zu_meridian
        self.sperre = threading.Lock()
        self.zustand = 0
        self.bytes = self.gesamt = 0
        self.name = self.absender = ""
        self.empfang_nr = 0
        self.zaehler = 0
        self.signatur = None
        self.pruef_zeit = 0.0
        self.gesendet = []                  # (Nummer, Dateiname) von ATLAS
        self.gesendet_nr = 0
        self.adresse = ""                   # "192.168.178.20:816" (setzt der Dienst)

    # ---------------------------------------------- fuer den Netzdienst
    def ordner_pruefen(self):
        """Etwa jede Sekunde: hat sich im Ordner etwas geaendert?"""
        jetzt = time.time()
        if jetzt - self.pruef_zeit < 1.0:
            return
        self.pruef_zeit = jetzt
        try:
            sig = []
            for n in os.listdir(self.ordner):
                if n.startswith("."):
                    continue
                p = os.path.join(self.ordner, n)
                if os.path.isfile(p):
                    st = os.stat(p)
                    sig.append((n, st.st_size, int(st.st_mtime)))
            sig.sort()
        except OSError:
            return
        if sig != self.signatur:
            if self.signatur is not None:
                self.zaehler = (self.zaehler + 1) & 0xFF
            self.signatur = sig

    def geaendert(self):
        self.pruef_zeit = 0.0

    def block(self):
        with self.sperre:
            name = self.zu_meridian(self.name)[:12].ljust(13, b"\0")
            absender = self.zu_meridian(self.absender)[:16].ljust(17, b"\0")
            return (bytes([self.zustand, self.zaehler, self.empfang_nr & 0xFF, 0])
                    + min(self.bytes, 0xFFFFFFFF).to_bytes(4, "little")
                    + min(self.gesamt, 0xFFFFFFFF).to_bytes(4, "little") + name + absender
                    + self.adresse.encode("ascii", "replace")[:21].ljust(22, b"\0"))

    def empfangen(self, name, lesen, laenge, absender):
        """Datei name aus lesen(n) in den Ordner: erst .NAME.teil, dann der
        Name. laenge = None: unbekannt (lesen liefert b"" am Ende). True: gut"""
        ziel = os.path.join(self.ordner, name)
        teil = os.path.join(self.ordner, "." + name + ".teil")
        kurz = name
        for k, e, n in self.kurzname(name):       # so heisst sie am MERIDIAN
            if n == name:
                kurz = k + ("." + e if e else "")
        with self.sperre:
            self.zustand, self.bytes, self.gesamt = 1, 0, laenge or 0
            self.name, self.absender = kurz, absender
            self.empfang_nr = (self.empfang_nr + 1) & 0xFF
        gut = False
        try:
            with open(teil, "wb") as f:
                da = 0
                while laenge is None or da < laenge:
                    stueck = lesen(65536 if laenge is None else min(laenge - da, 65536))
                    if not stueck:
                        break
                    da += len(stueck)
                    if da > GRENZE:
                        raise OSError("zu gross")
                    f.write(stueck)
                    with self.sperre:
                        self.bytes = da
                        if laenge is None:
                            self.gesamt = da
                f.flush()
                os.fsync(f.fileno())
            gut = laenge is None or da == laenge
            if gut:
                os.replace(teil, ziel)
        except OSError as e:
            print("Ablage:", e, flush=True)
        finally:
            if not gut and os.path.exists(teil):
                os.remove(teil)
            with self.sperre:
                self.zustand = 2 if gut else 3
            self.geaendert()
        if gut:
            print("Ablage: empfangen", name, da, "Bytes von", absender, flush=True)
        return gut

    def herunterladen(self, url, oeffnen):
        """Fuer ATLAS (Art 11): url im Hintergrund nach files holen"""
        if "://" not in url:
            url = "http://" + url
        teile = urllib.parse.urlsplit(url)
        if teile.scheme not in ("http", "https") or not teile.netloc:
            return False

        aus_url = name_pruefen(urllib.parse.unquote(teile.path.rsplit("/", 1)[-1]))

        def holen():
            name = None
            try:
                with oeffnen(url) as r:
                    kopf = r.headers.get("Content-Disposition", "")
                    if "filename=" in kopf:
                        name = name_pruefen(kopf.split("filename=")[-1].strip('"; '))
                    if not name:
                        name = name_pruefen(urllib.parse.unquote(urllib.parse.urlsplit(r.geturl()).path.rsplit("/", 1)[-1]))
                    laenge = r.headers.get("Content-Length")
                    laenge = int(laenge) if laenge and laenge.isdigit() else None
                    if laenge and laenge > GRENZE:
                        raise OSError("zu gross")
                    self.empfangen(name or "DOWNLOAD", r.read, laenge, teile.hostname or "?")
            except Exception as e:
                print("Ablage: herunterladen", url, "-", e, flush=True)
                with self.sperre:
                    self.zustand, self.name = 3, (name or aus_url or "DOWNLOAD")[:12]
                    self.absender = teile.hostname or "?"
                    self.empfang_nr = (self.empfang_nr + 1) & 0xFF

        threading.Thread(target=holen, daemon=True).start()
        return True

    def senden(self, dateiname):
        with self.sperre:
            self.gesendet_nr += 1
            self.gesendet.append((self.gesendet_nr, dateiname))
            del self.gesendet[:-50]

    # ---------------------------------------------- Webseite
    def liste(self):
        aus = []
        for kurz, e, n in self.kurzname():
            p = os.path.join(self.ordner, n)
            try:
                st = os.stat(p)
            except OSError:
                continue
            aus.append({"name": n, "meridian": kurz + ("." + e if e else ""),
                        "groesse": st.st_size, "zeit": int(st.st_mtime)})
        return aus

    def starten(self, port):
        ablage = self

        class Seite(BaseHTTPRequestHandler):
            server_version = "DRAHT"

            def log_message(self, f, *a):
                pass

            def heimnetz(self):
                try:
                    ip = ipaddress.ip_address(self.client_address[0])
                    if getattr(ip, "ipv4_mapped", None):
                        ip = ip.ipv4_mapped
                    if ip.is_private or ip.is_loopback or ip.is_link_local:
                        return True
                except ValueError:
                    pass
                self.antwort(403, b"only from the home network\n", "text/plain")
                return False

            def antwort(self, code, daten, art="application/json", kopf=None):
                self.send_response(code)
                self.send_header("Content-Type", art)
                self.send_header("Content-Length", str(len(daten)))
                self.send_header("Cache-Control", "no-store")
                for k, v in (kopf or {}).items():
                    self.send_header(k, v)
                self.end_headers()
                self.wfile.write(daten)

            def dateiname(self):
                teil = urllib.parse.urlparse(self.path).path
                if not teil.startswith("/datei/"):
                    return None
                return name_pruefen(urllib.parse.unquote(teil[len("/datei/"):]))

            def do_GET(self):
                if not self.heimnetz():
                    return
                url = urllib.parse.urlparse(self.path)
                if url.path == "/":
                    return self.antwort(200, SEITE.encode("utf-8"), "text/html; charset=utf-8")
                if url.path == "/liste":
                    return self.antwort(200, json.dumps(ablage.liste()).encode())
                if url.path == "/ereignisse":
                    ab = int(urllib.parse.parse_qs(url.query).get("ab", ["0"])[0] or 0)
                    with ablage.sperre:
                        neu = [n for nr, n in ablage.gesendet if nr > ab]
                        nr = ablage.gesendet_nr
                    return self.antwort(200, json.dumps({"nr": nr, "senden": neu}).encode())
                name = self.dateiname()
                if name:
                    p = os.path.join(ablage.ordner, name)
                    if os.path.isfile(p):
                        daten = open(p, "rb").read()
                        q = urllib.parse.quote(name)
                        return self.antwort(200, daten, "application/octet-stream",
                                            {"Content-Disposition": "attachment; filename*=UTF-8''" + q})
                self.antwort(404, b"not found\n", "text/plain")

            def do_PUT(self):
                if not self.heimnetz():
                    return
                name = self.dateiname()
                try:
                    laenge = int(self.headers.get("Content-Length", "-1"))
                except ValueError:
                    laenge = -1
                if not name or laenge < 0:
                    return self.antwort(400, b"bad request\n", "text/plain")
                if laenge > GRENZE:
                    return self.antwort(413, b"too big (64 MB at most)\n", "text/plain")
                absender = absender_aus(self.headers, self.client_address[0])
                if ablage.empfangen(name, self.rfile.read, laenge, absender):
                    return self.antwort(201, json.dumps({"name": name}).encode())
                self.antwort(500, b"could not save\n", "text/plain")

            def do_DELETE(self):
                if not self.heimnetz():
                    return
                name = self.dateiname()
                p = os.path.join(ablage.ordner, name) if name else None
                if not p or not os.path.isfile(p):
                    return self.antwort(404, b"not found\n", "text/plain")
                os.remove(p)
                ablage.geaendert()
                print("Ablage: geloescht", name, flush=True)
                self.antwort(200, b"{}")

        server = ThreadingHTTPServer(("", port), Seite)
        server.daemon_threads = True
        threading.Thread(target=server.serve_forever, daemon=True).start()
        return server


SEITE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>MERIDIAN files</title>
<style>
:root { --bg:#0b1230; --feld:#141d4a; --linie:#2b3a86; --text:#dfe6ff; --matt:#8e9bd6;
        --gelb:#ffd84a; --gruen:#5be36a; --rot:#ff6b6b; }
* { box-sizing:border-box; }
body { margin:0; background:var(--bg); color:var(--text);
       font:15px/1.4 ui-monospace, Menlo, Consolas, monospace; }
header { background:linear-gradient(#2b3a86,#141d4a); padding:14px 20px; border-bottom:2px solid var(--gelb); }
header h1 { margin:0; font-size:20px; color:var(--gelb); letter-spacing:1px; }
header p { margin:2px 0 0; color:var(--matt); font-size:13px; }
main { max-width:900px; margin:0 auto; padding:16px; }
#ablage { border:2px dashed var(--linie); border-radius:10px; padding:26px; text-align:center;
          color:var(--matt); margin-bottom:16px; cursor:pointer; }
#ablage.drueber { border-color:var(--gelb); color:var(--gelb); background:#1a2560; }
table { width:100%; border-collapse:collapse; background:var(--feld); border-radius:8px; overflow:hidden; }
th, td { padding:6px 10px; text-align:left; border-bottom:1px solid var(--linie); }
th { color:var(--gelb); font-weight:normal; }
td.zahl, th.zahl { text-align:right; }
td.m { color:var(--matt); }
a { color:var(--text); }
button { background:none; border:1px solid var(--linie); color:var(--matt); border-radius:5px;
         padding:2px 8px; font:inherit; cursor:pointer; }
button:hover { color:var(--rot); border-color:var(--rot); }
.lauf { margin:6px 0; }
.balken { height:6px; background:var(--linie); border-radius:3px; overflow:hidden; }
.balken div { height:100%; width:0; background:var(--gruen); }
footer { color:var(--matt); font-size:12px; margin-top:14px; }
@media (max-width:600px) { td.m, th.m, td.z, th.z { display:none; } }
</style></head><body>
<header><h1>MERIDIAN 816 &middot; files</h1>
<p>Drive 3 of the MERIDIAN &ndash; ATLAS shows it as 3 NET</p></header>
<main>
<div id="ablage">Drop files here to send them to the MERIDIAN &ndash; or click to choose
<input id="wahl" type="file" multiple hidden></div>
<div id="laeufe"></div>
<table><thead><tr><th>File</th><th class="m">on the MERIDIAN</th><th class="zahl">Size</th>
<th class="z">Date</th><th></th></tr></thead><tbody id="liste"></tbody></table>
<footer>Only in your home network. Files sent with SEND in ATLAS download here by themselves
while this page is open.</footer>
</main>
<script>
const liste = document.getElementById("liste"), ablage = document.getElementById("ablage"),
      wahl = document.getElementById("wahl"), laeufe = document.getElementById("laeufe");
const zahl = n => n.toLocaleString("en-US").replace(/,/g, " ");
function zeigen(dateien) {
  liste.innerHTML = "";
  for (const d of dateien) {
    const tr = document.createElement("tr");
    const datum = new Date(d.zeit * 1000).toLocaleString();
    const q = encodeURIComponent(d.name);
    tr.innerHTML = `<td><a href="/datei/${q}" download></a></td><td class="m"></td>
      <td class="zahl">${zahl(d.groesse)}</td><td class="z m">${datum}</td>
      <td><button title="Delete">&#x2715;</button></td>`;
    tr.querySelector("a").textContent = d.name;
    tr.querySelector("td.m").textContent = d.meridian;
    tr.querySelector("button").onclick = async () => {
      if (!confirm("Delete " + d.name + "?")) return;
      await fetch("/datei/" + q, {method: "DELETE"});
      laden();
    };
    liste.appendChild(tr);
  }
}
async function laden() { zeigen(await (await fetch("/liste")).json()); }
function hochladen(datei) {
  return new Promise(fertig => {
    const zeile = document.createElement("div");
    zeile.className = "lauf";
    zeile.innerHTML = `<span></span><div class="balken"><div></div></div>`;
    zeile.querySelector("span").textContent = datei.name;
    laeufe.appendChild(zeile);
    const xhr = new XMLHttpRequest();
    xhr.open("PUT", "/datei/" + encodeURIComponent(datei.name));
    xhr.upload.onprogress = e => { if (e.lengthComputable)
      zeile.querySelector(".balken div").style.width = (100 * e.loaded / e.total) + "%"; };
    xhr.onloadend = () => {
      if (xhr.status === 201) zeile.remove();
      else zeile.querySelector("span").textContent = datei.name + " - " + (xhr.responseText || "failed");
      fertig();
    };
    xhr.send(datei);
  });
}
async function alle(dateien) { for (const d of dateien) await hochladen(d); laden(); }
ablage.onclick = () => wahl.click();
wahl.onchange = () => alle([...wahl.files]);
ablage.ondragover = e => { e.preventDefault(); ablage.classList.add("drueber"); };
ablage.ondragleave = () => ablage.classList.remove("drueber");
ablage.ondrop = e => { e.preventDefault(); ablage.classList.remove("drueber"); alle([...e.dataTransfer.files]); };
let ereignis = -1;
async function horchen() {
  try {
    const r = await (await fetch("/ereignisse?ab=" + Math.max(ereignis, 0))).json();
    if (ereignis >= 0) for (const n of r.senden) {
      const a = document.createElement("a");
      a.href = "/datei/" + encodeURIComponent(n); a.download = n;
      document.body.appendChild(a); a.click(); a.remove();
    }
    if (r.nr !== ereignis) { ereignis = r.nr; laden(); }
  } catch (e) {}
  setTimeout(horchen, 1000);
}
laden(); horchen();
setInterval(laden, 5000);
</script></body></html>
"""
