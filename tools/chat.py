#!/usr/bin/env python3
"""Gegenstelle fuer CHAT auf dem MERIDIAN (Etappe 12): wartet auf einen
Anruf (oder ruft selbst an) und tauscht Zeilen aus.

    chat.py                         auf Port 6502 warten, Zeilen von der Tastatur
    chat.py 192.168.178.20:6502     selbst anrufen (IP des MiSTer; MERIDIAN mit NET "LISTEN 6502",1)
    chat.py --ki                    eine KI antwortet (lokales Ollama-Modell)
    chat.py --ki --modell qwen-c64

Mit --ki beantwortet ein Sprachmodell auf diesem Mac jede Zeile, kurz und in
der Art einer Mailbox der 80er.
"""
import argparse
import json
import socket
import sys
import threading
import urllib.request

OLLAMA = "http://localhost:11434/api/chat"
ROLLE = ("You are the sysop of a small 1980s bulletin board system, chatting with "
         "someone on a MERIDIAN 816 home computer. Answer in one or two short lines "
         "(at most 70 characters each), friendly, plain ASCII, no emoji. Answer in "
         "the language the user writes in.")


def ki_antwort(verlauf, modell):
    anfrage = json.dumps({"model": modell, "messages": verlauf, "stream": False,
                          "think": False, "options": {"num_predict": 80}}).encode()
    r = urllib.request.urlopen(urllib.request.Request(OLLAMA, anfrage, {"Content-Type": "application/json"}),
                               timeout=120)
    text = json.loads(r.read())["message"]["content"].strip()
    return [z.strip() for z in text.splitlines() if z.strip()][:3]


def main():
    a = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    a.add_argument("ziel", nargs="?", help="host:port zum Anrufen (sonst warten)")
    a.add_argument("--port", type=int, default=6502)
    a.add_argument("--ki", action="store_true")
    a.add_argument("--modell", default="qwen3.8:27b-mlx")
    o = a.parse_args()
    if o.ziel:
        host, _, port = o.ziel.rpartition(":")
        s = socket.create_connection((host, int(port)))
    else:
        srv = socket.socket()
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(("0.0.0.0", o.port))
        srv.listen(1)
        print(f"warte auf Port {o.port} ...", flush=True)
        s, adr = srv.accept()
        print("Anruf von", adr[0], flush=True)

    def senden(z):
        s.sendall(z.encode("utf-8") + b"\r\n")
        print("<", z, flush=True)

    verlauf = [{"role": "system", "content": ROLLE}]
    if o.ki:
        senden("Welcome to the MERIDIAN BBS! Type something.")
    else:
        threading.Thread(target=lambda: [senden(z.rstrip("\n")) for z in sys.stdin], daemon=True).start()
    puffer = b""
    while True:
        d = s.recv(4096)
        if not d:
            print("Verbindung beendet")
            return
        puffer += d
        while b"\n" in puffer:
            z, puffer = puffer.split(b"\n", 1)
            z = z.decode("utf-8", "replace").strip()
            if not z:
                continue
            print(">", z, flush=True)
            if o.ki:
                verlauf.append({"role": "user", "content": z})
                try:
                    antwort = ki_antwort(verlauf, o.modell)
                except Exception as e:
                    antwort = ["(the sysop is away: " + str(e)[:40] + ")"]
                verlauf.append({"role": "assistant", "content": "\n".join(antwort)})
                for zz in antwort:
                    senden(zz)


if __name__ == "__main__":
    main()
