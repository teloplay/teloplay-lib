import 'dart:async';
import 'dart:io';
import 'skeleton_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/cache_service_provider.dart';
import '../services/performance_service.dart';

/// ⚠️ Phase 1 (Smart Performance Foundation) → ✅ Phase 3 Item C
/// (Thumbnail Cache Wiring) — single reusable artwork widget। এই ফাইলের
/// বাইরে অ্যাপের কোথাও সরাসরি network image loading দিয়ে thumbnail/
/// artwork দেখানো উচিত না — এই widget-ই একমাত্র জায়গা যেখানে caching
/// policy, placeholder, error-fallback এবং Low RAM downscaling সিদ্ধান্ত
/// নেওয়া হয়।
///
/// ✅ Item C পরিবর্তন (স্থায়ী সিদ্ধান্ত): `cached_network_image` package
/// এখান থেকে সরিয়ে ফেলা হয়েছে। আগে এই widget সরাসরি সেই package-এর
/// নিজস্ব disk+memory cache ব্যবহার করত, যেটা roadmap-এর "Media Asset
/// Cache Foundation" নীতির সাথে সাংঘর্ষিক ছিল — দুইটা সম্পূর্ণ আলাদা,
/// একে অপরের অজানা disk-cache system একসাথে চলছিল (আমাদের
/// `MediaAssetManager`/LRU/budget system প্রথমে চেক করত, কিন্তু
/// `cached_network_image`-ও নিজে থেকে আলাদাভাবে ডিস্কে সেভ করত) —
/// ফলে thumbnail budget (50MB, Settings-এ user-configurable বলে
/// দেখানো) প্রকৃতপক্ষে অর্ধেক নিয়ন্ত্রণহীন থাকত, কারণ package-এর
/// নিজস্ব cache-এর উপর আমাদের কোনো visibility/eviction control নেই।
///
/// নতুন flow (সম্পূর্ণ আমাদের নিজস্ব `MediaAssetManager` দিয়ে
/// নিয়ন্ত্রিত, single source of truth):
///   1. build()-এ প্রথমে `CacheService.checkCachedThumbnail()` (sync-ish
///      quick filesystem check) — hit থাকলে সরাসরি `Image.file` দেখানো
///      হয়, কোনো network call ছাড়াই।
///   2. Miss হলে placeholder দেখিয়ে সাথে সাথে
///      `CacheService.cacheThumbnailIfNeeded()` fire-and-forget ট্রিগার
///      হয় (download + `MediaAssetManager.put()`), সফল হলে `setState()`
///      দিয়ে local file-এ switch করা হয়।
///   3. Cache lookup/download দুটোই ব্যর্থ হলে (network-off, 404,
///      ইত্যাদি) — icon-based error fallback, আগের মতোই।
///
/// এটা একটা `StatefulWidget`-এ পরিণত হয়েছে (আগে `StatelessWidget` ছিল)
/// কারণ cache-check/download asynchronous এবং widget-কে নিজের local
/// state (`_resolvedLocalPath`, `_failed`) ট্র্যাক রাখতে হয় miss→hit
/// transition-এর জন্য।
///
/// Low RAM policy অপরিবর্তিত: `PerformanceService.isLowRamMode` true
/// হলে caller-এর দেওয়া `memCacheWidth`/`memCacheHeight` downscale করা
/// হয় `Image.file`-এর `cacheWidth`/`cacheHeight` parameter-এ (আগে
/// `cached_network_image`-এর `memCacheWidth`/`memCacheHeight`-এ যেত,
/// এখন Flutter-এর native `Image` widget-এর সমতুল্য parameter-এ)।
class CachedArtwork extends ConsumerStatefulWidget {
  const CachedArtwork({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.memCacheWidth,
    this.memCacheHeight,
    this.placeholderIcon = Icons.music_note,
    this.iconColor,
    this.backgroundColor,
    this.cacheKey,
    this.onLocalPathResolved,
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  /// Decode-time target pixel dimensions (device pixels)। না দিলে
  /// original resolution decode হবে।
  final int? memCacheWidth;
  final int? memCacheHeight;

  final IconData placeholderIcon;
  final Color? iconColor;
  final Color? backgroundColor;

  /// ⚠️ Item C — `MediaAssetManager` disk-cache key হিসেবে videoId
  /// ব্যবহার করে (URL না, কারণ resolved stream/thumbnail URL সময়ের
  /// সাথে বদলাতে পারে যদিও track একই থাকে)। বেশিরভাগ caller-এর কাছে
  /// videoId সহজলভ্য (Song/SearchResult model-এই থাকে), তাই এই
  /// parameter explicit রাখা হয়েছে — null হলে fallback হিসেবে
  /// `imageUrl`-কেই cache key হিসেবে ব্যবহার করা হয় (URL সরাসরি key
  /// হিসেবে ব্যবহারযোগ্য, শুধু stream-URL-এর মতো ঘন ঘন বদলায় না বলে
  /// ঠিক আছে, কিন্তু videoId দেওয়া থাকলে সবসময় preferred — বেশি
  /// stable cache hit rate দেয়)।
  final String? cacheKey;

  /// ⚠️ Phase 6 — artwork resolve হওয়ার পর (cache-hit বা fresh
  /// download শেষে) local file path জানানোর জন্য generic callback।
  /// ইচ্ছাকৃতভাবে "onPaletteReady" না করে path-ভিত্তিক রাখা হয়েছে —
  /// caller নিজে ঠিক করবে path দিয়ে কী করবে (এখন: ColorExtractor
  /// দিয়ে album accent বের করা; ভবিষ্যতে: Canvas/video artwork,
  /// image metadata ইত্যাদি একই hook পুনরায় ব্যবহার করতে পারবে)।
  /// প্রতি resolve-এ (cache-hit + fresh-download দুটো পথেই) একবার
  /// কল হয় — rebuild-এ বারবার না (দেখো _resolveArtwork-এর ভেতরে)।
  final ValueChanged<String>? onLocalPathResolved;

  @override
  ConsumerState<CachedArtwork> createState() => _CachedArtworkState();
}

class _CachedArtworkState extends ConsumerState<CachedArtwork> {
  String? _localPath;
  bool _failed = false;
  bool _fetchInFlight = false;

  // ⚠️ Low RAM mode-এ decode dimension কমানোর factor — RAM byte-usage
  // dimension² অনুপাতে কমে।
  static const _lowRamDownscaleFactor = 0.6;

  String get _effectiveCacheKey => widget.cacheKey ?? widget.imageUrl;

  @override
  void initState() {
    super.initState();
    _resolveArtwork();
  }

  @override
  void didUpdateWidget(covariant CachedArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ⚠️ Track/artwork বদলালে (list scroll-এ widget reuse, বা track
    // change) আগের resolved path/error state clear করে নতুন করে resolve
    // করা — নাহলে পুরনো track-এর artwork ভুলভাবে নতুন track-এর জন্য
    // দেখানো হতে পারে (element reuse-এর কারণে)।
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.cacheKey != widget.cacheKey) {
      setState(() {
        _localPath = null;
        _failed = false;
        _fetchInFlight = false;
      });
      _resolveArtwork();
    }
  }

  Future<void> _resolveArtwork() async {
    if (widget.imageUrl.isEmpty) {
      if (mounted) setState(() => _failed = true);
      return;
    }

    final cacheService = ref.read(cacheServiceProvider);

    // ⚠️ FIX: CacheService cold-start-এ async initialize হয় — ready না
    // হওয়া পর্যন্ত অপেক্ষা করা হচ্ছে, নাহলে প্রথম build-এর সময়
    // checkCachedThumbnail/cacheThumbnailIfNeeded দুটোই সবসময় early-return
    // null দিয়ে দিত (_initialized guard) এবং widget permanently _failed
    // state-এ আটকে যেত app cold-start-এ।
    await cacheService.ready;
    if (!mounted) return;

    // ধাপ ১ — দ্রুত cache-hit check।
    final cachedPath =
        await cacheService.checkCachedThumbnail(_effectiveCacheKey);
    if (!mounted) return;
    if (cachedPath != null) {
      setState(() => _localPath = cachedPath);
      widget.onLocalPathResolved?.call(cachedPath);
      return;
    }

    // ধাপ ২ — miss, background download+cache ট্রিগার (fire-and-forget
    // এই ফাংশনের ভেতর থেকে awaited, কিন্তু caller/build() কে block করে
    // না কারণ এটা initState/didUpdateWidget থেকে asynchronously চলছে)।
    if (_fetchInFlight) return;
    _fetchInFlight = true;

    final downloadedPath = await cacheService.cacheThumbnailIfNeeded(
      videoId: _effectiveCacheKey,
      imageUrl: widget.imageUrl,
    );

    if (!mounted) return;
    _fetchInFlight = false;

    if (downloadedPath != null) {
      setState(() => _localPath = downloadedPath);
      widget.onLocalPathResolved?.call(downloadedPath);
    } else {
      setState(() => _failed = true);
    }
  }

  int? _effectiveCacheWidth() {
    if (widget.memCacheWidth == null) return null;
    if (!PerformanceService.instance.isLowRamMode) return widget.memCacheWidth;
    return (widget.memCacheWidth! * _lowRamDownscaleFactor).round();
  }

  int? _effectiveCacheHeight() {
    if (widget.memCacheHeight == null) return null;
    if (!PerformanceService.instance.isLowRamMode) {
      return widget.memCacheHeight;
    }
    return (widget.memCacheHeight! * _lowRamDownscaleFactor).round();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.backgroundColor ?? const Color(0xFF2A2A2A);
    final icColor = widget.iconColor ?? Colors.white24;

    Widget child;

    if (_localPath != null) {
      // ✅ Cache hit — local file থেকে decode, কোনো network call না।
      child = Image.file(
        File(_localPath!),
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        cacheWidth: _effectiveCacheWidth(),
        cacheHeight: _effectiveCacheHeight(),
        // ⚠️ local file read খুব কমই ব্যর্থ হয় (ফাইল আছে বলেই এই path
        // নেওয়া হয়েছে), কিন্তু race condition (অন্য কোনো process/eviction
        // sweep ঠিক এই মুহূর্তে ফাইল delete করে ফেললে) থেকে বাঁচতে
        // defensive errorBuilder রাখা হচ্ছে — placeholder-এ fallback,
        // crash না করে।
        errorBuilder: (context, error, stackTrace) => _errorFallback(
          bgColor,
          icColor,
        ),
      );
    } else if (_failed) {
      child = _errorFallback(bgColor, icColor);
    } else {
      // ⚠️ এখনো resolve হচ্ছে (cache-check বা download in-progress), অথবা
      // cache service uninitialized — লোডিং placeholder।
      child = SkeletonLoader(
        width: widget.width,
        height: widget.height,
        borderRadius: widget.borderRadius ?? BorderRadius.zero,
      );
    }

    if (widget.borderRadius != null) {
      child = ClipRRect(borderRadius: widget.borderRadius!, child: child);
    }

    return child;
  }

  Widget _errorFallback(Color bgColor, Color icColor) {
    return Container(
      width: widget.width,
      height: widget.height,
      color: bgColor,
      child: Icon(
        widget.placeholderIcon,
        size: (widget.width != null && widget.width! < 80) ? 24 : 80,
        color: icColor,
      ),
    );
  }
}