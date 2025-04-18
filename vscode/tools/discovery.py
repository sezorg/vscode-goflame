#!/usr/bin/env python3

from fastapi import FastAPI
import re
import netifaces

from wsdiscovery.discovery import ThreadedWSDiscovery as WSDiscovery

app = FastAPI()


class Finder:
    def __init__(self):
        self.ips = list()
        for iface in netifaces.interfaces():
            if netifaces.AF_INET in netifaces.ifaddresses(iface):
                self.ips.append(
                    netifaces.ifaddresses(iface)[netifaces.AF_INET][0]["addr"]
                )
        self.scope = [".".join(ip.split(".")[:2]) for ip in self.ips]
        self.wsd = WSDiscovery()

    def start(self):
        self.wsd.start()
        self.ret = self.wsd.searchServices()
        self.wsd.stop()
        self.onvif_services = [
            s for s in self.ret if str(s.getTypes()).find("onvif") >= 0
        ]
        self.urls = [ip for s in self.onvif_services for ip in s.getXAddrs()]
        self.ips = [
            ip for url in self.urls for ip in re.findall(r"\d+\.\d+\.\d+\.\d+", url)
        ]
        self.lst = [
            ip for ip in self.ips if any(ip.startswith(sp) for sp in self.scope)
        ]
        return {"results": self.lst}


finder = Finder()


@app.get("/cameras")
def find_cameras():
    return {"cameras": finder.start()}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app)