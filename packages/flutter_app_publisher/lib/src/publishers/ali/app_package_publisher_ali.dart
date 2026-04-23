import 'dart:convert';
import 'dart:io';

import 'package:flutter_app_publisher/src/api/app_package_publisher.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

const kEnvAliCookie = 'ALI_COOKIE';
const kEnvAliLicenseNo = 'ALI_LICENSE_NO';
const kEnvAliAppId = 'ALI_APP_ID';
const kEnvUpdateLog = 'UPDATE_LOG';

class AppPackagePublisherAli extends AppPackagePublisher {
  late String cookie;
  late String appId;
  late String cpType;
  late String appKey;
  late String updateLog;
  late String apkName;
  late String licenseNo;

  @override
  String get name => 'ali';

  late Map<String, String> globalEnvironment;

  @override
  Future<PublishResult> publish(
    FileSystemEntity fileSystemEntity, {
    Map<String, String>? environment,
    Map<String, dynamic>? publishArguments,
    PublishProgressCallback? onPublishProgress,
  }) async {
    try {
      globalEnvironment = environment ?? Platform.environment;
      //需要修改JWS_SESSION、__AOM_SESSION、isg、tfstk
      cookie = globalEnvironment[kEnvAliCookie] ??
          '''_USER_REFER=a93976b6-5628-4b18-a9b9-9bc3656aaf01+https%3A%2F%2Fopen.9game.cn%2F+null;
cna=tUjTHg2Y2gkCAXZy6HKGcx44;
_uab_collina=176334491321444168345944;
ctoken=q9geodQOCerCBCfwAz3Xopen-platform;
HAS_LOGIN_FIRST=;
xlly_s=1;
_ALARM_TYPE_KEY=200;
JWS_SESSION=e8b8e70ac28bfb418525d5072333838b77599825-___AT=c59b00ff5911f9b14aa5171b0c9c85fdeb801730;
__AOM_SESSION=be8635ce5f40819efd3ab3f303f1b7e2;
isg=BOfny4NeQhd_Ssk-8zGd7L_Sdh2xbLtOkNHphblUbXadqAZqwT4Pnr8rzqg2QJPG;
tfstk=g_oiZljwfW1Ww55eqsr6JduiWcYLflZbyjIYMoF28WPQ6SpsH2xEaj4tWxRsoXqsvVIY6CZm3bEDwQKJ2AM_foRJwtbrLMEzEsPVMPSULoemFLuCLAM_c96dgU3ECnftBtPa0jrU882z0OyZgWkUO-wV_-SwKvPQTR7a0NkF8-el7orqgvJ3hWP40PlqLp2bTS8oeiPo0DieaIV0-53I4D2gS7kHPiS0GgUaa4Nh0Qo3ISPrQWjV05MocEDqgIjY44GnmzlJmMZtE2rUI2vV85zo7feIi3ja_DDZb5nw9GFZfvu-DXJV0S0Ezz3rQBQ3K2ktxynyZi4s8fg7omdpVl3-emarbhf79zwmZluHTGcP4CQFzudPcJJxYZ_b7Jw3wRRgICPpQGPBKpbW5PyQBQnvKw7cNiSf-pvhzc4adRtF.;
''';

      appId = globalEnvironment[kEnvAliAppId] ?? '223862';
      cpType = "8";
      licenseNo = globalEnvironment[kEnvAliLicenseNo] ?? '91510108MA6632C60R';
      updateLog = globalEnvironment[kEnvUpdateLog] ?? '';

      Map<String, dynamic> appInfo = await getApkInfo();
      print("appinfo =========${appInfo}========");
      File file = fileSystemEntity as File;
      Map<String, dynamic> appUpLoadInfo =
          await uploadAliApk(appInfo, file.path);
      Map<String, dynamic> icpInfo = await queryAppIcpInfo(appUpLoadInfo);
      await submitAliAppFull(appUpLoadInfo, appInfo, icpInfo);
      print("阿里 发布成功");
      return PublishResult(url: "阿里" + name + '提交成功}');
    } catch (e) {
      return PublishResult(url: "阿里" + name + '提交失败: $e');
    }
  }

