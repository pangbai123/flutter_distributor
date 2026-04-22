import 'dart:convert';
import 'dart:io';

import 'package:flutter_app_publisher/src/api/app_package_publisher.dart';
import 'package:http/http.dart' as http;

const kEnv360Cookie = '360_COOKIE';
const kEnv360ApkName = '360_APK_NAME';
const kEnv360AppId = '360_APP_ID';
const kEnv360AppQId = '360_APP_QID';
const kEnv360AppKey = '360_APP_KEY';
const kEnvUpdateLog = 'UPDATE_LOG';
const kEnv360AppSubmitInfo = '360_APP_SUBMIT_INFO';



class AppPackagePublisher360 extends AppPackagePublisher {

  late String cookie;
  late String appId;
  late String appQId;
  late String appKey;
  late String updateLog;
  late String apkName;

  @override
  String get name => '360';

  late Map<String, String> globalEnvironment;


  @override
  Future<PublishResult> publish(
      FileSystemEntity fileSystemEntity, {
        Map<String, String>? environment,
        Map<String, dynamic>? publishArguments,
        PublishProgressCallback? onPublishProgress,
      }) async {

    try{
      globalEnvironment = environment ?? Platform.environment;

      cookie = globalEnvironment[kEnv360Cookie]??'';
      appId = globalEnvironment[kEnv360AppId]??'';
      appQId = globalEnvironment[kEnv360AppQId]??'';
      apkName = globalEnvironment[kEnv360ApkName]??'';
      appKey = globalEnvironment[kEnv360AppKey]??'';
      updateLog = globalEnvironment[kEnvUpdateLog]??'';


      final jsonFile = (environment ?? Platform.environment)[kEnv360AppSubmitInfo];
      Map<String,dynamic> releaseNotesMap = await loadReleaseNotes(jsonFile);

      File file = fileSystemEntity as File;
      print("开始上传APK...");
      Map<String,dynamic> data = await upload360Apk(file.path);
      print("上传APK完成");

      // Map<String,dynamic> data = {
      //   "label": "挖煤姬",
      //   "pname": "com.sig.wameiji",
      //   "version_code": 344,
      //   "ver_code": 344,
      //   "version_name": "2.0.71",
      //   "icon": "http:\/\/p16.qhimg.com\/t11a4d74fff5a9f9d9084373987.png",
      //   "rsa_md5s": "709166fb299244a55212d754a586b7a5",
      //   "file_url": "http:\/\/dev.360.cn\/show.php?key=ef742e04865e31410480cda4234e554d&suffix=apk&size=large",
      //   "apk_md5": "ef742e04865e31410480cda4234e554d",
      //   "file_size": "105404629",
      //   "apk_name": "app.apk",
      //   "sensitive_permission": [],
      //   "parsAppkey": null,
      //   "parserAppkey": null,
      //   "isAccessSdk": false,
      //   "sdkVer": null,
      //   "parseAppid": null,
      //   "isNeedAppid": null,
      //   "public_key": null,
      //   "sdkVerCode": null,
      //   "sdkType": null,
      //   "sdkCheckResult": null,
      //   "sdkcheckDesc": null,
      //   "score": 0,
      //   "qid": 3316623843,
      //   "appid": 204934991,
      //   "isProtect": 0,
      //   "protect_type": "OTHER",
      //   "unprotected": true,
      //   "is_top": false,
      //   "display_level": true,
      //   "must_protect": true,
      //   "_apk_token": "7db2b024b253777eb77205a2be5b935c",
      //   "sha256": false
      // };



    await submitVersion(data,releaseNotesMap);

      print("360 发布成功");
      return PublishResult(url: "360" + name + '提交成功}');
    }
    catch(e){
      return PublishResult(url: "360" + name + '提交失败: $e');
    }

  }



  Future<dynamic> upload360Apk(String apkPath) async {


    var uri = Uri.parse(
        "https://upload.dev.360.cn/mod/upload/apk/"
            "?apptype=soft"
            "&apkType=Mobilecase"
            "&appid=${appId}"
            "&qid=${appQId}"
            "&appkey=${appKey}"
            "&needContract=HTTP/1.1");

    var request = http.MultipartRequest("POST", uri);

    request.fields.addAll({
      "apptype": "soft",
      "apkType": "Mobilecase",
      "appid": appId,
      "qid": appQId,
      "appkey": appKey,
      "needContract": "HTTP/1.1",
    });

    request.headers.addAll({
      "cookie": cookie,
      "origin": "https://dev.360.cn",
      "referer": "https://dev.360.cn/",
      "user-agent":
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/146 Safari/537.36"
    });

    request.files.add(
      await http.MultipartFile.fromPath(
        "Filedata",
        apkPath,
        filename: apkName,
      ),
    );

    var response = await request.send();

    String body = await response.stream.bytesToString();


    var data = jsonDecode(body);

    if (data["status"] != 0) {
      throw Exception("上传失败");
    }
    return data["data"];
  }

