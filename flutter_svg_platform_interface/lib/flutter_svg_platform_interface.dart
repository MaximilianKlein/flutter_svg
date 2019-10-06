library flutter_svg_platform_interface;

// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'package:flutter_svg_platform_interface/src/picture_provider.dart';

export 'src/picture_cache.dart';
export 'src/picture_provider.dart';
export 'src/picture_stream.dart';

typedef SvgBuilder = Widget Function(
  PictureProvider pictureProvider, {
  Key key,
  double width,
  double height,
  BoxFit fit,
  Alignment alignment,
  bool matchTextDirection,
  bool allowDrawingOutsideViewBox,
  WidgetBuilder placeholderBuilder,
  String semanticsLabel,
  bool excludeFromSemantics,
});

/// Interface for a platform implementation of a SvgPicture.
///
/// [SvgPicture.platform] controls the builder that is used by [WebView].
/// [MobileSvgPlatform] is the default implementation for Android and iOS.
abstract class SvgPicturePlatform {
  /// Builds a new SvgPicture.
  Widget build(
    PictureProvider pictureProvider, {
    Key key,
    double width,
    double height,
    BoxFit fit,
    Alignment alignment,
    bool matchTextDirection,
    bool allowDrawingOutsideViewBox,
    WidgetBuilder placeholderBuilder,
    String semanticsLabel,
    bool excludeFromSemantics,
  });
}