  Map<String,String> commonHeader(){
    return {
      "Content-Type": "application/x-www-form-urlencoded",
      "Accept": "application/json, text/javascript, */*",
      "Origin": "https://aliapp-open.9game.cn",
      "Referer":
      "https://aliapp-open.9game.cn/editapp?appId=${appId}&cptype=${cpType}",
      "User-Agent":
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36",
      "X-Requested-With": "XMLHttpRequest",
      "Cookie": cookie.replaceAll('\n', '').replaceAll(' ', ''),
    };
  }


  Future<Map<String, dynamic>> getApkInfo() async {
    final url = Uri.parse(
      "https://aliapp-open.9game.cn/package/apkinfo",
    );
    try {
      final response = await http.post(
        url,
        headers: commonHeader(),
        body: {
          "appId": appId,
          "cptype": cpType,
        },
      );

      // var responseData = {
      //   "data": {
      //     "packageDto": {
      //       "id": 234278,
      //       "appId": 223862,
      //       "name": "com.sig.wameiji",
      //       "versionCode": 327,
      //       "versionName": "2.0.64",
      //       "url": "20260312_2dcea94a2d46930ff9f5f6270aa0c0ee354600628.apk",
      //       "size": 74089156,
      //       "sizeMb": "70.66MB",
      //       "sign": "f53a2e0a00fe1a0e0dd350397b5f0af1",
      //       "md5": "002dad85322f267377e8c3d1fb225e9e",
      //       "sdkVersion": 27,
      //       "targetSdkVersion": 36,
      //       "isEnable": 1,
      //       "createTime": 1773321643967,
      //       "updateTime": 1773386459445,
      //       "cptype": 8,
      //       "auditStatus": 1,
      //       "croAuditMsg":
      //           "AuditMqResult(srcId\u003dDEVELOPER_f75365a1f14348a080b3a03e41e97eb2, code\u003d2000000, msg\u003dnull, result\u003d0, callbackData\u003d{\"appId\":223862,\"appName\":\"挖煤姬\",\"appType\":1,\"packageId\":234278}, type\u003d0, riskTypeList\u003dnull, riskTypeNameList\u003dnull, riskPointId\u003dnull, riskPointName\u003dnull, riskSource\u003dnull)",
      //       "permissionGroupDescDtoList":
      //           "[{\"permissionGroupKey\":\"STORAGE\",\"permissionGroup\":\"存储权限\",\"permissionKey\":[\"android.permission.WRITE_EXTERNAL_STORAGE\",\"android.permission.READ_EXTERNAL_STORAGE\"],\"permissionKeyCn\":[\"允许程序写入外部存储\",\"程序可以读取设备外部存储空间的文件\"],\"usage\":\"允许应用修改或删除存储卡上的照片、媒体内容和文件是方便用户在浏览商品图片时能够手动保存图片至相册\"},{\"permissionGroupKey\":\"PHONE\",\"permissionGroup\":\"电话权限\",\"permissionKey\":[\"android.permission.READ_PHONE_STATE\"],\"permissionKeyCn\":[\"允许程序访问电话状态\"],\"usage\":\"允许应用电话权限用于用户一键登录\"},{\"permissionGroupKey\":\"CAMERA\",\"permissionGroup\":\"摄像头权限\",\"permissionKey\":[\"android.permission.CAMERA\"],\"permissionKeyCn\":[\"允许程序访问摄像头进行拍照\"],\"usage\":\"允许应用拍摄照片和视频是方便用户与客服沟通时发送图片和视频消息。\"},{\"permissionGroupKey\":\"MICROPHONE\",\"permissionGroup\":\"麦克风权限\",\"permissionKey\":[\"android.permission.RECORD_AUDIO\"],\"permissionKeyCn\":[\"允许程序录制声音通过手机或耳机的麦克\"],\"usage\":\"允许应用录制音频是方便用户与客服沟通时发送语音消息。\"},{\"permissionGroupKey\":\"NOTIFICATIONS\",\"permissionGroup\":\"通知权限\",\"permissionKey\":[\"android.permission.POST_NOTIFICATIONS\"],\"permissionKeyCn\":[\"允许应用程序进行通知推送\"],\"usage\":\"允许应用通知是为了及时通知用户订单消息\"},{\"permissionGroupKey\":\"READ_MEDIA_VISUAL\",\"permissionGroup\":\"读取视觉媒体\",\"permissionKey\":[\"android.permission.READ_MEDIA_IMAGES\",\"android.permission.READ_MEDIA_VIDEO\"],\"permissionKeyCn\":[\"允许程序访问外部存储中的图片文件\",\"允许程序访问外部存储中的视频文件\"],\"usage\":\"允许应用读取存储卡上的照片、媒体内容和文件是方便用户与客服沟通时发送图片消息。\"}]",
      //       "permissionStatement":
      //           "1.存储权限:允许应用修改或删除存储卡上的照片、媒体内容和文件是方便用户在浏览商品图片时 能够手动保存图片至相册\n2.电话权限:允许应用电话权限用于用户一键登录\n3.摄像头权限:允许应用拍摄照片和视频是方便用户与客服沟通时发送图片和视频消息。\n4.麦克风权限:允许应用录制音频是方便用户与客服沟通时发送语音消息。\n5.通知权限:允许应用通知是为了及时通知用户订单消息\n6.读取视觉媒体:允许应用读取存储卡上的照片、媒体内容和文件是方便用户 与客服沟通时发送图片消息。",
      //       "isOnline": 1,
      //       "isPushed": 1,
      //       "specialType": 0,
      //       "isDemoPack": 0,
      //       "auditTime": 1773386433316,
      //       "auditComment": "",
      //       "submitTag": "1773321693260"
      //     }
      //   },
      //   "state": {"msg": "Ok", "code": 200}
      // };
      Map<String,dynamic> data = jsonDecode(response.body);
      if(data["state"]["code"] != 200){
        throw Exception("请求App信息失败：${data["state"]["msg"]}");
      }
      return data["data"]["packageDto"];
    } catch (e) {
      throw Exception("请求App信息失败：$e");
    }
  }

