/// একটা favorited গান — Favorites screen-এ দেখানোর জন্য, thumbnail-সহ।
///
/// Favorites টেবিল নিজে শুধু (userId, songId, createdAt) রাখে — এখানে
/// Songs টেবিলের সাথে join করে UI-friendly shape বানানো হচ্ছে,
/// RecentlyPlayedEntry-এর মতোই একই নীতি (raw Drift row UI-তে সরাসরি
/// এক্সপোজ না করে)।
class FavoriteSong {
  final String songId;
  final String title;
  final String author;
  final String thumbnail;
  final DateTime addedAt;

  const FavoriteSong({
    required this.songId,
    required this.title,
    required this.author,
    required this.thumbnail,
    required this.addedAt,
  });
}