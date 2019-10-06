// Copyright 2015 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui'
    show BlendMode, Color, ColorFilter, Locale, Rect, TextDirection, hashValues;

import 'package:flutter/foundation.dart';

import 'package:flutter_svg_platform_interface/flutter_svg_platform_interface.dart';
import 'utilities/http.dart';

/// Fetches the given URL from the network, associating it with the given scale.
///
/// The picture will be cached regardless of cache headers from the server.
///
/// See also:
///
///  * [SvgPicture.network] for a shorthand of an [SvgPicture] widget backed by [NetworkPicture].
// TODO(ianh): Find some way to honour cache headers to the extent that when the
// last reference to a picture is released, we proactively evict the picture from
// our cache if the headers describe the picture as having expired at that point.
class NetworkPicture extends PictureProvider<NetworkPicture> {
  /// Creates an object that fetches the picture at the given URL.
  ///
  /// The arguments must not be null.
  const NetworkPicture(this.decoder, this.url, {this.headers, this.colorFilter})
      : assert(url != null);

  /// The decoder to use to turn a [Uint8List] into a [PictureInfo] object.
  final PictureInfoDecoder<Uint8List> decoder;

  /// The URL from which the picture will be fetched.
  final String url;

  /// The HTTP headers that will be used with [HttpClient.get] to fetch picture from network.
  final Map<String, String> headers;

  /// The [ColorFilter], if any, to apply to the drawing.
  final ColorFilter colorFilter;

  @override
  Future<NetworkPicture> obtainKey(PictureConfiguration picture) {
    return SynchronousFuture<NetworkPicture>(this);
  }

  @override
  PictureStreamCompleter load(NetworkPicture key,
      {PictureErrorListener onError}) {
    return OneFramePictureStreamCompleter(_loadAsync(key, onError: onError),
        informationCollector: () sync* {
      yield DiagnosticsProperty<PictureProvider>('Picture provider', this);
      yield DiagnosticsProperty<NetworkPicture>('Picture key', key);
    });
  }

  Future<PictureInfo> _loadAsync(NetworkPicture key,
      {PictureErrorListener onError}) async {
    assert(key == this);
    final Uint8List bytes = await httpGet(url);
    if (onError != null) {
      return decoder(bytes, colorFilter, key.toString())..catchError(onError);
    }
    return decoder(bytes, colorFilter, key.toString());
  }

  @override
  bool operator ==(dynamic other) {
    if (other.runtimeType != runtimeType) {
      return false;
    }
    final NetworkPicture typedOther = other;
    return url == typedOther.url && colorFilter == typedOther.colorFilter;
  }

  @override
  int get hashCode => hashValues(url.hashCode, colorFilter);

  @override
  String toString() =>
      '$runtimeType("$url", headers: $headers, colorFilter: $colorFilter)';
}
