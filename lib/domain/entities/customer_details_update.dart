/// The customer-detail edits the agent makes on the Visit Customer Address
/// screen, sent to the customers service on Save.
///
/// Addressed by [customerId] (`PATCH /api/v1/customers/{id}`) whenever the
/// ticket detail carried one. Phone numbers are not unique in that backend —
/// the by-phone route answers 409 "Ambiguous phonePrimary" when several
/// customers share a number — so it is only the fallback for a missing id.
///
/// Every editable field is nullable and serialized even when null — the
/// contract distinguishes "the agent left this blank" (explicit `null`) from a
/// value, so [toJson] must not drop keys.
class CustomerDetailsUpdate {
  const CustomerDetailsUpdate({
    required this.phonePrimary,
    this.customerId = '',
    this.phoneSecondary,
    this.addressLine1,
    this.city,
    this.state,
    this.pincode,
    this.metadata = const {},
  });

  /// The customers-service id from the ticket detail, filled into the `{id}`
  /// path segment. Empty when the ticket detail carried none, which is the
  /// only case that falls back to the by-phone route. Never serialized — it
  /// addresses the resource, it isn't part of the patch.
  final String customerId;

  /// The customer's existing primary number, parsed from the ticket detail.
  /// Also the lookup key on the by-phone fallback route.
  final String phonePrimary;

  /// "Update Alternate Phone Number If Any" — validated to 10 digits before
  /// this object is built.
  final String? phoneSecondary;

  final String? addressLine1;
  final String? city;
  final String? state;
  final String? pincode;

  /// Free-form extras that aren't first-class columns — currently the
  /// "Customer Visit Remarks" the agent typed on the same screen.
  final Map<String, dynamic> metadata;

  /// True when the agent actually entered something. Guards the caller against
  /// firing a PATCH whose explicit nulls would blank out server-side values the
  /// agent never intended to touch.
  bool get hasEdits =>
      phoneSecondary != null ||
      addressLine1 != null ||
      city != null ||
      state != null ||
      pincode != null ||
      metadata.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'phonePrimary': phonePrimary,
        'phoneSecondary': phoneSecondary,
        'addressLine1': addressLine1,
        'city': city,
        'state': state,
        'pincode': pincode,
        if (metadata.isNotEmpty) 'metadata': metadata,
      };

  /// Round-trips through the offline sync queue, so [customerId] rides along
  /// under a key the request body itself never carries.
  Map<String, dynamic> toQueuePayload() => {
        ...toJson(),
        '_customerId': customerId,
      };

  factory CustomerDetailsUpdate.fromJson(Map<String, dynamic> json) =>
      CustomerDetailsUpdate(
        customerId: json['_customerId'] as String? ?? '',
        phonePrimary: json['phonePrimary'] as String? ?? '',
        phoneSecondary: json['phoneSecondary'] as String?,
        addressLine1: json['addressLine1'] as String?,
        city: json['city'] as String?,
        state: json['state'] as String?,
        pincode: json['pincode'] as String?,
        metadata: (json['metadata'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}
