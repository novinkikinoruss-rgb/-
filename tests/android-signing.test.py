import importlib.util
import base64
import contextlib
import io
import pathlib
import platform
import shutil
import subprocess
import tempfile
import types
import unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('signing',pathlib.Path(__file__).parents[1]/'scripts/configure-android-signing.py')
signing=importlib.util.module_from_spec(spec);spec.loader.exec_module(signing)

class SigningTests(unittest.TestCase):
    def test_windows_uses_acl_without_posix_user_id(self):
        with tempfile.TemporaryDirectory() as directory:
            path=pathlib.Path(directory)/'private'
            with patch.object(signing.platform,'system',return_value='Windows'),patch.object(signing.os,'geteuid',create=True,side_effect=AssertionError('POSIX-only API')),patch.object(signing,'run') as process:
                signing.prepare_private_directory(path)
                args,kwargs=process.call_args
                self.assertEqual(args[0][0],'powershell.exe')
                self.assertIn('SetAccessRuleProtection($true, $false)',args[0][-1])
                self.assertNotIn(str(path),args[0][-1])
                self.assertEqual(kwargs['env']['DRIVER_SETUP_PRIVATE_DIRECTORY'],str(path))

    def test_windows_never_changes_acl_of_a_nonempty_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            path=pathlib.Path(directory);existing=path/'existing-key.p12';existing.write_bytes(b'unchanged')
            with patch.object(signing.platform,'system',return_value='Windows'),patch.object(signing,'run') as process:
                with self.assertRaisesRegex(RuntimeError,'dedicated empty directory'):
                    signing.prepare_private_directory(path)
                process.assert_not_called();self.assertEqual(existing.read_bytes(),b'unchanged')

    def test_denied_access_never_creates_key_or_requests_password(self):
        with tempfile.TemporaryDirectory() as directory:
            path=pathlib.Path(directory)/'private/key.p12'
            args=types.SimpleNamespace(keystore=str(path),create=True,alias='driver-release',build=False)
            with patch.object(signing.shutil,'which',return_value='/bin/test'),patch.object(signing,'run',side_effect=RuntimeError('403')),patch.object(signing.getpass,'getpass') as password:
                with self.assertRaisesRegex(RuntimeError,'403'):signing.setup(args)
                password.assert_not_called();self.assertFalse(path.exists())

    def test_existing_remote_key_is_not_replaced(self):
        args=types.SimpleNamespace(keystore='/tmp/uncreated-driver-key',create=True,alias='driver-release',build=False)
        with patch.object(signing.shutil,'which',return_value='/bin/test'),patch.object(signing,'run',side_effect=[b'{}',b'DRIVER_ANDROID_KEYSTORE_BASE64\n']),patch.object(signing.getpass,'getpass') as password:
            with self.assertRaisesRegex(RuntimeError,'already exists'):signing.setup(args)
            password.assert_not_called()

    def test_existing_local_key_is_not_replaced(self):
        with tempfile.TemporaryDirectory() as directory:
            path=pathlib.Path(directory)/'key.p12';path.write_bytes(b'original')
            args=types.SimpleNamespace(keystore=str(path),create=True,alias='driver-release',build=False)
            with patch.object(signing.shutil,'which',return_value='/bin/test'),patch.object(signing,'run',side_effect=[b'{}',b'']),patch.object(signing.getpass,'getpass') as password:
                with self.assertRaisesRegex(RuntimeError,'already exists'):signing.setup(args)
                password.assert_not_called();self.assertEqual(path.read_bytes(),b'original')

    def test_private_payload_is_stdin_not_process_arguments(self):
        with patch.object(signing.subprocess,'run',return_value=subprocess.CompletedProcess([],0,b'',b'')) as process:
            signing.run(['gh','secret','set','DRIVER_ANDROID_STORE_PASSWORD','--repo',signing.REPO],b'test-private-password')
            args,kwargs=process.call_args
            self.assertNotIn('test-private-password',str(args));self.assertEqual(kwargs['input'],b'test-private-password')

    @unittest.skipUnless(shutil.which('keytool'),'JDK keytool is required for the integration check')
    def test_real_keytool_creation_export_and_secret_payloads(self):
        # Only a disposable test key; GitHub calls are intercepted before networking.
        with tempfile.TemporaryDirectory() as directory:
            path=pathlib.Path(directory)/'private-test-key/key.p12'
            args=types.SimpleNamespace(keystore=str(path),create=True,alias='driver-release',build=True)
            original=signing.run;secrets={};builds=[];password='disposable-test-password-only'
            def fake_github(command,payload=None,env=None):
                if command[0]!='gh':return original(command,payload=payload,env=env)
                if command[1]=='api':return b'{}'
                if command[1:3]==['secret','list']:return b''
                if command[1:3]==['secret','set']:secrets[command[3]]=payload;return b''
                if command[1:3]==['workflow','run']:builds.append(command);return b''
                raise AssertionError('Unexpected GitHub call')
            output=io.StringIO()
            with patch.object(signing,'run',side_effect=fake_github),patch.object(signing.getpass,'getpass',side_effect=[password,password]),contextlib.redirect_stdout(output):
                signing.setup(args)
            self.assertTrue(path.is_file())
            self.assertEqual(base64.b64decode(secrets['DRIVER_ANDROID_KEYSTORE_BASE64']),path.read_bytes())
            self.assertEqual(secrets['DRIVER_ANDROID_STORE_PASSWORD'],password.encode())
            self.assertEqual(secrets['DRIVER_ANDROID_KEY_PASSWORD'],password.encode())
            self.assertRegex(secrets['DRIVER_ANDROID_CERT_SHA256'].decode(),r'^[a-f0-9]{64}$')
            self.assertEqual(len(secrets),5);self.assertEqual(len(builds),1)
            self.assertNotIn(password,output.getvalue())
            if platform.system()!='Windows':self.assertEqual(path.stat().st_mode & 0o077,0)

if __name__=='__main__':unittest.main()
