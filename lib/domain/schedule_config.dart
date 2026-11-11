
class ScheduleConfig {
  final int sunriseHour;
  final int sunriseMinute;
  final int sunsetHour;
  final int sunsetMinute;
  final int nightHour;
  final int nightMinute;
  final int nightBrightness; // De 0 à 255

  ScheduleConfig({
    required this.sunriseHour,
    required this.sunriseMinute,
    required this.sunsetHour,
    required this.sunsetMinute,
    required this.nightHour,
    required this.nightMinute,
    required this.nightBrightness,
  });

  Map<String, dynamic> toMap() {
    return {
      'sunriseHour': sunriseHour,
      'sunriseMinute': sunriseMinute,
      'sunsetHour': sunsetHour,
      'sunsetMinute': sunsetMinute,
      'nightHour': nightHour,
      'nightMinute': nightMinute,
      'nightBrightness': nightBrightness,
    };
  }
}