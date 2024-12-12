import 'dart:convert';
import 'dart:io';

import 'package:flutter_app_publisher/src/api/app_package_publisher.dart';
import 'package:flutter_app_publisher/src/publishers/mi/app_package_publisher_mi.dart';
import 'package:flutter_app_publisher/src/publishers/oppo/app_package_publisher_oppo.dart';
import 'package:googleapis/androidpublisher/v3.dart' as publisher;
import 'package:googleapis_auth/auth_io.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:http/http.dart' as http;

//https://developers.google.cn/android-publisher?authuser=0&hl=ca#publishing

class AppPackagePublisherGoogle  extends AppPackagePublisher {
  @override
  String get name => 'google';
  String? client;
  String? access;
  late Map<String, String> globalEnvironment;
  String? accessToken;
  String? uploadUrl;
  String? sessionId;

  String? packageName; // 应用包名
  String? serviceAccountJsonPath; // 服务账户的 JSON 文件路径
  publisher.AndroidPublisherApi? api;


  @override
  Future<PublishResult> publish(
      FileSystemEntity fileSystemEntity, {
        Map<String, String>? environment,
        Map<String, dynamic>? publishArguments,
        PublishProgressCallback? onPublishProgress,
      }) async {
    globalEnvironment = environment ?? Platform.environment;
    packageName = globalEnvironment[kEnvPkgName];
    serviceAccountJsonPath = globalEnvironment[kEnvPkgName];

    // 上传新的 APK 文件
    File apkFile = File('path_to_your_apk_file.apk');
    await uploadApk(apkFile);

    // 更新应用信息
    Map<String, dynamic> updateInfo = {
      'subscriptionId': 'your_subscription_id',
      // 可包含更多需要更新的信息，如标题、描述等
    };
    await updateAppInfo(updateInfo);
    // 提交应用
    await submitApp();

    return PublishResult(url: globalEnvironment[kEnvAppName]! + name + '提交成功}');
  }



  // 获取访问令牌
  Future<String> getAccessToken() async {
    // 加载服务账户 JSON
    final credentials = auth.ServiceAccountCredentials.fromJson(
        File(serviceAccountJsonPath!).readAsStringSync());

    final authClient = await clientViaServiceAccount(
        credentials, [publisher.AndroidPublisherApi.androidpublisherScope]);


    accessToken = authClient.credentials.accessToken.data;
    return accessToken!;
  }

  // 上传新的 APK 文件
  Future<void> uploadApk(File apkFile) async {
    // 获取 API 客户端
    await getAccessToken();

    final apiClient = http.Client();
    final uploader = publisher.AndroidPublisherApi(apiClient);

    // 创建一个新的编辑会话
    final edit = await uploader.edits.insert(
      publisher.AppEdit(),
      packageName!,
    );

    // 创建上传请求
    var request = http.MultipartRequest(
      'POST',
      Uri.parse(
        'https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/$packageName/edits/${edit.id}/apks',
      ),
    );

    // 设置请求头
    request.headers.addAll({
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/octet-stream',
    });

    // 添加 APK 文件
    var fileStream = http.ByteStream(apkFile.openRead());
    var length = await apkFile.length();
    var multipartFile = http.MultipartFile('file', fileStream, length,
        filename: "google.apk");
    request.files.add(multipartFile);

    try {
      var response = await request.send();
      if (response.statusCode == 200) {
        var responseData = await response.stream.bytesToString();
        var responseMap = jsonDecode(responseData);
        final apk = responseMap['apks'][0];
        print('APK uploaded with versionCode: ${apk["versionCode"]}');
      } else {
        print('Upload failed with status: ${response.statusCode}');
      }
    } catch (e) {
      print('Error during file upload: $e');
    }
  }

  // 更新应用信息
  Future<void> updateAppInfo(Map<String, dynamic> updateInfo) async {
    await getAccessToken();

    final apiClient = http.Client();
    final uploader = publisher.AndroidPublisherApi(apiClient);

    // 获取 Edit ID
    final edit = await uploader.edits.insert(
      publisher.AppEdit(),
      packageName!,
    );

    // // 更新应用标题、描述等信息
    // final updateResponse = await uploader.edits.commit(
    //   publisher.Subscription(),
    //   packageName,
    //   edit.id!,
    //   updateInfo['subscriptionId'],
    // );

    // 提交更改
    await uploader.edits.commit(packageName!, edit.id!);
    print('App info updated successfully');
  }

  // 提交应用
  Future<void> submitApp() async {
    await getAccessToken();

    final apiClient = http.Client();
    final uploader = publisher.AndroidPublisherApi(apiClient);

    // 获取 Edit ID
    final edit = await uploader.edits.insert(
      publisher.AppEdit(),
      packageName!,
    );

    // 提交应用
    await uploader.edits.commit(edit.id!, packageName!);
    print('App submitted successfully');
  }
}
