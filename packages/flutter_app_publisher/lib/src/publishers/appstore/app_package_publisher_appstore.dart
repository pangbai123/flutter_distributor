import 'dart:convert';
import 'dart:io';

import 'package:flutter_app_publisher/src/api/app_package_publisher.dart';
import 'package:flutter_app_publisher/src/publishers/appstore/publish_appstore_config.dart';
import 'package:flutter_app_publisher/src/publishers/oppo/app_package_publisher_oppo.dart';
import 'package:http/http.dart' as http;
import 'package:jose/jose.dart';
import 'package:shell_executor/shell_executor.dart';

const kEnvReleaseNotes = 'APPSTORE_NOTES_FILE';
const kAppID = "APPSTORE_APP_ID";
const kKeyId = "APPSTORE_APIKEY";
const kIssuerId = "APPSTORE_APIISSUER";
const kPrivateKey = "APPSTORE_PRIVATEKEY";

class AppPackagePublisherAppStore extends AppPackagePublisher {
  @override
  String get name => 'appstore';

  @override
  List<String> get supportedPlatforms => ['ios', 'macos'];

  late Map<String, dynamic> globalEnvironment;
  late String token;

  @override
  Future<PublishResult> publish(
    FileSystemEntity fileSystemEntity, {
    Map<String, String>? environment,
    Map<String, dynamic>? publishArguments,
    PublishProgressCallback? onPublishProgress,
  }) async {
    globalEnvironment = environment ?? Platform.environment;
    File file = fileSystemEntity as File;

    final releaseNotesMap;
    try {
      final jsonFile = (environment ?? Platform.environment)[kEnvReleaseNotes];
      releaseNotesMap = await loadReleaseNotes(jsonFile);
    } catch (e) {
      throw PublishError('$name 提交失败: $e');
    }

    // 1. 判断平台
    String type = file.path.endsWith('.ipa') ? 'ios' : 'osx';

    // 2. 获取配置
    PublishAppStoreConfig publishConfig =
        PublishAppStoreConfig.parse(environment);

    // 3. 上传 IPA
    ProcessResult processResult = await $(
      'xcrun',
      [
        'altool',
        '--upload-app',
        '--file',
        file.path,
        '--type',
        type,
        ...publishConfig.toAppStoreCliDistributeArgs(),
      ],
    );

    if (processResult.exitCode != 0) {
      throw PublishError(
        '${processResult.exitCode} - Upload of appstore failed: ${processResult.stderr}',
      );
    }
    processResult.toString();
    final stdoutText = processResult.stdout.toString();
    print('Appstore 上传IPA包成功: $stdoutText');

    // 5. 生成 App Store Connect API Token
    token = generateAppStoreToken(
      keyId: globalEnvironment[kKeyId], // 替换成你的 Key ID
      issuerId: globalEnvironment[kIssuerId], // 替换成你的 Issuer ID
      privateKey: globalEnvironment[kPrivateKey],
    );


    // 6. 获取环境变量中的版本号和更新日志
    String? version = globalEnvironment[kEnvVersionName];
    if (version == null || releaseNotesMap == null) {
      throw PublishError('缺少版本号或更新日志信息');
    }

    try {
      // 7. 创建新版本并更新 release notes
      await _createOrUpdateVersionWithLocales(
          globalEnvironment[kAppID], version, releaseNotesMap);

      return PublishResult(
        url: 'https://appstoreconnect.apple.com/apps',
      );
    } catch (e) {
      throw PublishError('Failed to publish app: $e');
    }
  }

  Future<Map<String, String>> loadReleaseNotes(String? jsonFile) async {
    if (jsonFile == null || jsonFile.isEmpty) {
      throw Exception("Release notes JSON file path is not set");
    }

    final file = File(jsonFile);

    if (!await file.exists()) {
      throw Exception("Release notes JSON file not found at: $jsonFile");
    }

    final content = await file.readAsString();
    final Map<String, dynamic> rawMap = jsonDecode(content);

    // 转成 Map<String, String>
    final Map<String, String> releaseNotesMap = rawMap.map((key, value) {
      return MapEntry(key, value.toString());
    });

    return releaseNotesMap;
  }

