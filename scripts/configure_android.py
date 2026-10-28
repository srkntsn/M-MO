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
