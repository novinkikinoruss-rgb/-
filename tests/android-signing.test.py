import importlib.util
import pathlib
import subprocess
import tempfile
import types
import unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('signing',pathlib.Path(__file__).parents[1]/'scripts/configure-android-signing.py')
signing=importlib.util.module_from_spec(spec);spec.loader.exec_module(signing)

class SigningTests(unittest.TestCase):
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

    def test_private_payload_is_stdin_not_process_arguments(self):
        with patch.object(signing.subprocess,'run',return_value=subprocess.CompletedProcess([],0,b'',b'')) as process:
            signing.run(['gh','secret','set','DRIVER_ANDROID_STORE_PASSWORD','--repo',signing.REPO],b'test-private-password')
            args,kwargs=process.call_args
            self.assertNotIn('test-private-password',str(args));self.assertEqual(kwargs['input'],b'test-private-password')

if __name__=='__main__':unittest.main()
