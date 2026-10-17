"""One marker-aligned sample of the current synthetic host. No CLI or import-time I/O."""
from pathlib import Path
from collections import Counter
import ctypes, errno, hashlib, json, os, re, selectors, stat, subprocess, tempfile, threading, time

BEGIN = 'ready-began.json'
END = 'ready-ended.json'
SUBDIR = 'REC636-FirstCaptureProfile'
MAX_PROFILE = 16 * 1024 * 1024

class Gap(RuntimeError): pass

def need(value, code):
    if not value: raise Gap(code)

def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def bounded_bytes(path, limit):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        st=os.fstat(fd); need(stat.S_ISREG(st.st_mode) and st.st_size<=limit and st.st_uid==os.getuid(), 'input_type_size_or_owner')
        raw=bytearray()
        while True:
            chunk=os.read(fd,min(65536,limit+1-len(raw)))
            if not chunk:break
            raw.extend(chunk);need(len(raw)<=limit,'input_size')
        return bytes(raw)
    finally:os.close(fd)

def marker(path, phase):
    value = json.loads(bounded_bytes(path,512))
    need(isinstance(value, dict) and set(value) == {'schema','phase','pid','systemUptime','epoch'}, 'marker_schema')
    need(type(value['schema']) is int and value['schema'] == 1 and value['phase'] == phase and type(value['pid']) is int and 1 < value['pid'] < 2**31, 'marker_identity')
    need(all(type(value[k]) in (int,float) and 0 < value[k] < 10**12 for k in ['systemUptime','epoch']), 'marker_clock')
    need(value['epoch']<=time.time()+.25 and value['systemUptime']<=time.monotonic()+.25,'future_marker')
    need(abs((time.time()-value['epoch'])-(time.monotonic()-value['systemUptime'])) <= 2, 'marker_clock_domain')
    return value

class BsdInfo(ctypes.Structure):
    _fields_ = [(n,ctypes.c_uint32) for n in ('flags','status','xstatus','pid','ppid','uid','gid','ruid','rgid','svuid','svgid','reserved')] + [('comm',ctypes.c_char*16),('name',ctypes.c_char*32)] + [(n,ctypes.c_uint32) for n in ('nfiles','pgid','jobc','tdev','tpgid')] + [('nice',ctypes.c_int32),('start_sec',ctypes.c_uint64),('start_usec',ctypes.c_uint64)]

def identity(pid, device_root, products, earliest, marked_epoch):
    lib = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
    lib.proc_pidpath.argtypes=[ctypes.c_int,ctypes.c_void_p,ctypes.c_uint32];lib.proc_pidpath.restype=ctypes.c_int
    lib.proc_pidinfo.argtypes=[ctypes.c_int,ctypes.c_int,ctypes.c_uint64,ctypes.c_void_p,ctypes.c_int];lib.proc_pidinfo.restype=ctypes.c_int
    buf=ctypes.create_string_buffer(4096)
    count=lib.proc_pidpath(pid,buf,len(buf))
    if count <= 0:
        if ctypes.get_errno() in (errno.EACCES,errno.EPERM):raise PermissionError('pid_identity_denied')
        raise Gap('pid_path_unavailable')
    path=Path(buf.value.decode()).resolve()
    need(path.name=='Wander' and path.parent.name=='Wander.app' and path.is_relative_to(device_root/'data/Containers/Bundle/Application'), 'pid_not_admitted_device_app')
    info=BsdInfo();count=lib.proc_pidinfo(pid,3,0,ctypes.byref(info),ctypes.sizeof(info))
    if count <= 0:
        if ctypes.get_errno() in (errno.EACCES,errno.EPERM):raise PermissionError('pid_identity_denied')
        raise Gap('pid_info_unavailable')
    need(count==ctypes.sizeof(info) and info.pid==pid and info.uid==os.getuid() and info.ruid==os.getuid(), 'pid_uid_or_info_mismatch')
    started=info.start_sec+info.start_usec/1000000
    need(earliest-2 <= started <= marked_epoch <= time.time()+2, 'pid_start_or_stale_marker')
    hashes={}
    for name in ['Wander','Wander.debug.dylib','Info.plist']:
        installed=path.parent/name;sealed=products/'Binaries/0/Debug-iphonesimulator/Wander.app'/name
        need(installed.is_file() and not installed.is_symlink() and installed.stat().st_size <= 512*1024*1024, 'installed_product_unavailable')
        need(digest(installed)==digest(sealed), 'installed_product_mismatch');hashes[name]=digest(sealed)
    token=hashlib.sha256(f'{pid}:{info.uid}:{info.start_sec}:{info.start_usec}'.encode()).hexdigest()
    return {'startIdentitySHA256':token,'sameUID':True,'currentDeviceApp':True,'installedProductSHA256':hashes}

