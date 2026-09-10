/// Picks the right [TextReader] for the platform.
///
/// The real one uses ML Kit through a platform channel, which the web build
/// does not have; the read route is never registered on web - the router
/// splits on `kIsWeb` - but the import still has to compile.
library;

export 'text_reader_stub.dart' if (dart.library.io) 'text_reader_io.dart';
