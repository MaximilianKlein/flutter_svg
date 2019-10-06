import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/parser.dart';
import 'package:flutter_svg_platform_interface/flutter_svg_platform_interface.dart';
import 'package:flutter_svg/src/vector_drawable.dart';
import 'package:flutter_svg/svg.dart';

import 'src/http_picture_provider.dart';

export 'src/vector_drawable.dart';
export 'svg.dart';

/// Instance for [Svg]'s utility methods, which can produce a [DrawableRoot]
/// or [PictureInfo] from [String] or [Uint8List].
final Svg svg = Svg._();

/// A utility class for decoding SVG data to a [DrawableRoot] or a [PictureInfo].
///
/// These methods are used by [SvgPicture], but can also be directly used e.g.
/// to create a [DrawableRoot] you manipulate or render to your own [Canvas].
/// Access to this class is provided by the exported [svg] member.
class Svg {
  Svg._();

  /// Produces a [PictureInfo] from a [Uint8List] of SVG byte data (assumes UTF8 encoding).
  ///
  /// The `allowDrawingOutsideOfViewBox` parameter should be used with caution -
  /// if set to true, it will not clip the canvas used internally to the view box,
  /// meaning the picture may draw beyond the intended area and lead to undefined
  /// behavior or additional memory overhead.
  ///
  /// The `colorFilter` property will be applied to any [Paint] objects used during drawing.
  ///
  /// The [key] will be used for debugging purposes.
  FutureOr<PictureInfo> svgPictureDecoder(
    Uint8List raw,
    bool allowDrawingOutsideOfViewBox,
    ColorFilter colorFilter,
    String key,
  ) async {
    final DrawableRoot svgRoot = await fromSvgBytes(raw, key);
    final Picture pic = svgRoot.toPicture(
      clipToViewBox: allowDrawingOutsideOfViewBox == true ? false : true,
      colorFilter: colorFilter,
    );
    return PictureInfo(
      picture: pic,
      viewport: svgRoot.viewport.viewBoxRect,
      size: svgRoot.viewport.size,
    );
  }

  /// Produces a [PictureInfo] from a [String] of SVG data.
  ///
  /// The `allowDrawingOutsideOfViewBox` parameter should be used with caution -
  /// if set to true, it will not clip the canvas used internally to the view box,
  /// meaning the picture may draw beyond the intended area and lead to undefined
  /// behavior or additional memory overhead.
  ///
  /// The `colorFilter` property will be applied to any [Paint] objects used during drawing.
  ///
  /// The [key] will be used for debugging purposes.
  FutureOr<PictureInfo> svgPictureStringDecoder(
      String raw,
      bool allowDrawingOutsideOfViewBox,
      ColorFilter colorFilter,
      String key) async {
    final DrawableRoot svg = await fromSvgString(raw, key);
    return PictureInfo(
      picture: svg.toPicture(
        clipToViewBox: allowDrawingOutsideOfViewBox == true ? false : true,
        colorFilter: colorFilter,
        size: svg.viewport.viewBox,
      ),
      viewport: svg.viewport.viewBoxRect,
      size: svg.viewport.size,
    );
  }

  /// Produces a [Drawableroot] from a [Uint8List] of SVG byte data (assumes UTF8 encoding).
  ///
  /// The [key] will be used for debugging purposes.
  FutureOr<DrawableRoot> fromSvgBytes(Uint8List raw, String key) async {
    // TODO(dnfield): do utf decoding in another thread?
    // Might just have to live with potentially slow(ish) decoding, this is causing errors.
    // See: https://github.com/dart-lang/sdk/issues/31954
    // See: https://github.com/flutter/flutter/blob/bf3bd7667f07709d0b817ebfcb6972782cfef637/packages/flutter/lib/src/services/asset_bundle.dart#L66
    // if (raw.lengthInBytes < 20 * 1024) {
    return fromSvgString(utf8.decode(raw), key);
    // } else {
    //   final String str =
    //       await compute(_utf8Decode, raw, debugLabel: 'UTF8 decode for SVG');
    //   return fromSvgString(str);
    // }
  }

  // String _utf8Decode(Uint8List data) {
  //   return utf8.decode(data);
  // }

  /// Creates a [DrawableRoot] from a string of SVG data.
  ///
  /// The `key` is used for debugging purposes.
  Future<DrawableRoot> fromSvgString(String rawSvg, String key) async {
    final SvgParser parser = SvgParser();
    return await parser.parse(rawSvg, key: key);
  }
}

