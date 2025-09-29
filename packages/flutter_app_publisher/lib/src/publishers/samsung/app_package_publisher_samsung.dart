import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:flutter_app_publisher/src/api/app_package_publisher.dart';
import 'package:flutter_app_publisher/src/publishers/util.dart';
import 'package:http/http.dart' as http;

const String serviceAccountId = "SAMSUNG_SACCOUNT_ID";
const String contentID = "SAMSUNG_CONTENT_ID";
const String privateKey = "SAMSUNG_PRIVITE_KEY";
const String baseUrl = "https://devapi.samsungapps.com";
const String tokenUrl = "$baseUrl/auth/accessToken";
const String sessionIDUrl = "$baseUrl/seller/createUploadSessionId";
const String appInfoUrl = "$baseUrl/seller/contentInfo";
const String addBinaryUrl = "$baseUrl/seller/v2/content/binary";
const String modifyBinaryUrl = "$baseUrl/seller/v2/content/binary";
const String updateUrl = "$baseUrl/seller/contentUpdate";
const String submitUrl = "$baseUrl/seller/contentSubmit";
const String createContentUrl = "$baseUrl/seller/contentCreate";



const kEnvPkgName = 'PKG_NAME';
const kEnvVersionCode = 'VERSION_CODE';
const kEnvVersionName = 'VERSION_NAME';
const kEnvAppName = 'APP_NAME';

