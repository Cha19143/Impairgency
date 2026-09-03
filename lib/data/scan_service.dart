/// Picks the right [ScanService] for the platform.
///
/// The real one uses `tflite_flutter`, which is built on `dart:ffi` and does
/// not exist on the web. The scan route is never registered on web anyway — the
/// router splits on `kIsWeb` — but the import still has to compile, which is
/// what the stub is for.
library;

export 'scan_service_stub.dart'
    if (dart.library.io) 'scan_service_io.dart';
