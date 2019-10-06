import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_svg_platform_interface/flutter_svg_platform_interface.dart';

/// Decodes the given [File] object as a picture, associating it with the given
/// scale.
///
/// See also:
///
///  * [SvgPicture.file] for a shorthand of an [SvgPicture] widget backed by [FilePicture].
class FilePicture extends PictureProvider<FilePicture> {
  /// Creates an object that decodes a [File] as a picture.
  ///
  /// The arguments must not be null.
  const FilePicture(this.decoder, this.file, {this.colorFilter})
      : assert(decoder != null),
        assert(file != null);

  /// The file to decode into a picture.
  final File file;

  /// The [PictureInfoDecoder] to use for loading this picture.
  final PictureInfoDecoder<Uint8List> decoder;

  /// The [ColorFilter], if any, to use when drawing this picture.
  final ColorFilter colorFilter;

  @override
  Future<FilePicture> obtainKey(PictureConfiguration picture) {
    return SynchronousFuture<FilePicture>(this);
  }

  @override
  PictureStreamCompleter load(FilePicture key, {PictureErrorListener onError}) {
    return OneFramePictureStreamCompleter(_loadAsync(key, onError: onError),
        informationCollector: () sync* {
      yield DiagnosticsProperty<String>('Path', file?.path);
    });
  }

  Future<PictureInfo> _loadAsync(FilePicture key,
      {PictureErrorListener onError}) async {
    assert(key == this);

    final Uint8List data = await file.readAsBytes();
    if (data == null || data.isEmpty) {
      return null;
    }
    if (onError != null) {
      return decoder(data, colorFilter, key.toString())..catchError(onError);
    }
    return decoder(data, colorFilter, key.toString());
  }

  @override
  bool operator ==(dynamic other) {
    if (other.runtimeType != runtimeType) {
      return false;
    }
    final FilePicture typedOther = other;
    return file?.path == typedOther.file?.path &&
        typedOther.colorFilter == colorFilter;
  }

  @override
  int get hashCode => hashValues(file?.path?.hashCode, colorFilter);

  @override
  String toString() =>
      '$runtimeType("${file?.path}", colorFilter: $colorFilter)';
}
