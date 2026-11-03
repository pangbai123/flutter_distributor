import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app_publisher/src/api/app_package_publisher.dart';
import 'package:http/http.dart' as http;

const kEnvAppName = 'APP_NAME';
const kEnvTencentAppUserId = 'TENCENT_USER_ID';
const kEnvTencentAccessSecret = 'TENCENT_ACCESS_SECRET';
const kEnvTencentAppId = 'TENCENT_APP_ID';
const kEnvPkgName = 'PKG_NAME';
const kEnvUpdateLog = 'UPDATE_LOG';

const domain = 'https://p.open.qq.com/open_file/developer_api'; // 正式环境接口域名

const _abi32 = {'armeabi', 'armeabi-v7a', 'x86'};
const _abi64 = {'arm64-v8a', 'x86_64'};

///  doc [https://wikinew.open.qq.com/index.html#/iwiki/4015262492]
class AppPackagePublisherTencent extends AppPackagePublisher {
  @override
  String get name => 'tencent';
  String? userId;
  String? accessSecret;
  String? appName;
  String? pkgName;
  String? appId;
  String? appUpdateLog;

  late Map<String, String> globalEnvironment;

  @override
  Future<PublishResult> publish(
    FileSystemEntity fileSystemEntity, {
    Map<String, String>? environment,
    Map<String, dynamic>? publishArguments,
    PublishProgressCallback? onPublishProgress,
  }) async {
    final file = fileSystemEntity as File;

    globalEnvironment = environment ?? Platform.environment;
    userId = _required(kEnvTencentAppUserId);
    appName = _required(kEnvAppName);
    pkgName = _required(kEnvPkgName);
    appId = _required(kEnvTencentAppId);
    accessSecret = _required(kEnvTencentAccessSecret);
    appUpdateLog = globalEnvironment[kEnvUpdateLog];

    if (!await file.exists()) {
      throw PublishError('File not found: ${file.path}');
    }

    final fileBytes = await file.readAsBytes();
    final fileMd5 = md5.convert(fileBytes).toString();
    final only64 = _is64BitOnly(fileBytes);

    await getAppInfo();
    final uploadInfo = await getUpLoadFileInfo();
    final preSignUrl = _requiredField(
      uploadInfo,
      'pre_sign_url',
      'get_file_upload_info',
    );
    final serialNumber = _requiredField(
      uploadInfo,
      'serial_number',
      'get_file_upload_info',
    );
    await uploadFile(preSignUrl, fileBytes);
    await updateAppInfo(
      serialNumber,
      fileMd5,
      only64: only64,
    );

    return PublishResult(url: '$appName$name提交成功}');
  }

  String _required(String key) {
    final value = globalEnvironment[key];
    if (value == null || value.isEmpty) {
      throw PublishError('Missing `$key` environment variable.');
    }
    return value;
  }

  /// 计算签名
  String calSign(String key, Map<String, String> data) {
    final sortedKeys = data.keys.toList()..sort();
    final signStr = sortedKeys.map((k) => '$k=${data[k]}').join('&');
    final hmacSha256 = Hmac(sha256, utf8.encode(key));
    final digest = hmacSha256.convert(utf8.encode(signStr));
    return digest.toString();
  }

  Future<Map<String, dynamic>> getAppInfo() {
    return _postApi('/query_app_detail', <String, String>{
      'pkg_name': pkgName!,
      'app_id': appId!,
    });
  }

  Future<Map<String, dynamic>> getUpLoadFileInfo() {
    return _postApi('/get_file_upload_info', <String, String>{
      'pkg_name': pkgName!,
      'app_id': appId!,
      'file_type': 'apk',
      'file_name': '$appName.apk',
    });
  }

  Map<String, String>? header() {
    return {'Content-Type': 'application/x-www-form-urlencoded'};
  }

  /// 上传文件到 COS（PUT 预签名 URL）
  Future<void> uploadFile(String preSignUrl, List<int> fileBytes) async {
    final response = await http.put(
      Uri.parse(preSignUrl),
      headers: {
        'Content-Type': 'application/octet-stream',
      },
      body: fileBytes,
    );

    if (response.statusCode != 200) {
      throw PublishError(
        'Upload failed: ${response.statusCode} ${response.reasonPhrase} ${response.body}',
      );
    }
  }

