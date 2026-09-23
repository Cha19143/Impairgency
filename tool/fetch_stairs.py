#!/usr/bin/env python3
"""Builds the stairs training set: Open Images "Stairs" boxes, and photographs
of what stairs are mistaken for.

    tool/fetch_stairs.py --negatives ~/Pictures/floors      # needs network
    tool/fetch_stairs.py --limit 300 --negatives ...        # a small trial set
    tool/fetch_stairs.py --negative-label Floor ... \
        --machine-negative-label "Zebra crossing" ...       # as trained

Why. YOLO11n is trained on COCO, which has no stairs, and the banding
heuristic that tried to fill the gap scored a tiled floor 0.86 and a zebra
crossing 0.75 - over its own threshold. A detector trained on real stairs,
with those two among its negatives, is the fix; `tool/train_stairs.sh`
trains it from what this writes, and `tool/eval_detector.py --stairs`
measures it before the app is allowed to say "Stop" for it.

What it writes, under build/stairs-data/ (git-ignored, like the eval set):

    images/train, images/val    photographs
    labels/train, labels/val    one YOLO text file each: `0 cx cy w h`, 0 to 1;
                                an empty file for a negative
    stairs.yaml                 the dataset, one class, `stairs`
    SOURCES.txt                 where every image came from, and its licence

Positives are the Open Images train split's boxes whose label is the class
named "Stairs" in Open Images' own class list - looked up by name at run time
and printed, not assumed. Crowds of stairs in one box, and pictures of stairs,
are left out, as `eval_detector.py` leaves them out. Open Images labels no
direction, so the model learns "stairs", never up or down.

Negatives are photographs with no stairs in them: every image in the
--negatives folders (tiled floors, rugs, corridors, zebra crossings, taken on
the phones the app runs on); with --negative-label, Open Images validation
images carrying that human-checked label and no Stairs box; and with
--machine-negative-label, train images whose machine-generated labels say
it at 0.7 or more, where nothing says stairs. The last is the only source of
zebra crossings, rugs and tiled floors in Open Images: its human-checked
labels have none of them in the validation or test split.

Licences: Open Images annotations are CC BY 4.0 and its images are listed as
CC BY 2.0 - the terms docs/VISION.md already records for the evaluation set.
The image list, with each image's Open Images id, is written to SOURCES.txt
so the attribution can be made. Photographs passed with --negatives are the
user's own.

Needs only the standard library to fetch. The train annotations file is large
(about 2 GB); it is read as a stream and only the stairs rows are kept, but it
is still a long download on a slow line. The machine labels are 7.35 GB more.
"""
import argparse, collections, csv, hashlib, io, os, shutil, sys, urllib.request
import concurrent.futures

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'build', 'stairs-data')

OI = 'https://storage.googleapis.com/openimages'
CLASSES = f'{OI}/v7/oidv7-class-descriptions-boxable.csv'
ALL_CLASSES = f'{OI}/v7/oidv7-class-descriptions.csv'
TRAIN_BOXES = f'{OI}/v6/oidv6-train-annotations-bbox.csv'
VAL_LABELS = f'{OI}/v7/oidv7-val-annotations-human-imagelabels.csv'
TRAIN_MACHINE = f'{OI}/v7/oidv7-train-annotations-machine-imagelabels.csv'
VAL_BOXES = f'{OI}/v5/validation-annotations-bbox.csv'
IMAGES = 'https://open-images-dataset.s3.amazonaws.com'


def lines(url):
    """The rows of a CSV at [url], read as they arrive."""
    with urllib.request.urlopen(url) as response:
        yield from csv.DictReader(io.TextIOWrapper(response, encoding='utf-8'))


def class_id(name, url=CLASSES):
    """Open Images' id for the class called [name]. Refuses to guess."""
    with urllib.request.urlopen(url) as response:
        for row in csv.reader(io.TextIOWrapper(response, encoding='utf-8')):
            if len(row) >= 2 and row[1].strip().lower() == name.lower():
                return row[0]
    sys.exit(f'Open Images has no class called "{name}" in {url}.')


def fetch(url, path):
    if os.path.exists(path) and os.path.getsize(path):
        return True
    try:
        urllib.request.urlretrieve(url, path)
        return True
    except Exception:
        if os.path.exists(path):
            os.remove(path)
        return False


