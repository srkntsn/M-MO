from pathlib import Path
import os
import re
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

# model_viewer_plus serves bundled assets over loopback only. Keep all other
# cleartext destinations denied.
s = p.read_text().replace('<application', '<application android:networkSecurityConfig="@xml/network_security_config"', 1)
p.write_text(s)
xml = p.parent / 'res/xml'
xml.mkdir(parents=True, exist_ok=True)
(xml / 'network_security_config.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
  <base-config cleartextTrafficPermitted="false" />
  <domain-config cleartextTrafficPermitted="true">
    <domain>localhost</domain><domain>127.0.0.1</domain>
  </domain-config>
</network-security-config>''')

play = os.environ.get('MIMO_PLAY_BUILD') == '1'
if not play:
    s = p.read_text().replace('</manifest>', '    <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />\n</manifest>')
    provider = '''<provider android:name="androidx.core.content.FileProvider"
        android:authorities="${applicationId}.updates" android:exported="false" android:grantUriPermissions="true">
        <meta-data android:name="android.support.FILE_PROVIDER_PATHS" android:resource="@xml/update_paths" />
    </provider>'''
    p.write_text(s.replace('</application>', provider + '\n</application>'))
    (xml / 'update_paths.xml').write_text('''<?xml version="1.0" encoding="utf-8"?>
<paths><cache-path name="mimo_updates" path="mimo-updates/" /></paths>''')
activities = list(Path('android/app/src/main/kotlin').rglob('MainActivity.kt'))
assert len(activities) == 1
activity = activities[0]
package = re.search(r'^package\s+(\S+)', activity.read_text()).group(1)
template = Path('scripts/MainActivity.kt.in').read_text()
activity.write_text(template.replace('{{PACKAGE}}', package).replace('{{PLAY_BUILD}}', 'true' if play else 'false'))
gradle = Path('android/app/build.gradle.kts')
if gradle.exists():
    gradle.write_text(gradle.read_text().replace('minSdk = flutter.minSdkVersion', 'minSdk = 24'))

# flutter create adds a counter-app test for MyApp, which this application replaces.
generated_test = Path('test/widget_test.dart')
if generated_test.exists() and 'MyApp' in generated_test.read_text():
    generated_test.unlink()
