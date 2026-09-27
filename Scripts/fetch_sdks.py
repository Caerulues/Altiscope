#!/usr/bin/env python3
"""Fetch pinned SDKs from official distribution endpoints; no global installations."""
from pathlib import Path
import hashlib, os, subprocess, tempfile, tarfile, zipfile, urllib.request, json
root = Path(__file__).resolve().parents[1]
vendor = root / 'Vendor'
vendor.mkdir(exist_ok=True)
opener = urllib.request.build_opener()  # Honors the user's environment/system proxy configuration.
def fetch(url, path, checksum=None):
    print('Downloading', url, flush=True)
    with opener.open(url, timeout=120) as response, path.open('wb') as output:
        while block := response.read(1024*1024): output.write(block)
    if checksum and hashlib.sha256(path.read_bytes()).hexdigest() != checksum: raise RuntimeError('SDK checksum mismatch')
def unzip(archive, destination):
    destination.mkdir(parents=True, exist_ok=True)
    # ditto preserves SDK symlinks and resource layout on macOS.
    subprocess.run(['ditto','-x','-k',str(archive),str(destination)],check=True)
with tempfile.TemporaryDirectory(prefix='antiscope-sdk-') as temporary:
    tmp=Path(temporary)
    fetch('https://dl.google.com/geosdk/swiftpm/11.2.0/GoogleMaps_3p.xcframework.zip',tmp/'google.zip','3678d0581cfbdf4dc84546bc55b11defb21ba517656a0fb1cd845d68d01ea4f3')
    unzip(tmp/'google.zip',vendor/'Google')
    fetch('https://api.github.com/repos/googlemaps/ios-maps-sdk/tarball/11.2.0',tmp/'google.tar.gz')
    (vendor/'Google/Distribution').mkdir(exist_ok=True)
    subprocess.run(['tar','-xzf',str(tmp/'google.tar.gz'),'--strip-components=1','-C',str(vendor/'Google/Distribution')],check=True)
    fetch('https://a.amap.com/lbs/static/zip/AMap_iOS_3DMap_Lib_V11.1.200.zip',tmp/'amap.zip')
    unzip(tmp/'amap.zip',vendor/'AMap')
    fetch('https://amappc.oss-cn-zhangjiakou.aliyuncs.com/lbs/static/zip/AMap_iOS_Foundation_Lib_V1.8.7.zip',tmp/'foundation.zip')
    unzip(tmp/'foundation.zip',vendor/'AMap')
subprocess.run(['python3',str(root/'Scripts/generate_project.py')],check=True)
print('SDKs ready. Open Antiscope.xcodeproj.')
