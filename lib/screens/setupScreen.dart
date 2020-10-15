import 'dart:async';
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:http/http.dart' as http;
import 'package:my_app/components/oauthHandler.dart';
import 'package:my_app/components/toastMessage.dart';
import 'package:my_app/models/cloudConfiguration.dart';
import 'package:my_app/services/ocfClient.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../appConstants.dart';

class SetupScreen extends StatefulWidget {
  @override
  _SetupState createState() => new _SetupState();
}

class _SetupState extends State<SetupScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _setupInProgress = false;
  bool _tryAuthInBackground = false;
  CloudConfiguration _cloudConfiguration;

  @override
  initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomPadding: false,
      body: Builder(
        builder: (context) => Stack(
          children: <Widget>[
            Container(
              alignment: Alignment.topCenter,
              color: Colors.white,
              child: Padding(
                padding: EdgeInsets.only(top: MediaQuery.of(context).size.height * 0.2),
                child: Image(
                  image: AssetImage('assets/logo.png'),
                  width: 220
                )
              )
            ),
            Container(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: EdgeInsets.only(bottom: 35, left: 20, right: 20),
                  child: _setupInProgress ? SpinKitDoubleBounce(color: AppConstants.blueMainColor) : FlatButton(
                    onPressed: () async => await _getCloudConfiguration(context, AppConstants.defautPlgdCloudEndpoint),
                    color: AppConstants.blueMainColor,
                    splashColor: AppConstants.yellowMainColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24.0),
                      side: BorderSide(color: AppConstants.blueMainColor)
                    ),
                    padding: const EdgeInsets.all(18.0),
                    child: RichText(
                      text: TextSpan(
                        children: <TextSpan>[
                          TextSpan(text: AppConstants.continueToPlgdCloudButtonPart1),
                          TextSpan(
                            text: AppConstants.continueToPlgdCloudButtonPart2, 
                            style: TextStyle(fontWeight: FontWeight.bold, color: AppConstants.yellowMainColor)
                          )
                        ],
                      ),
                    )
                  )
                )
              )
            ),
            Container(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: 15, left: 20, right: 20),
                child: _setupInProgress ? null : RichText(
                  text: TextSpan(
                    style: TextStyle(fontStyle: FontStyle.italic, fontSize: 10),
                    children: <TextSpan>[
                      TextSpan(
                        text: AppConstants.configureCustomEndpointButtonPart1,
                        style: TextStyle(color: AppConstants.blueMainColor, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () => _showCustomEndpointDialog()
                      ),
                      TextSpan(
                        text: AppConstants.configureCustomEndpointButtonPart2,
                        style: TextStyle(color: AppConstants.darkMainColor),
                      )
                    ],
                  ),
                )
              )
            ),
            Visibility(
              visible: false,
              maintainState: _tryAuthInBackground,
              child: OAuthHandler(
                authUrl: _cloudConfiguration?.accessTokenUrl,
                promptForCredentials: _showLoginModal,
                authCompleted: _onAuthCompleted
              )
            )
          ]
        )
      )
    );
  }

  Future _getCloudConfiguration(BuildContext context, Uri cloudEndpoint) async {
    setState(() {
      _setupInProgress = true;
    });

    String configurationResponse;
    try {
      var response = await http.get(cloudEndpoint).timeout(const Duration(seconds: 10));
      configurationResponse = response.body;
    } on TimeoutException catch (_) {
      ToastMessage.show(AppConstants.unableToFetchConfiguration);
      setState(() {
        _setupInProgress = false;
      });
      return;
    }

    if (!CloudConfiguration.isValid(configurationResponse)) {
      ToastMessage.show(AppConstants.unableToFetchConfiguration);
      setState(() {
        _setupInProgress = false;
      });
      return;
    }

    setState(() {
      _cloudConfiguration = CloudConfiguration.fromJson(configurationResponse);
      _tryAuthInBackground = true;
    });
  }

  Future _onAuthCompleted(String response) async {
    var storage = await SharedPreferences.getInstance();
    var configurationStored = await storage.setString(OCFClient.cloudConfigurationStorageKey, _cloudConfiguration.rawJson);
    if (!configurationStored) {
      ToastMessage.show(AppConstants.messageUnableToPersistConfiguration);
    }

    OCFClient.setTokenResponse(response);
    Navigator.of(context).pushNamedAndRemoveUntil('/devices', (route) => false);
  }

  void _showLoginModal() {
    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.95,
        child: Container(
          margin: const EdgeInsets.only(top: 5, left: 15, right: 15),
          child: Stack(
            alignment: AlignmentDirectional.topCenter,
            children: [
              Container(
                height: 3,
                width: 40,
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.all(Radius.circular(50))
                )
              ),
              Padding(
                padding: EdgeInsets.only(top: 7),
                child: OAuthHandler(
                  authUrl: _cloudConfiguration.accessTokenUrl,
                  authCompleted: _onAuthCompleted
                )
              )
            ]
          )
        )
      )
    ).whenComplete(() => 
      setState(() {
        _setupInProgress = false;
        _tryAuthInBackground = false;
      })
    );
  }

  Future _showCustomEndpointDialog() async {
  TextEditingController controller = TextEditingController();
    return await showDialog<String>(
      context: context,
      child: AlertDialog(
        contentPadding: const EdgeInsets.all(16.0),
        content: Form(
            key: _formKey,
            child: Row(
            children: <Widget>[
              Expanded(
                child: TextFormField(
                  validator: (url) {
                    Pattern pattern = r'[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)';
                    RegExp regex = RegExp(pattern);
                    if (!regex.hasMatch(url))
                      return AppConstants.invalidEndpoint;
                    else
                      return null;
                  },
                  controller: controller,
                  keyboardType: TextInputType.url,
                  autofocus: true,
                  decoration: InputDecoration(
                    suffixIcon: Icon(Icons.cloud, color: AppConstants.blueMainColor),
                    prefixText: 'https://',
                    hintText: 'plgd.cloud',
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: AppConstants.blueMainColor),
                    ) 
                  )
                )
              )
            ]
          )
        ),
        actions: <Widget>[
          FlatButton(
            child: Text(
              AppConstants.customEndpointButtonCancel,
              style: TextStyle(color: AppConstants.blueMainColor)
            ),
            onPressed: () {
              Navigator.pop(context);
            }
          ),
          FlatButton(
            child: Text(
              AppConstants.customEndpointButtonContinue,
              style: TextStyle(color: AppConstants.blueMainColor)
            ),
            onPressed: () {
              if (_formKey.currentState.validate()) {
                Navigator.pop(context);
                _getCloudConfiguration(context, Uri.parse('https://' + controller.text + AppConstants.cloudConfigurationPath));
              }
            }
          )
        ]
      )
    );
  }
}