/// Prefetches an SVG Picture into the picture cache.
///
/// Returns a [Future] that will complete when the first image yielded by the
/// PictureProvider is available or failed to load.
///
/// If the image is later used by an [SvgPicture], it will probably be loaded
/// faster. The consumer of the image does not need to use the same
/// PictureProvider instance. The [PictureCache] will find the picture
/// as long as both pictures share the same key.
///
/// The `onError` argument can be used to manually handle errors while precaching.
///
/// See also:
///
///  * [PictureCache], which holds images that may be reused.
Future<void> precachePicture(
  PictureProvider provider,
  BuildContext context, {
  Rect viewBox,
  ColorFilter colorFilterOverride,
  Color color,
  BlendMode colorBlendMode,
  PictureErrorListener onError,
}) {
  final PictureConfiguration config = createLocalPictureConfiguration(
    context,
    viewBox: viewBox,
    colorFilterOverride: colorFilterOverride,
    color: color,
    colorBlendMode: colorBlendMode,
  );
  final Completer<void> completer = Completer<void>();
  PictureStream stream;

  void listener(PictureInfo picture, bool synchronous) {
    completer.complete();
    stream?.removeListener(listener);
  }

  void errorListener(dynamic exception, StackTrace stackTrace) {
    if (onError != null) {
      onError(exception, stackTrace);
    } else {
      FlutterError.reportError(FlutterErrorDetails(
        context: ErrorDescription('picture failed to precache'),
        library: 'SVG',
        exception: exception,
        stack: stackTrace,
        silent: true,
      ));
    }
    completer.complete();
    stream?.removeListener(listener);
  }

  stream = provider.resolve(config, onError: errorListener)
    ..addListener(listener, onError: errorListener);
  return completer.future;
}

class SvgPicture extends StatelessWidget {
  /// Instantiates a widget that renders an SVG picture using the `pictureProvider`.
  ///
  /// Either the [width] and [height] arguments should be specified, or the
  /// widget should be placed in a context that sets tight layout constraints.
  /// Otherwise, the image dimensions will change as the image is loaded, which
  /// will result in ugly layout changes.
  ///
  /// If `matchTextDirection` is set to true, the picture will be flipped
  /// horizontally in [TextDirection.rtl] contexts.
  ///
  /// The `allowDrawingOutsideOfViewBox` parameter should be used with caution -
  /// if set to true, it will not clip the canvas used internally to the view box,
  /// meaning the picture may draw beyond the intended area and lead to undefined
  /// behavior or additional memory overhead.
  ///
  /// A custom `placeholderBuilder` can be specified for cases where decoding or
  /// acquiring data may take a noticeably long time, e.g. for a network picture.
  ///
  /// The `semanticsLabel` can be used to identify the purpose of this picture for
  /// screen reading software.
  ///
  /// If [excludeFromSemantics] is true, then [semanticLabel] will be ignored.
  const SvgPicture(
    this.pictureProvider, {
    Key key,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.matchTextDirection = false,
    this.allowDrawingOutsideViewBox = false,
    this.placeholderBuilder,
    this.semanticsLabel,
    this.excludeFromSemantics = false,
  }) : super(key: key);

