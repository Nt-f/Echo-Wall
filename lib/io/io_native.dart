// io.dart on the Echo: dart:io, and the response's bytes as Flutter collects them
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' as f;

export 'dart:io';

Future<Uint8List> consolidateBytes(HttpClientResponse r) => f.consolidateHttpClientResponseBytes(r);
