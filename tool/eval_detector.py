#!/usr/bin/env python3
"""Measures the detector the app ships, on annotated photographs.

    tool/eval_detector.py --fetch          # first run: builds the set (~850 images)
    tool/eval_detector.py                  # thereafter

    tool/eval_detector.py --stairs --fetch --per-class 1000 \
        --negative-label "Tile flooring" --negative-label "Zebra crossing"
                                           # the stairs model: recall on Open
                                           # Images "Stairs", and how often it
                                           # fires on floors and crossings;
                                           # --negatives adds a folder of
                                           # your own photographs

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
BOXES = {
    'validation': 'https://storage.googleapis.com/openimages/v5/validation-annotations-bbox.csv',
    'test': 'https://storage.googleapis.com/openimages/v5/test-annotations-bbox.csv',
}
IMAGES = 'https://open-images-dataset.s3.amazonaws.com'

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

# The scores the stairs model is measured at. 0.35 is where the named tier
# started; kStairsSoft and kStairsHard have both been 0.55 since the first
# measurement (docs/VISION.md, "The gate"); 0.65 is past them.
STAIRS_SCORES = [0.35, 0.45, 0.55, 0.65]
STAIRS_SOFT = STAIRS_HARD = 0.55


def band_of(w, h):
    e = max(w, h)
    for name, floor in BANDS:
        if e > floor:
            return name
    return BANDS[-1][0]


def build(per_class, pairs=PAIRS, cache=None, splits=('validation',)):
    cache = cache or CACHE
    os.makedirs(cache, exist_ok=True)
    rows = collections.defaultdict(list)
    split_of = {}
    for split in splits:
        ann = os.path.join(cache, f'{split}-annotations-bbox.csv')
        if not os.path.exists(ann):
            print(f'fetching {split} annotations...', flush=True)
            urllib.request.urlretrieve(BOXES[split], ann)
        with open(ann) as f:
            for r in csv.DictReader(f):
                if r['LabelName'] not in pairs:
                    continue
                # A crowd in one box is not an object, and a painting of a dog
                # is not a dog in the room.
                if r['IsGroupOf'] == '1' or r['IsDepiction'] == '1':
                    continue
                rows[r['ImageID']].append((
                    pairs[r['LabelName']], float(r['XMin']), float(r['YMin']),
                    float(r['XMax']), float(r['YMax'])))
                split_of[r['ImageID']] = split

    chosen, seen = {}, collections.Counter()
    for image_id, boxes in sorted(rows.items()):
        if not any(seen[c] < per_class for c, *_ in boxes):
            continue          # spread the pick; "person" would take the lot
        chosen[image_id] = boxes
        for c in {c for c, *_ in boxes}:
            seen[c] += 1

    d = os.path.join(cache, 'images')
    os.makedirs(d, exist_ok=True)

    def fetch(image_id):
        p = os.path.join(d, image_id + '.jpg')
        if os.path.exists(p) and os.path.getsize(p):
            return 1
        try:
            urllib.request.urlretrieve(
                f'{IMAGES}/{split_of[image_id]}/{image_id}.jpg', p)
            return 1
        except Exception:
            if os.path.exists(p):
                os.remove(p)
            return 0

    print(f'fetching {len(chosen)} images...', flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
        got = sum(pool.map(fetch, chosen))

    with open(os.path.join(cache, 'ground-truth.csv'), 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['ImageID', 'label', 'xmin', 'ymin', 'xmax', 'ymax'])
        for image_id, boxes in chosen.items():
            if os.path.exists(os.path.join(d, image_id + '.jpg')):
                for b in boxes:
                    w.writerow([image_id, *b])
    print(f'{got} images ready in {cache}')


def iou(a, b):
    ow = min(a[2], b[2]) - max(a[0], b[0])
    oh = min(a[3], b[3]) - max(a[1], b[1])
    if ow <= 0 or oh <= 0:
        return 0.0
    ov = ow * oh
    un = (a[2]-a[0])*(a[3]-a[1]) + (b[2]-b[0])*(b[3]-b[1]) - ov
    return 0.0 if un <= 0 else ov / un


def load_detector(model, names, args):
    """The app's pipeline, as a function: a PIL image in, the boxes the app
    would act on out, as (score, name, left, top, right, bottom) in fractions
    of the image. Returns it with the model's input side."""
    import numpy as np
    from PIL import Image
    try:
        from ai_edge_litert.interpreter import Interpreter
    except ImportError:
        from tensorflow.lite.python.interpreter import Interpreter

    it = Interpreter(model_path=model, num_threads=os.cpu_count() or 4)
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

    return detect, side