  Future<dynamic> uploadAliApk(
      Map<String, dynamic> appInfo, String apkPath) async {
    //开始上传
    var uri = Uri.parse("https://aliapp-open.9game.cn/upload/apk");

    var request = http.MultipartRequest("POST", uri);

    request.headers.addAll(commonHeader());

    request.fields.addAll({
      "uploadFileDto.fileType": "3",
      "appId": appId,
      "cptype": cpType,
    });

    /// 上传 APK
    request.files.add(
      await http.MultipartFile.fromPath(
        "file", // ✅ 抓包确认字段名
        apkPath,
        filename: apkPath.split("/").last,
        contentType: MediaType('application', 'vnd.android.package-archive'),
      ),
    );

    var response = await request.send();
    String body = await response.stream.bytesToString();

    var data = jsonDecode(body);

    print("uploadAliApk==========${data}===========");
    // var responseData = {
    // 	"data": {
    // 		"tmpPackageId": 1758521,
    // 		"applicationLabel": "挖煤姬",
    // 		"keywords": [
    // 			"煤炉",
    // 			"雅虎拍卖",
    // 			"二次元"],
    // 		"packageDto": {
    // 			"id": null,
    // 			"appId": 0,
    // 			"name": "com.sig.wameiji",
    // 			"versionCode": 345,
    // 			"versionName": "2.0.72",
    // 			"url": "20260422_44cc63fa43cfb5e2d559e4137207d7151610724009.apk",
    // 			"size": 105404629,
    // 			"sizeMb": "100.52MB",
    // 			"sign": "f53a2e0a00fe1a0e0dd350397b5f0af1",
    // 			"md5": "8979e020c14245bdbad73720daddb4a8",
    // 			"sdkVersion": 27,
    // 			"targetSdkVersion": 36,
    // 			"isEnable": 1,
    // 			"createTime": 1776846559210,
    // 			"updateTime": 1776846559210,
    // 			"createTimeStr": null,
    // 			"cptype": 8,
    // 			"cptypeName": null,
    // 			"auditStatus": -1,
    // 			"croAuditMsg": null,
    // 			"business_type": null,
    // 			"permissions": "94,69,6,8,82,140,89,163,164,40,34,106,135,134,173,60",
    // 			"permissionGroupDescDtoList": "[{\"permissionGroupKey\":\"STORAGE\",\"permissionGroup\":\"存储权限\",\"permissionKey\":[\"android.permission.WRITE_EXTERNAL_STORAGE\",\"android.permission.READ_EXTERNAL_STORAGE\"],\"permissionKeyCn\":[\"允许程序写入外部存储\",\"程序可以读取设备外部存储空间的文件\"],\"usage\":\"允许应用修改或删除存储卡上的照片、媒体内容和文件是方便用户在浏览商品图片时能够手动保存图片至相册\"},{\"permissionGroupKey\":\"PHONE\",\"permissionGroup\":\"电话权限\",\"permissionKey\":[\"android.permission.READ_PHONE_STATE\"],\"permissionKeyCn\":[\"允许程序访问电话状态\"],\"usage\":\"允许应用电话权限用于用户一键登录\"},{\"permissionGroupKey\":\"CAMERA\",\"permissionGroup\":\"摄像头权限\",\"permissionKey\":[\"android.permission.CAMERA\"],\"permissionKeyCn\":[\"允许程序访问摄像头进行拍照\"],\"usage\":\"允许应用拍摄照片和视频是方便用户与客服沟通时发送图片和视频消息。\"},{\"permissionGroupKey\":\"MICROPHONE\",\"permissionGroup\":\"麦克风权限\",\"permissionKey\":[\"android.permission.RECORD_AUDIO\"],\"permissionKeyCn\":[\"允许程序录制声音通过手机或耳机的麦克\"],\"usage\":\"允许应用录制音频是方便用户与客服沟通时发送语音消息。\"},{\"permissionGroupKey\":\"NOTIFICATIONS\",\"permissionGroup\":\"通知权限\",\"permissionKey\":[\"android.permission.POST_NOTIFICATIONS\"],\"permissionKeyCn\":[\"允许应用程序进行通知推送\"],\"usage\":\"允许应用通知是为了及时通知用户订单消息\"},{\"permissionGroupKey\":\"READ_MEDIA_VISUAL\",\"permissionGroup\":\"读取视觉媒体\",\"permissionKey\":[\"android.permission.READ_MEDIA_IMAGES\",\"android.permission.READ_MEDIA_VIDEO\"],\"permissionKeyCn\":[\"允许程序访问外部存储中的图片文件\",\"允许程序访问外部存储中的视频文件\"],\"usage\":\"允许应用读取存储卡上的照片、媒体内容和文件是方便用户与客服沟通时发送图片消息。\"}]",
    // 			"permissionStatement": null,
    // 			"isOnline": null,
    // 			"isPushed": null,
    // 			"specialType": null,
    // 			"isDemoPack": null,
    // 			"aliasName": null,
    // 			"channel": null,
    // 			"auditTime": null,
    // 			"auditComment": null,
    // 			"submitTag": null,
    // 			"inputMd5": null,
    // 			"sdkResolveStatus": null
    // 		},
    // 		"appType": 0,
    // 		"appDto": {
    // 			"id": 223862,
    // 			"developerId": 182075,
    // 			"categoryId": 5017,
    // 			"categoryId2": null,
    // 			"appName": "挖煤姬",
    // 			"appType": 1,
    // 			"appTypeCn": null,
    // 			"auditStatus": 1,
    // 			"platformId": 1,
    // 			"appNameEn": null,
    // 			"iconUrl": "https://aliapp-open.9game.cn/f/oth?fid=20251024_c2ecf29e931bc559fd14fa0c8611be831966171083.png",
    // 			"appDesc": "【海量日本商品，足不出户逛日本】\r\n从动漫周边、模玩手办到掌机、户外装备，新品中古超多商品任您挑选！\r\n\r\n【专业售后团队，海淘安心有保障】\r\n担心淘到问题商品？行业首创售后服务「售后安心宝」，拒绝错发漏发、假货瑕疵，平台兜底服务透明，让您的海淘之旅不再冒险！\r\n\r\n【无需外卡转运，支付宝一步搞定】\r\n还嫌海淘太麻烦？商品和日本官网实时同步，一键下单直邮到家。海淘真的很简单！\r\n\r\n【国际物流任选，各种商品放心运】\r\nEMS，航空，可追踪小航空，海运按需选择，更有独家包清关物流“竹蜻蜓专线”低至40元！\r\n\r\n【商品选择困难，前沿资讯买好物】\r\n提供时尚、生活、二次元等全方位的日本流行资讯，随时随地种草各类好物。",
    // 			"appChangelog": "1、修复已知问题。\r\n2、优化购物体验。",
    // 			"packageId": null,
    // 			"adStatus": 1,
    // 			"adStatusCn": null,
    // 			"supportLan": 1,
    // 			"chargeType": 1,
    // 			"chargeTypeCn": null,
    // 			"sentenceDesc": "日本直邮代购",
    // 			"sdkVersion": 27,
    // 			"createTime": 1627026711739,
    // 			"chgnameReason": null,
    // 			"chgnameReasonFile": null,
    // 			"chgnameReasonFileTmpId": null,
    // 			"resAppId": 8328579,
    // 			"belongPP": 1,
    // 			"privacyPolicyUrl": "https://app.meruki.cn/?n=Sig.Front.User.AppUser.PrivacyPolicyMC",
    // 			"serverIp": "",
    // 			"testAccount": "",
    // 			"singleGameType": 0,
    // 			"subjectType": null,
    // 			"licenseNo": null,
    // 			"appSubjectName": "成都西格塞维斯科技有限公司",
    // 			"icpStatus": null,
    // 			"icpNo": null,
    // 			"integrateSdk": null,
    // 			"riskSdkCheckStatus": 0,
    // 			"icpStatusDTO": null,
    // 			"updateTime": 1776845538942,
    // 			"tagId": 591,
    // 			"tagId2": null
    // 		},
    // 		"loadData": true,
    // 		"iconUrl": "https://aliapp-open.9game.cn/f/oth?fid=20260422_244c196afa59c18680746b7df02a08a41488513305.png",
    // 		"cptypeCode": 8,
    // 		"categoryId": 5017,
    // 		"snapUrlList": [
    // 			"https://aliapp-open.9game.cn/f/oth?fid=20260203_0cb0d89226a821bc2b0b398f55d903401209063470.jpg",
    // 			"https://aliapp-open.9game.cn/f/oth?fid=20250813_a745c5ac2c1c0725bf4b1fb96dc7e66c1852927992.jpg",
    // 			"https://aliapp-open.9game.cn/f/oth?fid=20250813_6ba90df5f4fe60d29802ea695532d8591286284179.jpg",
    // 			"https://aliapp-open.9game.cn/f/oth?fid=20250813_ec3011fff81f291657f485dc4f8d1bb22027318718.jpg",
    // 			"https://aliapp-open.9game.cn/f/oth?fid=20250813_678d0a09c48dc81e4627e249405d63091101955906.jpg"]
    // 	},
    // 	"state": {
    // 		"msg": "success",
    // 		"code": 200
    // 	}
    // };

    if (data["state"]["code"] != 200) {
      throw Exception("上传失败");
    }
    return data["data"];
  }