def yolo_line(xmin, ymin, xmax, ymax):
    """One box as Ultralytics reads it: class, centre, size, all 0 to 1."""
    return (f'0 {(xmin + xmax) / 2:.6f} {(ymin + ymax) / 2:.6f} '
            f'{xmax - xmin:.6f} {ymax - ymin:.6f}')


def split_of(image_id, val_fraction):
    """The same image always lands in the same split, run after run - which
    Python's own hash() of a string does not promise."""
    bucket = int(hashlib.sha1(image_id.encode()).hexdigest(), 16) % 1000
    return 'val' if bucket / 1000 < val_fraction else 'train'


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--limit', type=int, default=4000,
                    help='most positive images to take (default 4000)')
    ap.add_argument('--negatives', action='append', default=[],
                    help='a folder of photographs with no stairs; repeatable')
    ap.add_argument('--negative-label', action='append', default=[],
                    help='an Open Images image-level label to take negatives '
                         'from, e.g. "Zebra crossing"; repeatable')
    ap.add_argument('--negative-limit', type=int, default=600)
    ap.add_argument('--machine-negative-label', action='append', default=[],
                    help='an Open Images label to take train-split negatives '
                         'from by its machine-generated labels, e.g. "Zebra '
                         'crossing"; repeatable. Reads a 7.35 GB list')
    ap.add_argument('--machine-confidence', type=float, default=0.7)
    ap.add_argument('--machine-negative-limit', type=int, default=600)
    ap.add_argument('--val-fraction', type=float, default=0.1)
    ap.add_argument('--out', default=OUT)
    args = ap.parse_args()

    stairs = class_id('Stairs')
    print(f'Open Images class "Stairs" is {stairs}', flush=True)

    for split in ('train', 'val'):
        os.makedirs(os.path.join(args.out, 'images', split), exist_ok=True)
        os.makedirs(os.path.join(args.out, 'labels', split), exist_ok=True)

    print('reading the train boxes (a long stream)...', flush=True)
    boxes = collections.defaultdict(list)
    # Every train image with stairs boxed in it, crowds and pictures too:
    # never to be taken as a negative.
    any_stairs = set()
    for r in lines(TRAIN_BOXES):
        if r['LabelName'] != stairs:
            continue
        any_stairs.add(r['ImageID'])
        if r['IsGroupOf'] == '1' or r['IsDepiction'] == '1':
            continue
        # The file is ordered by image, so a new image past the limit means
        # every box of the ones kept has been read - but the rest of the file
        # still says which images have stairs, for the machine negatives.
        if r['ImageID'] not in boxes and len(boxes) >= args.limit:
            if not args.machine_negative_label:
                break
            continue
        boxes[r['ImageID']].append((float(r['XMin']), float(r['YMin']),
                                    float(r['XMax']), float(r['YMax'])))
    chosen = sorted(boxes)[:args.limit]
    print(f'{len(chosen)} images with stairs boxes', flush=True)

    sources = []

    def positive(image_id):
        split = split_of(image_id, args.val_fraction)
        img = os.path.join(args.out, 'images', split, image_id + '.jpg')
        if not fetch(f'{IMAGES}/train/{image_id}.jpg', img):
            return 0
        with open(os.path.join(args.out, 'labels', split, image_id + '.txt'),
                  'w') as f:
            f.write('\n'.join(yolo_line(*b) for b in boxes[image_id]) + '\n')
        sources.append(f'{image_id}\tOpen Images train\tCC BY 2.0 (image), '
                       f'CC BY 4.0 (boxes)')
        return 1

    with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
        got = sum(pool.map(positive, chosen))
    print(f'{got} positives ready', flush=True)

    negatives = 0
    # Photographs of floors and crossings taken on the phones the app runs on.
    for folder in args.negatives:
        for name in sorted(os.listdir(folder)):
            if not name.lower().endswith(('.jpg', '.jpeg', '.png')):
                continue
            stem = 'neg-' + os.path.splitext(name)[0].replace(' ', '_')
            split = split_of(stem, args.val_fraction)
            ext = os.path.splitext(name)[1].lower()
            shutil.copy(os.path.join(folder, name),
                        os.path.join(args.out, 'images', split, stem + ext))
            open(os.path.join(args.out, 'labels', split, stem + '.txt'),
                 'w').close()
            sources.append(f'{stem}\t{folder}\tthe user\'s own photograph')
            negatives += 1

    if args.negative_label:
        wanted = {class_id(n, ALL_CLASSES): n for n in args.negative_label}
        print(f'negatives from image labels: {wanted}', flush=True)
        with_stairs = {r['ImageID'] for r in lines(VAL_BOXES)
                       if r['LabelName'] == stairs}
        # A dict, not a list: a floor photograph carries "Floor", "Flooring"
        # and "Tile flooring" at once, and is still one negative.
        picked = {}
        for r in lines(VAL_LABELS):
            if (r['LabelName'] in wanted and r['Confidence'] == '1'
                    and r['ImageID'] not in with_stairs):
                picked[r['ImageID']] = True
                if len(picked) >= args.negative_limit:
                    break

        def negative(image_id):
            stem = 'neg-oi-' + image_id
            split = split_of(stem, args.val_fraction)
            img = os.path.join(args.out, 'images', split, stem + '.jpg')
            if not fetch(f'{IMAGES}/validation/{image_id}.jpg', img):
                return 0
            open(os.path.join(args.out, 'labels', split, stem + '.txt'),
                 'w').close()
            sources.append(f'{stem}\tOpen Images validation\tCC BY 2.0')
            return 1

        with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
            negatives += sum(pool.map(negative, picked))

    if args.machine_negative_label:
        # Open Images' human-checked labels have no zebra crossing, rug or
        # tiled floor in the validation or test split, so none of the
        # negatives above is one - and those are what the old heuristic and
        # the first model took for stairs. Its machine-generated labels for
        # the train split have them. A photograph goes in only if nothing
        # says stairs: no Stairs box of any kind, and no machine Stairs label
        # at 0.3 or more.
        machine = {class_id(n, ALL_CLASSES): n
                   for n in args.machine_negative_label}
        print(f'negatives from machine labels at {args.machine_confidence} '
              f'or more: {machine} (a longer stream)...', flush=True)
        guessed = collections.defaultdict(set)
        for r in lines(TRAIN_MACHINE):
            if r['LabelName'] == stairs:
                if float(r['Confidence']) >= 0.3:
                    any_stairs.add(r['ImageID'])
            elif (r['LabelName'] in machine
                    and float(r['Confidence']) >= args.machine_confidence):
                guessed[r['ImageID']].add(machine[r['LabelName']])
        clear = [i for i in guessed if i not in any_stairs]
        # An even share for each label first: hardwood floors outnumber zebra
        # crossings many times over.
        share = max(1, args.machine_negative_limit // len(machine))
        taken = {}
        for name in args.machine_negative_label:
            for i in [i for i in clear if name in guessed[i]][:share]:
                taken[i] = True
        for i in clear:
            if len(taken) >= args.machine_negative_limit:
                break
            taken[i] = True
        taken = list(taken)[:args.machine_negative_limit]

        def machine_negative(image_id):
            stem = 'neg-oim-' + image_id
            split = split_of(stem, args.val_fraction)
            img = os.path.join(args.out, 'images', split, stem + '.jpg')
            if not fetch(f'{IMAGES}/train/{image_id}.jpg', img):
                return 0
            open(os.path.join(args.out, 'labels', split, stem + '.txt'),
                 'w').close()
            sources.append(f'{stem}\tOpen Images train, machine label '
                           f'{"; ".join(sorted(guessed[image_id]))}'
                           f'\tCC BY 2.0')
            return 1

        with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
            got = sum(pool.map(machine_negative, taken))
        by_label = collections.Counter(
            n for i in taken for n in guessed[i]
            if os.path.exists(os.path.join(
                args.out, 'images', split_of('neg-oim-' + i, args.val_fraction),
                'neg-oim-' + i + '.jpg')))
        print(f'{got} machine-labelled negatives: {dict(by_label)}', flush=True)
        negatives += got
    print(f'{negatives} negatives ready', flush=True)
    if negatives == 0:
        print('No negatives: the model will learn nothing about tiled floors. '
              'Pass --negatives with photographs of them.', file=sys.stderr)

    with open(os.path.join(args.out, 'stairs.yaml'), 'w') as f:
        f.write(f'path: {os.path.abspath(args.out)}\n'
                'train: images/train\n'
                'val: images/val\n'
                'names:\n'
                '  0: stairs\n')
    with open(os.path.join(args.out, 'SOURCES.txt'), 'w') as f:
        f.write(f'# Open Images class "Stairs" = {stairs}\n')
        f.write('\n'.join(sorted(sources)) + '\n')
    print(f'dataset at {args.out}/stairs.yaml')


if __name__ == '__main__':
    main()
