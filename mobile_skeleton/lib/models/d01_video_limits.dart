/// D01 pilot analizi video sınırları.
///
/// Sunucudaki `PILOT_D01_MAX_VIDEO_SECONDS` (varsayılan 210 sn = 3,5 dakika) ile aynı tutulmalıdır.
/// İleride sınır sunucudan okunarak dinamik hale getirilecek; o zamana kadar tek kaynak burasıdır.
class D01VideoLimits {
  const D01VideoLimits._();

  static const maxDuration = Duration(seconds: 210);

  /// Kap süresi ses izi nedeniyle birkaç ms taşabilir; sunucuyla aynı tolerans.
  static const durationTolerance = Duration(milliseconds: 500);

  static double get maxSeconds => maxDuration.inMilliseconds / 1000;

  /// Yükleme boyutu sınırı; sunucudaki `PILOT_D01_MAX_UPLOAD_MB` (varsayılan 100) ile aynı.
  /// 24 fps, 3,5 dk videolar ölçümde 42–67 MiB; 100 MiB ≈ 4 Mbps'e kadar pay bırakır.
  static const maxUploadMiB = 100;
  static const maxUploadBytes = maxUploadMiB * 1024 * 1024;

  static bool exceeds(Duration duration) => duration > maxDuration + durationTolerance;

  /// Kullanıcıya gösterilecek süre metni: "3,5 dakika", "45 saniye", "4 dk 12 sn".
  static String describeLimit() {
    final seconds = maxDuration.inSeconds;
    if (seconds % 60 == 0) return '${seconds ~/ 60} dakika';
    if (seconds > 60 && seconds % 30 == 0) {
      return '${(seconds / 60).toStringAsFixed(1).replaceAll('.', ',')} dakika';
    }
    return '$seconds saniye';
  }

  static String describe(Duration duration) {
    final total = (duration.inMilliseconds / 1000).round();
    if (total < 60) return '$total saniye';
    final minutes = total ~/ 60, rest = total % 60;
    return rest == 0 ? '$minutes dakika' : '$minutes dk $rest sn';
  }
}