def curate(raw):
    """Retain static call-tree rows only. Unknown lines are counted, never echoed."""
    need(len(raw)<=MAX_PROFILE, 'profile_size')
    text=raw.decode('utf-8',errors='replace'); active=False; rows=[]; stack=[]; unknown=0; omitted=0; threads=0
    pattern=re.compile(r'^([ +!|:]*)(\d+)\s+(.+?)\s+\(in ([A-Za-z0-9_.+\-]{1,80})\)(?:\s+\+\s+\d+)?(?:\s+\[0x[0-9a-fA-F]+\])?\s*$')
    for line in text.splitlines():
        if line.strip()=='Call graph:':active=True;continue
        if active and (line.startswith('Total number in stack') or line.startswith('Sort by top') or line.startswith('Binary Images:')):active=False;continue
        if not active:omitted+=1;continue
        if not line.strip():continue
        if re.match(r'^[ +!|:]*\d+\s+Thread_',line):threads+=1;stack=[];continue
        match=pattern.fullmatch(line)
        if not match:unknown+=1;continue
        symbol=match[3]
        plain=re.fullmatch(r'[A-Za-z_$][A-Za-z0-9_.$<>:,() ?!&*+\-=#\[\]]{0,511}',symbol)
        objc=re.fullmatch(r'[-+]\[[A-Za-z_$][A-Za-z0-9_.$]*(?:\([A-Za-z0-9_.$]+\))? [A-Za-z_$][A-Za-z0-9_$]*(?::[A-Za-z0-9_$]*)*\]',symbol)
        if not (plain or objc) or re.search(r'\b0x[0-9a-fA-F]+\b',symbol):unknown+=1;continue
        depth=len(match[1]);count=int(match[2]);need(0<count<10**9 and len(rows)<100000,'profile_row_bound')
        while stack and stack[-1][0]>=depth:stack.pop()
        rows.append({'symbol':symbol,'module':match[4],'count':count,'indent':depth,'parent':stack[-1][1] if stack else None,'threadOrdinal':threads})
        stack.append((depth,len(rows)-1))
    totals=Counter()
    for row in rows:totals[(row['symbol'],row['module'])]+=row['count']
    ordered=totals.most_common(); selected=[]
    preferences=[('webp',lambda s,m:'webp' in (s+m).lower()),('posthog',lambda s,m:'posthog' in (s+m).lower()),('layout_draw',lambda s,m:any(t in (s+m).lower() for t in ['swiftui','attributegraph','layout','drawhierarchy','uikit'])),('wait_lock',lambda s,m:any(t in s.lower() for t in ['wait','lock','semaphore','mach_msg']))]
    for category,predicate in preferences:
        hit=next(((key,n) for key,n in ordered if predicate(*key) and key not in [x[0] for x in selected]),None)
        if hit:selected.append((hit[0],hit[1],category))
    for key,n in ordered:
        if len(selected)==8:break
        if key not in [x[0] for x in selected]:selected.append((key,n,'count_fill'))
    return {'selectionRule':'one representative each WebP, PostHog, UI layout/draw, wait/lock; fill by inclusive node observation count; not CPU percent','rawSHA256':hashlib.sha256(raw).hexdigest(),'rawBytes':len(raw),'rows':rows,'retainedStaticRows':len(rows),'unknownCallTreeLines':unknown,'omittedNonTreeLines':omitted,'threadHeadersCounted':threads,'completeCallTreeClaimed':False,'parentMeaning':'nearest retained ancestor by indentation; unknown rows omitted','sampleCountsAreCPUOrRunnableTime':False,'topSymbols':[{'symbol':s,'module':m,'count':n,'category':c} for (s,m),n,c in selected]}

