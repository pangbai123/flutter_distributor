import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:flutter_app_publisher/src/api/app_package_publisher.dart';
import 'package:flutter_app_publisher/src/publishers/mi/app_package_publisher_mi.dart';
import 'package:flutter_app_publisher/src/publishers/oppo/app_package_publisher_oppo.dart';
import 'package:flutter_app_publisher/src/publishers/util.dart';
import 'package:http/http.dart' as http;

const String serviceAccountId = "SAMSUNG_SACCOUNT_ID";
const String contentID = "SAMSUNG_CONTENT_ID";
const String privateKey = "SAMSUNG_PRIVITE_KEY";
const String baseUrl = "https://devapi.samsungapps.com";
const String tokenUrl = baseUrl + "/auth/accessToken";
const String sessionIDUrl = baseUrl + "/seller/createUploadSessionId";
const String appInfoUrl = baseUrl + "/seller/contentInfo";
const String updateUrl = baseUrl + "/seller/contentUpdate";
const String submitUrl = baseUrl + "/seller/contentSubmit";



const kEnvPkgName = 'PKG_NAME';

///  doc [https://developer.samsung.com/galaxy-store/galaxy-store-developer-api.html]
class AppPackagePublisherSamsung extends AppPackagePublisher {
  @override
  String get name => 'samsung';
  String? client;
  String? access;
  late Map<String, String> globalEnvironment;
  String? accessToken;
  String? uploadUrl;
  String? sessionId;

  @override
  Future<PublishResult> publish(
    FileSystemEntity fileSystemEntity, {
    Map<String, String>? environment,
    Map<String, dynamic>? publishArguments,
    PublishProgressCallback? onPublishProgress,
  }) async {
    globalEnvironment = environment ?? Platform.environment;
    accessToken = await requestAccessToken();
    if ((accessToken ?? '').isEmpty) {
      throw PublishError('accessToken 为空');
    }
    Map? map = await createUploadSessionId();
    uploadUrl = map?['url'];
    sessionId = map?['sessionId'];
    if ((uploadUrl ?? '').isEmpty || (sessionId ?? '').isEmpty) {
      throw PublishError('uploadUrl 或者 sessionId 为空');
    }
    Map<String, dynamic>? appInfo = await getAppInfo();
    if (appInfo == null) {
      throw PublishError('app信息 为空');
    }

    File file = fileSystemEntity as File;
    Map<String, dynamic>? uploadInfo = await uploadApp(
            globalEnvironment[kEnvPkgName]!, file, onPublishProgress)
        as Map<String, dynamic>;
    if (uploadInfo == null) {
      throw PublishError('上传文件信息 为空');
    }

    Map<String, dynamic> binaryParam;
    List<dynamic> list = appInfo?["binaryList"]??[];
    // if ((list?.length ?? 0) > 0) {
    //   binaryParam = Map.from(list![0]);
    //   binaryParam["binarySeq"] = list?.length.toString();
    // } else {
    //   list = [];
    //   binaryParam = {};
    //   binaryParam = {"binarySeq":"1","gms": "Y","iapSdk": "N","packageName":globalEnvironment[kEnvPkgName]};
    // }
    list = [];
    binaryParam = {};
    binaryParam = {"gms": "N","iapSdk": "N","packageName":globalEnvironment[kEnvPkgName]};
    binaryParam["fileName"] = uploadInfo["fileName"];
    binaryParam["versionCode"] = globalEnvironment[kEnvVersionCode];
    binaryParam["versionName"] = globalEnvironment[kEnvVersionName];
    binaryParam["filekey"] = uploadInfo["fileKey"];
    list.add(binaryParam);

    Map<String, dynamic> params = {
      "contentId": appInfo["contentId"],
      "appTitle": appInfo["appTitle"],
      "defaultLanguageCode": appInfo["defaultLanguageCode"],
      "paid": appInfo["paid"],
      "publicationType": appInfo["publicationType"],
      "binaryList": list,
    };
    await updateAppInfo(params);
    await submit();
    return PublishResult(url: globalEnvironment[kEnvAppName]! + name + '提交成功}');
  }

  submit() {
    Map<String, dynamic> header = getHeaderPrams();
    Map<String, dynamic> params = {
      "contentId": globalEnvironment[contentID],
    };
    dynamic response = PublishUtil.sendRequest(submitUrl, params,
        header: header, isGet: false);
    return response;
  }

