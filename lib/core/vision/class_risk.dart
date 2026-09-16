/// How much each thing the detector can name matters to someone walking.
///
/// What to say about a frame is chosen by how big and how central a box is,
/// and every one of the model's 80 classes used to count the same. A phone
/// held up in front of the lens outranked a motorcycle at the kerb, and it was
/// a "Stop". These weights put the things that move fast or hit hard first,
/// the things that trip next, and the things that are held in a hand or sit
/// on a table last.
///
/// Pure, so the ordering is tested without a camera.
library;

/// A multiplier on a detection's size-and-centrality risk. Anything not
/// listed counts as 1.0.
const Map<String, double> kClassRisk = {
  // Moves fast, hits hard.
  'car': 1.6,
  'truck': 1.6,
  'bus': 1.6,
  'train': 1.6,
  'motorcycle': 1.5,
  'bicycle': 1.3,
  // Moves on its own, or does not move and is at shin height.
  'dog': 1.2,
  'horse': 1.2,
  'cow': 1.2,
  'fire hydrant': 1.2,
  'parking meter': 1.1,
  'bench': 1.1,
  'chair': 1.1,
  'dining table': 1.1,
  'suitcase': 1.0,
  'potted plant': 1.0,
  'couch': 1.0,
  'person': 1.0,
  // Usually overhead, or far off.
  'traffic light': 0.8,
  'stop sign': 0.8,
  // Carried, worn, or near the lens because it is in someone's hand.
  'umbrella': 0.6,
  'backpack': 0.5,
  'handbag': 0.4,
  'vase': 0.4,
  'bottle': 0.4,
  'sports ball': 0.4,
  'baseball bat': 0.4,
  'laptop': 0.3,
  'keyboard': 0.3,
  'book': 0.3,
  'cup': 0.3,
  'wine glass': 0.3,
  'bowl': 0.3,
  'clock': 0.3,
  'scissors': 0.3,
  'teddy bear': 0.3,
  'tennis racket': 0.3,
  'baseball glove': 0.3,
  'frisbee': 0.3,
  'kite': 0.3,
  'cell phone': 0.2,
  'remote': 0.2,
  'mouse': 0.2,
  'fork': 0.2,
  'knife': 0.2,
  'spoon': 0.2,
  'toothbrush': 0.2,
  'hair drier': 0.2,
  'tie': 0.2,
  'banana': 0.2,
  'apple': 0.2,
  'orange': 0.2,
  'sandwich': 0.2,
  'broccoli': 0.2,
  'carrot': 0.2,
  'hot dog': 0.2,
  'pizza': 0.2,
  'donut': 0.2,
  'cake': 0.2,
};

/// Below this a class is never a "Stop", however close: it is almost always
/// something in a hand.
const double kHazardClassFloor = 0.5;

double riskWeight(String label) => kClassRisk[label] ?? 1.0;

/// Whether a class can be warned about as a hazard at all.
bool canBeHazard(String label) => riskWeight(label) >= kHazardClassFloor;
