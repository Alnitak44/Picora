import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fluro/fluro.dart';

import 'package:picora/utils/common_functions.dart';
import 'package:picora/widgets/common_widgets.dart';
import 'package:picora/hero/hero_theme.dart';
import 'package:picora/picture_host_manage/manage_api/upyun_manage_api.dart';
import 'package:picora/router/application.dart';
import 'package:picora/router/routers.dart';

class UpyunLogIn extends StatefulWidget {
  const UpyunLogIn({super.key});

  @override
  UpyunLogInState createState() => UpyunLogInState();
}

class UpyunLogInState extends State<UpyunLogIn> {
  final _userNametext = TextEditingController();
  final _passwordcontroller = TextEditingController();
  bool loginStatus = false;
  bool _obscurePassword = true;
  final _formKey = GlobalKey<FormState>();

  @override
  initState() {
    super.initState();
    loginStatus = false;
  }

  _saveuserpasswd() async {
    try {
      var queryUpyunManage = await UpyunManageAPI().readUpyunManageConfig();
      if (queryUpyunManage != 'Error' && queryUpyunManage != '') {
        var jsonResult = jsonDecode(queryUpyunManage);
        if ((await UpyunManageAPI().checkToken(jsonResult['token']))[0] ==
            'success') {
          loginStatus = true;
          return showToast('登录成功');
        }
      }

      var getTokenResult = await UpyunManageAPI().getToken(
        _userNametext.text,
        _passwordcontroller.text,
      );
      if (getTokenResult[0] != 'success') {
        return showToast('登录失败');
      }
      String token = getTokenResult[1]['access_token'];
      String tokenName = getTokenResult[1]['name'];
      var saveResult = await UpyunManageAPI().saveUpyunManageConfig(
        _userNametext.text,
        _passwordcontroller.text,
        token,
        tokenName,
      );
      loginStatus = saveResult;
      return showToast(saveResult ? '登录成功' : '登录失败');
    } catch (e) {
      flogErr(
        e,
        {'userName': _userNametext.text, 'password': _passwordcontroller.text},
        'UpyunLogInState',
        '_saveuserpasswd',
      );
      return showToast('未知错误');
    }
  }

  bool _loggingIn = false;
  Future<void> _login() async {
    if (_loggingIn || !_formKey.currentState!.validate()) return;
    setState(() => _loggingIn = true);
    await _saveuserpasswd();
    if (!mounted) return;
    setState(() => _loggingIn = false);
    if (loginStatus) {
      await Application.router.navigateTo(
        context,
        Routes.upyunBucketList,
        replace: true,
        transition: TransitionType.cupertino,
      );
    }
  }

  @override
  void dispose() {
    _userNametext.dispose();
    _passwordcontroller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: getLeadingIcon(context),
      title: const Text('又拍云管理'),
    ),
    body: signUpPage(),
  );
  Widget signUpPage() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const PageHeading(
        eyebrow: 'PIC HERO / CLOUD',
        title: '连接管理空间',
        subtitle: '使用又拍云账号登录，管理存储桶与云端文件。',
      ),
      HeroPanel(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('账号与认证'),
              TextFormField(
                controller: _userNametext,
                enabled: !_loggingIn,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '用户名',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '请输入用户名' : null,
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _passwordcontroller,
                obscureText: _obscurePassword,
                enabled: !_loggingIn,
                onFieldSubmitted: (_) => _login(),
                decoration: InputDecoration(
                  labelText: '密码',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                validator: (v) => v == null || v.isEmpty ? '请输入密码' : null,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _loggingIn ? null : _login,
                  icon: _loggingIn
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login_rounded),
                  label: Text(_loggingIn ? '正在连接…' : '登录管理空间'),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}