  /// flag：1=上传该槽位，2=不上传。不能传 0。
  /// 纯 64 位包必须走 apk64，否则服务端按 64 位包解析并返回 4000046。
  /// 32 位或 32/64 兼容包走 apk32，并显式 apk64_flag=2，避免沿用旧的 64 位包再校验失败。
  Future<Map<String, dynamic>> updateAppInfo(
    String serialNumber,
    String fileMd5, {
    required bool only64,
  }) {
    final data = <String, String>{
      'pkg_name': pkgName!,
      'app_id': appId!,
      'deploy_type': '1', //立即发布
    };
    if (only64) {
      data['apk32_flag'] = '2';
      data['apk64_flag'] = '1';
      data['apk64_file_serial_number'] = serialNumber;
      data['apk64_file_md5'] = fileMd5;
    } else {
      data['apk32_flag'] = '1';
      data['apk64_flag'] = '2';
      data['apk32_file_serial_number'] = serialNumber;
      data['apk32_file_md5'] = fileMd5;
    }
    final feature = appUpdateLog;
    if (feature != null && feature.isNotEmpty) {
      data['feature'] = feature;
    }
    print('tencent update_app abi only64=$only64 md5=$fileMd5');
    return _postApi('/update_app', data);
  }

  Future<Map<String, dynamic>> _postApi(
    String path,
    Map<String, String> business,
  ) async {
    final data = <String, String>{
      'user_id': userId!,
      'timestamp': (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
      ...business,
    };
    final sign = calSign(accessSecret!, data);
    print('api sign: $sign');
    data['sign'] = sign;

    final response = await http.post(
      Uri.parse('$domain$path'),
      headers: header(),
      body: data,
    );
    final content = response.body;
    if (response.statusCode != 200) {
      throw PublishError('$path HTTP ${response.statusCode}: $content');
    }

    final decoded = jsonDecode(content);
    if (decoded is! Map) {
      throw PublishError('$path 响应不是对象: $content');
    }
    final responseMap = Map<String, dynamic>.from(decoded);
    if (responseMap['ret'] != 0) {
      throw PublishError(content);
    }
    return responseMap;
  }

  String _requiredField(Map<String, dynamic> map, String key, String api) {
    final value = map[key];
    if (value is! String || value.isEmpty) {
      throw PublishError('$api 缺少 $key: $map');
    }
    return value;
  }

  bool _is64BitOnly(List<int> bytes) {
    final abis = _readNativeAbis(bytes);
    if (abis.isEmpty) return false;
    if (abis.any(_abi32.contains)) return false;
    return abis.every(_abi64.contains);
  }
}

/// 从 APK（ZIP）中央目录读取 `lib/<abi>/`。
Set<String> _readNativeAbis(List<int> bytes) {
  final eocd = _findEocdOffset(bytes);
  if (eocd == null) {
    throw PublishError('无法解析 APK：未找到 ZIP 目录');
  }
  final totalEntries = _u16(bytes, eocd + 10);
  final cdSize = _u32(bytes, eocd + 12);
  final cdOffset = _u32(bytes, eocd + 16);
  if (totalEntries == 0xFFFF ||
      cdSize == 0xFFFFFFFF ||
      cdOffset == 0xFFFFFFFF) {
    throw PublishError('APK 使用 ZIP64，当前无法判断架构');
  }
  if (cdOffset + cdSize > bytes.length) {
    throw PublishError('无法解析 APK 中央目录');
  }

  final abis = <String>{};
  var offset = cdOffset;
  final end = cdOffset + cdSize;
  for (var i = 0; i < totalEntries; i++) {
    if (offset + 46 > end) {
      throw PublishError('无法解析 APK 中央目录');
    }
    if (_u32(bytes, offset) != 0x02014b50) {
      throw PublishError('无法解析 APK 中央目录');
    }
    final nameLength = _u16(bytes, offset + 28);
    final extraLength = _u16(bytes, offset + 30);
    final commentLength = _u16(bytes, offset + 32);
    final nameStart = offset + 46;
    final nameEnd = nameStart + nameLength;
    if (nameEnd + extraLength + commentLength > end) {
      throw PublishError('无法解析 APK 文件名');
    }
    final name = String.fromCharCodes(bytes.sublist(nameStart, nameEnd));
    if (name.startsWith('lib/')) {
      final parts = name.split('/');
      if (parts.length >= 3 && parts[1].isNotEmpty) {
        abis.add(parts[1]);
      }
    }
    offset = nameEnd + extraLength + commentLength;
  }
  return abis;
}

int? _findEocdOffset(List<int> bytes) {
  if (bytes.length < 22) return null;
  final start = bytes.length - 22;
  final min = bytes.length > 65557 ? bytes.length - 65557 : 0;
  for (var i = start; i >= min; i--) {
    if (bytes[i] != 0x50) continue;
    if (_u32(bytes, i) != 0x06054b50) continue;
    final commentLength = _u16(bytes, i + 20);
    if (i + 22 + commentLength == bytes.length) return i;
  }
  return null;
}

int _u16(List<int> bytes, int offset) {
  return bytes[offset] | (bytes[offset + 1] << 8);
}

int _u32(List<int> bytes, int offset) {
  return bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);
}
