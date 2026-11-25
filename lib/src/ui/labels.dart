/// Human-readable labels for native enum names and timestamps.
abstract final class Labels {
  static String phase(String? p) => switch (p) {
        'STOPPED' => 'Stopped',
        'MONITORING_OUTSIDE' => 'Watching for arrival',
        'MONITORING_INSIDE' => 'Inside · already handled',
        'WAITING_FOR_VEHICLE_SIGNAL' => 'Inside · waiting for vehicle',
        'PENDING_DELAYED_CALL' => 'Revalidating before call',
        'CALLING' => 'Calling gate',
        'COOLDOWN' => 'Cooldown',
        _ => p ?? 'Unknown',
      };

  static String geofence(String? g) => switch (g) {
        'INSIDE' => 'Inside',
        'OUTSIDE' => 'Outside',
        _ => 'Unknown',
      };

  static String vehicle(String? v) => switch (v) {
        'ACTIVE' => 'In vehicle',
        'INACTIVE' => 'Not in vehicle',
        'DISABLED' => 'Detection off',
        _ => 'Unknown',
      };

  static String androidAuto(String? a) => switch (a) {
        'ACTIVE' => 'Connected',
        'INACTIVE' => 'Not connected',
        'DISABLED' => 'Detection off',
        _ => 'Not observed',
      };

  static String triggerSource(String? s) => switch (s) {
        'ENTER_WHILE_IN_VEHICLE' => 'Arrived while driving',
        'ENTER_WHILE_IN_VEHICLE_DELAYED' => 'Arrived while driving (delayed)',
        'ENTER_WITH_ANDROID_AUTO' => 'Arrived with Android Auto',
        'ENTER_WITH_CAR_BLUETOOTH' => 'Arrived connected to the car',
        'ACTIVITY_IN_VEHICLE' => 'In vehicle inside parking',
        'ANDROID_AUTO' => 'Android Auto connected inside parking',
        'CAR_BLUETOOTH' => 'Car Bluetooth connected inside parking',
        _ => s ?? '—',
      };

  static String callOutcome(String? o) => switch (o) {
        'INITIATED' => 'Call started',
        'SIMULATED' => 'Simulated (test mode)',
        'FAILED_PERMISSION' => 'Failed: phone permission missing',
        'FAILED_INVALID_NUMBER' => 'Failed: invalid number',
        'FAILED_SIM_UNAVAILABLE' => 'Failed: selected SIM unavailable',
        'FAILED_SECURITY' => 'Blocked by Android (tap-to-call offered)',
        'FAILED_OTHER' => 'Failed',
        'UNKNOWN_PROCESS_DIED' => 'Unknown (app was stopped during the call)',
        _ => o ?? '—',
      };

  static String two(int v) => v.toString().padLeft(2, '0');

  /// "14:03:22" today, otherwise "24 Nov 14:03".
  static String time(int? epochMs, {DateTime? now}) {
    if (epochMs == null) return '—';
    final t = DateTime.fromMillisecondsSinceEpoch(epochMs);
    final n = now ?? DateTime.now();
    final hms = '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
    if (t.year == n.year && t.month == n.month && t.day == n.day) return hms;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${t.day} ${months[t.month - 1]} ${two(t.hour)}:${two(t.minute)}';
  }

  /// "5 s ago", "3 min ago", "2 h ago".
  static String ago(int? epochMs, {DateTime? now}) {
    if (epochMs == null) return '';
    final d = (now ?? DateTime.now()).difference(DateTime.fromMillisecondsSinceEpoch(epochMs));
    if (d.inSeconds < 60) return '${d.inSeconds.clamp(0, 59)} s ago';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 48) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}
