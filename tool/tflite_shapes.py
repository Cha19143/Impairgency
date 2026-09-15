#!/usr/bin/env python3
"""Print a .tflite model's input and output tensors: name, type, shape.

Checks a model file against what the Dart code reads before it goes in
assets/models - no TensorFlow needed, the file is a flatbuffer and only a few
of its fields matter:

    python3 tool/tflite_shapes.py assets/models/face_detection_short_range.tflite
    input 0 ('input', 'float32', [1, 128, 128, 3])
    output 0 ('regressors', 'float32', [1, 896, 16])
    output 1 ('classificators', 'float32', [1, 896, 1])
"""
import struct, sys

TYPES = {0: 'float32', 1: 'float16', 2: 'int32', 3: 'uint8', 4: 'int64', 9: 'int8'}

def u32(b, o): return struct.unpack_from('<I', b, o)[0]
def i32(b, o): return struct.unpack_from('<i', b, o)[0]
def u16(b, o): return struct.unpack_from('<H', b, o)[0]

def field(b, table, index):
    vtable = table - i32(b, table)
    size = u16(b, vtable)
    slot = 4 + 2 * index
    if slot >= size: return None
    off = u16(b, vtable + slot)
    return table + off if off else None

def ref(b, pos): return pos + u32(b, pos)

def vector(b, pos):
    start = ref(b, pos)
    return start + 4, u32(b, start)

def main(path):
    b = open(path, 'rb').read()
    model = u32(b, 0)
    subgraphs_pos = field(b, model, 2)
    start, n = vector(b, subgraphs_pos)
    sub = ref(b, start)
    t_start, t_n = vector(b, field(b, sub, 0))
    def tensor(i):
        t = ref(b, t_start + 4 * i)
        s_start, s_n = vector(b, field(b, t, 0))
        shape = [i32(b, s_start + 4 * k) for k in range(s_n)]
        typ = b[field(b, t, 1)] if field(b, t, 1) else 0
        name_pos = field(b, t, 3)
        ns, nn = vector(b, name_pos) if name_pos else (0, 0)
        name = b[ns:ns + nn].decode() if name_pos else ''
        return name, TYPES.get(typ, typ), shape
    for label, idx in (('input', 1), ('output', 2)):
        v_start, v_n = vector(b, field(b, sub, idx))
        for k in range(v_n):
            print(label, k, tensor(i32(b, v_start + 4 * k)))

main(sys.argv[1])