///  doc [https://developer.samsung.com/galaxy-store/galaxy-store-developer-api.html]
class AppPackagePublisherSamsung extends AppPackagePublisher {
  @override
  String get name => 'samsung';
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
    try {
      globalEnvironment = environment ?? Platform.environment;

      /// Step 1 获取 token
      accessToken = await requestAccessToken();
      if ((accessToken ?? '').isEmpty) {
        throw PublishError('accessToken 为空');
      }

      /// Step 2 创建上传会话
      Map? map = await createUploadSessionId();
      uploadUrl = map?['url'];
      sessionId = map?['sessionId'];
      if ((uploadUrl ?? '').isEmpty || (sessionId ?? '').isEmpty) {
        throw PublishError('uploadUrl 或者 sessionId 为空');
      }

      /// Step 3 获取 App 信息
      Map<String, dynamic>? appInfo = await getAppInfo();
      if (appInfo == null) {
        throw PublishError('app信息 为空');
      }

      /// Step 4 上传 APK
      File file = fileSystemEntity as File;
      Map<String, dynamic>? uploadInfo = await uploadApp(
        globalEnvironment[kEnvPkgName]!,
        file,
        onPublishProgress,
      );
      if (uploadInfo == null) {
        throw PublishError('上传文件信息 为空');
      }

      /// Step 7 更新元数据
      Map<String, dynamic> params = {
        "contentId": appInfo["contentId"],
        "appTitle": appInfo["appTitle"],
        "defaultLanguageCode": appInfo["defaultLanguageCode"],
        "paid": appInfo["paid"],
        "publicationType": appInfo["publicationType"],
      };

      /// Step 5 构造 binary 参数
      await updateAppInfo(params);


      /// Step 6 构造 binary 参数
      Map<String, dynamic> binaryParam = {
        "gms": "N",
        "iapSdk": "N",
        "packageName": globalEnvironment[kEnvPkgName],
        "fileName": uploadInfo["fileName"],
        "versionCode": globalEnvironment[kEnvVersionCode],
        "versionName": globalEnvironment[kEnvVersionName],
        "filekey": uploadInfo["fileKey"],
      };

      /// Step 7 调用新增 / 修改二进制接口
      if ((appInfo["binaryList"] as List?)?.isEmpty ?? true) {
        await addBinary(appInfo["contentId"], binaryParam);
      } else {
        for (int i = 0; i < (appInfo["binaryList"].length ?? 0); i++) {
          Map<String, dynamic> binaryMap = appInfo["binaryList"][i];
          await deleteBinary(appInfo["contentId"], binaryMap['binarySeq']);
        }
        await addBinary(appInfo["contentId"], binaryParam);
        // await modifyBinary(appInfo["contentId"], binaryMap['binarySeq'],binaryParam,);
      }

      /// Step 8 提交审核
      await submit();

      return PublishResult(url: "${globalEnvironment[kEnvAppName]} $name 提交成功");
    } on Exception catch (e) {
      exit(1);
    }
  }


  /// 创建 App 内容
  Future<String> createContent() async {
    Map<String, String> header = getHeaderPrams();
    final resp = await http.post(Uri.parse(createContentUrl),
        headers: header,
        body: jsonEncode({
          "appTitle": globalEnvironment[kEnvAppName],
          "defaultLanguageCode": "en",
          "packageName": globalEnvironment[kEnvPkgName],
          "publicationType": "PAID",
          "paid": "N",
        }));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      return data["createdItem"]["contentId"];
    } else {
      throw Exception("创建 App 内容失败: ${resp.body}");
    }
  }

  /// ============ API 调用 ============

  Future<void> addBinary(String contentId, Map<String, dynamic> binaryParam) async {
    Map<String, dynamic> header = getHeaderPrams();
    binaryParam['contentId'] = contentId;
    binaryParam['gms'] = "N";
    Map<String, dynamic> params = binaryParam;
    Map? response = await PublishUtil.sendRequest(addBinaryUrl, params, header: header, isGet: false);
    if (response != null && response["errorCode"] != null) {
      throw PublishError("新增二进制失败: ${response["errorCode"]} ${response["errorMsg"]}");
    }
  }

  Future<void> deleteBinary(String contentId, String binarySeq) async {
    Map<String, dynamic> header = getHeaderPrams();
    Map<String, dynamic> params = {
      'contentId':contentId,
      'binarySeq':binarySeq,
    };
    Map? response = await PublishUtil.sendRequest(modifyBinaryUrl, params, header: header,isGet: false, isDelete: true,queryParams:params);
    if (response != null && response["errorCode"] != null) {
      throw PublishError("修改二进制失败: ${response["errorCode"]} ${response["errorMsg"]}");
    }
  }

  Future<void> modifyBinary(String contentId, String binarySeq,Map<String, dynamic> binaryParam) async {
    Map<String, dynamic> header = getHeaderPrams();
    Map<String, dynamic> params = {};
    binaryParam['contentId'] = contentId;
    binaryParam['binarySeq'] = binarySeq;
    binaryParam['gms'] = "N";
    params = binaryParam;
    Map? response = await PublishUtil.sendRequest(modifyBinaryUrl, params, header: header,isGet: false, isPut: true);
    if (response != null && response["errorCode"] != null) {
      throw PublishError("修改二进制失败: ${response["errorCode"]} ${response["errorMsg"]}");
    }
  }

  Future<void> submit() async {
    Map<String, dynamic> header = getHeaderPrams();
    Map<String, dynamic> params = {
      "contentId": globalEnvironment[contentID],
    };
    dynamic response = await PublishUtil.sendRequest(submitUrl, params, header: header, isGet: false);
    if (response != null && response["errorCode"] != null) {
      throw PublishError("${name} 更新失败: ${response["errorCode"]} ${response["errorMsg"]}");
    }
  }

  Future<void> updateAppInfo(Map<String, dynamic> params) async {
    Map<String, dynamic> header = getHeaderPrams();
    Map? response = await PublishUtil.sendRequest(updateUrl, params, header: header, isGet: false);
    if (response != null && response["errorCode"] != null) {
      throw PublishError("${name} 更新失败: ${response["errorCode"]} ${response["errorMsg"]}");
    }
  }

  Future<Map<String, dynamic>?> getAppInfo() async {
    Map<String, dynamic> header = getHeaderPrams();
    Map<String, dynamic> params = {
      "contentId": globalEnvironment[contentID],
    };
    dynamic response = await PublishUtil.sendRequest(appInfoUrl, params, header: header);
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
    var request = http.MultipartRequest('POST', Uri.parse(uploadUrl!));
    request.headers.addAll(getHeaderPrams());
    var fileStream = http.ByteStream(file.openRead());
    var length = await file.length();
    var multipartFile = http.MultipartFile('file', fileStream, length, filename: file.path.split("/").last);
    request.files.add(multipartFile);
    request.fields['sessionId'] = sessionId!;

    try {
      var response = await request.send();
      if (response.statusCode == 200) {
        var responseData = await response.stream.bytesToString();
        return jsonDecode(responseData);
      } else {
        print('Upload failed with status: ${response.statusCode}');
      }
    } catch (e) {
      print('Error during file upload: $e');
    }
    return null;
  }

  Future<Map?> createUploadSessionId() async {
    Map<String, dynamic> header = getHeaderPrams();
    Map<String, dynamic> params = {
      "contentId": globalEnvironment[contentID],
    };
    return await PublishUtil.sendRequest(sessionIDUrl, params, header: header, isGet: false);
  }

  Future<String?> requestAccessToken() async {
    try {
      final jwt = JWT({
        "iss": globalEnvironment[serviceAccountId],
        "iat": DateTime.now().millisecondsSinceEpoch ~/ 1000,
        "scopes": ["publishing", "gss"],
        "exp": DateTime.now().add(Duration(minutes: 5)).millisecondsSinceEpoch ~/ 1000,
      });
      final jwtToken = jwt.sign(RSAPrivateKey(globalEnvironment[privateKey]!), algorithm: JWTAlgorithm.RS256);

      final response = await http.post(
        Uri.parse(tokenUrl),
        headers: {
          "Authorization": "Bearer $jwtToken",
          "Content-Type": "application/json",
        },
      );
      if (response.statusCode == 200) {
        final responseBody = jsonDecode(response.body);
        return responseBody["createdItem"]?["accessToken"];
      } else {
        print("Error: ${response.statusCode} ${response.body}");
        return null;
      }
    } catch (e) {
      print("Exception: $e");
      return null;
    }
  }

  Map<String, String> getHeaderPrams() {
    return {
      "Authorization": "Bearer $accessToken",
      "Content-Type": "application/json",
      "service-account-id": globalEnvironment[serviceAccountId]!,
    };
  }
}
