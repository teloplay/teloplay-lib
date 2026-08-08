/// Playlist list-এ দেখানোর জন্য summary model — একটা playlist-এর
/// metadata + item count (পুরো item list না, list screen-এ শুধু
/// count/cover লাগে, পুরো song list না)।
///
/// [coverThumbnail] প্রথম item-এর thumbnail (থাকলে) — ব্যবহারকারী কোনো
/// custom cover আপলোড করার UI এখনো নেই (Phase 7+), তাই আপাতত প্রথম
/// গানের artwork-ই cover হিসেবে দেখানো হচ্ছে। খালি playlist-এর জন্য
/// null (UI generic icon দেখাবে)।
class PlaylistSummary {
  final String id;
  final String name;
  final int itemCount;
  final String? coverThumbnail;
  final DateTime updatedAt;

  const PlaylistSummary({
    required this.id,
    required this.name,
    required this.itemCount,
    required this.coverThumbnail,
    required this.updatedAt,
  });
}

/// একটা playlist-এর ভেতরের single song entry — PlaylistItems row +
/// joined Songs metadata, playlist-detail screen-এর জন্য।
class PlaylistItemEntry {
  /// PlaylistItems.id (UUID) — reorder/remove-এর জন্য দরকার, songId না
  /// (একই গান একাধিকবার একই playlist-এ থাকতে পারলে ambiguity এড়াতে,
  /// যদিও ভবিষ্যতে duplicate-prevention যোগ হতে পারে, এখন schema-level
  /// কোনো unique constraint নেই)।
  final String itemId;
  final String songId;
  final String title;
  final String author;
  final String thumbnail;
  final int position;

  const PlaylistItemEntry({
    required this.itemId,
    required this.songId,
    required this.title,
    required this.author,
    required this.thumbnail,
    required this.position,
  });
}

/// পূর্ণ playlist detail — metadata + ordered item list, একসাথে।
/// PlaylistDetailScreen-এর মূল data shape।
class PlaylistDetail {
  final String id;
  final String name;
  final List<PlaylistItemEntry> items;

  const PlaylistDetail({
    required this.id,
    required this.name,
    required this.items,
  });
}