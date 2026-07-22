import 'package:asset_recovery_app/domain/entities/geo_point.dart';

/// Customer mapped to a battery pack. Field agents may update address/mobile
/// and capture a fresh home location (PRD §5.2.2 / §5.2.3).
class Customer {
  const Customer({
    required this.name,
    required this.mobile,
    required this.address,
    this.homeLocation,
  });

  final String name;
  final String mobile;
  final String address;
  final GeoPoint? homeLocation;

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
        name: json['name'] as String? ?? '',
        mobile: json['mobile'] as String? ?? '',
        address: json['address'] as String? ?? '',
        homeLocation: json['homeLocation'] == null
            ? null
            : GeoPoint.fromJson(json['homeLocation'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'mobile': mobile,
        'address': address,
        if (homeLocation != null) 'homeLocation': homeLocation!.toJson(),
      };

  Customer copyWith({String? name, String? mobile, String? address, GeoPoint? homeLocation}) =>
      Customer(
        name: name ?? this.name,
        mobile: mobile ?? this.mobile,
        address: address ?? this.address,
        homeLocation: homeLocation ?? this.homeLocation,
      );

  String maskedMobile() {
    if (mobile.length < 4) return mobile;
    return '${mobile.substring(0, 2)}XXXXX${mobile.substring(mobile.length - 3)}';
  }
}
