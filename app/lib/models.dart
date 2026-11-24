// Data shapes shared by the YouTube Music client, the player, the library and the UI.

class ArtistRef {
  final String name;
  final String? id; // YouTube Music channel id (UC...), if known
  const ArtistRef(this.name, [this.id]);

  Map<String, dynamic> toJson() => {'name': name, 'id': id};
  factory ArtistRef.fromJson(Map<String, dynamic> j) => ArtistRef(j['name'] ?? '', j['id']);
}

class AlbumRef {
  final String name;
  final String? id; // browse id (MPRE...), if known
  const AlbumRef(this.name, [this.id]);

  Map<String, dynamic> toJson() => {'name': name, 'id': id};
  factory AlbumRef.fromJson(Map<String, dynamic> j) => AlbumRef(j['name'] ?? '', j['id']);
}

/// Anything that can appear in a search result / shelf.
sealed class Item {
  String get id;
  String get label; // title or name
  String? get art;
}

class Track implements Item {
  @override
  final String id; // YouTube video id
  final String title;
  final List<ArtistRef> artists;
  final AlbumRef? album;
  final int? duration; // seconds
  @override
  final String? art; // best thumbnail URL (square album art, or a 16:9 video frame for videos)
  final bool explicit;
  final bool isVideo; // a music video / upload rather than an album track

  const Track({
    required this.id,
    required this.title,
    this.artists = const [],
    this.album,
    this.duration,
    this.art,
    this.explicit = false,
    this.isVideo = false,
  });

  @override
  String get label => title;
  String get artistNames => artists.map((a) => a.name).join(', ');

  Track copyWith({String? art, AlbumRef? album, List<ArtistRef>? artists, int? duration}) => Track(
        id: id,
        title: title,
        artists: artists ?? this.artists,
        album: album ?? this.album,
        duration: duration ?? this.duration,
        art: art ?? this.art,
        explicit: explicit,
        isVideo: isVideo,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artists': artists.map((a) => a.toJson()).toList(),
        'album': album?.toJson(),
        'duration': duration,
        'art': art,
        'explicit': explicit,
        'isVideo': isVideo,
      };

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: j['id'],
        title: j['title'] ?? '',
        artists: [for (final a in (j['artists'] as List? ?? const [])) ArtistRef.fromJson(Map<String, dynamic>.from(a))],
        album: j['album'] == null ? null : AlbumRef.fromJson(Map<String, dynamic>.from(j['album'])),
        duration: j['duration'],
        art: j['art'],
        explicit: j['explicit'] ?? false,
        isVideo: j['isVideo'] ?? false,
      );

  @override
  bool operator ==(Object other) => other is Track && other.id == id;
  @override
  int get hashCode => id.hashCode;
}

class AlbumCard implements Item {
  @override
  final String id; // MPRE...
  final String title;
  final List<ArtistRef> artists;
  final String? year;
  final String type; // Album, Single, EP
  @override
  final String? art;
  const AlbumCard({required this.id, required this.title, this.artists = const [], this.year, this.type = 'Album', this.art});
  @override
  String get label => title;

  Map<String, dynamic> toJson() => {
        'id': id, 'title': title, 'artists': artists.map((a) => a.toJson()).toList(),
        'year': year, 'type': type, 'art': art,
      };
  factory AlbumCard.fromJson(Map<String, dynamic> j) => AlbumCard(
        id: j['id'], title: j['title'] ?? '',
        artists: [for (final a in (j['artists'] as List? ?? const [])) ArtistRef.fromJson(Map<String, dynamic>.from(a))],
        year: j['year'], type: j['type'] ?? 'Album', art: j['art'],
      );
}

class ArtistCard implements Item {
  @override
  final String id; // UC...
  final String name;
  @override
  final String? art;
  const ArtistCard({required this.id, required this.name, this.art});
  @override
  String get label => name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'art': art};
  factory ArtistCard.fromJson(Map<String, dynamic> j) => ArtistCard(id: j['id'], name: j['name'] ?? '', art: j['art']);
}

