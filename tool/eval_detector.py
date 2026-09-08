#!/usr/bin/env python3
"""Measures the detector the app ships, on annotated photographs.

    tool/eval_detector.py --fetch          # first run: builds the set (~850 images)
    tool/eval_detector.py                  # thereafter

Why this exists. "The model works" was, for a while, one photograph of a bus.
That is enough to prove a pipeline is wired up and nothing at all about whether
somebody walking down a corridor gets told about the chair. This runs the
shipped pipeline - the same letterbox, the same flat NCHW input, the same
class-agnostic suppression, the same thresholds - over Open Images validation
photographs and their boxes, and prints what it found.

**Recall, not mAP, and on purpose.** Open Images does not label every object in
every image, so a correct detection of something nobody annotated scores as a
false positive and any precision figure over the whole set is meaningless.
Recall is unharmed by missing labels: of the objects the ground truth does
name, how many were found. It is also the number this app lives on. A missed
obstacle is somebody walking into it; a spurious one is a sentence they ignore.

Precision is still reported, but only over images where the class in question
is annotated - Open Images is exhaustive per class within such an image, so an
unmatched detection there really is a false one.

**Stratified by how big the thing is in frame**, because that is the app's own
question rather than a detector benchmark's. `guidanceFor` speaks about the
largest, most central object: `Detection.extent` over 0.55 is "Stop", over 0.30
is "close". A detector that finds only big objects is a detector that does this
job, and the "close or nearer" line is the one to read.

Needs `ai-edge-litert` (or tensorflow) and `pillow`; nothing else, and no
Firebase, no device and no network once the set is built.
"""
import argparse, collections, csv, os, sys, urllib.request, concurrent.futures

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.environ.get('IMPAIRGENCY_EVAL_CACHE',
                       os.path.join(ROOT, 'build', 'detector-eval'))
OI = 'https://storage.googleapis.com/openimages/v5/validation-annotations-bbox.csv'
IMAGES = 'https://open-images-dataset.s3.amazonaws.com/validation'

# Open Images label -> the COCO name the shipped labels.txt uses. Only pairs
# that mean the same thing, so that a miss is a miss and not a taxonomy
# argument, and only things somebody walking would want to know about.
PAIRS = {
    '/m/01g317': 'person',       '/m/0199g': 'bicycle',
    '/m/0k4j': 'car',            '/m/04_sv': 'motorcycle',
    '/m/01bjv': 'bus',           '/m/07r04': 'truck',
    '/m/015qff': 'traffic light','/m/01pns0': 'fire hydrant',
    '/m/02pv19': 'stop sign',    '/m/0cvnqh': 'bench',
    '/m/0bt9lr': 'dog',          '/m/01yrx': 'cat',
    '/m/01mzpv': 'chair',        '/m/02crq1': 'couch',
    '/m/03ssj5': 'bed',          '/m/09g1w': 'toilet',
    '/m/0130jx': 'sink',         '/m/040b_t': 'refrigerator',
    '/m/07c52': 'tv',            '/m/01c648': 'laptop',
}

BANDS = [('very close (>0.55)', 0.55), ('close (0.30-0.55)', 0.30),
         ('far (<0.30)', 0.0)]


def band_of(w, h):
    e = max(w, h)
    for name, floor in BANDS:
        if e > floor:
            return name
    return BANDS[-1][0]


