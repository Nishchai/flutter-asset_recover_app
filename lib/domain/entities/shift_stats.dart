/// Aggregate shift counters shown on the home header (Figma).
class ShiftStats {
  const ShiftStats({
    required this.assigned,
    required this.inProgress,
    required this.pending,
  });

  final int assigned;
  final int inProgress;
  final int pending;

  static const empty = ShiftStats(assigned: 0, inProgress: 0, pending: 0);

  factory ShiftStats.fromMap(Map<String, int> map) => ShiftStats(
        assigned: map['assigned'] ?? 0,
        inProgress: map['inProgress'] ?? 0,
        pending: map['pending'] ?? 0,
      );
}