class PlaylistCard implements Item {
  @override
  final String id; // playlist id WITHOUT the "VL" prefix
  final String title;
  final String? author;
  final String? count; // e.g. "52 songs" / "1.2M views" — display only
  @override
  final String? art;
  const PlaylistCard({required this.id, required this.title, this.author, this.count, this.art});
  @override
  String get label => title;

  Map<String, dynamic> toJson() => {'id': id, 'title': title, 'author': author, 'count': count, 'art': art};
  factory PlaylistCard.fromJson(Map<String, dynamic> j) =>
      PlaylistCard(id: j['id'], title: j['title'] ?? '', author: j['author'], count: j['count'], art: j['art']);
}

class Album {
  final String id;
  final String title;
  final String type;
  final List<ArtistRef> artists;
  final String? year;
  final String? art;
  final List<Track> tracks; // each track's art = album art, album = this album
  final List<AlbumCard> otherVersions;
  const Album({
    required this.id,
    required this.title,
    this.type = 'Album',
    this.artists = const [],
    this.year,
    this.art,
    this.tracks = const [],
    this.otherVersions = const [],
  });
  int get duration => tracks.fold(0, (s, t) => s + (t.duration ?? 0));
  AlbumCard get card => AlbumCard(id: id, title: title, artists: artists, year: year, type: type, art: art);
}

class Artist {
  final String id;
  final String name;
  final String? art; // large banner/portrait
  final String? description;
  final String? listeners; // e.g. "207M monthly audience"
  final List<Track> songs; // popular
  final String? songsPlaylistId; // full "all songs" playlist, if available
  final List<AlbumCard> albums;
  final List<AlbumCard> singles;
  final List<Track> videos;
  final List<ArtistCard> related;
  final List<Shelf> more; // other shelves (featured on, playlists, live…)
  const Artist({
    required this.id,
    required this.name,
    this.art,
    this.description,
    this.listeners,
    this.songs = const [],
    this.songsPlaylistId,
    this.albums = const [],
    this.singles = const [],
    this.videos = const [],
    this.related = const [],
    this.more = const [],
  });
  ArtistCard get card => ArtistCard(id: id, name: name, art: art);
}

class Playlist {
  final String id;
  final String title;
  final String? author;
  final String? description;
  final String? art;
  final List<Track> tracks;
  const Playlist({required this.id, required this.title, this.author, this.description, this.art, this.tracks = const []});
  PlaylistCard get card => PlaylistCard(id: id, title: title, author: author, art: art);
}

class Shelf {
  final String title;
  final List<Item> items;
  const Shelf(this.title, this.items);
}

class SearchResults {
  final Item? top;
  final List<Track> songs;
  final List<AlbumCard> albums;
  final List<ArtistCard> artists;
  final List<PlaylistCard> playlists;
  final List<Track> videos;
  const SearchResults({
    this.top,
    this.songs = const [],
    this.albums = const [],
    this.artists = const [],
    this.playlists = const [],
    this.videos = const [],
  });
  bool get isEmpty => top == null && songs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty && videos.isEmpty;
}

class Lyrics {
  final String text;
  final String? source;
  const Lyrics(this.text, [this.source]);
}

final _sizeRe = RegExp(r'=[ws]\d+[^/=]*$');

/// Ask Google's image server for a square image of about [px] pixels.
/// Video frames (i.ytimg.com) are returned as-is.
String? artUrl(String? url, int px) {
  if (url == null || url.isEmpty) return null;
  if (url.contains('googleusercontent.com') || url.contains('ggpht.com')) {
    const steps = [96, 160, 240, 360, 544, 800, 1200];
    final n = steps.firstWhere((s) => s >= px, orElse: () => 1200);
    return '${url.replaceFirst(_sizeRe, '')}=w$n-h$n-l90-rj';
  }
  return url;
}
