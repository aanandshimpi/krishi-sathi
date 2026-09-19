import 'dart:async';

import 'package:geolocator/geolocator.dart';

class LocationException implements Exception {
  final String message;
  final bool needsSettings;
  const LocationException(this.message, {this.needsSettings = false});
  @override
  String toString() => message;
}

class FarmLocation {
  final double lat, lng;
  const FarmLocation(this.lat, this.lng);
  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};
  factory FarmLocation.fromPosition(Position p) =>
      FarmLocation(p.latitude, p.longitude);
}

class LocationService {
  Future<void> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException(
        'Turn on location services, then try again.',
        needsSettings: true,
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        'Allow location access in the app settings.',
        needsSettings: true,
      );
    }
    if (permission == LocationPermission.denied) {
      throw const LocationException(
        'Location access was denied. You can enter farm coordinates instead.',
      );
    }
  }

  Future<FarmLocation> current() async {
    await ensurePermission();
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return FarmLocation.fromPosition(p);
    } on TimeoutException {
      throw const LocationException(
        'GPS took too long. Move to an open area and try again.',
      );
    }
  }

  Stream<FarmLocation> updates() => Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 50,
    ),
  ).map(FarmLocation.fromPosition);
}