  updateAppInfo(Map<String, dynamic> params) async {
    Map<String, dynamic> header = getHeaderPrams();
    Map? response = await PublishUtil.sendRequest(updateUrl, params,
        header: header, isGet: false);
    print("updateAppInfo======${response}========");
    return;
  }

  Future<Map<String, dynamic>?> getAppInfo() async {
    Map<String, dynamic> header = getHeaderPrams();
    Map<String, dynamic> params = {
      "contentId": globalEnvironment[contentID],
    };
    dynamic response =
        await PublishUtil.sendRequest(appInfoUrl, params, header: header);
    if ((response?.length ?? 0) > 0) {
      return response![0];
    }
    return null;
  }

  Future<Map<String, dynamic>?> uploadApp(
    String pkg,
    File file,
    PublishProgressCallback? onPublishProgress,
  ) async {
    // 构建上传的文件
    var request = http.MultipartRequest('POST', Uri.parse(uploadUrl!));

    // 设置请求头
    request.headers.addAll(getHeaderPrams());

    // 将文件添加到请求中
    var fileStream = http.ByteStream(file.openRead());
    var length = await file.length();
    var multipartFile =
        http.MultipartFile('file', fileStream, length, filename: "google.apk");
    request.files.add(multipartFile);
    request.fields['sessionId'] = sessionId!;
    if (onPublishProgress != null) {
      // 你可以在这里通过 ByteStream 和监听进度来实现进度回调
      // 例如你可以监听 `fileStream`，根据上传进度来触发回调
    }

    try {
      // 发送请求并等待响应
      var response = await request.send();
      if (response.statusCode == 200) {
        // 读取响应内容
        var responseData = await response.stream.bytesToString();
        Map<String, dynamic> responseMap = jsonDecode(responseData);
        return responseMap; // 或者根据返回格式解析返回的 JSON 数据
      } else {
        print('Upload failed with status: ${response.statusCode}');
      }
    } catch (e) {
      print('Error during file upload: $e');
    }

    return null;
  }

  String generateJWT() {
    final jwt = JWT(
      {
        "iss": globalEnvironment[serviceAccountId],
        "iat": DateTime.now().millisecondsSinceEpoch ~/ 1000,
        "scopes": ["publishing", "gss"],
        "exp":
            DateTime.now().add(Duration(minutes: 5)).millisecondsSinceEpoch ~/
                1000,
      },
    );
    final token = jwt.sign(
      RSAPrivateKey(globalEnvironment[privateKey]!),
      algorithm: JWTAlgorithm.RS256,
    );
    return token;
  }

  Future<Map?> createUploadSessionId() async {
    Map<String, dynamic> header = getHeaderPrams();
    Map<String, dynamic> params = {
      "contentId": globalEnvironment[contentID],
    };
    Map? response = await PublishUtil.sendRequest(sessionIDUrl, params,
        header: header, isGet: false);
    return response;
  }

  Map<String, String> getHeaderPrams() {
    return {
      "Authorization": "Bearer $accessToken",
      "Content-Type": "application/json",
      "service-account-id": globalEnvironment[serviceAccountId]!,
    };
  }

  Future<String?> requestAccessToken() async {
    try {
      final jwt = JWT(
        {
          "iss": globalEnvironment[serviceAccountId],
          "iat": DateTime.now().millisecondsSinceEpoch ~/ 1000,
          "scopes": ["publishing", "gss"],
          "exp":
              DateTime.now().add(Duration(minutes: 5)).millisecondsSinceEpoch ~/
                  1000,
        },
      );
      final jwtToken = jwt.sign(
        RSAPrivateKey(globalEnvironment[privateKey]!),
        algorithm: JWTAlgorithm.RS256,
      );
      final response = await http.post(
        Uri.parse(tokenUrl),
        headers: {
          "Authorization": "Bearer $jwtToken",
          "Content-Type": "application/json",
        },
      );
      if (response.statusCode == 200) {
        final responseBody = jsonDecode(response.body);
        String accessToken = responseBody["createdItem"]?["accessToken"];
        return accessToken;
      } else {
        print("Error: ${response.statusCode} ${response.body}");
        return null;
      }
    } catch (e) {
      print("Exception: $e");
      return null;
    }
  }
}
