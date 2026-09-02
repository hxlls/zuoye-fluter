// 跨平台导出辅助：按编译目标自动选择实现（Web / 非Web）
export 'export_file_io.dart' if (dart.library.html) 'export_file_web.dart';