def build(per_class):
    os.makedirs(CACHE, exist_ok=True)
    ann = os.path.join(CACHE, 'validation-annotations-bbox.csv')
    if not os.path.exists(ann):
        print('fetching annotations...', flush=True)
        urllib.request.urlretrieve(OI, ann)

    rows = collections.defaultdict(list)
    with open(ann) as f:
        for r in csv.DictReader(f):
            if r['LabelName'] not in PAIRS:
                continue
            # A crowd in one box is not an object, and a painting of a dog is
            # not a dog in the room.
            if r['IsGroupOf'] == '1' or r['IsDepiction'] == '1':
                continue
            rows[r['ImageID']].append((
                PAIRS[r['LabelName']], float(r['XMin']), float(r['YMin']),
                float(r['XMax']), float(r['YMax'])))

    chosen, seen = {}, collections.Counter()
    for image_id, boxes in sorted(rows.items()):
        if not any(seen[c] < per_class for c, *_ in boxes):
            continue          # spread the pick; "person" would take the lot
        chosen[image_id] = boxes
        for c in {c for c, *_ in boxes}:
            seen[c] += 1

    d = os.path.join(CACHE, 'images')
    os.makedirs(d, exist_ok=True)

    def fetch(image_id):
        p = os.path.join(d, image_id + '.jpg')
        if os.path.exists(p) and os.path.getsize(p):
            return 1
        try:
            urllib.request.urlretrieve(f'{IMAGES}/{image_id}.jpg', p)
            return 1
        except Exception:
            if os.path.exists(p):
                os.remove(p)
            return 0

    print(f'fetching {len(chosen)} images...', flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
        got = sum(pool.map(fetch, chosen))

    with open(os.path.join(CACHE, 'ground-truth.csv'), 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['ImageID', 'label', 'xmin', 'ymin', 'xmax', 'ymax'])
        for image_id, boxes in chosen.items():
            if os.path.exists(os.path.join(d, image_id + '.jpg')):
                for b in boxes:
                    w.writerow([image_id, *b])
    print(f'{got} images ready in {CACHE}')


def iou(a, b):
    ow = min(a[2], b[2]) - max(a[0], b[0])
    oh = min(a[3], b[3]) - max(a[1], b[1])
    if ow <= 0 or oh <= 0:
        return 0.0
    ov = ow * oh
    un = (a[2]-a[0])*(a[3]-a[1]) + (b[2]-b[0])*(b[3]-b[1]) - ov
    return 0.0 if un <= 0 else ov / un


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--fetch', action='store_true',
                    help='build the evaluation set first (needs network)')
    ap.add_argument('--per-class', type=int, default=60)
    ap.add_argument('--model', default=os.path.join(ROOT, 'assets/models/yolo11n.tflite'))
    ap.add_argument('--labels', default=os.path.join(ROOT, 'assets/models/labels.txt'))
    # Defaults mirror lib/core/vision/detection.dart and yolo.dart. Change them
    # here to ask what a different threshold would have done, then change them
    # there if the answer is better.
    ap.add_argument('--min-score', type=float, default=0.35)
    ap.add_argument('--nms-iou', type=float, default=0.45)
    ap.add_argument('--max-boxes', type=int, default=20)
    ap.add_argument('--hit-iou', type=float, default=0.5)
    # What the camera actually hands over. ResolutionPreset.low is 320x240 on
    # Android, so the frame reaching the model is 320 pixels on its long side
    # whatever the model's input is - evaluating on 1024px photographs measures
    # a detector the app does not have. 0 disables the simulation.
    ap.add_argument('--camera-frame', type=int, default=320,
                    help='longest side the camera delivers; 0 for the '
                         'full-resolution photograph')
    args = ap.parse_args()

    if args.fetch:
        build(args.per_class)

    gt_path = os.path.join(CACHE, 'ground-truth.csv')
    if not os.path.exists(gt_path):
        sys.exit(f'No evaluation set at {CACHE}. Run with --fetch first.')

    import numpy as np
    from PIL import Image
    try:
        from ai_edge_litert.interpreter import Interpreter
    except ImportError:
        from tensorflow.lite.python.interpreter import Interpreter

    names = [l.strip() for l in open(args.labels) if l.strip()]
    it = Interpreter(model_path=args.model, num_threads=os.cpu_count() or 4)
    it.allocate_tensors()
    inp, out = it.get_input_details()[0], it.get_output_details()[0]
    nchw = inp['shape'][1] == 3
    side = int(inp['shape'][2] if nchw else inp['shape'][1])

    def detect(im):
        if args.camera_frame:
            w, h = im.size
            k = args.camera_frame / max(w, h)
            if k < 1.0:
                im = im.resize((max(1, round(w*k)), max(1, round(h*k))),
                               Image.BILINEAR)
        # lib/core/vision/yolo.dart's Letterbox, and the same planar input.
        w, h = im.size
        scale = min(side / w, side / h)
        dw = min(max(round(w * scale), 1), side)
        dh = min(max(round(h * scale), 1), side)
        px, py = (side - dw) // 2, (side - dh) // 2
        canvas = Image.new('RGB', (side, side), (114, 114, 114))
        canvas.paste(im.convert('RGB').resize((dw, dh), Image.BILINEAR), (px, py))
        x = np.asarray(canvas, np.float32) / 255.0
        it.set_tensor(inp['index'],
                      np.transpose(x, (2, 0, 1))[None] if nchw else x[None])
        it.invoke()
        o = it.get_tensor(out['index'])[0]
        anchors = o.shape[1]
        box, cls = o[:4], o[4:]
        conf, best = cls.max(0), cls.argmax(0)

        cand = []
        for a in np.nonzero(conf >= args.min_score)[0]:
            cx, cy, bw, bh = box[:, a]
            cand.append((float(conf[a]), int(best[a]),
                         cx-bw/2, cy-bh/2, cx+bw/2, cy+bh/2))
        cand.sort(key=lambda c: -c[0])

        kept = []
        for c in cand:                       # class-agnostic, as the app is
            if len(kept) >= args.max_boxes:
                break
            if not any(iou(c[2:], k[2:]) > args.nms_iou for k in kept):
                kept.append(c)
        return [(s, names[i], (l*side-px)/dw, (t*side-py)/dh,
                 (r*side-px)/dw, (b*side-py)/dh)
                for s, i, l, t, r, b in kept]

    gt = collections.defaultdict(list)
    for r in csv.DictReader(open(gt_path)):
        gt[r['ImageID']].append((r['label'], float(r['xmin']), float(r['ymin']),
                                 float(r['xmax']), float(r['ymax'])))

    found, total = collections.Counter(), collections.Counter()
    by_class = collections.defaultdict(lambda: [0, 0])
    hits, shots = collections.Counter(), collections.Counter()

    for n, (image_id, boxes) in enumerate(sorted(gt.items()), 1):
        path = os.path.join(CACHE, 'images', image_id + '.jpg')
        if not os.path.exists(path):
            continue
        dets = detect(Image.open(path))
        for label, x0, y0, x1, y1 in boxes:
            b = band_of(x1-x0, y1-y0)
            total[b] += 1
            by_class[label][1] += 1
            if any(d[1] == label and iou((x0, y0, x1, y1), d[2:]) >= args.hit_iou
                   for d in dets):
                found[b] += 1
                by_class[label][0] += 1
        present = {b[0] for b in boxes}
        for d in dets:
            if d[1] not in present:
                continue     # nothing to compare against; not evidence either way
            shots[d[1]] += 1
            if any(b[0] == d[1] and iou(b[1:], d[2:]) >= args.hit_iou for b in boxes):
                hits[d[1]] += 1
        if n % 200 == 0:
            print(f'  ...{n}', flush=True)

    frame = (f'camera {args.camera_frame}px' if args.camera_frame
             else 'full-resolution photo')
    print(f'\n{os.path.basename(args.model)}   input {side}   '
          f'score >= {args.min_score}   {frame}')
    print(f'{"how big in frame":22s} {"found":>7s} {"of":>7s} {"recall":>8s}')
    for name, _ in BANDS:
        if total[name]:
            print(f'{name:22s} {found[name]:7d} {total[name]:7d} '
                  f'{found[name]/total[name]:7.0%}')
    near_f = sum(found[n] for n, _ in BANDS[:2])
    near_t = sum(total[n] for n, _ in BANDS[:2])
    print('-' * 47)
    print(f'{"close or nearer":22s} {near_f:7d} {near_t:7d} '
          f'{near_f/max(near_t,1):7.0%}   <- what the app speaks about')
    print(f'{"everything":22s} {sum(found.values()):7d} {sum(total.values()):7d} '
          f'{sum(found.values())/max(sum(total.values()),1):7.0%}')
    print(f'{"precision":22s} {sum(hits.values()):7d} {sum(shots.values()):7d} '
          f'{sum(hits.values())/max(sum(shots.values()),1):7.0%}   '
          f'<- only where the class is labelled')

    print('\nper class, all sizes:')
    for c, (f_, t_) in sorted(by_class.items(), key=lambda kv: -kv[1][1]):
        print(f'  {c:15s} {f_:5d}/{t_:<5d} {f_/max(t_,1):5.0%}')


if __name__ == '__main__':
    main()