  Future<Map<String, dynamic>> queryAppIcpInfo(
      Map<String, dynamic> appUpLoadInfo) async {
    final uri = Uri.parse(
      "https://aliapp-open.9game.cn/queryAppIcpInfo",
    );

    final response = await http.post(
      uri,
      headers: commonHeader(),
      body: {
        "appName": appUpLoadInfo["applicationLabel"],
        "pkgName": appUpLoadInfo["packageDto"]["name"],
        "licenseNo": licenseNo,
      },
    );
    print("statusCode: ${response.statusCode}");
    print("body: ${response.body}");
    final data = jsonDecode(response.body);
    if (data["data"] == null) {
      throw Exception("查询阿里ICP失败");
    }

    // var responseData = {
    //   "data": {
    //     "cxtjlx": 102,
    //     "cxtj": "OTE1MTAxMDhNQTY2MzJDNjBS",
    //     "cxtj2": "Y29tLnNpZy53YW1laWpp",
    //     "wzmc": "挖煤姬",
    //     "ztbah": "蜀ICP备2021014694号",
    //     "wzbah": "蜀ICP备2021014694号-10A",
    //     "bazt": 0
    //   }};

    return data["data"];
  }

  Future submitAliAppFull(
    Map<String, dynamic>? appUpLoadInfo,
    Map<String, dynamic>? appInfo,
    Map<String, dynamic>? icpInfo,
  ) async {

    var uri = Uri.parse("https://aliapp-open.9game.cn/saveapp");

    var request = http.MultipartRequest("POST", uri);

    /// ===== headers =====
    request.headers.addAll(commonHeader());


    try{
      var bodyData = {

        /// ================= 基础字段 =================
        "iconFileUrl": "",
        "tmpPackageId": appUpLoadInfo?['tmpPackageId']??"",
        "tmpSnapshots": "",
        "tmpCertificates": "",
        "tmpECopyright": "",
        "tmpSafeReport": "",

        "planId": "",
        "planType": "",
        "checkRiskSdk": "1",

        "submitType": "submit",
        "authenticityToken": extractAT(cookie) ?? "",


        /// ================= appDto =================
        "appDto.id": appUpLoadInfo?["appDto"]?["id"]??"",
        "appDto.createTime": appUpLoadInfo?["appDto"]?["createTime"]??"",

        "appDto.riskSdkCheckStatus": appUpLoadInfo?["appDto"]?["riskSdkCheckStatus"]??"",
        "appDto.appName": appUpLoadInfo?["appDto"]?["appName"]??"",
        "appDto.appType": appUpLoadInfo?["appDto"]?["appType"]??"",
        "appDto.tagId": appUpLoadInfo?["appDto"]?["tagId"]??"",

        "categoryId": appUpLoadInfo?["categoryId"]??"",

        "appDto.sentenceDesc": appUpLoadInfo?["appDto"]?["sentenceDesc"]??"",
        "appDto.appDesc": appUpLoadInfo?["appDto"]?["appDesc"]??"",
        "appDto.appChangelog": updateLog,
        "appDto.privacyPolicyUrl": appUpLoadInfo?["appDto"]?["privacyPolicyUrl"]??"",

        "appDto.serverIp": appUpLoadInfo?["appDto"]?["serverIp"]??"",
        "appDto.testAccount": appUpLoadInfo?["appDto"]?["testAccount"]??"",

        "appDto.chargeType": appUpLoadInfo?["appDto"]?["chargeType"]??"",
        "radioChargeInput": "true",

        "appDto.adStatus": appUpLoadInfo?["appDto"]?["adStatus"]??"",
        "radioAdInput": "true",

        "appDto.supportLan": appUpLoadInfo?["appDto"]?["supportLan"]??"",
        "radioLanInput": "true",

        "appDto.singleGameType": appUpLoadInfo?["appDto"]?["singleGameType"]??"",
        "radioSingleGameInput": "true",

        "appDto.subjectType": "1",
        "radioSubjectTypeInput": "true",

        "appDto.licenseNo": licenseNo,
        "appDto.appSubjectName": appUpLoadInfo?["appDto"]?["appSubjectName"]??"",

        "appDto.icpStatus": "0",
        "radioIcpStatusInput": "true",
        "appDto.icpNo": icpInfo?["wzbah"]??"",


        /// ================= packageDto =================
        "packageDto.appId": appUpLoadInfo?["packageDto"]?["appId"]??"",
        "packageDto.id": appUpLoadInfo?["packageDto"]?["id"]??"",
        "packageDto.name": appUpLoadInfo?["packageDto"]?["name"]??"",
        "packageDto.versionCode": appUpLoadInfo?["packageDto"]?["versionCode"]??"",
        "packageDto.versionName": appUpLoadInfo?["packageDto"]?["versionName"]??"",
        "packageDto.url": appUpLoadInfo?["packageDto"]?["url"]??"",
        "packageDto.size": appUpLoadInfo?["packageDto"]?["size"]??"",
        "packageDto.sign": appUpLoadInfo?["packageDto"]?["sign"]??"",
        "packageDto.md5": appUpLoadInfo?["packageDto"]?["md5"]??"",
        "packageDto.sdkVersion": appUpLoadInfo?["packageDto"]?["sdkVersion"]??"",
        "packageDto.targetSdkVersion": appUpLoadInfo?["packageDto"]?["targetSdkVersion"]??"",
        "packageDto.cptype": appUpLoadInfo?["packageDto"]?["cptype"]??"",
        "packageDto.auditStatus": appUpLoadInfo?["packageDto"]?["auditStatus"]??"",
        "packageDto.isEnable": appUpLoadInfo?["packageDto"]?["isEnable"]??"",
        "packageDto.createTime": appUpLoadInfo?["packageDto"]?["createTime"]??"",
        "packageDto.updateTime": appUpLoadInfo?["packageDto"]?["updateTime"]??"",
        "packageDto.permissions": appUpLoadInfo?["packageDto"]?["permissions"]??"",

        "packageDto.permissionStatement":
        appInfo?["packageDto"]?["permissionStatement"]??"",
        "packageDto.inputMd5":
        appUpLoadInfo?["packageDto"]?["inputMd5"]??"",


        /// ================= 权限 JSON =================
        "packageDto.permissionGroupDescDtoList": appInfo?["permissionGroupDescDtoList"]??"",

        /// ================= SDK / JSON =================
        "appSdkCommitmentJson": jsonEncode({
          "type": 0,
          "isSign": 0,
          "sdkInfoList": []
        }),


        /// ================= 文件占位 =================
        "file": "",
        "iconErrorInput": "1",

        "files1": "",
        "files2": "",
        "files3": "",
        "files4": "",
        "files5": "",
        "shotErrorInput": "5",

        "files": "",
        "electronicErrorInput": "1",

        "files": "",
        "copyrightErrorInput": "4",

        "files": "",
        "safeReportErrorInput": "1",
      };

      final fixedBody = bodyData.map(
            (key, value) => MapEntry(key, value?.toString() ?? ""),
      );

      request.fields.addAll(fixedBody);

      /// ================= keywords（重复key） =================
      final keywords = appUpLoadInfo?["keywords"];
      if (keywords is List) {
        request.fields.addEntries(
          keywords.map<MapEntry<String, String>>(
                (e) => MapEntry("keywords", e.toString()),
          ),
        );
      }

      /// ================= 权限拆分字段 =================
      request.fields.addAll(
        buildPermissionMap(
          appInfo?["appUpLoadInfo"]?["permissionGroupDescDtoList"],
        ),
      );
    }
    catch(e){
      print("========提交阿里参数出错=====${e}");
    }

    /// 发送请求
    var response = await request.send();
    var body = await response.stream.bytesToString();

    // print("status: ${response.statusCode}");
    // print("body: $body");


    // iconFileUrl
    // tmpPackageId			1758679
    // tmpSnapshots
    // tmpCertificates
    // tmpECopyright
    // tmpSafeReport
    // appDto.id			223862
    // appDto.createTime			1627026711739
    // packageDto.appId			0
    // packageDto.id
    // packageDto.name			com.sig.wameiji
    // packageDto.versionCode			345
    // packageDto.versionName			2.0.72
    // packageDto.url			20260423_91de185ec250b8fb7ce219461f7654f1678596591.apk
    // packageDto.size			105404629
    // packageDto.sign			f53a2e0a00fe1a0e0dd350397b5f0af1
    // packageDto.md5			8979e020c14245bdbad73720daddb4a8
    // packageDto.sdkVersion			27
    // packageDto.targetSdkVersion			36
    // packageDto.cptype			8
    // packageDto.auditStatus			-1
    // packageDto.isEnable			1
    // packageDto.createTime			1776910650379
    // packageDto.updateTime			1776910650379
    // packageDto.permissions			94,69,6,8,82,140,89,163,164,40,34,106,135,134,173,60
    // packageDto.permissionGroupDescDtoList			1.88 KB (1,923 bytes)
    // planId
    // planType
    // checkRiskSdk			1
    // appDto.riskSdkCheckStatus			0
    // appDto.appName			挖煤姬
    // appDto.appType			1
    // categoryId			5017
    // appDto.tagId			591
    // keywords			煤炉
    // keywords			雅虎拍卖
    // keywords			二次元
    // appDto.sentenceDesc			日本直邮代购
    // appDto.appDesc			【海量日本商品，足不出户逛日本】
    // 从动漫周边、模玩手办到掌机、户外装备，新品中古超多商品任您挑选！
    //
    // 【专业售后团队，海淘安心有保障】
    // 担心淘到问题商品？行业首创售后服务「售后安心宝」，拒绝错发漏发、假货瑕疵，平台兜底服务透明，让您的海淘之旅不再冒险！
    //
    // 【无需外卡转运，支付宝一步搞定】
    // 还嫌海淘太麻烦？商品和日本官网实时同步，一键下单直邮到家。海淘真的很简单！
    //
    // 【国际物流任选，各种商品放心运】
    // EMS，航空，可追踪小航空，海运按需选择，更有独家包清关物流“竹蜻蜓专线”低至40元！
    //
    // 【商品选择困难，前沿资讯买好物】
    // 提供时尚、生活、二次元等全方位的日本流行资讯，随时随地种草各类好物。
    // appDto.appChangelog			1、修复已知问题。
    // 2、优化购物体验。
    // appDto.privacyPolicyUrl			https://app.meruki.cn/?n=Sig.Front.User.AppUser.PrivacyPolicyMC
    // packageDto.permissionStatement			1.存储权限:允许应用修改或删除存储卡上的照片、媒体内容和文件是方便用户在浏览商品图片时能够手动保存图片至相册
    // 2.电话权限:允许应用电话权限用于用户一键登录
    // 3.摄像头权限:允许应用拍摄照片和视频是方便用户与客服沟通时发送图片和视频消息。
    // 4.麦克风权限:允许应用录制音频是方便用户与客服沟通时发送语音消息。
    // 5.通知权限:允许应用通知是为了及时通知用户订单消息
    // 6.读取视觉媒体:允许应用读取存储卡上的照片、媒体内容和文件是方便用户与客服沟通时发送图片消息。
    // permissionGroupDescDto.STORAGE			允许应用修改或删除存储卡上的照片、媒体内容和文件是方便用户在浏览商品图片时能够手动保存图片至相册
    // permissionGroupDescDto.PHONE			允许应用电话权限用于用户一键登录
    // permissionGroupDescDto.CAMERA			允许应用拍摄照片和视频是方便用户与客服沟通时发送图片和视频消息。
    // permissionGroupDescDto.MICROPHONE			允许应用录制音频是方便用户与客服沟通时发送语音消息。
    // permissionGroupDescDto.NOTIFICATIONS			允许应用通知是为了及时通知用户订单消息
    // permissionGroupDescDto.READ_MEDIA_VISUAL			允许应用读取存储卡上的照片、媒体内容和文件是方便用户与客服沟通时发送图片消息。
    // packageDto.inputMd5
    // appDto.serverIp
    // appDto.testAccount
    // appDto.chargeType			1
    // radioChargeInput			true
    // appDto.adStatus			1
    // radioAdInput			true
    // appDto.supportLan			1
    // radioLanInput			true
    // appDto.singleGameType			0
    // radioSingleGameInput			true
    // appDto.subjectType			1
    // radioSubjectTypeInput			true
    // appDto.licenseNo			91510108MA6632C60R
    // appDto.appSubjectName			成都西格塞维斯科技有限公司
    // appDto.icpStatus			0
    // radioIcpStatusInput			true
    // appDto.icpNo			蜀ICP备2021014694号-10A
    // appSdkCommitmentJson			{"type":0,"isSign":0,"sdkInfoList":[]}
    // file
    // iconErrorInput			1
    // files1
    // files2
    // files3
    // files4
    // files5
    // shotErrorInput			5
    // files
    // electronicErrorInput			1
    // files
    // copyrightErrorInput			4
    // files
    // safeReportErrorInput			1
    // submitType			submit
    // authenticityToken			c59b00ff5911f9b14aa5171b0c9c85fdeb801730

    if (response.statusCode != 200) {
      throw Exception("提交失败=======response.statusCode======= ${response.statusCode}=======body======= ${body}");
    }

    return body;
  }

  String? extractAT(String cookie) {
    final reg = RegExp(r'___AT=([^;]+)');
    final match = reg.firstMatch(cookie);
    return match?.group(1);
  }

  Map<String, String> buildPermissionMap(dynamic data) {
    Map<String, String> result = {};

    if (data == null) return result;

    List list;

    /// 1. 如果是字符串 → decode
    if (data is String) {
      try {
        list = jsonDecode(data);
      } catch (e) {
        print("permissionGroupDescDtoList jsonDecode失败: $e");
        return result;
      }
    }
    /// 2. 如果已经是 List → 直接用
    else if (data is List) {
      list = data;
    }
    /// 3. 其它类型直接返回
    else {
      return result;
    }

    /// 解析
    for (var item in list) {
      if (item is Map) {
        final key = item['permissionGroupKey']?.toString();
        final usage = item['usage']?.toString();

        if (key != null && key.isNotEmpty) {
          result['permissionGroupDescDto.$key'] = usage ?? "";
        }
      }
    }

    return result;
  }
}