  /// Instantiates a widget that renders an SVG picture from an [AssetBundle].
  ///
  /// The key will be derived from the `assetName`, `package`, and `bundle`
  /// arguments. The `package` argument must be non-null when displaying an SVG
  /// from a package and null otherwise. See the `Assets in packages` section for
  /// details.
  ///
  /// Either the [width] and [height] arguments should be specified, or the
  /// widget should be placed in a context that sets tight layout constraints.
  /// Otherwise, the image dimensions will change as the image is loaded, which
  /// will result in ugly layout changes.
  ///
  /// If `matchTextDirection` is set to true, the picture will be flipped
  /// horizontally in [TextDirection.rtl] contexts.
  ///
  /// The `allowDrawingOutsideOfViewBox` parameter should be used with caution -
  /// if set to true, it will not clip the canvas used internally to the view box,
  /// meaning the picture may draw beyond the intended area and lead to undefined
  /// behavior or additional memory overhead.
  ///
  /// A custom `placeholderBuilder` can be specified for cases where decoding or
  /// acquiring data may take a noticeably long time.
  ///
  /// The `color` and `colorBlendMode` arguments, if specified, will be used to set a
  /// [ColorFilter] on any [Paint]s created for this drawing.
  ///
  /// ## Assets in packages
  ///
  /// To create the widget with an asset from a package, the [package] argument
  /// must be provided. For instance, suppose a package called `my_icons` has
  /// `icons/heart.svg` .
  ///
  /// Then to display the image, use:
  ///
  /// ```dart
  /// SvgPicture.asset('icons/heart.svg', package: 'my_icons')
  /// ```
  ///
  /// Assets used by the package itself should also be displayed using the
  /// [package] argument as above.
  ///
  /// If the desired asset is specified in the `pubspec.yaml` of the package, it
  /// is bundled automatically with the app. In particular, assets used by the
  /// package itself must be specified in its `pubspec.yaml`.
  ///
  /// A package can also choose to have assets in its 'lib/' folder that are not
  /// specified in its `pubspec.yaml`. In this case for those images to be
  /// bundled, the app has to specify which ones to include. For instance a
  /// package named `fancy_backgrounds` could have:
  ///
  /// ```
  /// lib/backgrounds/background1.svg
  /// lib/backgrounds/background2.svg
  /// lib/backgrounds/background3.svg
  ///```
  ///
  /// To include, say the first image, the `pubspec.yaml` of the app should
  /// specify it in the assets section:
  ///
  /// ```yaml
  ///  assets:
  ///    - packages/fancy_backgrounds/backgrounds/background1.svg
  /// ```
  ///
  /// The `lib/` is implied, so it should not be included in the asset path.
  ///
  ///
  /// See also:
  ///
  ///  * [AssetPicture], which is used to implement the behavior when the scale is
  ///    omitted.
  ///  * [ExactAssetPicture], which is used to implement the behavior when the
  ///    scale is present.
  ///  * <https://flutter.io/assets-and-images/>, an introduction to assets in
  ///    Flutter.
  ///
  /// If [excludeFromSemantics] is true, then [semanticLabel] will be ignored.
  SvgPicture.asset(
    String assetName, {
    Key key,
    this.matchTextDirection = false,
    AssetBundle bundle,
    String package,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.allowDrawingOutsideViewBox = false,
    this.placeholderBuilder,
    Color color,
    BlendMode colorBlendMode = BlendMode.srcIn,
    this.semanticsLabel,
    this.excludeFromSemantics = false,
  })  : pictureProvider = ExactAssetPicture(
            allowDrawingOutsideViewBox == true
                ? svgStringDecoderOutsideViewBox
                : svgStringDecoder,
            assetName,
            bundle: bundle,
            package: package,
            colorFilter: _getColorFilter(color, colorBlendMode)),
        super(key: key);

  /// Creates a widget that displays a [PictureStream] obtained from the network.
  ///
  /// The [url] argument must not be null.
  ///
  /// Either the [width] and [height] arguments should be specified, or the
  /// widget should be placed in a context that sets tight layout constraints.
  /// Otherwise, the image dimensions will change as the image is loaded, which
  /// will result in ugly layout changes.
  ///
  /// If `matchTextDirection` is set to true, the picture will be flipped
  /// horizontally in [TextDirection.rtl] contexts.
  ///
  /// The `allowDrawingOutsideOfViewBox` parameter should be used with caution -
  /// if set to true, it will not clip the canvas used internally to the view box,
  /// meaning the picture may draw beyond the intended area and lead to undefined
  /// behavior or additional memory overhead.
  ///
  /// A custom `placeholderBuilder` can be specified for cases where decoding or
  /// acquiring data may take a noticeably long time, such as high latency scenarios.
  ///
  /// The `color` and `colorBlendMode` arguments, if specified, will be used to set a
  /// [ColorFilter] on any [Paint]s created for this drawing.
  ///
  /// All network images are cached regardless of HTTP headers.
  ///
  /// An optional `headers` argument can be used to send custom HTTP headers
  /// with the image request.
  ///
  /// If [excludeFromSemantics] is true, then [semanticLabel] will be ignored.
  SvgPicture.network(
    String url, {
    Key key,
    Map<String, String> headers,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.matchTextDirection = false,
    this.allowDrawingOutsideViewBox = false,
    this.placeholderBuilder,
    Color color,
    BlendMode colorBlendMode = BlendMode.srcIn,
    this.semanticsLabel,
    this.excludeFromSemantics = false,
  })  : pictureProvider = NetworkPicture(
            allowDrawingOutsideViewBox == true
                ? svgByteDecoderOutsideViewBox
                : svgByteDecoder,
            url,
            headers: headers,
            colorFilter: _getColorFilter(color, colorBlendMode)),
        super(key: key);

