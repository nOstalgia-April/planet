import ctypes as c
from ctypes import wintypes as w
import time
import uuid


class GUID(c.Structure):
    _fields_ = [("Data1", w.DWORD), ("Data2", w.WORD), ("Data3", w.WORD), ("Data4", c.c_ubyte * 8)]


def guid(value):
    return GUID.from_buffer_copy(uuid.UUID(value).bytes_le)


def call(obj, index, restype, argtypes, *args):
    vtable = c.cast(obj, c.POINTER(c.POINTER(c.c_void_p))).contents
    return c.WINFUNCTYPE(restype, c.c_void_p, *argtypes)(vtable[index])(obj, *args)


def checked(result):
    if result < 0:
        raise OSError(hex(result & 0xFFFFFFFF))


c.windll.ole32.CoInitialize(None)
enumerator = c.c_void_p()
checked(c.windll.ole32.CoCreateInstance(
    c.byref(guid("BCDE0395-E52F-467C-8E3D-C4579291692E")), None, 23,
    c.byref(guid("A95664D2-9614-4F35-A746-DE8DB63617E6")), c.byref(enumerator)))
device = c.c_void_p()
checked(call(enumerator, 4, c.c_long, [c.c_int, c.c_int, c.POINTER(c.c_void_p)], 0, 1, c.byref(device)))
manager = c.c_void_p()
checked(call(device, 3, c.c_long, [c.POINTER(GUID), w.DWORD, c.c_void_p, c.POINTER(c.c_void_p)],
             c.byref(guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F")), 23, None, c.byref(manager)))
sessions = c.c_void_p()
checked(call(manager, 5, c.c_long, [c.POINTER(c.c_void_p)], c.byref(sessions)))
count = c.c_int()
checked(call(sessions, 3, c.c_long, [c.POINTER(c.c_int)], c.byref(count)))
for index in range(count.value):
    control = c.c_void_p()
    checked(call(sessions, 4, c.c_long, [c.c_int, c.POINTER(c.c_void_p)], index, c.byref(control)))
    control2 = c.c_void_p()
    checked(call(control, 0, c.c_long, [c.POINTER(GUID), c.POINTER(c.c_void_p)],
                 c.byref(guid("BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D")), c.byref(control2)))
    process = w.DWORD()
    checked(call(control2, 14, c.c_long, [c.POINTER(w.DWORD)], c.byref(process)))
    # Only inspect this project's existing editor and game process.
    if process.value not in [24360, 41408]:
        continue
    state = c.c_int()
    checked(call(control, 3, c.c_long, [c.POINTER(c.c_int)], c.byref(state)))
    meter = c.c_void_p()
    checked(call(control, 0, c.c_long, [c.POINTER(GUID), c.POINTER(c.c_void_p)],
                 c.byref(guid("C02216F6-8C67-4B5B-9D00-D008E73E0064")), c.byref(meter)))
    peak = 0.0
    for _ in range(20):
        value = c.c_float()
        checked(call(meter, 3, c.c_long, [c.POINTER(c.c_float)], c.byref(value)))
        peak = max(peak, value.value)
        time.sleep(0.05)
    print({"pid": process.value, "session_state": state.value, "peak_over_one_second": peak})
