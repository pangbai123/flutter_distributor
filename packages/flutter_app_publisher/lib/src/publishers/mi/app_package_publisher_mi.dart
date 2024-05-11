import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';
import 'package:encrypt/encrypt_io.dart';
import 'package:flutter_app_publisher/src/api/app_package_publisher.dart';
import 'package:flutter_app_publisher/src/publishers/oppo/app_package_publisher_oppo.dart';
import 'package:flutter_app_publisher/src/publishers/util.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/asymmetric/api.dart';

const kEnvMiAccount = 'MI_ACCOUNT';
const kEnvMiCer = 'MI_CER';
const kEnvMiPrivateKey = 'MI_PRIVATE_KEY';
const kEnvAppName = 'APP_NAME';
const kEnvPrivacyUrl = 'PRIVACY_URL';

///  doc [https://dev.mi.com/distribute/doc/details?pId=1134]
///  使用命令转换证书： openssl x509 -pubkey -noout -in dev.api.public.cer  > pubkey.pem
class AppPackagePublisherMi extends AppPackagePublisher {
  @override
  String get name => 'mi';

  late Map<String, String> globalEnvironment;

  @override
  Future<PublishResult> publish(
    FileSystemEntity fileSystemEntity, {
    Map<String, String>? environment,
    Map<String, dynamic>? publishArguments,
    PublishProgressCallback? onPublishProgress,
  }) async {
    globalEnvironment = environment ?? Platform.environment;
    File file = fileSystemEntity as File;
    Map uploadInfo = await uploadApp(
        globalEnvironment[kEnvPkgName]!, file, onPublishProgress);
    return PublishResult(
      url: 'mi提交成功：${jsonEncode(uploadInfo)}',
    );
  }

  ///上传文件
  Future<Map> uploadApp(
    String pkg,
    File file,
    PublishProgressCallback? onPublishProgress,
  ) async {
    var request = http.MultipartRequest('POST',
        Uri.parse('https://api.developer.xiaomi.com/devupload/dev/push'));
    var appInfo = <String, dynamic>{
      'appName': globalEnvironment[kEnvAppName],
      'packageName': globalEnvironment[kEnvPkgName],
      'updateDesc': globalEnvironment[kEnvUpdateLog],
      'privacyUrl': globalEnvironment[kEnvPrivacyUrl],
      'testAccount':
          jsonEncode({"zh_CN": "账号：nervzztc@hotmail.com\n密码：123456"}),
    };
    var RequestData = <String, dynamic>{
      'userName': globalEnvironment[kEnvMiAccount],
      'synchroType': 1,
      'appInfo': jsonEncode(appInfo),
    };
    request.fields['RequestData'] = jsonEncode(RequestData);

    request.files.add(await http.MultipartFile.fromPath('apk', file.path));

    var arr = {
      "sig": [
        {
          "name": "RequestData",
          "hash": md5
              .convert(utf8.encode(request.fields['RequestData']!))
              .toString()
              .toLowerCase()
        },
        {
          "name": "apk",
          "hash": md5.convert(file.readAsBytesSync()).toString().toLowerCase()
        },
      ],
      "password": globalEnvironment[kEnvMiPrivateKey]
    };
    final publicKey =
        parseKeyFromFileSync<RSAPublicKey>(globalEnvironment[kEnvMiCer]!);
    var sign = await encodeString(jsonEncode(arr), publicKey);
    request.fields['SIG'] = sign;
    // print(sign);
    // throw PublishError(sign);
    var response = await request.send();
    if (response.statusCode == 200) {
      String content = await response.stream.bytesToString();
      Map responseMap = jsonDecode(content);
      if (responseMap["result"] == 0) {
        return responseMap;
      } else {
        throw PublishError(content);
      }
    } else {
      // 处理错误的响应
      throw PublishError("请求失败：${response.statusCode}");
    }
  }

  // Rsa加密最大长度(密钥长度/8-11)
  int MAX_ENCRYPT_BLOCK = 117;

  //公钥分段加密
  Future encodeString(String content, RSAPublicKey publicKey) async {
    //创建加密器
    final encrypter = Encrypter(RSA(publicKey: publicKey));

    //分段加密
    // 原始字符串转成字节数组
    List<int> sourceBytes = utf8.encode(content);
    //数据长度
    int inputLength = sourceBytes.length;
    // 缓存数组
    List<int> cache = [];
    // 分段加密 步长为MAX_ENCRYPT_BLOCK
    for (int i = 0; i < inputLength; i += MAX_ENCRYPT_BLOCK) {
      //剩余长度
      int endLen = inputLength - i;
      List<int> item;
      if (endLen > MAX_ENCRYPT_BLOCK) {
        item = sourceBytes.sublist(i, i + MAX_ENCRYPT_BLOCK);
      } else {
        item = sourceBytes.sublist(i, i + endLen);
      }
      // 加密后对象转换成数组存放到缓存
      cache.addAll(encrypter.encryptBytes(item).bytes);
    }
    return PublishUtil.bytesToHex(cache);
  }
}