  static ColorFilter _getColorFilter(Color color, BlendMode colorBlendMode) =>
      color == null
          ? null
          : ColorFilter.mode(color, colorBlendMode ?? BlendMode.srcIn);

  /// A [PictureInfoDecoder] for [Uint8List]s that will clip to the viewBox.
  static final PictureInfoDecoder<Uint8List> svgByteDecoder =
      (Uint8List bytes, ColorFilter colorFilter, String key) =>
          svg.svgPictureDecoder(bytes, false, colorFilter, key);

  /// A [PictureInfoDecoder] for strings that will clip to the viewBox.
  static final PictureInfoDecoder<String> svgStringDecoder =
      (String data, ColorFilter colorFilter, String key) =>
          svg.svgPictureStringDecoder(data, false, colorFilter, key);

  /// A [PictureInfoDecoder] for [Uint8List]s that will not clip to the viewBox.
  static final PictureInfoDecoder<Uint8List> svgByteDecoderOutsideViewBox =
      (Uint8List bytes, ColorFilter colorFilter, String key) =>
          svg.svgPictureDecoder(bytes, true, colorFilter, key);

  /// A [PictureInfoDecoder] for [String]s that will not clip to the viewBox.
  static final PictureInfoDecoder<String> svgStringDecoderOutsideViewBox =
      (String data, ColorFilter colorFilter, String key) =>
          svg.svgPictureStringDecoder(data, true, colorFilter, key);

  /// If specified, the width to use for the SVG.  If unspecified, the SVG
  /// will take the width of its parent.
  final double width;

  /// If specified, the height to use for the SVG.  If unspecified, the SVG
  /// will take the height of its parent.
  final double height;

  /// How to inscribe the picture into the space allocated during layout.
  /// The default is [BoxFit.contain].
  final BoxFit fit;

  /// How to align the picture within its parent widget.
  ///
  /// The alignment aligns the given position in the picture to the given position
  /// in the layout bounds. For example, an [Alignment] alignment of (-1.0,
  /// -1.0) aligns the image to the top-left corner of its layout bounds, while a
  /// [Alignment] alignment of (1.0, 1.0) aligns the bottom right of the
  /// picture with the bottom right corner of its layout bounds. Similarly, an
  /// alignment of (0.0, 1.0) aligns the bottom middle of the image with the
  /// middle of the bottom edge of its layout bounds.
  ///
  /// If the [alignment] is [TextDirection]-dependent (i.e. if it is a
  /// [AlignmentDirectional]), then a [TextDirection] must be available
  /// when the picture is painted.
  ///
  /// Defaults to [Alignment.center].
  ///
  /// See also:
  ///
  ///  * [Alignment], a class with convenient constants typically used to
  ///    specify an [AlignmentGeometry].
  ///  * [AlignmentDirectional], like [Alignment] for specifying alignments
  ///    relative to text direction.
  final Alignment alignment;

  /// The [PictureProvider] used to resolve the SVG.
  final PictureProvider pictureProvider;

  /// The placeholder to use while fetching, decoding, and parsing the SVG data.
  final WidgetBuilder placeholderBuilder;

  /// If true, will horizontally flip the picture in [TextDirection.rtl] contexts.
  final bool matchTextDirection;

  /// If true, will allow the SVG to be drawn outside of the clip boundary of its
  /// viewBox.
  final bool allowDrawingOutsideViewBox;

  /// The [Semantics.label] for this picture.
  ///
  /// The value indicates the purpose of the picture, and will be
  /// read out by screen readers.
  final String semanticsLabel;

  /// Whether to exclude this picture from semantics.
  ///
  /// Useful for pictures which do not contribute meaningful information to an
  /// application.
  final bool excludeFromSemantics;

  static SvgPicturePlatform _platform;

  static SvgPicturePlatform get platform {
    if (_platform == null) {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
        case TargetPlatform.iOS:
          _platform = MobileSvgPicture();
          break;
        default:
          throw Exception('not implemented');
      }
    }
    return _platform;
  }

  @override
  Widget build(BuildContext context) {
    return platform.build(
      pictureProvider,
      key: key,
      width: width,
      height: height,
      alignment: alignment,
      allowDrawingOutsideViewBox: allowDrawingOutsideViewBox,
      excludeFromSemantics: excludeFromSemantics,
      fit: fit,
      matchTextDirection: matchTextDirection,
      placeholderBuilder: placeholderBuilder,
      semanticsLabel: semanticsLabel,
    );
  }
}
