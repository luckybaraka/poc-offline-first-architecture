/// Settings passed at run time, so no code changes are needed between emulator and phone:
///
///   flutter run --dart-define=API_BASE=http://192.168.1.20:8000/api --dart-define=DEVICE_ID=phone-a
///
/// The default API_BASE is the Android emulator's address for the laptop (10.0.2.2).
library;

const String kApiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://10.0.2.2:8000/api');
const String kDeviceIdOverride = String.fromEnvironment('DEVICE_ID');

const Duration kSyncInterval = Duration(seconds: 5);
const Duration kPingInterval = Duration(seconds: 10);
const int kBatchSize = 50;

const List<String> kStatuses = ['ACTIVE', 'INACTIVE', 'SUSPENDED'];
const List<String> kSyncedFields = ['name', 'phone', 'status', 'deleted'];
