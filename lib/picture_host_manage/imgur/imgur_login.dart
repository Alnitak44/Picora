import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:fluro/fluro.dart';

import 'package:picora/utils/common_functions.dart';
import 'package:picora/widgets/common_widgets.dart';
import 'package:picora/hero/hero_theme.dart';
import 'package:picora/picture_host_manage/manage_api/imgur_manage_api.dart';
import 'package:picora/router/application.dart';
import 'package:picora/router/routers.dart';

class ImgurLogIn extends StatefulWidget {
  const ImgurLogIn({super.key});

  @override
  ImgurLogInState createState() => ImgurLogInState();
}

class ImgurLogInState extends State<ImgurLogIn> {
  final _imgurUserController = TextEditingController();
  final _clientIDcontroller = TextEditingController();
  final _accessTokencontroller = TextEditingController();
  final _proxyController = TextEditingController();
  bool loginStatus = false;
  final _formKey = GlobalKey<FormState>();

  @override
  initState() {
    super.initState();
    loginStatus = false;
  }

  _saveuserpasswd() async {
    try {
      String proxy = 'None';
      if (_proxyController.text.isNotEmpty) {
        proxy = _proxyController.text;
      }

      var checkTokenResult = await ImgurManageAPI().checkToken(
        _imgurUserController.text,
        _accessTokencontroller.text,
        proxy,
      );
      if (checkTokenResult[0] == 'success') {
        var saveResult = await ImgurManageAPI().saveImgurManageConfig(
          _imgurUserController.text,
          _clientIDcontroller.text,
          _accessTokencontroller.text,
          proxy,
        );
        if (saveResult) {
          loginStatus = true;
          return showToast('保存成功');
        } else {
          return showToast('保存失败');
        }
      } else {
        return showToast('登录失败');
      }
    } catch (e) {
      flogErr(e, {}, 'ImgurLogInState', '_saveuserpasswd');
      return showToast('未知错误');
    }
  }

  bool _loggingIn = false, _hideToken = true;
  Future<void> _login() async {
    if (_loggingIn || !_formKey.currentState!.validate()) return;
    setState(() => _loggingIn = true);
    await _saveuserpasswd();
    if (!mounted) return;
    setState(() => _loggingIn = false);
    if (loginStatus) {
      final profile = {
        'imguruser': _imgurUserController.text,
        'clientid': _clientIDcontroller.text,
        'accesstoken': _accessTokencontroller.text,
        'proxy': _proxyController.text.isEmpty ? 'None' : _proxyController.text,
      };
      final route =
          '${Routes.imgurFileExplorer}?userProfile=${Uri.encodeComponent(jsonEncode(profile))}&albumInfo=${Uri.encodeComponent('{}')}&allImages=${Uri.encodeComponent('[]')}';
      await Application.router.navigateTo(
        context,
        route,
        replace: true,
        transition: TransitionType.cupertino,
      );
    }
  }

  @override
  void dispose() {
    _imgurUserController.dispose();
    _clientIDcontroller.dispose();
    _accessTokencontroller.dispose();
    _proxyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: getLeadingIcon(context),
      title: const Text('Imgur 管理'),
    ),
    body: signUpPage(),
  );
  Widget signUpPage() => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const PageHeading(
        eyebrow: 'PIC HERO / CLOUD',
        title: '连接 Imgur',
        subtitle: '通过账号与访问令牌管理相册和图片。',
      ),
      HeroPanel(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('认证信息'),
              buildInputField(
                controller: _imgurUserController,
                hintText: 'Imgur 用户名',
                icon: Icons.person_outline_rounded,
              ),
              const SizedBox(height: 18),
              buildInputField(
                controller: _clientIDcontroller,
                hintText: 'Client ID',
                icon: Icons.code_rounded,
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _accessTokencontroller,
                obscureText: _hideToken,
                enabled: !_loggingIn,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? '请输入访问令牌' : null,
                decoration: InputDecoration(
                  labelText: 'Access Token',
                  prefixIcon: const Icon(Icons.key_outlined),
                  suffixIcon: IconButton(
                    tooltip: _hideToken ? '显示令牌' : '隐藏令牌',
                    onPressed: () => setState(() => _hideToken = !_hideToken),
                    icon: Icon(
                      _hideToken
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              buildInputField(
                controller: _proxyController,
                hintText: '代理地址（可选）',
                icon: Icons.route_outlined,
                validator: (_) => null,
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
                  label: Text(_loggingIn ? '正在连接…' : '连接 Imgur'),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
  Widget buildInputField({
    required TextEditingController controller,
    required String hintText,
    required IconData icon,
    String? Function(String?)? validator,
  }) => TextFormField(
    controller: controller,
    enabled: !_loggingIn,
    textInputAction: TextInputAction.next,
    decoration: InputDecoration(labelText: hintText, prefixIcon: Icon(icon)),
    validator:
        validator ??
        (v) => v == null || v.trim().isEmpty ? '请填写$hintText' : null,
  );
}
