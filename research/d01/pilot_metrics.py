"""Local process telemetry only; never load Torch/model to obtain metadata."""
import ctypes as ct
import importlib.metadata
import os
import platform
import re
import sys
import time
from datetime import datetime, timezone

def environment(torch_module=None, device=None):
    versions={}
    for name in ('torch','torchvision','numpy','scipy','opencv-python','opencv-python-headless','Pillow','matplotlib'):
        try:versions[name]=importlib.metadata.version(name)
        except importlib.metadata.PackageNotFoundError:versions[name]=None
    return dict(python_version=sys.version,python_executable=sys.executable,implementation=platform.python_implementation(),
        pid=os.getpid(),parent_pid=os.getppid(),platform=platform.platform(),packages=versions,
        torch_runtime_version=None if torch_module is None else str(torch_module.__version__),
        torch_threads=None if torch_module is None else torch_module.get_num_threads(),
        torch_interop_threads=None if torch_module is None else torch_module.get_num_interop_threads(),device=device,
        torch_runtime_measured=torch_module is not None)

def _windows_memory():
    try:
        from ctypes import wintypes as w
        class C(ct.Structure):
            _fields_=[('cb',w.DWORD),('PageFaultCount',w.DWORD)]+[(n,ct.c_size_t) for n in ('PeakWorkingSetSize','WorkingSetSize','QuotaPeakPagedPoolUsage','QuotaPagedPoolUsage','QuotaPeakNonPagedPoolUsage','QuotaNonPagedPoolUsage','PagefileUsage','PeakPagefileUsage','PrivateUsage')]
        kernel=ct.WinDLL('kernel32',use_last_error=True);psapi=ct.WinDLL('psapi',use_last_error=True)
        kernel.GetCurrentProcess.restype=w.HANDLE;psapi.GetProcessMemoryInfo.argtypes=[w.HANDLE,ct.POINTER(C),w.DWORD]
        c=C();c.cb=ct.sizeof(c)
        if not psapi.GetProcessMemoryInfo(kernel.GetCurrentProcess(),ct.byref(c),c.cb):raise OSError()
        return dict(working_set_bytes=c.WorkingSetSize,os_peak_working_set_bytes=c.PeakWorkingSetSize,memory_status='measured_windows_process')
    except Exception:
        return dict(working_set_bytes=None,os_peak_working_set_bytes=None,memory_status='unavailable_with_current_method')

def _linux_proc_memory(status_path='/proc/self/status'):
    """Read this process's RSS and Linux VmHWM peak RSS; values are bytes."""
    try:
        with open(status_path,encoding='ascii') as stream:
            lines=stream.readlines()
    except (OSError,UnicodeError):
        return dict(working_set_bytes=None,os_peak_working_set_bytes=None,
            memory_status='unavailable_linux_proc_status_unreadable')

    found={}
    malformed=set()
    for line in lines:
        match=re.match(r'^\s*(VmRSS|VmHWM):\s*(.*?)\s*$',line)
        if not match:
            continue
        key,value=match.groups()
        if key in found or key in malformed:
            malformed.add(key);found.pop(key,None);continue
        amount=re.fullmatch(r'(\d+)\s+kB',value)
        if amount is None:
            malformed.add(key);continue
        found[key]=int(amount.group(1))*1024

    rss=found.get('VmRSS');peak=found.get('VmHWM')
    if rss is not None and peak is not None:
        status='measured_linux_proc_status'
    else:
        missing=sorted(({'VmRSS','VmHWM'}-set(found)) | malformed)
        status='partial_linux_proc_status:'+','.join(missing)
    return dict(working_set_bytes=rss,os_peak_working_set_bytes=peak,memory_status=status)

def memory():
    system=platform.system()
    if system=='Windows':
        return _windows_memory()
    if system=='Linux':
        return _linux_proc_memory()
    return dict(working_set_bytes=None,os_peak_working_set_bytes=None,
        memory_status='unavailable_unsupported_platform')

class Metrics:
    def __init__(self, clock=time.perf_counter, cpu=time.process_time):
        self.clock,self.cpu=clock,cpu;self.start=clock();self.last=None
        self.timings={k:None for k in ('runtime_initialization_s','model_load_s','raw_phase_s','decode_s','preprocess_s','input_save_s','forward_s','prediction_call_s','raw_jsonl_write_s','state_checkpoint_write_s','postprocess_s','postprocess_detail_write_s','report_files_write_s')}
    def add(self,name,seconds):self.timings[name]=(self.timings.get(name) or 0)+seconds
    def sample(self):
        wall,cpu=self.clock(),self.cpu();percent=None
        if self.last and wall>self.last[0]:percent=100*(cpu-self.last[1])/(wall-self.last[0])
        self.last=(wall,cpu)
        return dict(timestamp_utc=datetime.now(timezone.utc).isoformat(),elapsed_s=wall-self.start,process_cpu_s=cpu,
            process_cpu_percent_since_previous_sample=percent,cpu_percent_scope='100 percent = one CPU core; may exceed 100; not host utilization',**memory())
    def snapshot(self):
        return dict(elapsed_s=self.clock()-self.start,timings_s=dict(self.timings),
            timing_scope='Nested wall times; not additive. model_load is inside runtime_initialization; forward is inside prediction_call and raw_phase; preprocessing/input_save/raw writes inside raw_phase; state writes overlap raw_phase and postprocess; postprocess includes postprocess_detail_write. File-write timers measure helper bodies, not all filesystem activity.',
            cpu_scope='Process CPU delta over wall time, all process threads; not a hardware or slowdown diagnosis')