class Observer:
    def __init__(self,out,products,device,command,cleanup):
        self.out=Path(out);self.products=Path(products);self.device=device;self.command=command;self.cleanup=cleanup
        need(re.fullmatch(r'[A-Fa-f0-9]{8}(?:-[A-Fa-f0-9]{4}){3}-[A-Fa-f0-9]{12}',device),'device_id')
        self.device_root=(Path.home()/'Library/Developer/CoreSimulator/Devices'/device).resolve()
        self.folder=self.out/'private/profile';self.stop=threading.Event();self.thread=None;self.container=None
        self.finished=None;self.finish_lock=threading.Lock();self.earliest=time.time();self.report={'diagnosticStatus':'Pending','markerStatus':'Missing','profileOverlapValid':False,'pidIdentityVerified':False,'processCPUSeconds':None,'processCPUValid':False,'stopRequired':False,'gate':None,'sample':None,'topSymbols':[]}
    def start(self):
        self.folder.mkdir();self.thread=threading.Thread(target=self._watch,name='rec636-profile',daemon=True);self.thread.start();return self
    def _end(self):
        path=self.container/'tmp'/SUBDIR/END
        need(not path.is_symlink(),'end_marker_symlink')
        return marker(path,'ready-ended') if path.exists() else None
    def _discover(self):
        base=self.device_root/'data/Containers/Data/Application'
        if not base.exists():return None
        dirs=list(base.iterdir());need(len(dirs)<=256,'container_directory_bound')
        candidates=[]
        for p in dirs:
            if p.is_symlink() or not p.is_dir():continue
            fixed=p/'tmp'/SUBDIR
            need(not (p/'tmp').is_symlink() and not fixed.is_symlink() and not (fixed/BEGIN).is_symlink(), 'candidate_marker_directory_symlink')
            if (fixed/BEGIN).exists():candidates.append(p)
        need(len(candidates)<=1,'multiple_marker_candidates')
        if not candidates:return None
        rc,data,_=self.command(['xcrun','simctl','get_app_container',self.device,'com.grayline.wander','data'],self.folder,'profile-container',timeout=5)
        need(rc==0 and 0<len(data)<=4096,'current_container_lookup_failed')
        actual=Path(data.decode().strip()).resolve();need(actual==candidates[0].resolve() and actual.is_relative_to(base.resolve()),'marker_not_current_app_container')
        self.container=actual
        fixed=actual/'tmp'/SUBDIR;need(not (actual/'tmp').is_symlink() and not fixed.is_symlink(),'marker_directory_symlink')
        return marker(fixed/BEGIN,'ready-began')
    def _sample(self,pid,scratch):
        proc=subprocess.Popen(['/usr/bin/sample',str(pid),'5','10','-mayDie','-file',str(scratch)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
        sel=selectors.DefaultSelector();streams={'stdout':hashlib.sha256(),'stderr':hashlib.sha256()};sizes=Counter();denial=False;tail=b'';reason=None
        for stream,name in [(proc.stdout,'stdout'),(proc.stderr,'stderr')]:os.set_blocking(stream.fileno(),False);sel.register(stream,selectors.EVENT_READ,name)
        began=time.monotonic();self.report['sample']={'startUptime':began,'endUptime':None,'durationSeconds':5,'intervalMilliseconds':10}
        facts={'ownedGroup':proc.pid,'term':False,'kill':False};cleanup_ok=False;failure=None;cleanup_error=None
        try:
            need(began<=self.report['gate']['begin']['systemUptime']+8,'sample_start_late_after_spawn')
            while sel.get_map() or proc.poll() is None:
                ended=self._end()
                if ended is not None:reason='gate_ended_during_sample';break
                if self.stop.is_set():reason='native_finished_during_sample';break
                if time.monotonic()-began>15:reason='sampler_wall_timeout';break
                if scratch.exists():need(not scratch.is_symlink() and scratch.stat().st_size<=MAX_PROFILE,'profile_size_or_link')
                for key,_ in sel.select(.1):
                    chunk=os.read(key.fileobj.fileno(),65536)
                    if not chunk:sel.unregister(key.fileobj);continue
                    streams[key.data].update(chunk);sizes[key.data]+=len(chunk);need(sum(sizes.values())<=1024*1024,'sampler_output_bound')
                    lower=(tail+chunk).lower();tail=lower[-512:]
                    denial|=any(s in lower for s in [b'permission denied',b'operation not permitted',b'not permitted to sample',b'cannot examine process'])
                    if denial:raise PermissionError('sampler_permission_denied')
        except BaseException as error:failure=error
        finally:
            # No second cleanup attempt or process probe after an observed denial.
            if isinstance(failure,PermissionError):self.report['stopRequired']=True
            else:
                try:self.cleanup(proc,facts);cleanup_ok=True
                except BaseException as error:cleanup_error=error;self.report['stopRequired']=True
            sel.close();proc.stdout.close();proc.stderr.close()
            self.report['sample']['endUptime']=time.monotonic()
            self.report['samplerProcess']={'exitCode':proc.returncode,'outputBytes':dict(sizes),'outputSHA256':{k:v.hexdigest() for k,v in streams.items()},'cleanupConfirmed':cleanup_ok,'rawOutputRetained':False,'permissionDenied':denial or isinstance(failure,PermissionError) or isinstance(cleanup_error,PermissionError),'initiatingCategory':str(failure) if type(failure) is Gap else type(failure).__name__ if failure else reason,'cleanupCategory':type(cleanup_error).__name__ if cleanup_error else None}
        if denial:self.report['stopRequired']=True
        if failure:return str(failure) if type(failure) is Gap else type(failure).__name__
        if cleanup_error:return type(cleanup_error).__name__
        if not cleanup_ok:return 'sampler_cleanup_unknown'
        if denial:return 'sampler_permission_denied'
        if reason:return reason
        return None if proc.returncode==0 else 'sampler_nonzero'
    def _watch(self):
        try:
            begin=None
            for _ in range(360):
                if self.stop.is_set():raise Gap('native_ended_before_marker')
                begin=self._discover()
                if begin:break
                self.stop.wait(.25)
            need(begin is not None,'marker_discovery_timeout')
            self.report['markerStatus']='Admitted';self.report['gate']={'begin':begin,'end':None}
            need(self.earliest-2<=begin['epoch']<=time.time()+2,'stale_marker')
            while time.monotonic()<begin['systemUptime']+6:
                need(not self.stop.is_set(),'native_ended_before_sample');need(self._end() is None,'gate_ended_before_sample');self.stop.wait(.05)
            need(time.monotonic()<=begin['systemUptime']+8,'sample_start_late');need(self._end() is None,'gate_ended_before_sample')
            first=identity(begin['pid'],self.device_root,self.products,self.earliest,begin['epoch'])
            self.report['identityBefore']=first
            need(time.monotonic()<=begin['systemUptime']+8,'sample_start_late_after_identity');need(self._end() is None,'gate_ended_before_sample')
            with tempfile.TemporaryDirectory(prefix='rec636-v45-profile-',dir=self.out.parent) as tmp:
                scratch=Path(tmp)/'sample.txt';sample_gap=self._sample(begin['pid'],scratch)
                if self.report['stopRequired']:raise Gap(sample_gap or 'sampler_boundary_stop')
                need(scratch.is_file() and not scratch.is_symlink(),'profile_missing')
                profile=curate(bounded_bytes(scratch,MAX_PROFILE));self.report['topSymbols']=profile['topSymbols']
                profile['partialObservation']=sample_gap is not None
                profile['diagnosticGap']=sample_gap
                self.report['sample']['selectionRule']=profile['selectionRule']
                with (self.folder/'profile.json').open('x') as f:json.dump(profile,f,indent=2);f.write('\n')
                self.report['profileSHA256']=digest(self.folder/'profile.json');self.report['rawProfileSHA256']=profile['rawSHA256'];self.report['unknownCallTreeLines']=profile['unknownCallTreeLines']
                need(profile['retainedStaticRows']>0,'no_recognized_static_tree_rows')
            final=identity(begin['pid'],self.device_root,self.products,self.earliest,begin['epoch'])
            need(final==first,'pid_identity_changed');self.report['identityAfter']=final;self.report['pidIdentityVerified']=True
            if sample_gap:raise Gap(sample_gap)
            self.report['diagnosticStatus']='SampleCollectedAwaitingGateEnd'
        except BaseException as error:
            if isinstance(error,PermissionError) or type(error) is RuntimeError:self.report['stopRequired']=True
            self.report['diagnosticStatus']='Gap';self.report['gap']=str(error) if type(error) is Gap else type(error).__name__
    def finish(self):
        with self.finish_lock:
            if self.finished is not None:return json.loads(json.dumps(self.finished))
            self.stop.set()
            if self.thread is not None:self.thread.join(45)
            if self.thread is not None and self.thread.is_alive():self.report['stopRequired']=True;self.report['diagnosticStatus']='Gap';self.report['gap']='watcher_join_unconfirmed'
            if self.container is not None and not self.report['stopRequired']:
                try:
                    end=self._end()
                    if end is not None:
                        begin=self.report['gate']['begin'];need(end['pid']==begin['pid'] and end['systemUptime']>=begin['systemUptime'] and end['epoch']>=begin['epoch'],'end_marker_mismatch')
                        self.report['gate']['end']=end
                        sample=self.report['sample'];self.report['profileOverlapValid']=bool(sample and begin['systemUptime']<=sample['startUptime']<=sample['endUptime']<=end['systemUptime'])
                    if self.report['diagnosticStatus']=='SampleCollectedAwaitingGateEnd':
                        self.report['diagnosticStatus']='Profiled' if self.report['profileOverlapValid'] else 'Gap'
                        if not self.report['profileOverlapValid']:self.report['gap']='gate_overlap_unverified'
                except BaseException as error:
                    if isinstance(error,PermissionError) or type(error) is RuntimeError:self.report['stopRequired']=True
                    self.report['diagnosticStatus']='Gap';self.report['gap']=str(error) if type(error) is Gap else type(error).__name__
            self.report['hashes']={k:self.report.get(k) for k in ['profileSHA256','rawProfileSHA256']}
            self.finished=json.loads(json.dumps(self.report))
            if self.folder.is_dir() and (self.thread is None or not self.thread.is_alive()):
                with (self.folder/'observation.json').open('x') as f:json.dump(self.finished,f,indent=2);f.write('\n')
            return json.loads(json.dumps(self.finished))