  /// 生成 JWT Token
  String generateAppStoreToken({
    required String keyId,
    required String issuerId,
    required String privateKey,
  }) {
    final currentTime = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final payload = {
      'iss': issuerId,
      'iat': currentTime,
      'exp': currentTime + (20 * 60),
      'aud': 'appstoreconnect-v1'
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

  /// 创建或更新 App Store 版本，并更新多语言 release notes
  Future<void> _createOrUpdateVersionWithLocales(
      String appId, String version, Map<String, String> whatsNewMap) async {
    // 1. 获取 App 的所有版本
    final versionsResp = await http.get(
      Uri.parse(
          'https://api.appstoreconnect.apple.com/v1/apps/$appId/appStoreVersions?fields[appStoreVersions]=versionString&limit=2'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (versionsResp.statusCode != 200) {
      throw Exception('Failed to list app versions: ${versionsResp.body}');
    }

    final data = jsonDecode(versionsResp.body)['data'] as List;
    String? versionId;

    // 2. 查找是否已存在指定版本号
    for (var ver in data) {
      if (ver['attributes']['versionString'] == version) {
        versionId = ver['id'];
        break;
      }
    }

    // 3. 如果不存在，则创建新版本
    if (versionId == null) {
      final createResp = await http.post(
        Uri.parse('https://api.appstoreconnect.apple.com/v1/appStoreVersions'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'data': {
            'type': 'appStoreVersions',
            'attributes': {
              'platform': 'IOS',
              'versionString': version,
              'releaseType': 'AFTER_APPROVAL',
            },
            'relationships': {
              'app': {
                'data': {'type': 'apps', 'id': appId}
              }
            }
          }
        }),
      );

      if (createResp.statusCode != 201) {
        throw Exception('Failed to create app version: ${createResp.body}');
      }

      versionId = jsonDecode(createResp.body)['data']['id'];
    }

    // 4. 获取已有版本的所有本地化
    final localizationsResp = await http.get(
      Uri.parse(
          'https://api.appstoreconnect.apple.com/v1/appStoreVersions/$versionId/appStoreVersionLocalizations?limit=50'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (localizationsResp.statusCode != 200) {
      throw Exception('Failed to get localizations: ${localizationsResp.body}');
    }

    final existingLocalizations =
        jsonDecode(localizationsResp.body)['data'] as List;

    // 5. 遍历传入的 whatsNewMap，更新或创建本地化
    for (var entry in whatsNewMap.entries) {
      final locale = entry.key;
      final whatsNew = entry.value;

      // 查找该语言是否已有 localization
      final existingLoc = existingLocalizations.firstWhere(
        (loc) => loc['attributes']['locale'] == locale,
        orElse: () => null,
      );

      if (existingLoc != null) {
        // 更新已有 localization
        final patchResp = await http.patch(
          Uri.parse(
              'https://api.appstoreconnect.apple.com/v1/appStoreVersionLocalizations/${existingLoc['id']}'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'data': {
              'type': 'appStoreVersionLocalizations',
              'id': existingLoc['id'],
              'attributes': {
                'whatsNew': whatsNew,
              }
            }
          }),
        );

        if (patchResp.statusCode == 200) {
          print('[$locale] Release notes updated successfully.');
        } else {
          print(
              '[$locale] Failed to update release notes: ${patchResp.statusCode} ${patchResp.body}');
        }
      } else {
        // 创建新的 localization
        final createLocResp = await http.post(
          Uri.parse(
              'https://api.appstoreconnect.apple.com/v1/appStoreVersionLocalizations'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'data': {
              'type': 'appStoreVersionLocalizations',
              'attributes': {
                'locale': locale,
                'whatsNew': whatsNew,
              },
              'relationships': {
                'appStoreVersion': {
                  'data': {'type': 'appStoreVersions', 'id': versionId}
                }
              }
            }
          }),
        );

        if (createLocResp.statusCode == 201) {
          print('[$locale] Release notes created successfully.');
        } else {
          print(
              '[$locale] Failed to create release notes: ${createLocResp.statusCode} ${createLocResp.body}');
        }
      }
    }
  }
}
