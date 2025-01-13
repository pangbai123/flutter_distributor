import 'dart:convert';
import 'dart:io';

import 'package:flutter_app_publisher/src/api/app_package_publisher.dart';
import 'package:flutter_app_publisher/src/publishers/appstore/publish_appstore_config.dart';
import 'package:http/http.dart' as http;
import 'package:jose/jose.dart';

import '../oppo/app_package_publisher_oppo.dart';

class AppPackagePublisherAppStore extends AppPackagePublisher {
  @override
  String get name => 'appstore';

  @override
  List<String> get supportedPlatforms => ['ios', 'macos'];

  late Map<String, String> globalEnvironment;
  late String token;

  @override
  Future<PublishResult> publish(
    FileSystemEntity fileSystemEntity, {
    Map<String, String>? environment,
    Map<String, dynamic>? publishArguments,
    PublishProgressCallback? onPublishProgress,
  }) async {
    File file = fileSystemEntity as File;

    globalEnvironment = environment ?? Platform.environment;

    // Get type (iOS or macOS)
    String type = file.path.endsWith('.ipa') ? 'ios' : 'osx';

    // Parse configuration
    PublishAppStoreConfig publishConfig =
        PublishAppStoreConfig.parse(environment);

    String? version = globalEnvironment[kEnvVersionName]; // Default version
    String? whatsNew = globalEnvironment[kEnvUpdateLog]; // Default update log

    print('Publishing App - Version: $version');
    print('Update Notes: $whatsNew');

    token = generateAppStoreToken(
      keyId: "1P6B1OWVK0KQ",
      issuerId: "4d502497-da44-487f-8ef8-ac75d3b1f7b3",
      privateKey: '''
-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQghdwIlLX2e8Y0aZi1
OGBLbhxWxQ1GKPnnO6xrTVz4jiShRANCAASU4Y+HmT8xC/aCcLpxSxXpAdS6/nXj
wsZo+nVtG5vgks4RPUlZzvmZdtmx06T8hCSRoCsyfbxKwmqEI8EgWRgg
-----END PRIVATE KEY-----
''',
    );

    try {
      // 1. 上传 IPA 文件到 App Store Connect
      final ipaFileUrl = await _uploadToAppStoreConnect(file, type);

      // 2. 更新应用元数据（版本和更新日志）
      await _updateAppVersionAndMetadata(version!, whatsNew!);

      return PublishResult(
        url: ipaFileUrl,
      );
    } catch (e) {
      throw PublishError('Failed to publish app: $e');
    }
  }

  String generateAppStoreToken({
    required String keyId,
    required String issuerId,
    required String privateKey,
  }) {
    final currentTime = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final payload = {
      'iss': issuerId,
      'iat': currentTime,
      'exp': currentTime + (20 * 60), // Token valid for 20 minutes
    };

    final builder = JsonWebSignatureBuilder()
      ..jsonContent = payload
      ..setProtectedHeader('alg', 'ES256')
      ..setProtectedHeader('kid', keyId)
      ..addRecipient(
        JsonWebKey.fromPem(privateKey),
        algorithm: 'ES256',
      );
    final jws = builder.build();
    return jws.toCompactSerialization();
  }


  // 上传 .ipa 文件到 App Store Connect
  Future<String> _uploadToAppStoreConnect(File ipaFile, String type) async {
    final String apiUrl =
        'https://api.appstoreconnect.apple.com/v1/appStoreVersions';

    final Map<String, String> headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };

    // 上传 IPA 文件
    final request = http.MultipartRequest(
      'POST',
      Uri.parse(apiUrl),
    );
    request.headers.addAll(headers);
    request.files.add(await http.MultipartFile.fromPath('file', ipaFile.path));

    final response = await request.send();
    if (response.statusCode == 201) {
      // 解析返回的 JSON 响应并获取文件上传成功后的 URL
      final responseBody = await response.stream.bytesToString();
      final Map<String, dynamic> jsonResponse = jsonDecode(responseBody);
      return jsonResponse['data']['url']; // 返回文件 URL
    } else {
      throw Exception('Failed to upload IPA file: ${response.statusCode}');
    }
  }

  // 更新应用版本和元数据（版本号、更新日志）
  Future<void> _updateAppVersionAndMetadata(
      String version, String whatsNew) async {
    final String apiUrl =
        'https://api.appstoreconnect.apple.com/v1/apps/1588193025/appStoreVersions';

    final Map<String, String> headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };

    final Map<String, dynamic> body = {
      'data': {
        'type': 'appStoreVersions',
        'attributes': {
          'version': version,
          'releaseNotes': whatsNew,
        }
      }
    };

    final response = await http.post(
      Uri.parse(apiUrl),
      headers: headers,
      body: jsonEncode(body),
    );

    if (response.statusCode == 200) {
      print('App version and metadata updated successfully.');
    } else {
      throw Exception('Failed to update app version: ${response.statusCode}');
    }
  }
}