def build_negatives(stairs, labels, limit, folder, test_boxes, machine=(),
                    machine_confidence=0.7):
    """Open Images *test* photographs carrying one of [labels] and neither a
    Stairs box nor a Stairs label, into [folder]. The test split, because
    tool/fetch_stairs.py takes its negatives from the validation split: a
    false-alarm rate measured on photographs the model trained on flatters
    it. [test_boxes] is the test split's box file, as build() saved it.

    Each label gets an even share of [limit] before the rest is filled in
    file order: "Floor" is on so many photographs that the first 600 are
    nearly all plain floors.

    Open Images' human-checked labels have no zebra crossings, rugs or tiled
    floors at all, in either held-out split. [machine] names labels taken
    from its machine-generated ones instead, at [machine_confidence] or more;
    they are marked "(machine)" in the table, and any photograph the machine
    thinks shows stairs at all (0.5) is left out."""
    import io as _io
    base = 'https://storage.googleapis.com/openimages'
    image_labels = os.path.join(os.path.dirname(test_boxes),
                                'test-annotations-human-imagelabels.csv')
    if not os.path.exists(image_labels):
        print('fetching test image labels...', flush=True)
        urllib.request.urlretrieve(
            f'{base}/v7/oidv7-test-annotations-human-imagelabels.csv',
            image_labels)

    def rows(url, reader=csv.DictReader):
        with urllib.request.urlopen(url) as resp:
            yield from reader(_io.TextIOWrapper(resp, encoding='utf-8'))

    wanted = {}
    for row in rows(f'{base}/v7/oidv7-class-descriptions.csv', csv.reader):
        for name in [*labels, *machine]:
            if (len(row) >= 2 and row[1].strip().lower() == name.lower()
                    and name not in wanted.values()):
                wanted[row[0]] = name
    missing = [n for n in [*labels, *machine] if n not in wanted.values()]
    if missing:
        sys.exit(f'Open Images has no image-level label called {missing}.')
    print(f'negatives from Open Images test labels: {wanted}', flush=True)
    human = {mid: n for mid, n in wanted.items() if n in labels}
    machined = {mid: f'{n} (machine)' for mid, n in wanted.items()
                if n in machine}

    with open(test_boxes) as f:
        with_stairs = {r['ImageID'] for r in csv.DictReader(f)
                       if r['LabelName'] == stairs}
    candidates = collections.defaultdict(set)
    with open(image_labels) as f:
        for r in csv.DictReader(f):
            if r['LabelName'] == stairs and r['Confidence'] == '1':
                with_stairs.add(r['ImageID'])
            elif r['LabelName'] in human and r['Confidence'] == '1':
                candidates[r['ImageID']].add(human[r['LabelName']])
    if machined:
        guessed = os.path.join(os.path.dirname(test_boxes),
                               'test-annotations-machine-imagelabels.csv')
        if not os.path.exists(guessed):
            print('fetching test machine labels...', flush=True)
            urllib.request.urlretrieve(
                f'{base}/v7/oidv7-test-annotations-machine-imagelabels.csv',
                guessed)
        with open(guessed) as f:
            for r in csv.DictReader(f):
                sure = float(r['Confidence'])
                if r['LabelName'] == stairs and sure >= 0.5:
                    with_stairs.add(r['ImageID'])
                elif r['LabelName'] in machined and sure >= machine_confidence:
                    candidates[r['ImageID']].add(machined[r['LabelName']])
    clear = [i for i in candidates if i not in with_stairs]
    names = [*labels, *(f'{n} (machine)' for n in machine)]
    picked, share = {}, max(1, limit // len(names))
    for name in names:
        for i in [i for i in clear if name in candidates[i]][:share]:
            picked[i] = True
    for i in clear:
        if len(picked) >= limit:
            break
        picked[i] = True
    picked = list(picked)[:limit]

    os.makedirs(folder, exist_ok=True)

    def fetch(image_id):
        p = os.path.join(folder, f'oi-test-{image_id}.jpg')
        if os.path.exists(p) and os.path.getsize(p):
            return 1
        try:
            urllib.request.urlretrieve(
                f'https://open-images-dataset.s3.amazonaws.com/test/{image_id}.jpg', p)
            return 1
        except Exception:
            if os.path.exists(p):
                os.remove(p)
            return 0

    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
        got = sum(pool.map(fetch, picked))
    # What each photograph shows, so the table can say which kind fired.
    with open(os.path.join(folder, 'labels.csv'), 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['file', 'labels'])
        for i in picked:
            if os.path.exists(os.path.join(folder, f'oi-test-{i}.jpg')):
                w.writerow([f'oi-test-{i}.jpg', ';'.join(sorted(candidates[i]))])
    print(f'{got} negatives ready in {folder}', flush=True)


def stairs_main(args):
    """Recall on Open Images' "Stairs" boxes, by size, and how often the model
    fires on photographs with no stairs in them - at each score it might
    speak at. The gate for letting it say "Stop" (lib/core/vision/stairs.dart):
    close-or-nearer recall of at least 70%, and at most 5% of negatives
    firing, at kStairsHard."""
    from PIL import Image
    cache = os.path.join(ROOT, 'build', 'stairs-eval')
    held_out = os.path.join(cache, 'negatives')
    if args.fetch:
        import urllib.request as ur, io as _io
        mid = None
        url = 'https://storage.googleapis.com/openimages/v7/oidv7-class-descriptions-boxable.csv'
        with ur.urlopen(url) as resp:
            for row in csv.reader(_io.TextIOWrapper(resp, encoding='utf-8')):
                if len(row) >= 2 and row[1].strip().lower() == 'stairs':
                    mid = row[0]
        if mid is None:
            sys.exit('Open Images has no class called "Stairs".')
        print(f'Open Images class "Stairs" is {mid}')
        # Both held-out splits: the validation split alone has a few dozen
        # usable photographs of stairs, and tool/fetch_stairs.py trains on
        # the train split's.
        build(args.per_class, pairs={mid: 'stairs'}, cache=cache,
              splits=('validation', 'test'))
        if args.negative_label or args.negative_machine_label:
            build_negatives(mid, args.negative_label, args.negative_limit,
                            held_out,
                            os.path.join(cache, 'test-annotations-bbox.csv'),
                            machine=args.negative_machine_label)
    if os.path.isdir(held_out) and held_out not in args.negatives:
        args.negatives.append(held_out)

    gt_path = os.path.join(cache, 'ground-truth.csv')
    if not os.path.exists(gt_path):
        sys.exit(f'No stairs evaluation set at {cache}. Run with --fetch.')
    lowest = min(STAIRS_SCORES)
    args.min_score = lowest
    detect, side = load_detector(args.model, ['stairs'], args)

    gt = collections.defaultdict(list)
    for r in csv.DictReader(open(gt_path)):
        gt[r['ImageID']].append((float(r['xmin']), float(r['ymin']),
                                 float(r['xmax']), float(r['ymax'])))

    found = {t: collections.Counter() for t in STAIRS_SCORES}
    total = collections.Counter()
    for image_id, boxes in sorted(gt.items()):
        path = os.path.join(cache, 'images', image_id + '.jpg')
        if not os.path.exists(path):
            continue
        dets = detect(Image.open(path))
        for b in boxes:
            band = band_of(b[2]-b[0], b[3]-b[1])
            total[band] += 1
            for t in STAIRS_SCORES:
                if any(d[0] >= t and iou(b, d[2:]) >= args.hit_iou
                       for d in dets):
                    found[t][band] += 1

    negatives = [os.path.join(folder, n)
                 for folder in args.negatives
                 for n in sorted(os.listdir(folder))
                 if n.lower().endswith(('.jpg', '.jpeg', '.png'))]
    # Which kind of photograph each negative is, where its folder says
    # (build_negatives writes labels.csv): tiled floors and zebra crossings
    # are the two the old heuristic took for stairs.
    kinds = {}
    for folder in args.negatives:
        listed = os.path.join(folder, 'labels.csv')
        if os.path.exists(listed):
            for r in csv.DictReader(open(listed)):
                kinds[os.path.join(folder, r['file'])] = r['labels'].split(';')
    lowest, soft, hard = STAIRS_SCORES[0], STAIRS_SOFT, STAIRS_HARD
    by_kind = collections.defaultdict(lambda: [0, 0, 0, 0])

    fired, named = collections.Counter(), collections.Counter()
    for path in negatives:
        dets = detect(Image.open(path))
        for t in STAIRS_SCORES:
            # A false alarm the app would act on: stairs close or nearer.
            if any(d[0] >= t and max(d[4]-d[2], d[5]-d[3]) > 0.30
                   for d in dets):
                fired[t] += 1
            # A false alarm the app would say at all: stairs at any size are
            # named ("Stairs on your right") from kStairsSoft up.
            if any(d[0] >= t for d in dets):
                named[t] += 1
        for kind in kinds.get(path, ()):
            row = by_kind[kind]
            row[0] += 1
            row[1] += any(d[0] >= lowest for d in dets)
            row[2] += any(d[0] >= soft for d in dets)
            row[3] += any(d[0] >= hard and max(d[4]-d[2], d[5]-d[3]) > 0.30
                          for d in dets)

    def share(n):
        return (f'{n}/{len(negatives)} {n/len(negatives):4.0%}'
                if negatives else 'no negatives')

    near = [n for n, _ in BANDS[:2]]
    near_total = sum(total[n] for n in near)
    frame = (f'camera {args.camera_frame}px' if args.camera_frame
             else 'full-resolution photo')
    print(f'\n{os.path.basename(args.model)}   input {side}   {frame}   '
          f'{sum(total.values())} stairs boxes ({near_total} close or nearer), '
          f'{len(negatives)} negatives')
    print(f'{"score >=":>9s} {"close+ recall":>14s} {"all recall":>11s} '
          f'{"negatives, close+":>18s} {"negatives, any":>15s}')
    for t in STAIRS_SCORES:
        near_found = sum(found[t][n] for n in near)
        all_found = sum(found[t].values())
        print(f'{t:9.2f} {near_found/max(near_total,1):13.0%} '
              f'{all_found/max(sum(total.values()),1):10.0%} '
              f'{share(fired[t]):>18s} {share(named[t]):>15s}')
    if by_kind:
        print(f'\n{"negatives by label":30s} {"photos":>7s} '
              f'{"any at " + str(lowest):>12s} {"any at " + str(soft):>12s} '
              f'{"close+ at " + str(hard):>15s}')
        for kind, (n, a, b, c) in sorted(by_kind.items(),
                                         key=lambda kv: -kv[1][0]):
            print(f'{kind:30s} {n:7d} {a:12d} {b:12d} {c:15d}')
    print(f'\nGate for "Stop": close+ recall >= 70% and negatives <= 5% at '
          f'kStairsHard ({hard}). The named tier, kStairsSoft ({soft}): the '
          f'lowest score\nat which at most 5% of negatives are named at all.')


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
    # What the camera actually hands over. ResolutionPreset.medium is 720x480
    # on Android (lib/data/scan_service_io.dart), so the frame reaching the
    # model is 720 pixels on its long side whatever the model's input is -
    # evaluating on 1024px photographs measures a detector the app does not
    # have. 320 is what ResolutionPreset.low saw; 0 disables the simulation.
    ap.add_argument('--camera-frame', type=int, default=720,
                    help='longest side the camera delivers; 0 for the '
                         'full-resolution photograph')
    ap.add_argument('--stairs', action='store_true',
                    help='measure the stairs model instead of the COCO one')
    ap.add_argument('--negatives', action='append', default=[],
                    help='with --stairs: a folder of photographs with no '
                         'stairs - tiled floors, rugs, crossings; repeatable')
    ap.add_argument('--negative-label', action='append', default=[],
                    help='with --stairs --fetch: also fetch Open Images test '
                         'photographs with this image-level label and no '
                         'stairs, e.g. "Tile flooring"; repeatable')
    ap.add_argument('--negative-machine-label', action='append', default=[],
                    help='as --negative-label, from the machine-generated '
                         'labels at 0.7 or more - Open Images has checked '
                         'no zebra crossing, rug or tiled floor by hand')
    ap.add_argument('--negative-limit', type=int, default=400)
    args = ap.parse_args()

    if args.stairs:
        if args.model.endswith('yolo11n.tflite'):
            args.model = os.path.join(ROOT, 'assets/models/yolo11n_stairs.tflite')
        stairs_main(args)
        return

    if args.fetch:
        build(args.per_class)

    gt_path = os.path.join(CACHE, 'ground-truth.csv')
    if not os.path.exists(gt_path):
        sys.exit(f'No evaluation set at {CACHE}. Run with --fetch first.')

    from PIL import Image
    names = [l.strip() for l in open(args.labels) if l.strip()]
    detect, side = load_detector(args.model, names, args)

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
