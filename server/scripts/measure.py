#!/usr/bin/env python3
"""Runs only on local box. Creates isolated synthetic DB and a local secret.
Result is process RSS from /proc, not Go heap or Docker/cgroup usage.
"""
import json,os,pathlib,secrets,subprocess,time,urllib.request,statistics
root=pathlib.Path(__file__).resolve().parents[1]; out=root/'artifacts';out.mkdir(exist_ok=True)
secret=out/'load-password';secret.write_text(secrets.token_hex(24));secret.chmod(0o600)
run=out/('load-data-'+str(int(time.time())))
env=os.environ.copy();env.update(CHAT_ADDR='127.0.0.1:18088',CHAT_DATA=str(run),CHAT_ADMIN_HANDLE='admin',CHAT_ADMIN_PASSWORD_FILE=str(secret),GOMEMLIMIT='64MiB',GOMAXPROCS='2',LOAD_ADMIN_PASSWORD_FILE=str(secret))
def rss(pid):
 d={}
 for line in pathlib.Path(f'/proc/{pid}/status').read_text().splitlines():
  if line.startswith(('VmRSS:','VmHWM:')):k,v,*_=line.split();d[k[:-1]]=int(v)
 return d
with (out/'server.log').open('w') as sl,(out/'load.log').open('w') as ll:
 server=subprocess.Popen([str(root/'bin/quietchat')],env=env,stdout=sl,stderr=sl);load=None
 try:
  for _ in range(100):
   if server.poll() is not None:raise RuntimeError('server failed')
   try:
    urllib.request.urlopen('http://127.0.0.1:18088/healthz',timeout=1).close();break
   except Exception:time.sleep(.1)
  else:raise RuntimeError('health timeout')
  time.sleep(1);baseline=rss(server.pid)
  load=subprocess.Popen([str(root/'bin/loadtest'),'-url','http://127.0.0.1:18088','-clients','200','-messages','100','-hold','25s'],env=env,stdout=ll,stderr=ll)
  samples=[];started=time.time()
  while load.poll() is None:
   m=rss(server.pid);samples.append({'seconds':round(time.time()-started,2),**m});time.sleep(.1)
   if time.time()-started>120:load.kill();raise RuntimeError('load timed out')
  result={'timezone':'Asia/Shanghai','date':time.strftime('%Y-%m-%d %H:%M:%S %z'),'server_pid':server.pid,'load_exit':load.returncode,'baseline_kib':baseline,'peak_sample_rss_kib':max(x['VmRSS'] for x in samples),'final_kib':rss(server.pid),'last_10_seconds_median_rss_kib':statistics.median(x['VmRSS'] for x in samples if x['seconds']>samples[-1]['seconds']-10),'binary_bytes':(root/'bin/quietchat').stat().st_size,'scenario':'200 WS connections reuse one receiving session; 100 text messages; 20000 fanout events; loopback, Go GOMAXPROCS=2, GOMEMLIMIT=64MiB; no media or actual push','samples':samples}
  (out/'memory.json').write_text(json.dumps(result,indent=2));print(json.dumps({k:v for k,v in result.items() if k!='samples'},ensure_ascii=False,indent=2));print((out/'load.log').read_text());
  if load.returncode:raise RuntimeError('load failed')
 finally:
  if load and load.poll() is None:load.terminate();load.wait()
  server.terminate()
  try:server.wait(timeout=15)
  except subprocess.TimeoutExpired:server.kill();server.wait()