  /// 提交版本
  Future submitVersion(
      Map<String,dynamic> upload,Map<String,dynamic> bodyData) async {


    var uri = Uri.parse(
        "https://dev.360.cn/mod3/createmobile/submitBaseInfo");


    // final Map<String, dynamic> bodyData = {
    //   "parserAppkey": "",
    //   "result": "",
    //   // "file_url": "http://dev.360.cn/show.php?key=ef742e04865e31410480cda4234e554d&suffix=apk&size=large",
    //   "file_key": "",
    //   // "file_size": "105404629",
    //   "sdk_version": "",
    //   // "pname": "com.sig.wameiji",
    //   // "version_code": "344",
    //   "permission": "",
    //   "sign_md5": "",
    //   // "apk_md5": "ef742e04865e31410480cda4234e554d",
    //   // "version_name": "2.0.71",
    //   "isAccessSdk": "false",
    //   "sdkVer": "",
    //   "sdkType": "",
    //   "sdkVerCode": "",
    //   "parseAppid": "",
    //   "isNeedAppid": "",
    //   "accordance": "0",
    //   "parsAppkey": "",
    //   "rsa_md5s": "709166fb299244a55212d754a586b7a5",
    //   "label": "挖煤姬",
    //   "icon": "http://p15.qhimg.com/t11a4d74fff5a9f9d9084373987.png",
    //   "apk_status": "1",
    //   "zhushouVersion": "",
    //   "public_key": "",
    //   "isProtect": "0",
    //   "apk_name": apkName,
    //   "_apk_token": "7db2b024b253777eb77205a2be5b935c",
    //   "sensitive_permission": "",
    //   "name_link": "-",
    //   "name": "挖煤姬",
    //   "appType": "soft",
    //   "is_devletter": "0",
    //   "name_ext": "",
    //   "cate_level1_id": "1",
    //   "tag1": "1131,12404",
    //   "tag2": "12404,12467",
    //   "devletter": "",
    //   "ag1": "0",
    //   "onewords": "日本直邮代购，自助日淘利器",
    //   "lang": "1",
    //   "is_free": "2",
    //   "brief": "【海量日本商品，足不出户逛日本】\n从动漫周边、模玩手办到掌机游戏、户外装备，新品中古超多商品任您挑选！\n\n【专业售后团队，海淘安心有保障】\n担心淘到问题商品？行业首创售后服务“售后安心宝”，拒绝错发漏发、假货瑕疵，平台兜底服务透明，让您的海淘之旅不再冒险！\n\n【无需外卡转运，支付宝一步搞定】\n还嫌海淘太麻烦？商品和日本官网实时同步，一键下单直邮到家。海淘真的很简单！\n\n【国际物流任选，各种商品放心运】\nEMS，航空，可追踪小航空，海运按需选择，更有独家包清关物流“竹蜻蜓专线”低至40元！\n\n【商品选择困难，前沿资讯买好物】\n提供时尚、生活、二次元等全方位的日本流行资讯，随时随地种草各类好物。",
    //   "edition_brief": "1、优化购物体验。\n2、修复已知问题。",
    //   "sensitive_permission_explain": "应用内更新服务需要",
    //   "sensitive_url": "https://app.meruki.cn/?n=Sig.Front.User.AppUser.PrivacyPolicyMC",
    //   "is_beian_same": "0",
    //   "beian_corp_name": "",
    //   "beian_id_code": "",
    //   "beian_number": "蜀ICP备2021014694号-10A",
    //   "beian_img": "http://p15.qhimg.com/t0156b315347bbe4222.png",
    //   "logo_name": "",
    //   "logo_key_512": "http://p19.qhimg.com/t11a4d74fff5e192ce05c14c1d1.png",
    //   "app_logo72_name_t": "512-挖煤姬.png",
    //   "app_logo72_key_t": "http://p17.qhimg.com/t11a4d74fff8ff2d8299ed1242b.png",
    //   "app_logo48_key_t": "http://p19.qhimg.com/bdm/48_48_/t11a4d74fff5e192ce05c14c1d1.png",
    //   "app_logo64_key_t": "http://p19.qhimg.com/bdm/64_64_/t11a4d74fff5e192ce05c14c1d1.png",
    //   "apk_desc": "测试账号：nervzztc@hotmail.com\n密码：123456",
    //   "is_smarter": "0",
    //   "timed_pub": "0",
    //   "timed_pub_hour": "00",
    //   "is_contr_vol": "n",
    //   "contr_level": "0",
    //   "contro_protocol": "on",
    //   "protocol": "1",
    //   "id": "204934991",
    //   "apptype": "soft",
    //   "common_tag": "",
    //   "common_other": "日淘",
    //   "feature_tag": "学生|不限|二次元,动漫|学校,碎片时间|不限制",
    //   "feature_other": "||||",
    //   "app_shot1_name":	"http://p16.qhimg.com/t11a4d74fffa5a78596f296a6ba.jpg",
    //   "app_shot1_key":	"http://p16.qhimg.com/t11a4d74fffa5a78596f296a6ba.jpg",
    //   "app_shot1_w":"113",
    //   "app_shot1_h":	"200",
    //   "app_shot2_name"	:"http://p16.qhimg.com/t11a4d74fff07c153549c079e6c.jpg",
    //   "app_shot2_key":	"http://p16.qhimg.com/t11a4d74fff07c153549c079e6c.jpg",
    //   "app_shot2_w":	"113",
    //   "app_shot2_h":	"200",
    //   "app_shot3_name":	"http://p15.qhimg.com/t11a4d74fff3a7ff841cae6c4d0.jpg",
    //   "app_shot3_key":	"http://p15.qhimg.com/t11a4d74fff3a7ff841cae6c4d0.jpg",
    //   "app_shot3_w":	"113",
    //   "app_shot3_h"	: "200",
    //   "app_shot4_name":	"http://p16.qhimg.com/t11a4d74fffd6d0e22969add341.jpg",
    //   "app_shot4_key":	"http://p16.qhimg.com/t11a4d74fffd6d0e22969add341.jpg",
    //   "app_shot4_w":	"113",
    //   "app_shot4_h":	"200",
    //   "app_shot5_name":	"http://p16.qhimg.com/t11a4d74fffef3dbed0255d3968.jpg",
    //   "app_shot5_key":	"http://p16.qhimg.com/t11a4d74fffef3dbed0255d3968.jpg",
    //   "app_shot5_w":	"113",
    //   "app_shot5_h":	"200"
    // };





    Map<String,dynamic> body = {
      "id": appId,
      "file_url": upload["file_url"],
      "apk_md5": upload["apk_md5"],
      "file_size":upload["file_size"],
      "_apk_token": upload["_apk_token"],
      "rsa_md5s": upload["rsa_md5s"],
      "icon": upload["icon"],
      "pname": upload["pname"],
      "version_code": upload["version_code"].toString(),
      "version_name": upload["version_name"],
      "isAccessSdk": upload["isAccessSdk"],
      "name": upload["label"],
      "label": upload["label"],
      "isProtect": upload["isProtect"],
      "apptype": "soft",
      "timed_pub_day": getTodayDate(),
      "start_time": getNowDateTime(),
      "end_time": getNowDateTime(),
      "edition_brief":updateLog,
      "apk_name": apkName,
    };

    bodyData.addAll(body);

    print("开始提交App ==== ${bodyData} ====");
    final fixedBody = bodyData.map((key, value) =>
        MapEntry(key, value.toString()));

    var res = await http.post(uri, headers: {
      "cookie": cookie,
      "origin": "https://dev.360.cn",
      "referer":
      "https://dev.360.cn/mod3/createmobile/baseinfo?id=$appId",
      "user-agent":
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/146 Safari/537.36",
      "content-type": "application/x-www-form-urlencoded"
    }, body: fixedBody);

    var data = jsonDecode(res.body);

    if (data["errno"] != "0") {
      throw Exception("提交失败 ${res.body}");
    }
  }

  String getTodayDate() {
    final now = DateTime.now();
    final year = now.year.toString();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }

  String getNowDateTime() {
    final now = DateTime.now();
    final year = now.year.toString();
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  Future<Map<String, dynamic>> loadReleaseNotes(String? jsonFile) async {
    if (jsonFile == null || jsonFile.isEmpty) {
      throw Exception("Release notes JSON file path is not set");
    }

    final file = File(jsonFile);

    if (!await file.exists()) {
      throw Exception("Release notes JSON file not found at: $jsonFile");
    }

    final content = await file.readAsString();
    final Map<String, dynamic> rawMap = jsonDecode(content);

    return rawMap;
  }
}


