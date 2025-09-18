import 'dart:convert';
import 'dart:ffi';
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
      throw PublishError('缺少版本号、构建号或更新日志信息version = ${version} releaseNotesMap=${releaseNotesMap} expectedBuild=${expectedBuild}');
    }

    try {

      // final existingBuildId = await _findExistingBuild(
      //     globalEnvironment[kAppID], version, expectedBuild);

      String buildId;

      // 检查是否已有对应版本 + 构建号
      bool ipaBuildNumRepeat = await _findCurrentIpaBuildNumRepeat(version,expectedBuild);

      if (ipaBuildNumRepeat) {
        throw PublishError('⚠️ 版本 $version 已存在指定构建号 停止发布上传');
      } else {
        // 上传 IPA
        try {
          await _uploadIpa(file, type, publishConfig);
        } catch (e) {
          throw PublishError('上传ipa失败 ${e.toString()}');
        }
        // 等待 build 处理完成
        buildId = await _waitForBuildProcessed(version, expectedBuild);
      }

      // 创建或获取版本
      String versionId = await _createOrUpdateVersion(globalEnvironment[kAppID], version);

      // 更新多语言 release notes
      await _updateReleaseNotes(versionId, releaseNotesMap);

      // 关联构建到版本
      await _associateBuildToVersion(versionId, buildId);

      // 设置加密合规
      await setEncryptionCompliance(buildId);


      // 确保 review submission 存在并添加版本
      await ensureReviewSubmissionForVersion(
        appId: globalEnvironment[kAppID],
        appStoreVersionId: versionId,
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
      'exp': currentTime + (30 * 60),
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
  Future<String?> _findExistingBuild(
      String appId,
      String version,
      String expectedBuild,
      ) async {
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

  Future<void> _uploadIpa(
      File file, String type, PublishAppStoreConfig config) async {
    print('✅ 开始上传 IPA ${file.path}');
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

  Future<bool> _findCurrentIpaBuildNumRepeat(String version, String expectedBuild) async {
    final resp = await http.get(
      Uri.parse(
          'https://api.appstoreconnect.apple.com/v1/preReleaseVersions?filter[app]=${globalEnvironment[kAppID]}&filter[version]=$version'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = jsonDecode(resp.body)['data'] as List;
    if (data.isEmpty) {
      return false;
    }

    String preReleaseVersionId = data.first['id'];

    final respBuild = await http.get(
      Uri.parse(
          'https://api.appstoreconnect.apple.com/v1/builds?filter[preReleaseVersion]=$preReleaseVersionId'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final dataBuild = jsonDecode(respBuild.body)['data'] as List;
    if(dataBuild.isEmpty){
      return false;
    }
    for (var build in dataBuild) {
      final buildNumber = build['attributes']['version'];
      final state = build['attributes']['processingState'];
      print('Build state: $state, buildNumber: $buildNumber, expected: $expectedBuild');
      if (buildNumber == expectedBuild) {
        return true;
      }
    }
    return false;
  }

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
            // 'releaseType': 'AFTER_APPROVAL',//自动发布
            'releaseType': 'MANUAL'//手动发布
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

  Future<void> submitForReviewPhasedRelease({
    required String appStoreVersionId,
    bool phasedRelease = false,
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

    for (var s in submissions) {
      final submissionId = s['id'] as String?;
      final itemsUrl = Uri.https(
        'api.appstoreconnect.apple.com',
        '/v1/reviewSubmissions/$submissionId/items',
      );

      final itemsResp =
      await http.get(itemsUrl, headers: {'Authorization': 'Bearer $token'});
      if (itemsResp.statusCode != 200) {
        print(
            '⚠️ 获取 submission items 失败（id=$submissionId）: ${itemsResp.statusCode} ${itemsResp.body}');
        continue;
      }

      final itemsBody = jsonDecode(itemsResp.body);
      final List items = (itemsBody['data'] ?? []) as List;
      for (var item in items) {
        final rels = item['relationships'] ?? {};
        final appStoreVersionRel = rels['appStoreVersion'];
        final appStoreVersionData =
        appStoreVersionRel != null ? appStoreVersionRel['data'] : null;
        final versionId =
        appStoreVersionData != null ? appStoreVersionData['id'] : null;
        if (versionId == appStoreVersionId) {
          print(
              '✅ 找到已有 submission ($submissionId) 包含目标版本，itemId=${item['id']}');
          return {
            'submissionId': submissionId,
            'itemId': item['id'] as String?
          };
        }
      }
    }

    return {'submissionId': null, 'itemId': null};
  }

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
      final stateStr = (attrs['state'] ?? attrs['status'] ?? '') as String;
      final id = s['id'] as String?;
      if (stateStr.toUpperCase().contains('IN_PROGRESS') ||
          stateStr.toUpperCase().contains('DRAFT') ||
          stateStr.toUpperCase().contains('OPEN')) {
        print('⚠️ 发现 in-progress submission: $id state=$stateStr');
        return id;
      }
    }

    return null;
  }

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

  Future<bool> submitReviewSubmission(String submissionId) async {
    final url = Uri.https(
      'api.appstoreconnect.apple.com',
      '/v1/reviewSubmissions/$submissionId',
    );

    final body = {
      "data": {
        "type": "reviewSubmissions",
        "id": submissionId,
        "attributes": {
          "submitted": true
        }
      }
    };

    final resp = await http.patch(
      url,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (resp.statusCode == 200) {
      print('✅ Submission 已提交审核: $submissionId');
      return true;
    } else {
      print('⚠️ 提交 submission 失败: ${resp.statusCode} ${resp.body}');
      return false;
    }
  }

  /// 确保 Review Submission 存在，并添加 appStoreVersion 进去，同时提交审核
  /// 返回最终提交的 submissionId（如果成功）
  Future<String?> ensureReviewSubmissionForVersion({
    required String appId,
    required String appStoreVersionId,
    String platform = 'IOS',
  }) async {
    // 1️⃣ 检查目标版本是否已在某个 submission 中
    final found = await _findExistingSubmissionForVersion(
      appId: appId,
      appStoreVersionId: appStoreVersionId,
    );

    String? submissionId;

    if (found['submissionId'] != null && found['itemId'] != null) {
      submissionId = found['submissionId'];
      print('✅ 目标版本已在 submission 中 (submission=${found['submissionId']}, item=${found['itemId']})');
    } else {
      // 2️⃣ 尝试复用现有进行中的 submission
      String? inProgressSubmissionId = await _findInProgressSubmission(appId);
      if (inProgressSubmissionId != null) {
        submissionId = inProgressSubmissionId;
        print('ℹ️ 将目标版本加入现有进行中的 submission: $submissionId');
        await _createReviewSubmissionItem(
          submissionId: submissionId,
          appStoreVersionId: appStoreVersionId,
        );
      } else {
        // 3️⃣ 创建新的 submission
        submissionId = await _createReviewSubmission(appId: appId, platform: platform);
        if (submissionId == null) {
          print('❌ 无法创建或复用 submission，请手动处理。');
          return null;
        }
        await _createReviewSubmissionItem(
          submissionId: submissionId,
          appStoreVersionId: appStoreVersionId,
        );
        print('✅ reviewSubmissionItem 已创建');
      }
    }

    // 4️⃣ 提交审核
    final submitted = await submitReviewSubmission(submissionId!);
    if (submitted) {
      print('✅ 目标版本已成功提交 App 审核 (submissionId=$submissionId)');
      return submissionId;
    } else {
      print('⚠️ 提交审核失败，请手动检查 submissionId=$submissionId');
      return null;
    }
  }

}
