import 'dart:convert';
import 'dart:io';

import 'package:flutter_app_publisher/src/api/app_package_publisher.dart';
import 'package:flutter_app_publisher/src/publishers/appstore/publish_appstore_config.dart';
import 'package:http/http.dart' as http;
import 'package:jose/jose.dart';
import 'package:shell_executor/shell_executor.dart';

const kEnvReleaseNotes = 'APPSTORE_NOTES_FILE';
const kAppID = "APPSTORE_APP_ID";
const kKeyId = "APPSTORE_APIKEY";
const kIssuerId = "APPSTORE_APIISSUER";
const kPrivateKey = "APPSTORE_PRIVATEKEY";
const kEnvVersionName = "IOS_VERSION_NAME";
const kEnvVersionCode = "IOS_VERSION_CODE";

//https://developer.apple.com/documentation/appstoreconnectapi

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

    // 加载 release notes
    final releaseNotesMap;
    try {
      final jsonFile = (environment ?? Platform.environment)[kEnvReleaseNotes];
      releaseNotesMap = await loadReleaseNotes(jsonFile);
    } catch (e) {
      throw PublishError('$name 提交失败: $e');
    }

    String type = file.path.endsWith('.ipa') ? 'ios' : 'osx';
    PublishAppStoreConfig publishConfig =
        PublishAppStoreConfig.parse(environment);

    // 生成 API Token
    token = generateAppStoreToken(
      keyId: globalEnvironment[kKeyId],
      issuerId: globalEnvironment[kIssuerId],
      privateKey: globalEnvironment[kPrivateKey],
    );

    String? version = globalEnvironment[kEnvVersionName];
    String? expectedBuild = globalEnvironment[kEnvVersionCode]?.toString();
    if (version == null || releaseNotesMap == null || expectedBuild == null) {
      throw PublishError('缺少版本号、构建号或更新日志信息');
    }

    try {
      // 检查是否已有对应版本 + 构建号
      final existingBuildId = await _findExistingBuild(
          globalEnvironment[kAppID], version, expectedBuild);

      String buildId;
      if (existingBuildId != null) {
        print('⚠️ 版本 $version 已存在指定构建号 $expectedBuild，跳过上传 IPA');
        buildId = existingBuildId;
      } else {
        // 上传 IPA
        try {
          await _uploadIpa(file, type, publishConfig);
        } catch (e) {
          if (e.toString().contains('already exists')) {
            print('⚠️ IPA 已存在，跳过上传');
          } else {
            rethrow;
          }
        }
        // 等待 build 处理完成
        buildId = await _waitForBuildProcessed(version, expectedBuild);
      }

      // 创建或获取版本
      String versionId =
          await _createOrUpdateVersion(globalEnvironment[kAppID], version);

      // // 更新多语言 release notes
      await _updateReleaseNotes(versionId, releaseNotesMap);
      //
      // // 关联构建到版本
      await _associateBuildToVersion(versionId, buildId);
      //
      // // 设置加密合规
      await setEncryptionCompliance(buildId);

      //设置分阶段发布
      await submitForReviewPhasedRelease(appStoreVersionId:versionId,phasedRelease:false);

      await ensureReviewSubmissionForVersion(
        appId: globalEnvironment[kAppID],
        appStoreVersionId: versionId, // 你 _createOrUpdateVersion 返回的 id
        platform: 'IOS',
      );


      return PublishResult(
        url: 'https://appstoreconnect.apple.com/apps',
      );
    } catch (e) {
      throw PublishError('Failed to publish app: $e');
    }
  }

  /// 加载本地的 release notes JSON 文件
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
    return rawMap.map((key, value) => MapEntry(key, value.toString()));
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

  /// 查找是否已有指定版本 + 构建号
  /// 查找已有版本和对应的构建号
  /// 如果找到与期望版本号和构建号匹配的构建，直接返回 buildId
  /// 否则返回 null（需要上传 IPA）
  /// 找到与指定 appId/version/expectedBuild 匹配且 processingState 为 VALID 的 buildId
  /// 返回 buildId 或 null
  Future<String?> _findExistingBuild(
      String appId,
      String version,
      String expectedBuild,
      ) async {
    // 1) 先获取 appStoreVersion id（匹配 versionString）
    final versionsResp = await http.get(
      Uri.parse(
          'https://api.appstoreconnect.apple.com/v1/apps/$appId/appStoreVersions?fields[appStoreVersions]=versionString&limit=50'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (versionsResp.statusCode != 200) {
      throw Exception('获取版本失败: ${versionsResp.body}');
    }

    final versionsData = jsonDecode(versionsResp.body)['data'] as List;
    String? versionId;
    for (var v in versionsData) {
      final vs = v['attributes']?['versionString']?.toString();
      if (vs == version) {
        versionId = v['id'] as String?;
        break;
      }
    }

    if (versionId == null) {
      print('⚠️ 未找到 appStoreVersion (versionString=$version)');
      return null;
    }

    print('ℹ️ 找到 appStoreVersion id=$versionId 对应 version=$version');

    // helper：检查一个 builds 列表里是否有匹配的 build
    String? _findInBuildsList(List builds) {
      for (var build in builds) {
        final attrs = build['attributes'] as Map<String, dynamic>? ?? {};
        final buildNumber = attrs['version']?.toString() ?? attrs['versionString']?.toString();
        final state = attrs['processingState']?.toString();
        print('Found build: id=${build['id']}, version=$buildNumber, state=$state');
        if (buildNumber == expectedBuild && state == 'VALID') {
          return build['id'] as String?;
        }
      }
      return null;
    }

    // 2) 优先：按 appStoreVersion 过滤 builds
    final buildsByVersionUrl = Uri.https('api.appstoreconnect.apple.com', '/v1/builds', {
      'filter[appStoreVersion]': versionId,
      'limit': '50',
    });
    final buildsByVersionResp = await http.get(buildsByVersionUrl, headers: {'Authorization': 'Bearer $token'});

    if (buildsByVersionResp.statusCode == 200) {
      final buildsData = jsonDecode(buildsByVersionResp.body)['data'] as List? ?? [];
      final found = _findInBuildsList(buildsData);
      if (found != null) return found;
      print('ℹ️ 按 appStoreVersion 筛选未找到匹配的 VALID build');
    } else {
      print('⚠️ 按 appStoreVersion 查询 builds 返回非200: ${buildsByVersionResp.statusCode} ${buildsByVersionResp.body}');
    }

    // 3) 备用：尝试按 preReleaseVersion 过滤（有时 build 被关联为 pre-release）
    final preResp = await http.get(
      Uri.parse('https://api.appstoreconnect.apple.com/v1/preReleaseVersions?filter[app]=$appId&filter[version]=$version'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (preResp.statusCode == 200) {
      final preData = jsonDecode(preResp.body)['data'] as List? ?? [];
      if (preData.isNotEmpty) {
        final preId = preData.first['id'];
        print('ℹ️ 找到 preReleaseVersion id=$preId，尝试按 preReleaseVersion 过滤 builds');
        final buildsByPreUrl = Uri.https('api.appstoreconnect.apple.com', '/v1/builds', {
          'filter[preReleaseVersion]': preId,
          'limit': '50',
        });
        final buildsByPreResp = await http.get(buildsByPreUrl, headers: {'Authorization': 'Bearer $token'});
        if (buildsByPreResp.statusCode == 200) {
          final buildsData = jsonDecode(buildsByPreResp.body)['data'] as List? ?? [];
          final found = _findInBuildsList(buildsData);
          if (found != null) return found;
          print('ℹ️ 按 preReleaseVersion 筛选也未找到匹配的 VALID build');
        } else {
          print('⚠️ 按 preReleaseVersion 查询 builds 返回非200: ${buildsByPreResp.statusCode} ${buildsByPreResp.body}');
        }
      } else {
        print('ℹ️ 未找到 preReleaseVersion');
      }
    } else {
      print('⚠️ 查询 preReleaseVersions 返回非200: ${preResp.statusCode} ${preResp.body}');
    }

    return null;
  }


  /// 上传 IPA
  Future<void> _uploadIpa(
      File file, String type, PublishAppStoreConfig config) async {
    // 这里用 xcrun altool 上传 IPA 的逻辑
    ProcessResult processResult = await $(
      'xcrun',
      [
        'altool',
        '--upload-app',
        '--file',
        file.path,
        '--type',
        type,
        ...config.toAppStoreCliDistributeArgs(),
      ],
    );
    if (processResult.exitCode != 0) throw Exception(processResult.stderr);
    print('✅ 上传 IPA 成功: ${file.path}');
  }

  /// 等待指定构建号的 build 处理完成
  Future<String> _waitForBuildProcessed(
      String version, String expectedBuild) async {
    String? preReleaseVersionId;
    while (preReleaseVersionId == null) {
      final resp = await http.get(
        Uri.parse(
            'https://api.appstoreconnect.apple.com/v1/preReleaseVersions?filter[app]=${globalEnvironment[kAppID]}&filter[version]=$version'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(resp.body)['data'] as List;
      if (data.isNotEmpty) {
        preReleaseVersionId = data.first['id'];
      } else {
        print('PreReleaseVersion not found yet, waiting...');
        await Future.delayed(const Duration(seconds: 30));
      }
    }

    while (true) {
      final resp = await http.get(
        Uri.parse(
            'https://api.appstoreconnect.apple.com/v1/builds?filter[preReleaseVersion]=$preReleaseVersionId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      final data = jsonDecode(resp.body)['data'] as List;
      if (data.isNotEmpty) {
        for (var build in data) {
          final buildNumber = build['attributes']['version'];
          final state = build['attributes']['processingState'];
          final buildId = build['id'];

          print('Build state: $state, buildNumber: $buildNumber, expected: $expectedBuild');

          if (buildNumber == expectedBuild && state == 'VALID') {
            print('✅ Build 已就绪并匹配构建号: $buildNumber');
            return buildId;
          }
        }
      } else {
        print('Build not found yet, waiting...');
      }
      await Future.delayed(const Duration(seconds: 30));
    }
  }

  /// 创建或获取 App Store 版本
  Future<String> _createOrUpdateVersion(String appId, String version) async {
    final versionsResp = await http.get(
      Uri.parse(
          'https://api.appstoreconnect.apple.com/v1/apps/$appId/appStoreVersions?fields[appStoreVersions]=versionString&limit=5'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (versionsResp.statusCode != 200)
      throw Exception('获取版本失败: ${versionsResp.body}');

    final data = jsonDecode(versionsResp.body)['data'] as List;
    for (var ver in data) {
      if (ver['attributes']['versionString'] == version) {
        print('✅ 版本已存在: $version');
        return ver['id'];
      }
    }

    final createResp = await http.post(
      Uri.parse('https://api.appstoreconnect.apple.com/v1/appStoreVersions'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json'
      },
      body: jsonEncode({
        'data': {
          'type': 'appStoreVersions',
          'attributes': {
            'platform': 'IOS',
            'versionString': version,
            'releaseType': 'AFTER_APPROVAL'
          },
          'relationships': {
            'app': {
              'data': {'type': 'apps', 'id': appId}
            }
          }
        }
      }),
    );
    if (createResp.statusCode != 201)
      throw Exception('创建版本失败: ${createResp.body}');

    final versionId = jsonDecode(createResp.body)['data']['id'];
    print('✅ 新版本创建成功: $version');
    return versionId;
  }

  /// 更新多语言 Release Notes
  Future<void> _updateReleaseNotes(
      String versionId, Map<String, String> whatsNewMap) async {
    final localizationsResp = await http.get(
      Uri.parse(
          'https://api.appstoreconnect.apple.com/v1/appStoreVersions/$versionId/appStoreVersionLocalizations?limit=50'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (localizationsResp.statusCode != 200)
      throw Exception('获取本地化失败: ${localizationsResp.body}');

    final existingLocalizations =
        jsonDecode(localizationsResp.body)['data'] as List;

    for (var entry in whatsNewMap.entries) {
      final locale = entry.key;
      final whatsNew = entry.value;

      final existingLoc = existingLocalizations.firstWhere(
        (loc) => loc['attributes']['locale'] == locale,
        orElse: () => null,
      );

      if (existingLoc != null) {
        final patchResp = await http.patch(
          Uri.parse(
              'https://api.appstoreconnect.apple.com/v1/appStoreVersionLocalizations/${existingLoc['id']}'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json'
          },
          body: jsonEncode({
            'data': {
              'type': 'appStoreVersionLocalizations',
              'id': existingLoc['id'],
              'attributes': {'whatsNew': whatsNew}
            }
          }),
        );
        print(
            '[$locale] ${patchResp.statusCode == 200 ? "✅" : "❌"} Release notes 更新成功');
      } else {
        final createLocResp = await http.post(
          Uri.parse(
              'https://api.appstoreconnect.apple.com/v1/appStoreVersionLocalizations'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json'
          },
          body: jsonEncode({
            'data': {
              'type': 'appStoreVersionLocalizations',
              'attributes': {'locale': locale, 'whatsNew': whatsNew},
              'relationships': {
                'appStoreVersion': {
                  'data': {'type': 'appStoreVersions', 'id': versionId}
                }
              }
            }
          }),
        );
        print(
            '[$locale] ${createLocResp.statusCode == 201 ? "✅" : "❌"} Release notes 创建成功');
      }
    }
  }

  /// 关联构建到版本
  Future<void> _associateBuildToVersion(
      String versionId, String buildId) async {
    final resp = await http.patch(
      Uri.parse(
          'https://api.appstoreconnect.apple.com/v1/appStoreVersions/$versionId'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json'
      },
      body: jsonEncode({
        'data': {
          'type': 'appStoreVersions',
          'id': versionId,
          'relationships': {
            'build': {
              'data': {'type': 'builds', 'id': buildId}
            }
          }
        }
      }),
    );
    if (resp.statusCode != 200) throw Exception('关联构建失败: ${resp.body}');
    print('✅ 构建已关联到版本');
  }

  /// 设置加密合规
  Future<void> setEncryptionCompliance(String buildId) async {
    final buildUrl =
        Uri.https('api.appstoreconnect.apple.com', '/v1/builds/$buildId');
    final resp = await http.get(buildUrl, headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json'
    });
    if (resp.statusCode != 200) throw Exception("获取构建信息失败: ${resp.body}");

    final currentValue = jsonDecode(resp.body)['data']?['attributes']
        ?['usesNonExemptEncryption'];
    if (currentValue == false) {
      print("⚠️ 加密合规已经设置为 false，跳过更新");
      return;
    }

    final patchResp = await http.patch(buildUrl,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json'
        },
        body: jsonEncode({
          "data": {
            "id": buildId,
            "type": "builds",
            "attributes": {"usesNonExemptEncryption": false}
          }
        }));
    if (patchResp.statusCode == 200) {
      print("✅ 已设置加密合规为 false");
    } else {
      throw Exception("设置加密合规失败: ${patchResp.body}");
    }
  }

  /// 阶段发布方式
  Future<void> submitForReviewPhasedRelease({
    required String appStoreVersionId,
    bool phasedRelease = false, // 是否开启阶段发布
  }) async {
    try {
      final url = Uri.https(
        'api.appstoreconnect.apple.com',
        '/v1/appStoreVersionPhasedReleases',
      );

      final body = {
        "data": {
          "type": "appStoreVersionPhasedReleases",
          "attributes": {"phasedReleaseState": "ACTIVE"},
          "relationships": {
            "appStoreVersion": {
              "data": {"type": "appStoreVersions", "id": appStoreVersionId}
            }
          }
        }
      };

      final resp = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

      if (resp.statusCode == 201) {
        print("✅ 已成功创建阶段发布");
      } else {
        print("⚠️ 创建阶段发布失败，但继续流程: ${resp.body}");
      }
    } catch (e) {
      print("⚠️ 创建阶段发布异常，跳过: $e");
    }
  }


  /// 确保 Review Submission 存在，并添加 appStoreVersion 进去


  /// 返回一个简单的 tuple（Map）表示匹配结果：
  /// {
  ///   'submissionId': '...',     // submission id (如果找到或创建)
  ///   'itemId': '...'            // 如果已存在 item 则返回 itemId，否则 null
  /// }
  Future<Map<String?, String?>> _findExistingSubmissionForVersion({
    required String appId,
    required String appStoreVersionId,
  }) async {
    final url = Uri.https(
      'api.appstoreconnect.apple.com',
      '/v1/apps/$appId/reviewSubmissions',
    );

    final resp =
        await http.get(url, headers: {'Authorization': 'Bearer $token'});
    if (resp.statusCode != 200) {
      print(
          '⚠️ 查询 app 的 reviewSubmissions 失败: ${resp.statusCode} ${resp.body}');
      return {'submissionId': null, 'itemId': null};
    }

    final body = jsonDecode(resp.body);
    final List submissions = (body['data'] ?? []) as List;

    // 遍历 submission，检查每个 submission 的 items 是否包含我们的版本
    for (var s in submissions) {
      final submissionId = s['id'] as String?;
      // 获取 items
      final itemsUrl = Uri.https(
        'api.appstoreconnect.apple.com',
        '/v1/reviewSubmissions/$submissionId/items',
      );

      final itemsResp =
          await http.get(itemsUrl, headers: {'Authorization': 'Bearer $token'});
      if (itemsResp.statusCode != 200) {
        // 继续检查下一个 submission（不要因为一个 items 请求失败就退出）
        print(
            '⚠️ 获取 submission items 失败（id=$submissionId）: ${itemsResp.statusCode} ${itemsResp.body}');
        continue;
      }

      final itemsBody = jsonDecode(itemsResp.body);
      final List items = (itemsBody['data'] ?? []) as List;
      for (var item in items) {
        // item 里通常会有 relationships.appStoreVersion.data.id（如果 item 是 appStoreVersion 类型）
        final rels = item['relationships'] ?? {};
        final appStoreVersionRel = rels['appStoreVersion'];
        final appStoreVersionData =
            appStoreVersionRel != null ? appStoreVersionRel['data'] : null;
        final versionId =
            appStoreVersionData != null ? appStoreVersionData['id'] : null;
        if (versionId == appStoreVersionId) {
          // 找到 submission 且包含目标版本
          print(
              '✅ 找到已有 submission ($submissionId) 包含目标版本，itemId=${item['id']}');
          return {
            'submissionId': submissionId,
            'itemId': item['id'] as String?
          };
        }
      }
    }

    // 没有直接包含目标版本的 submission
    return {'submissionId': null, 'itemId': null};
  }

  /// 如果存在 in-progress 的 submission（未完成），返回它的 id，否则返回 null
  Future<String?> _findInProgressSubmission(String appId) async {
    final url = Uri.https(
      'api.appstoreconnect.apple.com',
      '/v1/apps/$appId/reviewSubmissions',
    );

    final resp =
        await http.get(url, headers: {'Authorization': 'Bearer $token'});
    if (resp.statusCode != 200) {
      print(
          '⚠️ 查询 app 的 reviewSubmissions 失败: ${resp.statusCode} ${resp.body}');
      return null;
    }

    final body = jsonDecode(resp.body);
    final List submissions = (body['data'] ?? []) as List;

    for (var s in submissions) {
      final attrs = s['attributes'] ?? {};
      // 不同 API 版本可能用 'state' 或 'status' 或 'attributes.state' 表示
      final state =
          attrs['state'] ?? attrs['status'] ?? attrs['attributes'] ?? null;
      final id = s['id'] as String?;
      // 常见可接受的 state 字符串： "IN_PROGRESS", "DRAFT" 等（以实际返回为准）
      if (id != null) {
        final stateStr = (attrs['state'] ?? attrs['status'] ?? '') as String;
        if (stateStr.toUpperCase().contains('IN_PROGRESS') ||
            stateStr.toUpperCase().contains('DRAFT') ||
            stateStr.toUpperCase().contains('OPEN')) {
          print('⚠️ 发现 in-progress submission: $id state=$stateStr');
          return id;
        }
      }
    }

    return null;
  }

  /// 创建 reviewSubmission（返回 id 或 null）
  Future<String?> _createReviewSubmission({
    required String appId,
    String platform = 'IOS',
  }) async {
    final url =
        Uri.https('api.appstoreconnect.apple.com', '/v1/reviewSubmissions');

    final body = {
      "data": {
        "type": "reviewSubmissions",
        "attributes": {"platform": platform},
        "relationships": {
          "app": {
            "data": {"type": "apps", "id": appId}
          }
        }
      }
    };

    final resp = await http.post(url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body));

    if (resp.statusCode == 201) {
      final id = jsonDecode(resp.body)['data']['id'] as String?;
      print('✅ 创建 reviewSubmission 成功: $id');
      return id;
    } else {
      print('⚠️ 创建 reviewSubmission 失败: ${resp.statusCode} ${resp.body}');
      return null;
    }
  }

  /// 在指定 submission 下为某个 appStoreVersion 创建 item，返回 itemId 或 null
  Future<String?> _createReviewSubmissionItem({
    required String submissionId,
    required String appStoreVersionId,
  }) async {
    final url =
        Uri.https('api.appstoreconnect.apple.com', '/v1/reviewSubmissionItems');

    final body = {
      "data": {
        "type": "reviewSubmissionItems",
        "relationships": {
          "reviewSubmission": {
            "data": {"type": "reviewSubmissions", "id": submissionId}
          },
          "appStoreVersion": {
            "data": {"type": "appStoreVersions", "id": appStoreVersionId}
          }
        }
      }
    };

    final resp = await http.post(url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body));

    if (resp.statusCode == 201) {
      final itemId = jsonDecode(resp.body)['data']['id'] as String?;
      print('✅ 创建 reviewSubmissionItem 成功: $itemId');
      return itemId;
    } else {
      print('⚠️ 创建 reviewSubmissionItem 失败: ${resp.statusCode} ${resp.body}');
      return null;
    }
  }

  /// PATCH 把 item 提交（submitted=true），返回 true/false
  Future<bool> _submitReviewSubmissionItem(String itemId) async {
    final url = Uri.https(
        'api.appstoreconnect.apple.com', '/v1/reviewSubmissionItems/$itemId');

    final body = {
      "data": {
        "type": "reviewSubmissionItems",
        "id": itemId,
        "attributes": {"submitted": true}
      }
    };

    final resp = await http.patch(url,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body));

    if (resp.statusCode == 200) {
      print('✅ reviewSubmissionItem 已提交（submitted=true）: $itemId');
      return true;
    } else {
      print('⚠️ 提交 reviewSubmissionItem 失败: ${resp.statusCode} ${resp.body}');
      return false;
    }
  }

  /// 主入口：确保 appStoreVersion 被“添加以供审核”并提交该 item
  Future<void> ensureReviewSubmissionForVersion({
    required String appId,
    required String appStoreVersionId,
    String platform = 'IOS',
  }) async {
    // 1) 先查是否已有 submission 且已包含该版本
    final found = await _findExistingSubmissionForVersion(
      appId: appId,
      appStoreVersionId: appStoreVersionId,
    );

    if (found['submissionId'] != null && found['itemId'] != null) {
      final subId = found['submissionId']!;
      final itemId = found['itemId']!;
      print(
          '✅ 目标版本已在 submission 中 (submission=$subId, item=$itemId)。尝试确保已提交该 item...');
      // 检查 item 是否已 submitted（可选：这里直接尝试提交一次）
      final ok = await _submitReviewSubmissionItem(itemId);
      if (!ok) {
        print('⚠️ 尝试提交已存在 item 失败，请在 App Store Connect UI 检查该 submission。');
      }
      return;
    }

    // 2) 如果没有直接包含目标版本，则看是否有 in-progress submission 可以复用
    String? inProgressSubmissionId = await _findInProgressSubmission(appId);
    if (inProgressSubmissionId != null) {
      print('ℹ️ 将目标版本加入现有进行中的 submission: $inProgressSubmissionId');
      final itemId = await _createReviewSubmissionItem(
        submissionId: inProgressSubmissionId,
        appStoreVersionId: appStoreVersionId,
      );
      if (itemId != null) {
        await _submitReviewSubmissionItem(itemId);
      } else {
        print('⚠️ 在现有 submission 中添加 item 失败，请手动在 App Store Connect 中添加版本。');
      }
      return;
    }

    // 3) 没有 in-progress submission，尝试创建一个新的 submission
    final createdSubmissionId =
        await _createReviewSubmission(appId: appId, platform: platform);
    if (createdSubmissionId == null) {
      // 如果创建失败且返回了 409（比如有另一个 submission 正在进行中），尝试再查询一次并复用
      print('ℹ️ 创建新的 submission 失败，尝试再次查询并复用已存在的 in-progress submission...');
      inProgressSubmissionId = await _findInProgressSubmission(appId);
      if (inProgressSubmissionId != null) {
        final itemId = await _createReviewSubmissionItem(
            submissionId: inProgressSubmissionId,
            appStoreVersionId: appStoreVersionId);
        if (itemId != null)
          await _submitReviewSubmissionItem(itemId);
        else
          print('⚠️ 在复用的 submission 上创建 item 失败: $inProgressSubmissionId');
        return;
      }

      print('❌ 无法创建或复用 submission，请登录 App Store Connect UI 手动处理。');
      return;
    }

    // 4) 在新建的 submission 下创建 item 并提交
    final newItemId = await _createReviewSubmissionItem(
        submissionId: createdSubmissionId,
        appStoreVersionId: appStoreVersionId);
    if (newItemId == null) {
      print('❌ 在新 submission ($createdSubmissionId) 下创建 item 失败，请手动检查。');
      return;
    }

    final submitOk = await _submitReviewSubmissionItem(newItemId);
    if (!submitOk) {
      print('❌ 提交新创建的 item 失败，请手动在 App Store Connect 检查。');
    }
  }
}
