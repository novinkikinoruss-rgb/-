#!/usr/bin/env python3
"""One-time setup using the operator's own GitHub login. Never prints private key/passwords."""
import argparse
import base64
import getpass
import hashlib
import os
from pathlib import Path
import platform
import re
import shutil
import ssl
import subprocess
import sys

REPO = 'novinkikinoruss-rgb/-'

def run(args, payload=None, env=None):
    try:
        result = subprocess.run(args, input=payload, capture_output=True, env=env)
    except OSError:
        raise RuntimeError('Could not start '+args[0]+'. Check installation and access permissions.') from None
    if result.returncode:
        # Don't echo command bodies, keytool output or an arbitrary process environment.
        if b'403' in result.stderr or b'Resource not accessible' in result.stderr:
            raise RuntimeError('GitHub denied Secrets access (403). Authorise a token with Secrets: Read and write for '+REPO+'.')
        raise RuntimeError(args[0]+' failed; no private values were printed. Check login, key/password and repository access.')
    return result.stdout

def prepare_private_directory(directory):
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    if platform.system() == 'Windows':
        # Do not replace ACLs on an existing directory containing other files/keys.
        if any(directory.iterdir()):
            raise RuntimeError('For a new key, use a dedicated empty directory outside the repository.')
        # Windows has no geteuid or POSIX permission bits. Use a protected NTFS ACL,
        # inherited by the new key, granting access only to this user and SYSTEM.
        # Pass the path as data; never interpolate it into PowerShell code.
        command = r'''
$ErrorActionPreference = 'Stop'
$path = $env:DRIVER_SETUP_PRIVATE_DIRECTORY
$userSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
$systemSid = [System.Security.Principal.SecurityIdentifier]::new('S-1-5-18')
$acl = [System.Security.AccessControl.DirectorySecurity]::new()
$acl.SetOwner($userSid)
$acl.SetAccessRuleProtection($true, $false)
foreach ($sid in @($userSid, $systemSid)) {
    $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
        $sid, [System.Security.AccessControl.FileSystemRights]::FullControl,
        [System.Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
        [System.Security.AccessControl.PropagationFlags]::None,
        [System.Security.AccessControl.AccessControlType]::Allow)
    $acl.AddAccessRule($rule)
}
# Use .NET Framework directly: a caller running PowerShell 7 may leave a
# PSModulePath that prevents Windows PowerShell 5 from importing Set-Acl.
[System.IO.Directory]::SetAccessControl($path, $acl)
$check = [System.IO.Directory]::GetAccessControl($path)
if (-not $check.AreAccessRulesProtected -or $check.GetOwner([System.Security.Principal.SecurityIdentifier]).Value -ne $userSid.Value) {
    throw 'Private directory ownership or ACL protection could not be verified.'
}
$rules = $check.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier])
foreach ($rule in $rules) {
    if ($rule.IdentityReference.Value -notin @($userSid.Value, $systemSid.Value)) {
        throw 'Unexpected access to the private key directory.'
    }
}
'''
        run(['powershell.exe', '-NoProfile', '-NonInteractive', '-Command', command],
            env=dict(os.environ, DRIVER_SETUP_PRIVATE_DIRECTORY=str(directory)))
    elif directory.stat().st_uid != os.geteuid() or directory.stat().st_mode & 0o022:
        raise RuntimeError('Use a private directory owned by you, without group/world write access.')

def setup(args):
    for binary in ['gh', 'keytool']:
        if not shutil.which(binary):
            raise RuntimeError('Install '+binary+' before running setup.')
    # Check permission BEFORE creating any key. A denied integration cannot change itself.
    run(['gh','api','repos/'+REPO+'/actions/secrets/public-key'])
    names = run(['gh','secret','list','--repo',REPO,'--json','name','--jq','.[].name']).decode().splitlines()
    key = Path(args.keystore).expanduser().resolve()
    repository = Path(__file__).resolve().parents[1]
    if key == repository or repository in key.parents:
        raise RuntimeError('Store the keystore outside the source checkout.')
    if args.create and ('DRIVER_ANDROID_KEYSTORE_BASE64' in names or key.exists()):
        raise RuntimeError('A signing key already exists locally or on GitHub. Reuse the original key; do not replace it.')
    if not args.create and not key.is_file():
        raise RuntimeError('Keystore missing. Use --create only for the first release.')
    if args.create:
        prepare_private_directory(key.parent)
    password = getpass.getpass('Keystore password (at least 12 characters): ')
    if len(password)<12:
        raise RuntimeError('Use at least 12 characters.')
    key_password = password if args.create else getpass.getpass('Signing key password: ')
    env = dict(os.environ, DRIVER_SETUP_STORE_PASSWORD=password, DRIVER_SETUP_KEY_PASSWORD=key_password)
    if args.create:
        if getpass.getpass('Confirm keystore password: ') != password:
            raise RuntimeError('Passwords do not match.')
        # Reserve with 0600 permissions before keytool writes it. No key overwrite.
        descriptor=os.open(key,os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600);os.close(descriptor)
        key.unlink()  # keytool requires a missing file; the private parent prevents other users writing.
        old_mask=os.umask(0o077) if platform.system() != 'Windows' else None
        try:
            run(['keytool','-genkeypair','-noprompt','-storetype','PKCS12','-keystore',str(key),'-alias',args.alias,
                 '-storepass:env','DRIVER_SETUP_STORE_PASSWORD','-keypass:env','DRIVER_SETUP_KEY_PASSWORD',
                 '-keyalg','RSA','-keysize','3072','-validity','10000','-dname','CN=Respectlogistic Driver'],env=env)
        finally:
            if old_mask is not None:
                os.umask(old_mask)
    certificate=run(['keytool','-exportcert','-rfc','-keystore',str(key),'-alias',args.alias,
                     '-storepass:env','DRIVER_SETUP_STORE_PASSWORD'],env=env).decode()
    pem=re.search(r'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----',certificate,re.S)
    if not pem: raise RuntimeError('Signing certificate unavailable.')
    fingerprint=hashlib.sha256(ssl.PEM_cert_to_DER_cert(pem.group())).hexdigest()
    values={'DRIVER_ANDROID_KEYSTORE_BASE64':base64.b64encode(key.read_bytes()),
            'DRIVER_ANDROID_STORE_PASSWORD':password.encode(),'DRIVER_ANDROID_KEY_PASSWORD':key_password.encode(),
            'DRIVER_ANDROID_KEY_ALIAS':args.alias.encode(),'DRIVER_ANDROID_CERT_SHA256':fingerprint.encode()}
    for name,value in values.items():
        run(['gh','secret','set',name,'--repo',REPO],payload=value)
        print(name+': configured')
    print('Permanent certificate SHA256: '+fingerprint)
    print('Keep an independent encrypted backup of '+str(key)+' and its password. Never upload them to the public repository.')
    if args.build:
        run(['gh','workflow','run','android-driver.yml','--repo',REPO,'--ref','respectlogistic/customers'])
        print('Signed APK build requested. Check Actions → Driver Android APK.')

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--keystore',required=True,help='Private path OUTSIDE the repository')
    parser.add_argument('--alias',default='driver-release')
    parser.add_argument('--create',action='store_true',help='Create a key only for the first release')
    parser.add_argument('--build',action='store_true')
    try: setup(parser.parse_args())
    except (RuntimeError,OSError,KeyboardInterrupt) as error:
        print(str(error) or 'Cancelled',file=sys.stderr);sys.exit(1)
