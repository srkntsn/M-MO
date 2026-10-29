from pathlib import Path
p = Path('android/app/src/main/AndroidManifest.xml')
s = p.read_text()
needle = '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
addition = '''<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.RECORD_AUDIO" />\n    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-feature android:name="android.hardware.camera" android:required="false" />
    <queries>
        <intent><action android:name="android.speech.RecognitionService" /></intent>
        <intent><action android:name="android.intent.action.TTS_SERVICE" /></intent>
    </queries>'''
assert needle in s
p.write_text(s.replace(needle, addition, 1))

# app_links handles invitations; disable Flutter's competing link handler.
s = p.read_text().replace('<application', '<application android:allowBackup="false"', 1)
marker = '</activity>'
link = '''<meta-data android:name="flutter_deeplinking_enabled" android:value="false" />
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="mimo" android:host="activate" />
            </intent-filter>
        </activity>'''
assert marker in s
p.write_text(s.replace(marker, link, 1))

# flutter create adds a counter-app test for MyApp, which this application replaces.
generated_test = Path('test/widget_test.dart')
if generated_test.exists() and 'MyApp' in generated_test.read_text():
    generated_test.unlink()
